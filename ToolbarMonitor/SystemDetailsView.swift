import AppKit
import SwiftUI

@MainActor
struct SystemDetailsView: View {
    @ObservedObject var metrics: SystemMetrics
    @ObservedObject var tokenUsage: TokenUsageMonitor
    @State private var selectedSection = DetailSection.tokens

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Group {
                switch selectedSection {
                case .tokens:
                    TokenDashboardView(monitor: tokenUsage)
                case .system:
                    systemDashboard
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()

            footer
        }
        .frame(width: 420, height: 680)
        .background(.regularMaterial)
    }

    private var systemDashboard: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                gauges
                history
                networkHistory
                detailRows
            }
            .padding(18)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: selectedSection == .tokens ? "bolt.fill" : "waveform.path.ecg")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selectedSection == .tokens ? Color.indigo : Color.accentColor)
                .frame(width: 30, height: 30)
                .background(
                    (selectedSection == .tokens ? Color.indigo : Color.accentColor).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(selectedSection == .tokens ? "Token 用量" : "系统状态")
                    .font(.headline)
                    .lineLimit(1)
                Text(selectedSection == .tokens ? "消耗 3 分钟 · 额度 10 分钟" : "每秒自动更新")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            Picker("详情", selection: $selectedSection) {
                ForEach(DetailSection.allCases) { section in
                    Text(section.title)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 158)

            Button {
                metrics.refresh()
                tokenUsage.refresh(forceAntigravitySync: true, forceQuotaRefresh: true)
            } label: {
                if tokenUsage.isRefreshing && selectedSection == .tokens {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("立即刷新")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var gauges: some View {
        HStack(spacing: 14) {
            MetricGauge(
                title: "CPU",
                value: metrics.cpu.total,
                detail: "\(metrics.processorDescription) · 系统 \(metrics.cpu.system.percentText)",
                color: .blue,
                systemImage: "cpu"
            )

            MetricGauge(
                title: "内存",
                value: metrics.memory.utilization,
                detail: "已用 \(metrics.memory.used.byteText)",
                color: .orange,
                systemImage: "memorychip"
            )
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("最近 3 分钟", systemImage: "chart.xyaxis.line")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 10) {
                    LegendDot(color: .blue, title: "CPU")
                    LegendDot(color: .orange, title: "内存")
                }
            }

            HistoryChart(
                cpu: metrics.cpuHistory,
                memory: metrics.memoryHistory
            )
            .frame(height: 58)
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private var detailRows: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
            GridRow {
                DetailLabel(title: "CPU 用户", value: metrics.cpu.user.percentText)
                DetailLabel(title: "CPU 空闲", value: metrics.cpu.idle.percentText)
            }
            GridRow {
                DetailLabel(title: "可用内存", value: metrics.memory.available.byteText)
                DetailLabel(title: "压缩内存", value: metrics.memory.compressed.byteText)
            }
            GridRow {
                DetailLabel(title: "内存总量", value: metrics.memory.total.byteText)
                DetailLabel(title: "交换空间", value: metrics.memory.swapUsed.byteText)
            }
        }
    }

    private var networkHistory: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("实时网速", systemImage: "network")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                SpeedValue(
                    title: "下载",
                    value: metrics.network.downloadBytesPerSecond,
                    color: .cyan,
                    symbol: "arrow.down"
                )
                SpeedValue(
                    title: "上传",
                    value: metrics.network.uploadBytesPerSecond,
                    color: .purple,
                    symbol: "arrow.up"
                )
            }

            ZStack(alignment: .topTrailing) {
                NetworkHistoryChart(
                    download: metrics.downloadHistory,
                    upload: metrics.uploadHistory
                )

                Text(networkScaleMaximum.speedText)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .frame(height: 72)

            HStack {
                Text("3 分钟前")
                Spacer()
                Text("现在")
            }
            .font(.system(size: 8))
            .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private var networkScaleMaximum: Double {
        max(
            metrics.downloadHistory.max() ?? 0,
            metrics.uploadHistory.max() ?? 0,
            1_000
        ) * 1.1
    }

    private var footer: some View {
        HStack {
            if selectedSection == .system {
                Label("已运行 \(metrics.uptimeText)", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

private enum DetailSection: String, CaseIterable, Identifiable {
    case tokens
    case system

    var id: String { rawValue }
    var title: String { self == .tokens ? "Token" : "系统与网速" }
    var symbol: String { self == .tokens ? "bolt.fill" : "waveform.path.ecg" }
}

private enum TokenPeriod: Int, CaseIterable, Identifiable {
    case today = 1
    case week = 7
    case month = 30

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .today: "今日"
        case .week: "7 天"
        case .month: "30 天"
        }
    }
}

private struct TokenDashboardView: View {
    @ObservedObject var monitor: TokenUsageMonitor
    @State private var period = TokenPeriod.week
    @State private var quotaLabelWidth: CGFloat = 0

    private var snapshot: TokenUsageSnapshot { monitor.snapshot }
    private var selectedTokens: TokenBreakdown { snapshot.totals(last: period.rawValue) }
    private var selectedAgents: [AgentTokenUsage] { snapshot.agents(last: period.rawValue) }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 14) {
                summaryCards

                if snapshot.days.isEmpty && monitor.isRefreshing && snapshot.quotaProviders.isEmpty {
                    loadingState
                } else {
                    if !snapshot.quotaProviders.isEmpty {
                        accountQuotaSection
                    }

                    if snapshot.last30Days.total == 0 {
                        emptyState
                    } else {
                        periodControl
                        activityStrip
                        breakdown
                        agentList
                    }

                    sourceNote
                }

                if let error = monitor.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 7) {
            TokenStatCard(title: "今日", value: snapshot.today.total.tokenText, detail: "tokens")
            TokenStatCard(title: "7 天", value: snapshot.last7Days.total.tokenText, detail: "累计")
            TokenStatCard(title: "30 天", value: snapshot.last30Days.total.tokenText, detail: "累计")
            TokenStatCard(
                title: "Agents",
                value: "\(snapshot.agents(last: 30).count)",
                detail: "已发现"
            )
        }
    }

    private var periodControl: some View {
        HStack(spacing: 3) {
            Text("Agent 用量")
                .font(.caption.weight(.semibold))

            Spacer()

            ForEach(TokenPeriod.allCases) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        period = item
                    }
                } label: {
                    Text(item.title)
                        .font(.caption2.weight(period == item ? .semibold : .regular))
                        .foregroundStyle(period == item ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            period == item ? Color.primary.opacity(0.09) : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var accountQuotaSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("账户额度")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("已用 · 自动重置")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 0) {
                ForEach(Array(snapshot.quotaProviders.enumerated()), id: \.element.id) { index, provider in
                    ProviderQuotaGroupView(
                        provider: provider,
                        labelColumnWidth: quotaLabelWidth,
                        color: accountColor(provider.canonicalAgent, index: index)
                    )
                    .padding(.vertical, 10)

                    if provider.id != snapshot.quotaProviders.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 11)
            .tokenCard()
        }
        .onPreferenceChange(QuotaLabelWidthKey.self) { width in
            quotaLabelWidth = min(max(quotaLabelWidth, width), 72)
        }
    }

    private var activityStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("最近 30 天", systemImage: "chart.bar.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("峰值 \((snapshot.days.map(\.tokens.total).max() ?? 0).tokenText)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            TokenActivityStrip(days: snapshot.days)
                .frame(height: 42)

            HStack {
                Text("30 天前")
                Spacer()
                Text("今天")
            }
            .font(.system(size: 8))
            .foregroundStyle(.tertiary)
        }
        .padding(11)
        .tokenCard()
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(period.title + "构成")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(selectedTokens.total.tokenText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.indigo)
            }

            HStack(spacing: 6) {
                TokenBreakdownPill(title: "输入", value: selectedTokens.input, color: .blue)
                TokenBreakdownPill(title: "输出", value: selectedTokens.output, color: .mint)
                TokenBreakdownPill(
                    title: "缓存",
                    value: selectedTokens.cacheRead + selectedTokens.cacheWrite,
                    color: .purple
                )
                TokenBreakdownPill(title: "推理", value: selectedTokens.reasoning, color: .orange)
            }
        }
        .padding(11)
        .tokenCard()
    }

    private var agentList: some View {
        VStack(spacing: 0) {
            if selectedAgents.isEmpty {
                Text("这个时间范围内没有 Token 记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                ForEach(Array(selectedAgents.enumerated()), id: \.element.id) { index, agent in
                    AgentUsageGroupView(
                        agent: agent,
                        color: agentColor(agent.agent, index: index),
                        total: selectedTokens.total
                    )
                    .padding(.vertical, 10)

                    if agent.id != selectedAgents.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(.horizontal, 11)
        .tokenCard()
    }

    @ViewBuilder
    private var sourceNote: some View {
        if let note = snapshot.note {
            Text(note)
                .font(.caption2)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
            Text("正在汇总各 Agent 的 Token 用量…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("首次扫描可能需要几秒")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(.secondary)
            Text("还没有找到 Token 记录")
                .font(.headline)
            Text("刷新后会自动汇总本机可用的 Agent 记录。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private func agentColor(_ agent: String, index: Int) -> Color {
        switch agent.lowercased() {
        case "codex": .green
        case "claude": .orange
        case "antigravity": .indigo
        case "gemini": .blue
        case "opencode": .mint
        case "cursor": .purple
        default: [.cyan, .pink, .teal, .yellow][index % 4]
        }
    }

    private func accountColor(_ provider: String, index: Int) -> Color {
        switch provider.lowercased() {
        case "codex": .green
        case "claude": .orange
        case "antigravity": .cyan
        case "gemini": .blue
        case "opencode": .purple
        case "copilot": .indigo
        default: [.mint, .pink, .teal, .yellow][index % 4]
        }
    }
}

private struct TokenStatCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(detail)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tokenCard()
        .accessibilityElement(children: .combine)
    }
}

private struct TokenActivityStrip: View {
    let days: [DailyTokenUsage]

    var body: some View {
        GeometryReader { geometry in
            let maximum = max(days.map(\.tokens.total).max() ?? 0, 1)
            let gap: CGFloat = 2
            let width = max(1, (geometry.size.width - gap * CGFloat(max(days.count - 1, 0))) / CGFloat(max(days.count, 1)))

            HStack(alignment: .bottom, spacing: gap) {
                ForEach(days) { day in
                    let ratio = Double(day.tokens.total) / Double(maximum)
                    RoundedRectangle(cornerRadius: min(width / 2, 2))
                        .fill(
                            day.tokens.total == 0
                                ? Color.primary.opacity(0.06)
                                : Color.indigo.opacity(0.28 + ratio * 0.72)
                        )
                        .frame(width: width, height: max(3, geometry.size.height * CGFloat(ratio)))
                        .help("\(day.dateKey) · \(day.tokens.total.tokenText)")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("最近 30 天 Token 活动")
    }
}

private struct TokenBreakdownPill: View {
    let title: String
    let value: Int64
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                Text(title)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            Text(value.tokenText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .combine)
    }
}

private struct ProviderQuotaGroupView: View {
    let provider: ProviderQuotaUsage
    let labelColumnWidth: CGFloat
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                AgentBrandLogo(agent: provider.canonicalAgent, color: color, size: 14)
                    .frame(width: 14, height: 14)

                Text(provider.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Spacer()
            }

            if !usageWindows.isEmpty {
                VStack(spacing: 5) {
                    ForEach(usageWindows) { window in
                        AccountQuotaRow(
                            window: window,
                            labelColumnWidth: labelColumnWidth
                        )
                    }
                }
            }

            if !resetWindows.isEmpty {
                Text("重置权益")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)

                VStack(spacing: 5) {
                    ForEach(resetWindows) { window in
                        AccountQuotaRow(
                            window: window,
                            labelColumnWidth: labelColumnWidth
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(provider.displayName)
    }

    private var usageWindows: [QuotaWindowUsage] {
        provider.windows.filter { $0.style == .usage }
    }

    private var resetWindows: [QuotaWindowUsage] {
        provider.windows.filter { $0.style == .resetCredit }
    }

}

private struct AccountQuotaRow: View {
    let window: QuotaWindowUsage
    let labelColumnWidth: CGFloat

    private var clampedPercent: Double {
        min(max(window.usedPercent, 0), 100)
    }

    private var resetText: String {
        guard let reset = window.resetsAt else { return "—" }
        let seconds = max(0, reset.timeIntervalSinceNow)
        if seconds >= 24 * 60 * 60 { return "\(Int(seconds / (24 * 60 * 60)))d" }
        if seconds >= 60 * 60 { return "\(Int(seconds / (60 * 60)))h" }
        return "\(max(1, Int(seconds / 60)))m"
    }

    private var expiryText: String {
        guard let reset = window.resetsAt else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MdHm")
        return formatter.string(from: reset)
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(window.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: QuotaLabelWidthKey.self, value: proxy.size.width)
                    }
                )
                .frame(width: labelColumnWidth > 0 ? labelColumnWidth : nil, alignment: .leading)

            AccountQuotaBar(percent: clampedPercent, style: window.style)
                .animation(.easeOut(duration: 0.45), value: clampedPercent)

            if window.style == .resetCredit {
                Text(expiryText)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: 66, alignment: .trailing)
            } else {
                Text("\(Int(clampedPercent.rounded()))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)

                Text(resetText)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: 27, alignment: .trailing)
            }
        }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var helpText: String {
        if window.style == .resetCredit {
            return "\(window.label)：有效期至 \(expiryText)"
        }
        var parts = ["\(window.label)：已用 \(Int(clampedPercent.rounded()))%"]
        if let remaining = window.remainingLabel, !remaining.isEmpty {
            parts.append(remaining)
        }
        if let reset = window.resetsAt {
            parts.append("重置：\(reset.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        if window.style == .resetCredit {
            return "\(window.label)，有效期至 \(expiryText)"
        }
        return "\(window.label)，已用 \(Int(clampedPercent.rounded()))%，\(resetAccessibilityText)"
    }

    private var resetAccessibilityText: String {
        window.resetsAt == nil ? "无重置时间" : "约 \(resetText) 后重置"
    }
}

private struct AccountQuotaBar: View {
    let percent: Double
    let style: QuotaWindowStyle
    var tint: Color? = nil

    private var fillColor: Color {
        if let tint { return tint }
        if style == .resetCredit {
            return Color(red: 0.25, green: 0.75, blue: 0.45)
        }
        switch percent {
        case 80...: return Color(red: 0.90, green: 0.30, blue: 0.30)
        case 60...: return Color(red: 0.94, green: 0.65, blue: 0.20)
        default: return Color(red: 0.25, green: 0.75, blue: 0.45)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let fraction = min(max(percent / 100, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.085))
                Capsule()
                    .fill(fillColor)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

private struct QuotaLabelWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct AgentUsageGroupView: View {
    let agent: AgentTokenUsage
    let color: Color
    let total: Int64

    private var sharePercent: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(agent.tokens.total) / Double(total) * 100, 0), 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                AgentBrandLogo(agent: agent.agent, color: color, size: 15, showsBackground: true)

                Text(agent.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(agent.topModel ?? "未知模型")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 5) {
                Text("用量")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .leading)

                AccountQuotaBar(percent: sharePercent, style: .usage, tint: color)
                    .animation(.easeOut(duration: 0.45), value: sharePercent)

                Text(agent.tokens.total.tokenText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)

                Text("\(Int(sharePercent.rounded()))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(agent.displayName)，\(agent.tokens.total.tokenText) Token，占所选时段 \(Int(sharePercent.rounded()))%"
        )
    }
}

@MainActor
private final class AgentLogoStore {
    static let shared = AgentLogoStore()

    private var cached: [String: NSImage] = [:]
    private var unavailable: Set<String> = []

    func image(for agent: String) -> NSImage? {
        let key = agent.lowercased()
        if let cached = cached[key] { return cached }
        if unavailable.contains(key) { return nil }

        if let image = installedApplicationIcon(for: key) ?? bundledBrandIcon(for: key) {
            cached[key] = image
            return image
        }

        unavailable.insert(key)
        return nil
    }

    private func installedApplicationIcon(for agent: String) -> NSImage? {
        let applicationNames: [String]
        switch agent {
        case "codex": applicationNames = ["Codex", "ChatGPT"]
        case "claude": applicationNames = ["Claude"]
        case "antigravity": applicationNames = ["Antigravity"]
        case "opencode": applicationNames = ["OpenCode"]
        case "cursor": applicationNames = ["Cursor"]
        case "openclaw": applicationNames = ["OpenClaw"]
        case "droid": applicationNames = ["Factory", "Droid"]
        case "kiro": applicationNames = ["Kiro"]
        case "trae": applicationNames = ["Trae"]
        case "zed": applicationNames = ["Zed"]
        default: applicationNames = []
        }

        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]

        for root in roots {
            for name in applicationNames {
                let url = root.appendingPathComponent("\(name).app", isDirectory: true)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                return NSWorkspace.shared.icon(forFile: url.path)
            }
        }
        return nil
    }

    private func bundledBrandIcon(for agent: String) -> NSImage? {
        let resourceName: String
        switch agent {
        case "claude": resourceName = "claude"
        case "gemini", "antigravity": resourceName = "googlegemini"
        case "cursor": resourceName = "cursor"
        case "copilot": resourceName = "githubcopilot"
        case "opencode": resourceName = "opencode"
        case "kimi": resourceName = "moonshotai"
        case "zed": resourceName = "zedindustries"
        default: return nil
        }

        guard
            let url = Bundle.main.url(
                forResource: resourceName,
                withExtension: "svg",
                subdirectory: "AgentLogos"
            ),
            let image = NSImage(contentsOf: url)
        else { return nil }

        image.isTemplate = agent != "opencode"
        return image
    }
}

private struct AgentBrandLogo: View {
    let agent: String
    let color: Color
    let size: CGFloat
    var showsBackground = false

    var body: some View {
        Group {
            if let image = AgentLogoStore.shared.image(for: agent) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(image.isTemplate ? .template : .original)
                    .scaledToFit()
                    .foregroundStyle(color)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.8, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .padding(showsBackground ? 5 : 0)
        .background(
            showsBackground ? color.opacity(0.11) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7)
        )
        .accessibilityHidden(true)
    }

    private var fallbackSymbol: String {
        switch agent.lowercased() {
        case "codex": "chevron.left.forwardslash.chevron.right"
        case "claude": "c.circle.fill"
        case "antigravity": "sparkles"
        case "gemini": "diamond.fill"
        case "opencode": "terminal.fill"
        case "cursor": "cursorarrow.rays"
        case "copilot": "infinity"
        case "openclaw": "pawprint.fill"
        default: "cpu.fill"
        }
    }
}

private extension View {
    func tokenCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.primary.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.5)
                )
        )
    }
}

private struct SpeedValue: View {
    let title: String
    let value: Double
    let color: Color
    let symbol: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                Text(value.speedText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)速度")
        .accessibilityValue(value.speedText)
    }
}

private struct MetricGauge: View {
    let title: String
    let value: Double
    let detail: String
    let color: Color
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.14), lineWidth: 7)

                Circle()
                    .trim(from: 0, to: min(max(value, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(color)
            }
            .frame(width: 54, height: 54)
            .accessibilityLabel(title)
            .accessibilityValue(value.percentText)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value.percentText)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct HistoryChart: View {
    let cpu: [Double]
    let memory: [Double]

    var body: some View {
        Canvas { context, size in
            drawGrid(in: &context, size: size)
            draw(cpu, color: .blue, in: &context, size: size)
            draw(memory, color: .orange, in: &context, size: size)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("最近 3 分钟利用率")
        .accessibilityValue("CPU \(cpu.last?.percentText ?? "0%")，内存 \(memory.last?.percentText ?? "0%")")
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        for ratio in [0.25, 0.5, 0.75] {
            let y = size.height * ratio
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(path, with: .color(.secondary.opacity(0.14)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
    }

    private func draw(
        _ values: [Double],
        color: Color,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard values.count > 1 else { return }

        var path = Path()
        for (index, value) in values.enumerated() {
            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = size.height * (1 - CGFloat(min(max(value, 0), 1)))
            let point = CGPoint(x: x, y: y)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
    }
}

private struct NetworkHistoryChart: View {
    let download: [Double]
    let upload: [Double]

    private var scaleMaximum: Double {
        max(download.max() ?? 0, upload.max() ?? 0, 1_000) * 1.1
    }

    var body: some View {
        Canvas { context, size in
            drawGrid(in: &context, size: size)
            draw(download, color: .cyan, in: &context, size: size)
            draw(upload, color: .purple, in: &context, size: size)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("最近 3 分钟网络速度")
        .accessibilityValue(
            "下载 \(download.last?.speedText ?? "0 B/s")，上传 \(upload.last?.speedText ?? "0 B/s")"
        )
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        for ratio in [0.25, 0.5, 0.75] {
            let y = size.height * ratio
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(
            path,
            with: .color(.secondary.opacity(0.14)),
            style: StrokeStyle(lineWidth: 0.5, dash: [3, 3])
        )
    }

    private func draw(
        _ values: [Double],
        color: Color,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard values.count > 1 else { return }

        var path = Path()
        for (index, value) in values.enumerated() {
            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
            let ratio = min(max(value / scaleMaximum, 0), 1)
            let y = size.height * (1 - CGFloat(ratio))
            let point = CGPoint(x: x, y: y)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }

        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
        )

        if let last = values.last {
            let y = size.height * (1 - CGFloat(min(max(last / scaleMaximum, 0), 1)))
            let marker = CGRect(x: size.width - 2.5, y: y - 2.5, width: 5, height: 5)
            context.fill(Path(ellipseIn: marker), with: .color(color))
        }
    }
}

private struct LegendDot: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DetailLabel: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}
