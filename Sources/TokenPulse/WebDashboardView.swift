import AppKit
import WebKit
import Combine

@MainActor
final class WebDashboardViewController: NSViewController, WKScriptMessageHandler, WKNavigationDelegate {
    private let engine: MonitorEngine
    private let onQuit: () -> Void
    private var webView: WKWebView!
    private var isLoaded = false
    private var loginItemError: String?
    private var cancellables = Set<AnyCancellable>()

    init(engine: MonitorEngine, onQuit: @escaping () -> Void) {
        self.engine = engine
        self.onQuit = onQuit
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "tokenPulse")
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 420, height: 590), configuration: config)
        wv.navigationDelegate = self
        wv.setValue(false, forKey: "drawsBackground")
        self.webView = wv
        self.view = wv
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.loadHTMLString(DashboardHTML.content, baseURL: nil)

        engine.objectWillChange
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.pushState()
            }
            .store(in: &cancellables)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        pushState()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "refresh":
            engine.refresh()
        case "setTimeRange":
            if let v = body["value"] as? String {
                switch v {
                case "today": engine.timeRange = .today
                case "sevenDays": engine.timeRange = .sevenDays
                case "thirtyDays": engine.timeRange = .thirtyDays
                case "all": engine.timeRange = .all
                default: break
                }
                pushState()
            }
        case "setProvider":
            if let v = body["value"] as? String {
                switch v {
                case "all": engine.providerFilter = .all
                case "gpt": engine.providerFilter = .gpt
                case "gemini": engine.providerFilter = .gemini
                case "claude": engine.providerFilter = .claude
                default: break
                }
                pushState()
            }
        case "dismissAlert":
            if let id = body["value"] as? String,
               let session = engine.allSessions.first(where: { $0.id == id }) {
                engine.dismissAlert(for: session)
                pushState()
            }
        case "setMenuBarMode":
            if let v = body["value"] as? String, let mode = MenuBarDisplayMode(rawValue: v) {
                engine.menuBarDisplayMode = mode
                pushState()
            }
        case "toggleLaunchAtLogin":
            if let flag = body["value"] as? Bool {
                do {
                    try engine.setLaunchAtLogin(flag)
                    loginItemError = nil
                } catch {
                    loginItemError = error.localizedDescription
                }
                pushState()
            }
        case "toggleSoundAlert":
            if let flag = body["value"] as? Bool {
                engine.soundAlertEnabled = flag
                pushState()
            }
        case "focusApp":
            if let sourceApp = body["value"] as? String {
                focusApp(sourceApp)
            }
        case "quit":
            onQuit()
        default:
            break
        }
    }

    private func focusApp(_ sourceApp: String) {
        let workspace = NSWorkspace.shared
        let path: String
        switch sourceApp {
        case "Antigravity":
            path = "/Applications/Antigravity.app"
        case "Antigravity IDE":
            path = "/Applications/Antigravity IDE.app"
        case "Codex", "Claude Code", "Antigravity CLI":
            let terminals = ["dev.warp.Warp-Stable", "com.googlecode.iterm2", "com.mitchellh.ghostty", "com.apple.Terminal"]
            let running = workspace.runningApplications
            for bundleID in terminals {
                guard let terminal = running.first(where: { $0.bundleIdentifier == bundleID }) else { continue }
                if terminal.isActive { return }
                if #available(macOS 14.0, *) {
                    if terminal.activate(from: .current, options: []) { return }
                } else if terminal.activate(options: .activateIgnoringOtherApps) {
                    return
                }
            }
            path = "/Applications/Antigravity.app"
        default:
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: URL(fileURLWithPath: path), configuration: configuration)
    }

    private func tokenBars(for records: [RequestRecord]) -> [[String: Any]] {
        let timeRange = engine.timeRange
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = timeRange == .today ? "HH':00'" : "MM-dd"
        let hourStart: (Date) -> Date = { calendar.dateInterval(of: .hour, for: $0)?.start ?? $0 }
        let bucket: (Date) -> Date = { date in
            if timeRange == .today { return hourStart(date) }
            let day = calendar.startOfDay(for: date)
            if timeRange == .thirtyDays,
               let daysAgo = calendar.dateComponents([.day], from: day, to: today).day,
               daysAgo.isMultiple(of: 2) {
                return calendar.date(byAdding: .day, value: -1, to: day) ?? day
            }
            return day
        }

        var totals: [Date: (tokens: Int, requests: Int)] = [:]
        for record in records {
            let date = bucket(record.timestamp)
            totals[date, default: (0, 0)].tokens += record.totalTokens
            totals[date, default: (0, 0)].requests += 1
        }

        let dates: [Date]
        switch timeRange {
        case .today:
            let end = hourStart(now)
            let minStart = calendar.date(byAdding: .hour, value: -23, to: end) ?? end
            let recentStart = calendar.date(byAdding: .hour, value: -11, to: end) ?? end
            let earliest = totals.keys.min() ?? recentStart
            let start = max(minStart, min(earliest, recentStart))
            let hours = calendar.dateComponents([.hour], from: start, to: end).hour ?? 0
            dates = (0...max(0, hours)).compactMap { calendar.date(byAdding: .hour, value: $0, to: start) }
        case .sevenDays:
            dates = (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        case .thirtyDays:
            dates = stride(from: -29, through: -1, by: 2).compactMap {
                calendar.date(byAdding: .day, value: $0, to: today)
            }
        case .all:
            dates = Array(totals.keys.sorted().suffix(14))
        }

        return dates.map { date in
            let total = totals[date] ?? (0, 0)
            let label = labelFormatter.string(from: date)
            let endLabel: String
            if timeRange == .thirtyDays, let end = calendar.date(byAdding: .day, value: 1, to: date) {
                endLabel = labelFormatter.string(from: end)
            } else {
                endLabel = label
            }
            return [
                "label": label,
                "endLabel": endLabel,
                "period": label == endLabel ? label : "\(label) ～ \(endLabel)",
                "tokensRaw": total.tokens,
                "tokensText": Formatters.tokens(total.tokens),
                "requests": total.requests
            ]
        }
    }

    func pushState() {
        guard isLoaded else { return }

        let overall: String
        let statusText: String
        let pendingCount = engine.activeNeedsActionSessions.count
        let runningCount = engine.activeRunningSessions.count
        if pendingCount > 0 {
            overall = "needsAction"
            statusText = "待操作 \(pendingCount)"
        } else if runningCount > 0 {
            overall = "running"
            statusText = "运行中 \(runningCount)"
        } else {
            overall = "idle"
            statusText = "空闲"
        }

        let timeRangeKey: String = {
            switch engine.timeRange {
            case .today: return "today"
            case .sevenDays: return "sevenDays"
            case .thirtyDays: return "thirtyDays"
            case .all: return "all"
            }
        }()

        let providerKey = engine.providerFilter == .all ? "all" : engine.providerFilter.rawValue.lowercased()
        let records = engine.filteredRecords
        let pricing = Pricing.estimate(records)

        let cacheRate: String = {
            guard engine.totalInputTokens > 0 else { return "--" }
            let pct = Int(round(Double(engine.totalCachedTokens) * 100.0 / Double(engine.totalInputTokens)))
            return "\(pct)%"
        }()

        let gptRaw = engine.gptTokensInRange
        let geminiRaw = engine.geminiTokensInRange
        let claudeRaw = engine.claudeTokensInRange
        let sumRaw = Double(max(gptRaw + geminiRaw + claudeRaw, 1))

        let shortTodayFmt = DateFormatter()
        shortTodayFmt.dateFormat = "HH:mm"
        let shortDateFmt = DateFormatter()
        shortDateFmt.dateFormat = "MM-dd"
        let exactTodayFmt = DateFormatter()
        exactTodayFmt.dateFormat = "HH:mm:ss"
        let exactDateFmt = DateFormatter()
        exactDateFmt.dateFormat = "MM-dd HH:mm"
        let calForTps = Calendar.current

        let tpsPoints: [[String: Any]] = Array(
            records
                .filter { $0.tps != nil }
                .prefix(24)
                .reversed()
        ).map { r in
            let tpsVal = r.tps ?? 0
            let isToday = calForTps.isDateInToday(r.timestamp)
            return [
                "tps": Double(round(tpsVal * 10) / 10),
                "tpsText": Formatters.tps(tpsVal),
                "axisTime": isToday ? shortTodayFmt.string(from: r.timestamp) : shortDateFmt.string(from: r.timestamp),
                "fullTime": isToday ? exactTodayFmt.string(from: r.timestamp) : exactDateFmt.string(from: r.timestamp),
                "model": r.model,
                "provider": r.provider.shortName
            ]
        }

        let alertsPayload: [[String: Any]] = engine.activeNeedsActionSessions.map { s in
            [
                "id": s.id,
                "provider": s.provider.shortName,
                "sourceApp": s.sourceApp,
                "title": s.title,
                "reason": s.state.label
            ]
        }

        let modelsPayload: [[String: Any]] = engine.modelAggregates.map { m in
            [
                "provider": m.provider.shortName,
                "model": m.model,
                "requestCount": m.requestCount,
                "totalTokensRaw": m.totalTokens,
                "totalTokens": Formatters.tokens(m.totalTokens),
                "inputTokens": Formatters.tokens(m.inputTokens),
                "cachedTokens": Formatters.tokens(m.cachedTokens),
                "outputTokens": Formatters.tokens(m.outputTokens),
                "avgTPS": Formatters.tps(m.avgTPS)
            ]
        }

        let sessionsPayload: [[String: Any]] = engine.filteredSessions.prefix(20).map { s in
            let stateType: String
            switch s.state {
            case .needsAction: stateType = "needsAction"
            case .running: stateType = "running"
            case .idle: stateType = "idle"
            }
            return [
                "id": s.id,
                "provider": s.provider.shortName,
                "title": s.title,
                "sourceApp": s.sourceApp,
                "model": s.model,
                "stateType": stateType,
                "stateLabel": s.state.label,
                "updatedAt": Formatters.relativeTime(s.updatedAt),
                "totalTokens": Formatters.tokens(s.totalTokens),
                "latestTPS": Formatters.tps(s.latestTPS)
            ]
        }

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "MM-dd HH:mm:ss"
        let todayFmt = DateFormatter()
        todayFmt.dateFormat = "HH:mm:ss"
        let cal = Calendar.current

        let requestsPayload: [[String: Any]] = records.prefix(50).map { r in
            let exactTime = cal.isDateInToday(r.timestamp)
                ? todayFmt.string(from: r.timestamp)
                : timeFmt.string(from: r.timestamp)
            let durStr = r.durationSec.map { String(format: "%.1fs", $0) } ?? "--"
            let cachePct = r.inputTokens > 0 ? Int(round(Double(r.cachedTokens) * 100.0 / Double(r.inputTokens))) : 0
            return [
                "provider": r.provider.shortName,
                "sourceApp": r.sourceApp,
                "model": r.model,
                "sessionTitle": r.sessionTitle,
                "time": Formatters.relativeTime(r.timestamp),
                "exactTime": exactTime,
                "totalTokens": Formatters.tokens(r.totalTokens),
                "inputTokens": Formatters.tokens(r.inputTokens),
                "cachedTokens": Formatters.tokens(r.cachedTokens),
                "cachePct": cachePct,
                "outputTokens": Formatters.tokens(r.outputTokens),
                "reasoningTokens": Formatters.tokens(r.reasoningTokens),
                "duration": durStr,
                "tps": Formatters.tps(r.tps)
            ]
        }

        let resetFmt = DateFormatter()
        resetFmt.dateFormat = "MM-dd HH:mm"

        func serializeWindow(_ w: QuotaWindow) -> [String: Any] {
            let now = Date()
            let expired = w.resetsAt.map { $0 <= now } ?? false
            let effectiveUsed = expired ? 0.0 : max(0.0, min(100.0, w.usedPercent))
            let resetDesc: String
            if let r = w.resetsAt {
                if expired {
                    resetDesc = "已于 \(resetFmt.string(from: r)) 重置（上次使用 \(Int(round(w.usedPercent)))%）"
                } else {
                    let secs = Int(r.timeIntervalSince(now))
                    if secs < 3600 {
                        resetDesc = "\(max(1, secs / 60)) 分钟后重置（\(resetFmt.string(from: r))）"
                    } else if secs < 86400 {
                        resetDesc = "\(secs / 3600) 小时 \((secs % 3600) / 60) 分后重置"
                    } else {
                        resetDesc = "\(secs / 86400) 天 \((secs % 86400) / 3600) 小时后重置（\(resetFmt.string(from: r))）"
                    }
                }
            } else {
                resetDesc = "重置时间未知"
            }
            return [
                "label": w.label,
                "usedPercent": Int(round(effectiveUsed)),
                "remainingPercent": Int(round(100.0 - effectiveUsed)),
                "resetDesc": resetDesc,
                "isReset": expired
            ]
        }

        var codexQuotaPayload: [String: Any] = ["available": false]
        if let q = engine.codexQuota {
            var windows: [[String: Any]] = []
            if let p = q.primary { windows.append(serializeWindow(p)) }
            if let s = q.secondary { windows.append(serializeWindow(s)) }
            let planDisplay: String = {
                switch q.planType.lowercased() {
                case "prolite": return "Pro Lite"
                case "pro": return "Pro"
                case "plus": return "Plus"
                case "team": return "Team"
                default: return q.planType
                }
            }()
            codexQuotaPayload = [
                "available": true,
                "plan": planDisplay,
                "windows": windows,
                "unlimited": q.unlimited,
                "hasCredits": q.hasCredits,
                "creditBalance": q.creditBalance ?? "0",
                "recordedAt": resetFmt.string(from: q.recordedAt)
            ]
        }

        let agyQuotaPayload: [String: Any] = [
            "recent5hTokens": Formatters.tokens(engine.antigravityRecent5hTokens),
            "todayTokens": Formatters.tokens(engine.antigravityTodayTokens),
            "note": "Antigravity 客户端暂未开放本地剩余额度接口，仅展示本地统计消耗"
        ]

        let payload: [String: Any] = [
            "overallState": overall,
            "statusText": statusText,
            "timeRange": timeRangeKey,
            "providerFilter": providerKey,
            "alerts": alertsPayload,
            "totalTokens": Formatters.tokens(engine.totalTokens),
            "requestCount": records.count,
            "estimatedCostUSD": pricing.estimatedCostUSD,
            "cacheSavedUSD": pricing.cacheSavedUSD,
            "pricedRequests": pricing.pricedRequests,
            "tokenBars": tokenBars(for: records),
            "inputTokens": Formatters.tokens(engine.totalInputTokens),
            "outputTokens": Formatters.tokens(engine.totalOutputTokens),
            "reasoningTokens": Formatters.tokens(engine.totalReasoningTokens),
            "cacheRate": cacheRate,
            "avgTPS": Formatters.tps(engine.averageTPS),
            "latestTPS": Formatters.tps(engine.latestTPS),
            "tpsPoints": tpsPoints,
            "gptTokens": Formatters.tokens(gptRaw),
            "geminiTokens": Formatters.tokens(geminiRaw),
            "claudeTokens": Formatters.tokens(claudeRaw),
            "gptPercent": Double(gptRaw) * 100 / sumRaw,
            "geminiPercent": Double(geminiRaw) * 100 / sumRaw,
            "claudePercent": Double(claudeRaw) * 100 / sumRaw,
            "models": modelsPayload,
            "sessions": sessionsPayload,
            "requests": requestsPayload,
            "codexQuota": codexQuotaPayload,
            "agyQuota": agyQuotaPayload,
            "updatedAt": Formatters.relativeTime(engine.lastUpdated),
            "launchAtLogin": engine.launchAtLogin,
            "launchAtLoginNeedsApproval": engine.launchAtLoginNeedsApproval,
            "loginItemError": loginItemError ?? "",
            "soundAlertEnabled": engine.soundAlertEnabled,
            "menuBarDisplayMode": engine.menuBarDisplayMode.rawValue
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: jsonData, encoding: .utf8) else { return }

        webView.evaluateJavaScript("window.renderTokenPulse(\(jsonStr));", completionHandler: nil)
    }
}
