import Foundation

/// Incrementally collects GPT/Codex request metrics and live session states from ~/.codex.
final class CodexCollector: @unchecked Sendable {
    private struct CachedRollout {
        let mtime: Date
        let size: UInt64
        let sessionId: String
        let model: String
        let records: [RequestRecord]
        let state: SessionActivityState
        let updatedAt: Date
        let totalTokens: Int
        let latestTPS: Double?
        let fallbackTitle: String
        let latestQuota: CodexQuotaInfo?
    }

    private let codexRoot: String
    private var cache: [String: CachedRollout] = [:]

    init(homeDirectory: String = NSHomeDirectory()) {
        self.codexRoot = (homeDirectory as NSString).appendingPathComponent(".codex")
    }

    func collect() -> CollectorSnapshot {
        let fm = FileManager.default
        let sessionsRoot = (codexRoot as NSString).appendingPathComponent("sessions")
        guard fm.fileExists(atPath: sessionsRoot) else {
            return CollectorSnapshot(records: [], sessions: [])
        }

        let threadMeta = loadThreadMetadata()
        var rolloutPaths: [String] = []
        if let enumerator = fm.enumerator(atPath: sessionsRoot) {
            while let rel = enumerator.nextObject() as? String {
                if rel.hasSuffix(".jsonl") {
                    rolloutPaths.append((sessionsRoot as NSString).appendingPathComponent(rel))
                }
            }
        }

        var activePaths = Set<String>()
        var allRecords: [RequestRecord] = []
        var allSessions: [ActiveSession] = []
        var newestQuota: CodexQuotaInfo? = nil

        for path in rolloutPaths {
            activePaths.insert(path)
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let mtime = attrs[.modificationDate] as? Date,
                  let size = (attrs[.size] as? NSNumber)?.uint64Value else {
                continue
            }

            let parsed: CachedRollout
            if let existing = cache[path], existing.mtime == mtime, existing.size == size {
                parsed = existing
            } else {
                parsed = parseRollout(path: path, mtime: mtime, size: size, threadMeta: threadMeta)
                cache[path] = parsed
            }

            allRecords.append(contentsOf: parsed.records)
            if let q = parsed.latestQuota {
                if newestQuota == nil || q.recordedAt > newestQuota!.recordedAt {
                    newestQuota = q
                }
            }

            let meta = threadMeta[parsed.sessionId]
            let title = cleanTitle(meta?.title ?? parsed.fallbackTitle)
            let state = refineState(parsed.state, mtime: mtime)

            allSessions.append(ActiveSession(
                id: "codex::\(parsed.sessionId)",
                provider: .gpt,
                sourceApp: "Codex",
                title: title,
                model: parsed.model,
                state: state,
                updatedAt: parsed.updatedAt,
                totalTokens: parsed.totalTokens,
                latestTPS: parsed.latestTPS
            ))
        }

        // Prune deleted files
        cache = cache.filter { activePaths.contains($0.key) }

        return CollectorSnapshot(records: allRecords, sessions: allSessions, codexQuota: newestQuota)
    }

    private struct ThreadMeta {
        let title: String
        let model: String
    }

    private func loadThreadMetadata() -> [String: ThreadMeta] {
        let dbPath = (codexRoot as NSString).appendingPathComponent("state_5.sqlite")
        guard let reader = SQLiteReader(path: dbPath) else { return [:] }
        var map: [String: ThreadMeta] = [:]
        reader.query("SELECT id, title, model FROM threads") { stmt in
            let id = SQLiteReader.string(stmt, col: 0)
            let title = SQLiteReader.string(stmt, col: 1)
            let model = SQLiteReader.string(stmt, col: 2)
            if !id.isEmpty {
                map[id] = ThreadMeta(title: title, model: model)
            }
        }
        return map
    }

    private func parseRollout(
        path: String,
        mtime: Date,
        size: UInt64,
        threadMeta: [String: ThreadMeta]
    ) -> CachedRollout {
        let fileName = (path as NSString).lastPathComponent
        var sessionId = fileName
        var fallbackTitle = "Codex 会话"
        var currentModel = "gpt"
        var currentApprovalPolicy = ""

        struct RawUsage {
            let id: String
            let turnId: String
            let model: String
            let timestamp: Date
            let inputTokens: Int
            let cachedTokens: Int
            let outputTokens: Int
            let reasoningTokens: Int
        }

        var rawUsages: [RawUsage] = []
        var turnDurations: [String: (durationMs: Double, ttftMs: Double?)] = [:]
        var openTurnId: String? = nil
        var pendingApprovalReason: String? = nil
        var lastEventDate: Date = mtime
        var latestQuota: CodexQuotaInfo? = nil

        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let text = String(data: data, encoding: .utf8) {
            var lineIdx = 0
            for lineSub in text.split(separator: "\n", omittingEmptySubsequences: true) {
                lineIdx += 1
                guard let lineData = lineSub.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let type = obj["type"] as? String else {
                    continue
                }

                let ts = (obj["timestamp"] as? String).flatMap(Formatters.parseISO8601) ?? mtime
                lastEventDate = ts
                let payload = obj["payload"] as? [String: Any] ?? [:]

                switch type {
                case "session_meta":
                    if let sid = payload["id"] as? String, !sid.isEmpty {
                        sessionId = sid
                    }
                    if let cwd = payload["cwd"] as? String, !cwd.isEmpty {
                        fallbackTitle = (cwd as NSString).lastPathComponent
                    }

                case "turn_context":
                    if let m = payload["model"] as? String, !m.isEmpty {
                        currentModel = m
                    }
                    if let ap = payload["approval_policy"] as? String {
                        currentApprovalPolicy = ap
                    }

                case "token_usage_record":
                    if let usage = payload["usage"] as? [String: Any] {
                        let inputT = usage["input_tokens"] as? Int ?? 0
                        let cachedT = usage["cached_input_tokens"] as? Int ?? 0
                        let outputT = usage["output_tokens"] as? Int ?? 0
                        let reasoningT = usage["reasoning_output_tokens"] as? Int ?? 0
                        let turnId = payload["turn_id"] as? String ?? "line-\(lineIdx)"
                        let respId = payload["response_id"] as? String ?? "\(sessionId)-\(lineIdx)"
                        let model = (payload["model"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? currentModel

                        if inputT > 0 || outputT > 0 {
                            rawUsages.append(RawUsage(
                                id: "codex::\(respId)",
                                turnId: turnId,
                                model: model,
                                timestamp: ts,
                                inputTokens: inputT,
                                cachedTokens: cachedT,
                                outputTokens: outputT,
                                reasoningTokens: reasoningT
                            ))
                        }
                    }

                case "event_msg":
                    let subType = payload["type"] as? String ?? ""
                    if subType == "task_started" {
                        openTurnId = payload["turn_id"] as? String ?? "open"
                        pendingApprovalReason = nil
                    } else if subType == "task_complete" {
                        if let turnId = payload["turn_id"] as? String,
                           let dur = (payload["duration_ms"] as? NSNumber)?.doubleValue, dur > 0 {
                            let ttft = (payload["time_to_first_token_ms"] as? NSNumber)?.doubleValue
                            turnDurations[turnId] = (dur, ttft)
                        }
                        openTurnId = nil
                        pendingApprovalReason = nil
                    } else if subType == "turn_aborted" {
                        openTurnId = nil
                        pendingApprovalReason = nil
                    } else if subType == "token_count",
                              let rl = payload["rate_limits"] as? [String: Any] {
                        func parseWindow(_ dict: [String: Any]?) -> QuotaWindow? {
                            guard let dict,
                                  let pct = (dict["used_percent"] as? NSNumber)?.doubleValue else { return nil }
                            let winMin = (dict["window_minutes"] as? NSNumber)?.intValue ?? 0
                            let resetEpoch = (dict["resets_at"] as? NSNumber)?.doubleValue
                            let resetDate = resetEpoch.map { Date(timeIntervalSince1970: $0) }
                            let label: String
                            if winMin >= 1440 {
                                label = "\(winMin / 1440) 天额度"
                            } else if winMin >= 60 {
                                label = "\(winMin / 60) 小时额度"
                            } else if winMin > 0 {
                                label = "\(winMin) 分钟额度"
                            } else {
                                label = "周期额度"
                            }
                            return QuotaWindow(label: label, usedPercent: pct, resetsAt: resetDate, windowMinutes: winMin)
                        }

                        let plan = (rl["plan_type"] as? String) ?? "Codex"
                        let primary = parseWindow(rl["primary"] as? [String: Any])
                        let secondary = parseWindow(rl["secondary"] as? [String: Any])
                        let credits = rl["credits"] as? [String: Any]
                        let hasCredits = (credits?["has_credits"] as? Bool) ?? false
                        let unlimited = (credits?["unlimited"] as? Bool) ?? false
                        let balance = credits?["balance"] as? String

                        if primary != nil || secondary != nil || hasCredits || unlimited {
                            latestQuota = CodexQuotaInfo(
                                planType: plan,
                                primary: primary,
                                secondary: secondary,
                                hasCredits: hasCredits,
                                unlimited: unlimited,
                                creditBalance: balance,
                                recordedAt: ts
                            )
                        }
                    } else if subType.contains("approval") || subType.contains("request_user_input") || subType.contains("elicitation") {
                        pendingApprovalReason = "等待你确认权限或输入"
                    }

                default:
                    break
                }
            }
        }

        // Resolve model fallback from state_5.sqlite
        if currentModel == "gpt", let metaModel = threadMeta[sessionId]?.model, !metaModel.isEmpty {
            currentModel = metaModel
        }

        // Sum output tokens per turn for TPS computation
        var outputPerTurn: [String: Int] = [:]
        for u in rawUsages {
            outputPerTurn[u.turnId, default: 0] += u.outputTokens
        }

        let resolvedTitle = cleanTitle(threadMeta[sessionId]?.title ?? fallbackTitle)
        var records: [RequestRecord] = []
        var totalTokens = 0
        var latestTPS: Double? = nil

        for u in rawUsages {
            let modelName = u.model == "gpt" ? currentModel : u.model
            var durationSec: Double? = nil
            var tps: Double? = nil

            if let timing = turnDurations[u.turnId] {
                let totalSec = timing.durationMs / 1000.0
                durationSec = totalSec
                let turnOut = outputPerTurn[u.turnId] ?? u.outputTokens
                if turnOut > 0 {
                    let genSec: Double
                    if let ttft = timing.ttftMs, timing.durationMs > ttft + 80 {
                        genSec = (timing.durationMs - ttft) / 1000.0
                    } else {
                        genSec = totalSec
                    }
                    if genSec >= 0.05 {
                        let candidate = Double(turnOut) / genSec
                        if candidate >= 0.1 && candidate <= 2500 {
                            tps = candidate
                            latestTPS = candidate
                        }
                    }
                }
            }

            totalTokens += u.inputTokens + u.outputTokens
            records.append(RequestRecord(
                id: u.id,
                provider: .gpt,
                sourceApp: "Codex",
                model: modelName,
                timestamp: u.timestamp,
                inputTokens: u.inputTokens,
                cachedTokens: u.cachedTokens,
                outputTokens: u.outputTokens,
                reasoningTokens: u.reasoningTokens,
                durationSec: durationSec,
                tps: tps,
                sessionId: sessionId,
                sessionTitle: resolvedTitle
            ))
        }

        let state: SessionActivityState
        if let reason = pendingApprovalReason {
            state = .needsAction(reason: reason)
        } else if openTurnId != nil {
            if currentApprovalPolicy != "never" && !currentApprovalPolicy.isEmpty {
                state = .running(detail: "执行中")
            } else {
                state = .running(detail: "运行中")
            }
        } else {
            state = .idle
        }

        return CachedRollout(
            mtime: mtime,
            size: size,
            sessionId: sessionId,
            model: currentModel,
            records: records,
            state: state,
            updatedAt: max(mtime, lastEventDate),
            totalTokens: totalTokens,
            latestTPS: latestTPS,
            fallbackTitle: fallbackTitle,
            latestQuota: latestQuota
        )
    }

    /// Prevent old abandoned/crashed rollout files from permanently showing as running.
    private func refineState(_ state: SessionActivityState, mtime: Date) -> SessionActivityState {
        let age = Date().timeIntervalSince(mtime)
        switch state {
        case .idle:
            return .idle
        case .needsAction:
            return age < 1800 ? state : .idle
        case .running:
            return age < 600 ? state : .idle
        }
    }

    private func cleanTitle(_ raw: String) -> String {
        let trimmed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Codex 会话" }
        if trimmed.count > 42 {
            return String(trimmed.prefix(42)) + "…"
        }
        return trimmed
    }
}
