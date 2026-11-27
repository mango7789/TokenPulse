import SwiftUI

struct MenuBarView: View {
    @ObservedObject var engine: MonitorEngine
    let onQuit: () -> Void

    @State private var detailTab: DetailTab = .models

    enum DetailTab: String, CaseIterable, Identifiable {
        case models = "按模型"
        case sessions = "活跃会话"
        case requests = "最近请求"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 12) {
                    if !engine.activeNeedsActionSessions.isEmpty {
                        needsActionBanner
                    }

                    kpiGrid
                    providerSplitBar
                    detailTabPicker

                    switch detailTab {
                    case .models:
                        modelBreakdownSection
                    case .sessions:
                        sessionsSection
                    case .requests:
                        recentRequestsSection
                    }
                }
                .padding(14)
            }

            Divider()
            footerSection
        }
        .frame(width: 400, height: 560)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text("TokenPulse")
                        .font(.system(size: 14, weight: .semibold))
                    Text(statusBadgeText)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.14))
                        .foregroundColor(statusColor)
                        .cornerRadius(4)
                }

                Spacer()

                Button {
                    engine.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("立即刷新")
            }

            HStack(spacing: 8) {
                Picker("", selection: $engine.timeRange) {
                    ForEach(TimeRangeFilter.allCases) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Picker("", selection: $engine.providerFilter) {
                    ForEach(ProviderFilter.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 155)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusColor: Color {
        switch engine.overallState {
        case .needsAction: return .orange
        case .running: return .blue
        case .idle: return .green
        }
    }

    private var statusBadgeText: String {
        let pending = engine.activeNeedsActionSessions.count
        if pending > 0 {
            return "待操作 \(pending)"
        }
        let running = engine.activeRunningSessions.count
        if running > 0 {
            return "运行中 \(running)"
        }
        return "空闲"
    }

    // MARK: - Needs Action Alert

    private var needsActionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 12))
                Text("AI 需要你操作")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
                Spacer()
                Text("\(engine.activeNeedsActionSessions.count) 项")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.orange)
            }

            ForEach(engine.activeNeedsActionSessions) { session in
                HStack(alignment: .center, spacing: 8) {
                    providerPill(session.provider)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text("\(session.sourceApp) · \(session.state.label)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("忽略") {
                        engine.dismissAlert(for: session)
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.45), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    // MARK: - KPI Cards

    private var kpiGrid: some View {
        let cacheRate: String = {
            guard engine.totalInputTokens > 0 else { return "缓存 --" }
            let pct = Int(round(Double(engine.totalCachedTokens) * 100.0 / Double(engine.totalInputTokens)))
            return "缓存命中 \(pct)%"
        }()

        let outputSub: String = {
            if engine.totalReasoningTokens > 0 {
                return "含思考 \(Formatters.tokens(engine.totalReasoningTokens))"
            }
            return "最近 \(Formatters.tps(engine.latestTPS))"
        }()

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            kpiCard(
                title: "总消耗 Token",
                value: Formatters.tokens(engine.totalTokens),
                subtitle: "\(engine.filteredRecords.count) 次请求",
                accent: .primary
            )
            kpiCard(
                title: "平均生成速度",
                value: Formatters.tps(engine.averageTPS),
                subtitle: "最近 \(Formatters.tps(engine.latestTPS))",
                accent: .blue
            )
            kpiCard(
                title: "输入 Token",
                value: Formatters.tokens(engine.totalInputTokens),
                subtitle: cacheRate,
                accent: .secondary
            )
            kpiCard(
                title: "输出 Token",
                value: Formatters.tokens(engine.totalOutputTokens),
                subtitle: outputSub,
                accent: .secondary
            )
        }
    }

    private func kpiCard(title: String, value: String, subtitle: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(accent)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Provider Split Bar

    private var providerSplitBar: some View {
        let gpt = engine.gptTokensInRange
        let gemini = engine.geminiTokensInRange
        let total = max(gpt + gemini, 1)
        let gptRatio = Double(gpt) / Double(total)
        let geminiRatio = Double(gemini) / Double(total)

        return VStack(spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                    Text("GPT: \(Formatters.tokens(gpt))")
                        .font(.system(size: 11, weight: .medium))
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Color.blue).frame(width: 7, height: 7)
                    Text("Gemini: \(Formatters.tokens(gemini))")
                        .font(.system(size: 11, weight: .medium))
                }
            }

            GeometryReader { geo in
                HStack(spacing: 2) {
                    if gpt > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.green.opacity(0.85))
                            .frame(width: max(4, geo.size.width * gptRatio))
                    }
                    if gemini > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue.opacity(0.85))
                            .frame(width: max(4, geo.size.width * geminiRatio))
                    }
                    if gpt == 0 && gemini == 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.2))
                    }
                }
            }
            .frame(height: 6)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Detail Tabs

    private var detailTabPicker: some View {
        Picker("", selection: $detailTab) {
            ForEach(DetailTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Models Breakdown

    private var modelBreakdownSection: some View {
        VStack(spacing: 8) {
            if engine.modelAggregates.isEmpty {
                emptyPlaceholder("当前时间范围内暂无 GPT / Gemini 请求记录")
            } else {
                ForEach(engine.modelAggregates) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            providerPill(item.provider)
                            Text(item.model)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Spacer()
                            Text(Formatters.tokens(item.totalTokens))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }

                        HStack(spacing: 10) {
                            Text("输入 \(Formatters.tokens(item.inputTokens))")
                            Text("输出 \(Formatters.tokens(item.outputTokens))")
                            if item.cachedTokens > 0 {
                                Text("缓存 \(Formatters.tokens(item.cachedTokens))")
                            }
                            Spacer()
                            Text("\(item.requestCount) 次 · \(Formatters.tps(item.avgTPS))")
                                .foregroundColor(.blue)
                        }
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Active Sessions

    private var sessionsSection: some View {
        VStack(spacing: 8) {
            let list = Array(engine.filteredSessions.prefix(20))
            if list.isEmpty {
                emptyPlaceholder("暂无检测到本地会话")
            } else {
                ForEach(list) { session in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(sessionColor(session.state))
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                providerPill(session.provider)
                                Text(session.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                            }
                            HStack(spacing: 6) {
                                Text(session.model)
                                Text("·")
                                Text(session.state.label)
                                    .foregroundColor(sessionColor(session.state))
                                Text("·")
                                Text(Formatters.relativeTime(session.updatedAt))
                            }
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Formatters.tokens(session.totalTokens))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Text(Formatters.tps(session.latestTPS))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(9)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Recent Requests

    private var recentRequestsSection: some View {
        VStack(spacing: 6) {
            let list = Array(engine.filteredRecords.prefix(30))
            if list.isEmpty {
                emptyPlaceholder("暂无请求明细")
            } else {
                ForEach(list) { rec in
                    HStack(spacing: 8) {
                        providerPill(rec.provider)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rec.model)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Text("\(rec.sessionTitle) · \(Formatters.relativeTime(rec.timestamp))")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("↑\(Formatters.tokens(rec.inputTokens)) ↓\(Formatters.tokens(rec.outputTokens))")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                            Text(Formatters.tps(rec.tps))
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(7)
                }
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 8) {
            Text("更新于 \(Formatters.relativeTime(engine.lastUpdated))")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
            Picker("", selection: $engine.menuBarDisplayMode) {
                Text("纯图标").tag(MenuBarDisplayMode.iconOnly)
                Text("TPS").tag(MenuBarDisplayMode.tps)
                Text("金额").tag(MenuBarDisplayMode.cost)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 130)
            Button("退出") {
                onQuit()
            }
            .font(.system(size: 11))
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func providerPill(_ provider: AIProvider) -> some View {
        let color: Color = provider == .gpt ? .green : .blue
        return Text(provider.shortName)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(4)
    }

    private func sessionColor(_ state: SessionActivityState) -> Color {
        switch state {
        case .needsAction: return .orange
        case .running: return .blue
        case .idle: return .gray
        }
    }

    private func emptyPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
    }
}
