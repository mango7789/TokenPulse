import AppKit
import Foundation
import ServiceManagement
import Combine

@MainActor
final class MonitorEngine: ObservableObject {
    @Published var timeRange: TimeRangeFilter = .today
    @Published var providerFilter: ProviderFilter = .all
    @Published var allRecords: [RequestRecord] = []
    @Published var allSessions: [ActiveSession] = []
    @Published var codexQuota: CodexQuotaInfo? = nil
    @Published var lastUpdated: Date = Date()
    @Published var isRefreshing: Bool = false
    @Published var menuBarDisplayMode: MenuBarDisplayMode = {
        if let raw = UserDefaults.standard.string(forKey: "menuBarDisplayMode"),
           let mode = MenuBarDisplayMode(rawValue: raw) {
            return mode
        }
        return UserDefaults.standard.bool(forKey: "showCompactTextInMenuBar") ? .cost : .iconOnly
    }() {
        didSet {
            UserDefaults.standard.set(menuBarDisplayMode.rawValue, forKey: "menuBarDisplayMode")
        }
    }

    @Published var soundAlertEnabled: Bool = UserDefaults.standard.object(forKey: "soundAlertEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(soundAlertEnabled, forKey: "soundAlertEnabled")
        }
    }

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    var launchAtLoginNeedsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Dismissed alert signatures (sessionId -> updatedAt timestamp) so a dismissed alert
    /// stays quiet until the session updates again.
    @Published private var dismissedAlerts: [String: Date] = [:]

    private struct AlertSignature: Hashable {
        let sessionId: String
        let updatedAt: Date
    }

    private var seenAlerts = Set<AlertSignature>()
    private let codexCollector = CodexCollector()
    private let antigravityCollector = AntigravityCollector()
    private let claudeCollector = ClaudeCollector()
    private var timer: Timer?

    init() {
        refresh()
        startPolling()
    }

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let codex = self.codexCollector
        let agy = self.antigravityCollector
        let claude = self.claudeCollector

        Task.detached(priority: .utility) {
            let codexSnap = codex.collect()
            let agySnap = agy.collect()
            let claudeSnap = claude.collect()

            let mergedRecords = (codexSnap.records + agySnap.records + claudeSnap.records)
                .sorted { $0.timestamp > $1.timestamp }
            let mergedSessions = (codexSnap.sessions + agySnap.sessions + claudeSnap.sessions)
                .sorted { lhs, rhs in
                    if lhs.state.priority != rhs.state.priority {
                        return lhs.state.priority > rhs.state.priority
                    }
                    return lhs.updatedAt > rhs.updatedAt
                }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.allRecords = mergedRecords
                self.allSessions = mergedSessions
                self.playSoundForNewAlerts()
                self.codexQuota = codexSnap.codexQuota
                self.lastUpdated = Date()
                self.isRefreshing = false
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled, service.status != .enabled && service.status != .requiresApproval {
            try service.register()
        } else if !enabled, service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
    }

    private func playSoundForNewAlerts() {
        var hasNewAlert = false
        for session in activeNeedsActionSessions {
            let signature = AlertSignature(sessionId: session.id, updatedAt: session.updatedAt)
            if seenAlerts.insert(signature).inserted {
                hasNewAlert = true
            }
        }
        if hasNewAlert && soundAlertEnabled {
            NSSound(named: "Pop")?.play()
        }
    }

    func dismissAlert(for session: ActiveSession) {
        dismissedAlerts[session.id] = session.updatedAt
    }

    // MARK: - Derived State

    var activeNeedsActionSessions: [ActiveSession] {
        allSessions.filter { session in
            guard session.state.isNeedsAction else { return false }
            if let dismissedAt = dismissedAlerts[session.id], dismissedAt >= session.updatedAt {
                return false
            }
            return true
        }
    }

    var activeRunningSessions: [ActiveSession] {
        allSessions.filter { $0.state.isRunning }
    }

    var overallState: SessionActivityState {
        if let first = activeNeedsActionSessions.first {
            return first.state
        }
        if let first = activeRunningSessions.first {
            return first.state
        }
        return .idle
    }

    var filteredRecords: [RequestRecord] {
        let start = timeRange.startDate
        return allRecords.filter { r in
            if let start, r.timestamp < start { return false }
            return providerFilter.includes(r.provider)
        }
    }

    var timeFilteredRecordsAllProviders: [RequestRecord] {
        let start = timeRange.startDate
        guard let start else { return allRecords }
        return allRecords.filter { $0.timestamp >= start }
    }

    var totalInputTokens: Int {
        filteredRecords.reduce(0) { $0 + $1.inputTokens }
    }

    var totalCachedTokens: Int {
        filteredRecords.reduce(0) { $0 + $1.cachedTokens }
    }

    var totalOutputTokens: Int {
        filteredRecords.reduce(0) { $0 + $1.outputTokens }
    }

    var totalReasoningTokens: Int {
        filteredRecords.reduce(0) { $0 + $1.reasoningTokens }
    }

    var totalTokens: Int {
        totalInputTokens + totalOutputTokens
    }

    /// Always computes rolling 24h total tokens (across all providers) for the menu bar tooltip.
    var todayTotalTokens: Int {
        let start = Date().addingTimeInterval(-24 * 3600)
        return allRecords
            .filter { $0.timestamp >= start }
            .reduce(0) { $0 + $1.totalTokens }
    }

    /// Always computes rolling 24h equivalent API cost in USD for the menu bar readout.
    var last24hEstimatedCostUSD: Double {
        let start = Date().addingTimeInterval(-24 * 3600)
        let recent = allRecords.filter { $0.timestamp >= start }
        return Pricing.estimate(recent).estimatedCostUSD
    }

    var antigravityRecent5hTokens: Int {
        let cutoff = Date().addingTimeInterval(-5 * 3600)
        return allRecords
            .filter { $0.provider == .gemini && $0.timestamp >= cutoff }
            .reduce(0) { $0 + $1.totalTokens }
    }

    var antigravityTodayTokens: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return allRecords
            .filter { $0.provider == .gemini && $0.timestamp >= start }
            .reduce(0) { $0 + $1.totalTokens }
    }

    var averageTPS: Double? {
        let valid = filteredRecords.compactMap(\.tps)
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    var latestTPS: Double? {
        filteredRecords.first(where: { $0.tps != nil })?.tps
    }

    /// Unfiltered latest TPS (prioritizing currently running sessions) for the menu bar & pulse speed.
    var liveLatestTPS: Double? {
        if let activeTps = activeRunningSessions.compactMap(\.latestTPS).first {
            return activeTps
        }
        return allRecords.first(where: { $0.tps != nil })?.tps
    }

    var gptTokensInRange: Int {
        timeFilteredRecordsAllProviders
            .filter { $0.provider == .gpt }
            .reduce(0) { $0 + $1.totalTokens }
    }

    var geminiTokensInRange: Int {
        timeFilteredRecordsAllProviders
            .filter { $0.provider == .gemini }
            .reduce(0) { $0 + $1.totalTokens }
    }

    var claudeTokensInRange: Int {
        timeFilteredRecordsAllProviders
            .filter { $0.provider == .claude }
            .reduce(0) { $0 + $1.totalTokens }
    }

    var modelAggregates: [ModelAggregate] {
        var groups: [String: [RequestRecord]] = [:]
        for r in filteredRecords {
            let key = "\(r.provider.rawValue)::\(r.model)"
            groups[key, default: []].append(r)
        }

        return groups.values.compactMap { recs -> ModelAggregate? in
            guard let first = recs.first else { return nil }
            let inputT = recs.reduce(0) { $0 + $1.inputTokens }
            let cachedT = recs.reduce(0) { $0 + $1.cachedTokens }
            let outputT = recs.reduce(0) { $0 + $1.outputTokens }
            let reasoningT = recs.reduce(0) { $0 + $1.reasoningTokens }
            let tpsVals = recs.compactMap(\.tps)
            let avgTps = tpsVals.isEmpty ? nil : tpsVals.reduce(0, +) / Double(tpsVals.count)
            let latestTps = recs.first(where: { $0.tps != nil })?.tps
            let lastActive = recs.map(\.timestamp).max() ?? Date.distantPast

            return ModelAggregate(
                provider: first.provider,
                model: first.model,
                requestCount: recs.count,
                inputTokens: inputT,
                cachedTokens: cachedT,
                outputTokens: outputT,
                reasoningTokens: reasoningT,
                avgTPS: avgTps,
                latestTPS: latestTps,
                lastActive: lastActive
            )
        }
        .sorted { $0.totalTokens > $1.totalTokens }
    }

    var filteredSessions: [ActiveSession] {
        allSessions.filter { providerFilter.includes($0.provider) }
    }
}
