import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case gpt = "GPT"
    case gemini = "Gemini"
    case claude = "Claude"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gpt: return "GPT (Codex)"
        case .gemini: return "Gemini (Antigravity)"
        case .claude: return "Claude (Claude Code)"
        }
    }

    var shortName: String { rawValue }
}

enum SessionActivityState: Equatable, Sendable {
    case idle
    case running(detail: String)
    case needsAction(reason: String)

    var priority: Int {
        switch self {
        case .idle: return 0
        case .running: return 1
        case .needsAction: return 2
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var isNeedsAction: Bool {
        if case .needsAction = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .idle: return "空闲"
        case .running(let detail): return detail.isEmpty ? "运行中" : detail
        case .needsAction(let reason): return reason.isEmpty ? "等待操作" : reason
        }
    }
}

struct RequestRecord: Identifiable, Sendable {
    let id: String
    let provider: AIProvider
    let sourceApp: String
    let model: String
    let timestamp: Date
    let inputTokens: Int
    let cachedTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let durationSec: Double?
    let tps: Double?
    let sessionId: String
    let sessionTitle: String

    var totalTokens: Int {
        inputTokens + outputTokens
    }
}

struct ActiveSession: Identifiable, Sendable {
    let id: String
    let provider: AIProvider
    let sourceApp: String
    let title: String
    let model: String
    let state: SessionActivityState
    let updatedAt: Date
    let totalTokens: Int
    let latestTPS: Double?
}

struct ModelAggregate: Identifiable, Sendable {
    var id: String { "\(provider.rawValue)::\(model)" }
    let provider: AIProvider
    let model: String
    let requestCount: Int
    let inputTokens: Int
    let cachedTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let avgTPS: Double?
    let latestTPS: Double?
    let lastActive: Date

    var totalTokens: Int { inputTokens + outputTokens }
}

enum TimeRangeFilter: String, CaseIterable, Identifiable, Sendable {
    case today = "近1天"
    case sevenDays = "7天"
    case thirtyDays = "30天"
    case all = "全部"

    var id: String { rawValue }

    var startDate: Date? {
        let now = Date()
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        switch self {
        case .today:
            return now.addingTimeInterval(-24 * 3600)
        case .sevenDays:
            return cal.date(byAdding: .day, value: -6, to: today)
        case .thirtyDays:
            return cal.date(byAdding: .day, value: -29, to: today)
        case .all:
            return nil
        }
    }
}

enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case iconOnly = "none"
    case tps = "tps"
    case cost = "cost"

    var id: String { rawValue }
}

enum ProviderFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "全部"
    case gpt = "GPT"
    case gemini = "Gemini"
    case claude = "Claude"

    var id: String { rawValue }

    func includes(_ provider: AIProvider) -> Bool {
        self == .all || rawValue == provider.rawValue
    }
}

enum Pricing {
    struct Estimate {
        var estimatedCostUSD = 0.0
        var cacheSavedUSD = 0.0
        var pricedRequests = 0
    }

    private struct Rates {
        let input: Double
        let cached: Double
        let output: Double
    }

    static func estimate(_ records: [RequestRecord]) -> Estimate {
        records.reduce(into: Estimate()) { estimate, record in
            guard let rates = rates(for: record.model) else { return }
            let cached = Double(min(max(record.cachedTokens, 0), max(record.inputTokens, 0)))
            let uncached = max(0, Double(record.inputTokens) - cached)
            let output = Double(max(record.outputTokens, 0))
            estimate.estimatedCostUSD += (uncached * rates.input + cached * rates.cached + output * rates.output) / 1_000_000
            estimate.cacheSavedUSD += cached * (rates.input - rates.cached) / 1_000_000
            estimate.pricedRequests += 1
        }
    }

    // Equivalent USD per million tokens. Claude cache creation counts as uncached input.
    private static func rates(for model: String) -> Rates? {
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let modelID = name.split(separator: "/").last.map(String.init) ?? name
        if modelID.hasPrefix("gemini"), modelID.contains("pro") || modelID.hasPrefix("gemini-4") {
            return Rates(input: 1.25, cached: 0.31, output: 10)
        }
        if ["gpt-5.6", "luna", "auto-review"].contains(where: { modelID.hasPrefix($0) }) {
            return Rates(input: 0.50, cached: 0.125, output: 4)
        }
        if ["gpt-6", "astra", "sol"].contains(where: { modelID.hasPrefix($0) }) {
            return Rates(input: 2.50, cached: 0.625, output: 15)
        }
        if ["claude-opus", "opus"].contains(where: { modelID.hasPrefix($0) }) {
            return Rates(input: 5, cached: 0.5, output: 25)
        }
        if ["claude-sonnet", "sonnet"].contains(where: { modelID.hasPrefix($0) }) {
            return Rates(input: 3, cached: 0.3, output: 15)
        }
        if ["claude-haiku", "haiku"].contains(where: { modelID.hasPrefix($0) }) {
            return Rates(input: 0.8, cached: 0.08, output: 4)
        }
        return nil
    }
}

struct QuotaWindow: Sendable {
    let label: String          // e.g. "5 小时窗口" or "7 天窗口"
    let usedPercent: Double    // 0...100
    let resetsAt: Date?
    let windowMinutes: Int
}

struct CodexQuotaInfo: Sendable {
    let planType: String       // e.g. "prolite", "plus", "pro"
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
    let hasCredits: Bool
    let unlimited: Bool
    let creditBalance: String?
    let recordedAt: Date
}

struct CollectorSnapshot: Sendable {
    let records: [RequestRecord]
    let sessions: [ActiveSession]
    let codexQuota: CodexQuotaInfo?

    init(records: [RequestRecord], sessions: [ActiveSession], codexQuota: CodexQuotaInfo? = nil) {
        self.records = records
        self.sessions = sessions
        self.codexQuota = codexQuota
    }
}

enum Formatters {
    static func tokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.2fM", Double(value) / 1_000_000.0)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000.0)
        }
        return "\(value)"
    }

    static func tps(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "--" }
        if value >= 100 {
            return String(format: "%.0f t/s", value)
        }
        return String(format: "%.1f t/s", value)
    }

    static func relativeTime(_ date: Date) -> String {
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 5 { return "刚刚" }
        if diff < 60 { return "\(diff)秒前" }
        if diff < 3600 { return "\(diff / 60)分钟前" }
        if diff < 86400 { return "\(diff / 3600)小时前" }
        return "\(diff / 86400)天前"
    }

    static func parseISO8601(_ str: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: str) { return d }

        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: str) { return d }

        // Handle SQLite datetime like "2026-11-26 14:59:59.15652+00:00"
        let normalized = str.replacingOccurrences(of: " ", with: "T")
        if let d = f1.date(from: normalized) { return d }
        if let d = f2.date(from: normalized) { return d }

        return nil
    }
}
