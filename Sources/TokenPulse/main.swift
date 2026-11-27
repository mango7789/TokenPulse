import AppKit
import Darwin

// Optional CLI self-test mode: `TokenPulse --probe` prints detected GPT/Gemini/Claude stats and exits.
if CommandLine.arguments.contains("--probe") {
    let codex = CodexCollector().collect()
    let agy = AntigravityCollector().collect()
    let claude = ClaudeCollector().collect()
    let allRecords = codex.records + agy.records + claude.records
    let allSessions = codex.sessions + agy.sessions + claude.sessions

    print("=== TokenPulse Probe ===")
    print("GPT/Codex records: \(codex.records.count), sessions: \(codex.sessions.count)")
    print("Gemini/Antigravity records: \(agy.records.count), sessions: \(agy.sessions.count)")

    print("Claude/Claude Code records: \(claude.records.count), sessions: \(claude.sessions.count)")

    var byModel: [String: (count: Int, inT: Int, outT: Int, cacheT: Int, tpsList: [Double])] = [:]
    for r in allRecords {
        let k = "[\(r.provider.shortName)] \(r.model)"
        var cur = byModel[k] ?? (0, 0, 0, 0, [])
        cur.count += 1
        cur.inT += r.inputTokens
        cur.outT += r.outputTokens
        cur.cacheT += r.cachedTokens
        if let t = r.tps { cur.tpsList.append(t) }
        byModel[k] = cur
    }

    print("\n--- By Model ---")
    for (k, v) in byModel.sorted(by: { ($0.value.inT + $0.value.outT) > ($1.value.inT + $1.value.outT) }) {
        let avg = v.tpsList.isEmpty ? "--" : String(format: "%.1f t/s", v.tpsList.reduce(0, +) / Double(v.tpsList.count))
        print("\(k): reqs=\(v.count), total=\(Formatters.tokens(v.inT + v.outT)) (in=\(Formatters.tokens(v.inT)), cache=\(Formatters.tokens(v.cacheT)), out=\(Formatters.tokens(v.outT))), avgTPS=\(avg)")
    }

    let active = allSessions.filter { $0.state != .idle }
    print("\n--- Active / Waiting Sessions (\(active.count)) ---")
    for s in active {
        print("[\(s.provider.shortName)] \(s.sourceApp) | \(s.title) | state=\(s.state.label) | updated=\(Formatters.relativeTime(s.updatedAt))")
    }
    exit(0)
}

// OS-level single-instance lock (works even if launched from different .app locations).
let cacheDir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Caches")
try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
let lockPath = (cacheDir as NSString).appendingPathComponent("com.mango.TokenPulse.lock")
let lockFd = open(lockPath, O_CREAT | O_RDWR, 0o600)
if lockFd >= 0 {
    if flock(lockFd, LOCK_EX | LOCK_NB) != 0 {
        // Another instance already holds the lock: ask it to show its panel and exit cleanly.
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.mango.TokenPulse.showPanel"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        close(lockFd)
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
