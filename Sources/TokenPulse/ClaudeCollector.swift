import Foundation

// MonitorEngine serializes calls to collect() while a refresh is in flight.
final class ClaudeCollector: @unchecked Sendable {
    private struct Transcript {
        let modifiedAt: Date
        let size: Int
        let records: [RequestRecord]
        let session: ActiveSession

        func session(at now: Date) -> ActiveSession {
            guard now.timeIntervalSince(modifiedAt) >= 120, session.state != .idle else {
                return session
            }
            return ActiveSession(
                id: session.id,
                provider: session.provider,
                sourceApp: session.sourceApp,
                title: session.title,
                model: session.model,
                state: .idle,
                updatedAt: session.updatedAt,
                totalTokens: session.totalTokens,
                latestTPS: session.latestTPS
            )
        }
    }

    private struct Usage {
        let id: String
        let model: String
        let timestamp: Date
        let inputTokens: Int
        let cachedTokens: Int
        let outputTokens: Int
        let duration: Double?
    }

    private let projects: URL
    private var cache: [URL: Transcript] = [:]

    init(homeDirectory: String = NSHomeDirectory()) {
        projects = URL(fileURLWithPath: homeDirectory).appendingPathComponent(".claude/projects", isDirectory: true)
    }

    func collect() -> CollectorSnapshot {
        let fm = FileManager.default
        let now = Date()
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        let directories = (try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        var nextCache: [URL: Transcript] = [:]
        var records: [RequestRecord] = []
        var sessions: [ActiveSession] = []

        for directory in directories {
            guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                guard let values = try? file.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      let modifiedAt = values.contentModificationDate,
                      let size = values.fileSize else { continue }
                let previous = cache[file]
                let transcript: Transcript?
                if let previous, previous.modifiedAt == modifiedAt, previous.size == size {
                    transcript = previous
                } else {
                    transcript = parse(file, modifiedAt: modifiedAt, size: size) ?? previous
                }
                guard let transcript else { continue }
                nextCache[file] = transcript
                records.append(contentsOf: transcript.records)
                let session = transcript.session(at: now)
                if !transcript.records.isEmpty || session.state != .idle {
                    sessions.append(session)
                }
            }
        }

        cache = nextCache
        return CollectorSnapshot(records: records, sessions: sessions)
    }

    private func parse(_ file: URL, modifiedAt: Date, size: Int) -> Transcript? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let sessionID = "Claude Code::\(file.deletingLastPathComponent().lastPathComponent)::\(file.deletingPathExtension().lastPathComponent)"
        var usage: [Usage] = []
        var indexByMessage: [String: Int] = [:]
        var title: String?
        var latestModel = "claude"
        var previousMessageAt: Date?
        var updatedAt: Date?
        var state: SessionActivityState = .idle
        var pendingQuestions = Set<String>()

        for (index, line) in data.split(separator: 0x0A).enumerated() {
            guard let event = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  let type = event["type"] as? String else { continue }
            let isSidechain = event["isSidechain"] as? Bool == true
            if type == "system", event["subtype"] as? String == "turn_duration", !isSidechain {
                state = .idle
            }
            guard type == "user" || type == "assistant",
                  let message = event["message"] as? [String: Any] else { continue }
            let content = message["content"] as? [[String: Any]] ?? []
            let results = content.filter { $0["type"] as? String == "tool_result" }
            if type == "user", results.isEmpty, event["isMeta"] as? Bool == true { continue }

            let timestamp = (event["timestamp"] as? String).flatMap(Formatters.parseISO8601)
            let duration = timestamp.flatMap { end in previousMessageAt.map { end.timeIntervalSince($0) } }
                .flatMap { (0.2...180).contains($0) ? $0 : nil }
            previousMessageAt = timestamp
            if !isSidechain {
                updatedAt = timestamp ?? modifiedAt
                if type == "user" {
                    for result in results {
                        if let id = result["tool_use_id"] as? String {
                            pendingQuestions.remove(id)
                        }
                    }
                    if results.isEmpty {
                        pendingQuestions.removeAll()
                        if title == nil {
                            let text = message["content"] as? String
                                ?? (content.first { $0["type"] as? String == "text" }?["text"] as? String)
                            title = text?.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                        }
                    }
                    state = .running(detail: "运行中")
                } else {
                    for block in content where block["type"] as? String == "tool_use" && block["name"] as? String == "AskUserQuestion" {
                        pendingQuestions.insert(block["id"] as? String ?? "question-\(index)")
                    }
                    let stopReason = message["stop_reason"] as? String
                    state = stopReason == nil || stopReason == "tool_use"
                        ? .running(detail: "运行中") : .idle
                }
            }

            guard type == "assistant",
                  let model = message["model"] as? String, !model.isEmpty,
                  let tokens = message["usage"] as? [String: Any] else { continue }
            let cached = max(0, tokens["cache_read_input_tokens"] as? Int ?? 0)
            let input = max(0, tokens["input_tokens"] as? Int ?? 0)
                + max(0, tokens["cache_creation_input_tokens"] as? Int ?? 0) + cached
            let output = max(0, tokens["output_tokens"] as? Int ?? 0)
            guard input > 0 || output > 0 else { continue }

            latestModel = model
            // Multiple streaming content blocks can carry the same API message's usage.
            let id = (message["id"] as? String) ?? (event["uuid"] as? String) ?? "line-\(index)"
            let existingIndex = indexByMessage[id]
            let previous = existingIndex.map { usage[$0] }
            let item = Usage(
                id: id,
                model: model,
                timestamp: previous?.timestamp ?? timestamp ?? modifiedAt,
                inputTokens: input,
                cachedTokens: cached,
                outputTokens: max(previous?.outputTokens ?? 0, output),
                duration: previous?.duration ?? duration
            )
            if let existingIndex {
                usage[existingIndex] = item
            } else {
                indexByMessage[id] = usage.count
                usage.append(item)
            }
        }

        let sessionTitle = title.flatMap { $0.isEmpty ? nil : $0 } ?? "Claude Code 对话"
        let shortTitle = sessionTitle.count > 42 ? String(sessionTitle.prefix(42)) + "…" : sessionTitle
        let records = usage.map { item in
            let duration = item.outputTokens > 0 ? item.duration : nil
            return RequestRecord(
                id: "\(sessionID)::\(item.id)",
                provider: .claude,
                sourceApp: "Claude Code",
                model: item.model,
                timestamp: item.timestamp,
                inputTokens: item.inputTokens,
                cachedTokens: item.cachedTokens,
                outputTokens: item.outputTokens,
                reasoningTokens: 0,
                durationSec: duration,
                tps: duration.map { Double(item.outputTokens) / $0 },
                sessionId: sessionID,
                sessionTitle: shortTitle
            )
        }
        if !pendingQuestions.isEmpty {
            state = .needsAction(reason: "等待你回答问题")
        }
        let session = ActiveSession(
            id: sessionID,
            provider: .claude,
            sourceApp: "Claude Code",
            title: shortTitle,
            model: latestModel,
            state: state,
            updatedAt: updatedAt ?? modifiedAt,
            totalTokens: records.reduce(0) { $0 + $1.totalTokens },
            latestTPS: records.reversed().compactMap(\.tps).first
        )
        return Transcript(modifiedAt: modifiedAt, size: size, records: records, session: session)
    }
}
