import Foundation

/// Incrementally collects Gemini/Antigravity request metrics and live session states
/// from ~/.gemini/antigravity, ~/.gemini/antigravity-ide, and ~/.gemini/antigravity-cli.
final class AntigravityCollector: @unchecked Sendable {
    private struct DataSource {
        let rootPath: String
        let sourceName: String
    }

    private struct ConversationRow {
        let id: String
        let title: String
        let status: String
        let lastModified: Date
        let notFullyIdle: Bool
    }

    private struct CachedTranscript {
        let mtime: Date
        let size: UInt64
        let records: [RequestRecord]
        let latestModel: String
        let totalTokens: Int
        let latestTPS: Double?
        let waitingReason: String?
        let lastStepAt: Date?
    }

    private let sources: [DataSource]
    private var cache: [String: CachedTranscript] = [:]

    init(homeDirectory: String = NSHomeDirectory()) {
        let geminiDir = (homeDirectory as NSString).appendingPathComponent(".gemini")
        self.sources = [
            DataSource(rootPath: (geminiDir as NSString).appendingPathComponent("antigravity"), sourceName: "Antigravity"),
            DataSource(rootPath: (geminiDir as NSString).appendingPathComponent("antigravity-ide"), sourceName: "Antigravity IDE"),
            DataSource(rootPath: (geminiDir as NSString).appendingPathComponent("antigravity-cli"), sourceName: "Antigravity CLI")
        ]
    }

    func collect() -> CollectorSnapshot {
        let fm = FileManager.default
        var allRecords: [RequestRecord] = []
        var allSessions: [ActiveSession] = []
        var seenFiles = Set<String>()

        for source in sources {
            guard fm.fileExists(atPath: source.rootPath) else { continue }
            let rows = loadConversationSummaries(rootPath: source.rootPath)
            let brainDir = (source.rootPath as NSString).appendingPathComponent("brain")

            var rowById: [String: ConversationRow] = [:]
            for r in rows { rowById[r.id] = r }

            // Enumerate all conversation directories in brain/
            var cidSet = Set(rows.map(\.id))
            if let brainItems = try? fm.contentsOfDirectory(atPath: brainDir) {
                for item in brainItems where !item.hasPrefix(".") {
                    cidSet.insert(item)
                }
            }

            for cid in cidSet {
                let transcriptPath = (brainDir as NSString)
                    .appendingPathComponent(cid)
                    .appending("/.system_generated/logs/transcript.jsonl")

                let row = rowById[cid]
                let title = cleanTitle(row?.title ?? "")

                var parsed: CachedTranscript? = nil
                if fm.fileExists(atPath: transcriptPath),
                   let attrs = try? fm.attributesOfItem(atPath: transcriptPath),
                   let mtime = attrs[.modificationDate] as? Date,
                   let size = (attrs[.size] as? NSNumber)?.uint64Value {
                    seenFiles.insert(transcriptPath)
                    if let existing = cache[transcriptPath], existing.mtime == mtime, existing.size == size {
                        parsed = existing
                    } else {
                        let newlyParsed = parseTranscript(
                            path: transcriptPath,
                            mtime: mtime,
                            size: size,
                            conversationId: cid,
                            sessionTitle: title,
                            sourceName: source.sourceName
                        )
                        cache[transcriptPath] = newlyParsed
                        parsed = newlyParsed
                    }
                }

                if let parsed {
                    allRecords.append(contentsOf: parsed.records)
                }

                // Determine live session state
                let updatedAt = max(row?.lastModified ?? .distantPast, parsed?.mtime ?? .distantPast)
                if updatedAt == .distantPast { continue }

                let state = computeSessionState(row: row, transcript: parsed, updatedAt: updatedAt)

                // Only include sessions that either have tokens or are actively running/waiting
                if (parsed?.totalTokens ?? 0) > 0 || state != .idle {
                    allSessions.append(ActiveSession(
                        id: "\(source.sourceName)::\(cid)",
                        provider: .gemini,
                        sourceApp: source.sourceName,
                        title: title,
                        model: parsed?.latestModel ?? "gemini",
                        state: state,
                        updatedAt: updatedAt,
                        totalTokens: parsed?.totalTokens ?? 0,
                        latestTPS: parsed?.latestTPS
                    ))
                }
            }
        }

        cache = cache.filter { seenFiles.contains($0.key) }
        return CollectorSnapshot(records: allRecords, sessions: allSessions)
    }

    private func loadConversationSummaries(rootPath: String) -> [ConversationRow] {
        let dbPath = (rootPath as NSString).appendingPathComponent("conversation_summaries.db")
        guard let reader = SQLiteReader(path: dbPath) else { return [] }
        var rows: [ConversationRow] = []
        let sql = "SELECT conversation_id, title, status, last_modified_time, not_fully_idle FROM conversation_summaries"
        reader.query(sql) { stmt in
            let id = SQLiteReader.string(stmt, col: 0)
            let title = SQLiteReader.string(stmt, col: 1)
            let status = SQLiteReader.string(stmt, col: 2)
            let modStr = SQLiteReader.string(stmt, col: 3)
            let notFullyIdle = SQLiteReader.int(stmt, col: 4) != 0
            if !id.isEmpty, let date = Formatters.parseISO8601(modStr), date.timeIntervalSince1970 > 1_000_000_000 {
                rows.append(ConversationRow(
                    id: id,
                    title: title,
                    status: status,
                    lastModified: date,
                    notFullyIdle: notFullyIdle
                ))
            }
        }
        return rows
    }

    private func parseTranscript(
        path: String,
        mtime: Date,
        size: UInt64,
        conversationId: String,
        sessionTitle: String,
        sourceName: String
    ) -> CachedTranscript {
        struct StepInfo {
            let stepIndex: Int
            let type: String
            let status: String
            let createdAt: Date?
            let model: String?
            let inputTokens: Int
            let cacheReadTokens: Int
            let outputTokens: Int
            let toolCallNames: [String]
            let requestsFeedback: Bool
        }

        var steps: [StepInfo] = []

        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let text = String(data: data, encoding: .utf8) {
            for lineSub in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let lineData = lineSub.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    continue
                }

                let idx = obj["step_index"] as? Int ?? steps.count
                let type = obj["type"] as? String ?? ""
                let status = obj["status"] as? String ?? ""
                let createdAt = (obj["created_at"] as? String).flatMap(Formatters.parseISO8601)
                let model = obj["model"] as? String
                let inputT = obj["input_tokens"] as? Int ?? 0
                let cacheT = obj["cache_read_tokens"] as? Int ?? 0
                let outputT = obj["output_tokens"] as? Int ?? 0

                var toolNames: [String] = []
                var reqFeedback = false
                if let toolCalls = obj["tool_calls"] as? [[String: Any]] {
                    for tc in toolCalls {
                        if let name = tc["name"] as? String {
                            toolNames.append(name)
                            let args = (tc["args"] as? [String: Any]) ?? (tc["arguments"] as? [String: Any])
                            if name == "ask_question" {
                                reqFeedback = true
                            } else if name == "notify_user",
                                      let blocked = args?["BlockedOnUser"] as? Bool, blocked {
                                reqFeedback = true
                            } else if (name == "write_file" || name == "edit_file"),
                                      let meta = args?["ArtifactMetadata"] as? [String: Any],
                                      let rf = meta["RequestFeedback"] as? Bool, rf {
                                reqFeedback = true
                            }
                        }
                    }
                }

                steps.append(StepInfo(
                    stepIndex: idx,
                    type: type,
                    status: status,
                    createdAt: createdAt,
                    model: model,
                    inputTokens: inputT,
                    cacheReadTokens: cacheT,
                    outputTokens: outputT,
                    toolCallNames: toolNames,
                    requestsFeedback: reqFeedback
                ))
            }
        }

        var records: [RequestRecord] = []
        var latestModel = "gemini"
        var totalTokens = 0
        var latestTPS: Double? = nil

        for i in 0..<steps.count {
            let s = steps[i]
            guard s.type == "PLANNER_RESPONSE" else { continue }
            guard s.inputTokens > 0 || s.outputTokens > 0 || s.cacheReadTokens > 0 else { continue }

            let model = (s.model?.isEmpty == false) ? s.model! : latestModel
            latestModel = model

            var durationSec: Double? = nil
            var tps: Double? = nil
            if let start = s.createdAt, i + 1 < steps.count, let end = steps[i + 1].createdAt {
                let dt = end.timeIntervalSince(start)
                if dt >= 0.2 && dt <= 180.0 && s.outputTokens > 0 {
                    durationSec = dt
                    let candidate = Double(s.outputTokens) / dt
                    if candidate >= 0.5 && candidate <= 1500.0 {
                        tps = candidate
                        latestTPS = candidate
                    }
                }
            }

            let totalInput = s.inputTokens + s.cacheReadTokens
            totalTokens += totalInput + s.outputTokens

            records.append(RequestRecord(
                id: "\(sourceName)::\(conversationId)::\(s.stepIndex)",
                provider: .gemini,
                sourceApp: sourceName,
                model: model,
                timestamp: s.createdAt ?? mtime,
                inputTokens: totalInput,
                cachedTokens: s.cacheReadTokens,
                outputTokens: s.outputTokens,
                reasoningTokens: 0,
                durationSec: durationSec,
                tps: tps,
                sessionId: conversationId,
                sessionTitle: sessionTitle
            ))
        }

        // Detect whether the latest step genuinely waits for user interaction
        var waitingReason: String? = nil
        if let last = steps.last {
            if last.type == "PLANNER_RESPONSE" && last.requestsFeedback {
                waitingReason = "等待你回答问题或确认"
            } else if last.status == "WAITING" || last.status == "WAITING_FOR_USER" {
                waitingReason = "等待你确认或操作"
            } else if last.status == "RUNNING", steps.count >= 2 {
                let prev = steps[steps.count - 2]
                if prev.type == "PLANNER_RESPONSE" && prev.requestsFeedback {
                    waitingReason = "等待你回答问题或确认"
                }
            }
        }

        return CachedTranscript(
            mtime: mtime,
            size: size,
            records: records,
            latestModel: latestModel,
            totalTokens: totalTokens,
            latestTPS: latestTPS,
            waitingReason: waitingReason,
            lastStepAt: steps.last?.createdAt
        )
    }

    private func computeSessionState(
        row: ConversationRow?,
        transcript: CachedTranscript?,
        updatedAt: Date
    ) -> SessionActivityState {
        let age = Date().timeIntervalSince(updatedAt)
        // Ignore stale statuses older than 30 minutes (e.g. crashed/closed IDE windows)
        guard age < 1800 else { return .idle }

        let status = row?.status ?? ""
        if status.contains("WAITING") || status.contains("PENDING") {
            return .needsAction(reason: transcript?.waitingReason ?? "等待你确认或操作")
        }

        if status == "CASCADE_RUN_STATUS_RUNNING" {
            if let reason = transcript?.waitingReason {
                return .needsAction(reason: reason)
            }
            return .running(detail: "运行中")
        }

        return .idle
    }

    private func cleanTitle(_ raw: String) -> String {
        let trimmed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Antigravity 对话" }
        if trimmed.count > 42 {
            return String(trimmed.prefix(42)) + "…"
        }
        return trimmed
    }
}
