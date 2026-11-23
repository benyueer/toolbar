import AppKit
import SwiftUI

/// 额度面板共享的静态日期格式化器，彻底消除每次渲染或悬停时重复创建 DateFormatter 实例的高昂开销
@MainActor
private enum QuotaDateFormatters {
    static let exactTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let expiry: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MdHm")
        return formatter
    }()

    static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}

@MainActor
struct SystemDetailsView: View {
    let metrics: SystemMetrics
    @ObservedObject var tokenUsage: TokenUsageMonitor
    @ObservedObject var popoverVisibility: PopoverVisibility
    @State private var selectedSection = DetailSection.tokens

    var body: some View {
        Group {
            if popoverVisibility.isShown {
                content
            } else {
                Color.clear
            }
        }
        .frame(width: 420, height: 680)
    }

    private var content: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Group {
                switch selectedSection {
                case .tokens:
                    TokenDashboardView(monitor: tokenUsage, isVisible: popoverVisibility.isShown)
                case .system:
                    systemDashboard
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()

            footer
        }
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.035),
                    Color.indigo.opacity(0.018),
                    Color.black.opacity(0.045)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var systemDashboard: some View {
        SystemDashboardView(metrics: metrics)
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

            let isRefreshing = (selectedSection == .tokens ? tokenUsage.isRefreshing : false)
            Button {
                metrics.refresh()
                tokenUsage.refresh(forceAntigravitySync: false, forceQuotaRefresh: true)
            } label: {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(isRefreshing)
            .help(isRefreshing ? "正在刷新用量与额度…" : (selectedSection == .tokens ? "立即刷新用量与额度" : "立即刷新系统指标"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            if selectedSection == .system {
                SystemUptimeLabel(metrics: metrics)
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

private struct SystemDashboardView: View {
    @ObservedObject var metrics: SystemMetrics

    var body: some View {
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
        .tokenCard()
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
        let maxScale = networkScaleMaximum
        return VStack(alignment: .leading, spacing: 10) {
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
                    upload: metrics.uploadHistory,
                    scaleMaximum: maxScale
                )

                Text(maxScale.speedText)
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
        .tokenCard()
    }

    private var networkScaleMaximum: Double {
        max(
            metrics.downloadHistory.max() ?? 0,
            metrics.uploadHistory.max() ?? 0,
            1_000
        ) * 1.1
    }
}

private struct SystemUptimeLabel: View {
    @ObservedObject var metrics: SystemMetrics

    var body: some View {
        Label("已运行 \(metrics.uptimeText)", systemImage: "clock")
            .font(.caption)
            .foregroundStyle(.secondary)
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
    let isVisible: Bool
    @State private var period: TokenPeriod? = .today
    @State private var selectedDateKey: String? = nil
    @State private var quotaLabelWidth: CGFloat = 0
    @State private var currentTime = Date()

    private var snapshot: TokenUsageSnapshot { monitor.snapshot }

    /// 当前选中的具体单日对象（O(1) 哈希查找）
    private var activeSelectedDay: DailyTokenUsage? {
        if let key = selectedDateKey {
            return snapshot.day(forKey: key)
        }
        if period == .today {
            return snapshot.days.last
        }
        return nil
    }

    /// 当前激活展示的 Token 构成数据（O(1) 预计算读取）
    private var selectedTokens: TokenBreakdown {
        if let day = activeSelectedDay {
            return day.tokens
        }
        return snapshot.totals(last: period?.rawValue ?? 1)
    }

    /// 当前激活展示的 Agent 用量列表（O(1) 预计算读取）
    private var selectedAgents: [AgentTokenUsage] {
        if let day = activeSelectedDay {
            return day.agents
        }
        return snapshot.agents(last: period?.rawValue ?? 1)
    }

    /// 当前构成卡片的标题
    private var breakdownTitle: String {
        if let day = activeSelectedDay {
            if day.dateKey == snapshot.days.last?.dateKey {
                return "今日构成"
            }
            return "\(formatTokenDateKey(day.dateKey))构成"
        }
        return (period?.title ?? "今日") + "构成"
    }

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
        // 倒计时最小粒度为分钟，使用 30 秒带容差定时器减少弹窗打开时的重绘频率
        .onReceive(Timer.publish(every: 30, tolerance: 5, on: .main, in: .common).autoconnect()) { date in
            guard isVisible else { return }
            currentTime = date
        }
        .onReceive(monitor.$snapshot) { _ in
            guard isVisible else { return }
            currentTime = Date()
        }
    }

    private var summaryCards: some View {
        let todayTotal = snapshot.today.total
        let monthTotal = snapshot.last30Days.total
        return HStack(spacing: 7) {
            TokenStatCard(
                title: "今日 Token",
                value: todayTotal.tokenText,
                detail: "tokens",
                tooltip: "今日总用量：\(todayTotal.formattedWithSeparators) tokens"
            )
            TokenStatCard(
                title: "预估花费",
                value: snapshot.todayEstimatedCost?.estimatedCostText ?? "$0.00",
                detail: "今日预估",
                valueColor: .green
            )
            TokenStatCard(
                title: "30 天",
                value: monthTotal.tokenText,
                detail: "累计",
                tooltip: "30天累计用量：\(monthTotal.formattedWithSeparators) tokens"
            )
            TokenStatCard(
                title: "Agents",
                value: "\(snapshot.agents30Days.count)",
                detail: "已发现"
            )
        }
    }

    private var periodControl: some View {
        let lastDayKey = snapshot.days.last?.dateKey
        return HStack(spacing: 6) {
            Text("Agent 用量")
                .font(.caption.weight(.semibold))

            if monitor.isUsageRefreshing {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("正在刷新…")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            } else if let lastRefresh = monitor.lastUsageRefresh {
                Text("更新于 \(lastRefresh.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            ForEach(TokenPeriod.allCases) { item in
                let isSelected = period == item && (item != .today || selectedDateKey == nil || selectedDateKey == lastDayKey)
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        period = item
                        if item == .today {
                            selectedDateKey = lastDayKey
                        } else {
                            selectedDateKey = nil
                        }
                    }
                } label: {
                    Text(item.title)
                        .font(.caption2.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            isSelected ? Color.primary.opacity(0.09) : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var accountQuotaSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("账户额度")
                    .font(.caption.weight(.semibold))
                if monitor.isQuotaRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                }
                Spacer()
                Text("已用 · 自动重置")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 0) {
                let providers = snapshot.quotaProviders
                let lastProviderId = providers.last?.id
                ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                    ProviderQuotaGroupView(
                        provider: provider,
                        labelColumnWidth: quotaLabelWidth,
                        color: accountColor(provider.canonicalAgent, index: index),
                        currentTime: currentTime
                    )
                    .padding(.vertical, 10)

                    if provider.id != lastProviderId {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 11)
            .tokenCard()
        }
        .onPreferenceChange(QuotaLabelWidthKey.self) { width in
            let clamped = min(max(quotaLabelWidth, width), 72)
            if abs(clamped - quotaLabelWidth) > 0.5 {
                quotaLabelWidth = clamped
            }
        }
    }

    private var activityStrip: some View {
        let currentDay = activeSelectedDay
        let lastDayKey = snapshot.days.last?.dateKey
        let maxTokens = snapshot.maxDailyTokens
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("最近 30 天", systemImage: "chart.bar.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                if let day = currentDay, day.dateKey != lastDayKey {
                    Text("· 已选 \(formatTokenDateKey(day.dateKey))")
                        .font(.caption2)
                        .foregroundStyle(.cyan)
                }

                Spacer()
                Text("峰值 \(maxTokens.tokenText)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            TokenActivityStrip(
                days: snapshot.days,
                maxTokens: max(maxTokens, 1),
                selectedDateKey: currentDay?.dateKey
            ) { day in
                withAnimation(.easeOut(duration: 0.16)) {
                    if selectedDateKey == day.dateKey && day.dateKey != lastDayKey {
                        // 再次点击已选中的非今日柱子，重置切回今日
                        selectedDateKey = lastDayKey
                        period = .today
                    } else {
                        selectedDateKey = day.dateKey
                        if day.dateKey == lastDayKey {
                            period = .today
                        } else {
                            period = nil
                        }
                    }
                }
            }
            .frame(height: 42)
            .zIndex(1)

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
        let tokens = selectedTokens
        let currentDay = activeSelectedDay
        let lastDayKey = snapshot.days.last?.dateKey
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(breakdownTitle)
                    .font(.caption.weight(.semibold))

                if let day = currentDay, day.dateKey != lastDayKey {
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            selectedDateKey = lastDayKey
                            period = .today
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 8))
                            Text("返回今日")
                                .font(.system(size: 9))
                        }
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.indigo.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
                Text(tokens.total.tokenText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.indigo)
            }

            HStack(spacing: 6) {
                TokenBreakdownPill(title: "输入", value: tokens.input, color: .blue)
                TokenBreakdownPill(title: "输出", value: tokens.output, color: .mint)
                TokenBreakdownPill(
                    title: "缓存",
                    value: tokens.cacheRead + tokens.cacheWrite,
                    color: .purple
                )
                TokenBreakdownPill(title: "推理", value: tokens.reasoning, color: .orange)
            }
        }
        .padding(11)
        .tokenCard()
    }

    private var agentList: some View {
        let agents = selectedAgents
        let totalTokens = selectedTokens.total
        let currentDay = activeSelectedDay
        return VStack(spacing: 0) {
            if agents.isEmpty {
                Text("这个时间范围内没有 Token 记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                let lastAgentId = agents.last?.id
                ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
                    AgentUsageGroupView(
                        agent: agent,
                        color: agentColor(agent.agent, index: index),
                        total: totalTokens
                    )
                    .padding(.vertical, 10)

                    if agent.id != lastAgentId {
                        Divider()
                    }
                }

                if let day = currentDay {
                    let currentAgentKeys = Set(agents.map(\.agent))
                    let inactiveAgents = snapshot.agents30Days.compactMap { item in
                        currentAgentKeys.contains(item.agent) ? nil : item.displayName
                    }
                    if !inactiveAgents.isEmpty {
                        Divider()
                        HStack(spacing: 5) {
                            let label = (day.dateKey == snapshot.days.last?.dateKey) ? "今日无消耗:" : "当日无消耗:"
                            Text(label)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.tertiary)
                            Text(inactiveAgents.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        case "agy-cli", "antigravity-cli", "agy": .cyan
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
        case "agy-cli", "antigravity-cli", "agy": .teal
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
    var valueColor: Color = .primary
    var tooltip: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)
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
        .help(tooltip ?? "\(title): \(value)")
        .accessibilityElement(children: .combine)
    }
}

/// 格式化形如 "2026-10-29" 的日期字符串为 "10月29日"
private func formatTokenDateKey(_ key: String) -> String {
    let parts = key.split(separator: "-")
    if parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) {
        return "\(month)月\(day)日"
    }
    return key
}

private struct TokenActivityStrip: View {
    let days: [DailyTokenUsage]
    let maxTokens: Int64
    var selectedDateKey: String? = nil
    var onSelectDay: ((DailyTokenUsage) -> Void)? = nil

    @State private var hoveredDay: DailyTokenUsage? = nil
    @State private var hoveredIndex: Int? = nil

    var body: some View {
        GeometryReader { geometry in
            let maximum = Double(max(maxTokens, 1))
            let gap: CGFloat = 2
            let totalGap = gap * CGFloat(max(days.count - 1, 0))
            let width = max(1, (geometry.size.width - totalGap) / CGFloat(max(days.count, 1)))

            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        let ratio = Double(day.tokens.total) / maximum
                        let isHovered = hoveredDay?.id == day.id
                        let isSelected = selectedDateKey == day.dateKey

                        ZStack(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())

                            RoundedRectangle(cornerRadius: min(width / 2, 2))
                                .fill(
                                    isSelected
                                        ? (day.tokens.total == 0 ? Color.cyan.opacity(0.45) : Color.cyan)
                                        : (day.tokens.total == 0
                                            ? (isHovered ? Color.primary.opacity(0.18) : Color.primary.opacity(0.06))
                                            : (isHovered ? Color.indigo : Color.indigo.opacity(0.28 + ratio * 0.72)))
                                )
                                .frame(width: width, height: max(3, geometry.size.height * CGFloat(ratio)))
                        }
                        .frame(width: width, height: geometry.size.height)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectDay?(day)
                        }
                        .onHover { hovering in
                            if hovering {
                                hoveredDay = day
                                hoveredIndex = index
                            } else if hoveredDay?.id == day.id {
                                hoveredDay = nil
                                hoveredIndex = nil
                            }
                        }
                        .help("\(day.dateKey) · \(day.tokens.total.tokenText)")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                if let day = hoveredDay, let index = hoveredIndex {
                    let barCenterX = CGFloat(index) * (width + gap) + width / 2
                    let tooltipWidth: CGFloat = 110
                    let halfTooltip = tooltipWidth / 2
                    let clampedX = min(max(barCenterX, halfTooltip), geometry.size.width - halfTooltip)

                    VStack(spacing: 2) {
                        Text(formatTokenDateKey(day.dateKey))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 3) {
                            Text(day.tokens.total.tokenText)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.primary)

                            Text("tokens")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }

                        if let cost = day.estimatedCost, cost > 0 {
                            Text("预估 $\(String(format: "%.3f", cost))")
                                .font(.system(size: 8))
                                .foregroundStyle(.green)
                        }

                        Text(selectedDateKey == day.dateKey ? "已选中" : "点击查看当日")
                            .font(.system(size: 7.5))
                            .foregroundStyle(selectedDateKey == day.dateKey ? Color.cyan : Color.secondary)
                            .padding(.top, 1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.16), radius: 3, x: 0, y: 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                            )
                    )
                    .position(x: clampedX, y: -16)
                    .allowsHitTesting(false)
                    .animation(.spring(response: 0.18, dampingFraction: 0.8), value: hoveredIndex)
                }
            }
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
        .help("\(title)：\(value.formattedWithSeparators) tokens")
        .accessibilityElement(children: .combine)
    }
}

private struct ProviderQuotaGroupView: View {
    let provider: ProviderQuotaUsage
    let labelColumnWidth: CGFloat
    let color: Color
    let currentTime: Date

    var body: some View {
        let usageList = usageWindows
        let resetList = resetWindows
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                AgentBrandLogo(agent: provider.canonicalAgent, color: color, size: 14)
                    .frame(width: 14, height: 14)

                Text(provider.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Spacer()
            }

            if !usageList.isEmpty {
                VStack(spacing: 5) {
                    ForEach(usageList) { window in
                        AccountQuotaRow(
                            window: window,
                            labelColumnWidth: labelColumnWidth,
                            currentTime: currentTime
                        )
                    }
                }
            }

            if !resetList.isEmpty {
                Text("重置权益")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)

                VStack(spacing: 5) {
                    ForEach(resetList) { window in
                        AccountQuotaRow(
                            window: window,
                            labelColumnWidth: labelColumnWidth,
                            currentTime: currentTime
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
    let currentTime: Date

    @State private var isHoveringResetTime = false
    @State private var isPinnedExactTime = false

    private var clampedPercent: Double {
        min(max(window.usedPercent, 0), 100)
    }

    /// 倒计时文本（具体到分钟）
    private var resetCountdownText: String {
        guard let reset = window.resetsAt else { return "—" }
        let seconds = max(0, reset.timeIntervalSince(currentTime))
        if seconds <= 0 {
            return "<1m"
        }
        let totalMinutes = Int(seconds / 60)
        if totalMinutes < 1 {
            return "<1m"
        }
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }
        let totalHours = totalMinutes / 60
        if totalHours < 24 {
            let mins = totalMinutes % 60
            if mins == 0 {
                return "\(totalHours)h"
            }
            return "\(totalHours)h \(mins)m"
        }
        let days = totalHours / 24
        let remainingHours = totalHours % 24
        if remainingHours == 0 {
            return "\(days)d"
        }
        return "\(days)d \(remainingHours)h"
    }

    /// 目标刷新时间点（复用共享静态 DateFormatter）
    private var exactTimeText: String {
        guard let reset = window.resetsAt else { return "—" }
        return QuotaDateFormatters.exactTime.string(from: reset)
    }

    /// 当前显示的刷新时间文本
    private var displayResetText: String {
        guard window.resetsAt != nil else { return "—" }
        if isPinnedExactTime {
            return isHoveringResetTime ? resetCountdownText : exactTimeText
        } else {
            return isHoveringResetTime ? exactTimeText : resetCountdownText
        }
    }

    private var expiryText: String {
        guard let reset = window.resetsAt else { return "—" }
        return QuotaDateFormatters.expiry.string(from: reset)
    }

    /// 刷新时间的悬浮提示（复用共享静态 DateFormatter）
    private var resetTooltipText: String {
        guard let reset = window.resetsAt else { return "无重置时间" }
        let calendar = Calendar.current
        let datePart: String
        if calendar.isDateInToday(reset) {
            datePart = "今天"
        } else if calendar.isDateInTomorrow(reset) {
            datePart = "明天"
        } else {
            datePart = QuotaDateFormatters.monthDay.string(from: reset)
        }

        let timePart = QuotaDateFormatters.exactTime.string(from: reset)
        let seconds = max(0, reset.timeIntervalSince(currentTime))
        let totalMinutes = Int(seconds / 60)
        let relativeDesc: String
        if totalMinutes < 1 {
            relativeDesc = "即将重置"
        } else if totalMinutes < 60 {
            relativeDesc = "约 \(totalMinutes) 分钟后"
        } else if totalMinutes < 1440 {
            let h = totalMinutes / 60
            let m = totalMinutes % 60
            relativeDesc = m > 0 ? "约 \(h) 小时 \(m) 分钟后" : "约 \(h) 小时后"
        } else {
            let d = totalMinutes / 1440
            let h = (totalMinutes % 1440) / 60
            let m = totalMinutes % 60
            if h > 0 {
                relativeDesc = "约 \(d) 天 \(h) 小时后"
            } else if m > 0 {
                relativeDesc = "约 \(d) 天 \(m) 分钟后"
            } else {
                relativeDesc = "约 \(d) 天后"
            }
        }

        return "重置时间：\(datePart) \(timePart)（\(relativeDesc)）"
    }

    var body: some View {
        let roundedPercent = Int(clampedPercent.rounded())
        let tooltip = resetTooltipText
        return HStack(spacing: 5) {
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
                let exp = expiryText
                Text(exp)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: 87, alignment: .trailing)
                    .help("\(window.label)：有效期至 \(exp)")
            } else {
                Text("\(roundedPercent)%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)

                Text(displayResetText)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(isHoveringResetTime || isPinnedExactTime ? .primary : .tertiary)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(
                        isHoveringResetTime
                            ? Color.primary.opacity(0.08)
                            : (isPinnedExactTime ? Color.primary.opacity(0.04) : Color.clear),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .frame(width: 48, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isHoveringResetTime = hovering
                        }
                    }
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isPinnedExactTime.toggle()
                        }
                    }
                    .help(tooltip)
            }
        }
        .help(makeHelpText(roundedPercent: roundedPercent, resetTooltip: tooltip))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(makeAccessibilityText(roundedPercent: roundedPercent))
    }

    private func makeHelpText(roundedPercent: Int, resetTooltip: String) -> String {
        if window.style == .resetCredit {
            return "\(window.label)：有效期至 \(expiryText)"
        }
        var parts = ["\(window.label)：已用 \(roundedPercent)%"]
        if let remaining = window.remainingLabel, !remaining.isEmpty {
            parts.append(remaining)
        }
        if window.resetsAt != nil {
            parts.append(resetTooltip)
        }
        return parts.joined(separator: " · ")
    }

    private func makeAccessibilityText(roundedPercent: Int) -> String {
        if window.style == .resetCredit {
            return "\(window.label)，有效期至 \(expiryText)"
        }
        let resetDesc = window.resetsAt != nil
            ? "重置时间 \(exactTimeText)，约 \(resetCountdownText) 后"
            : "无重置时间"
        return "\(window.label)，已用 \(roundedPercent)%，\(resetDesc)"
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
    @State private var showModels = false
    let agent: AgentTokenUsage
    let color: Color
    let total: Int64

    private var sharePercent: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(agent.tokens.total) / Double(total) * 100, 0), 100)
    }

    private var detailedHelpText: String {
        let totalFormatted = agent.tokens.total.formattedWithSeparators
        let inFormatted = agent.tokens.input.formattedWithSeparators
        let outFormatted = agent.tokens.output.formattedWithSeparators
        let cacheFormatted = (agent.tokens.cacheRead + agent.tokens.cacheWrite).formattedWithSeparators
        let reasoningFormatted = agent.tokens.reasoning.formattedWithSeparators
        let costPart = agent.estimatedCost.map { " · 预估 \($0.estimatedCostText)" } ?? ""
        return "\(agent.displayName)：\(totalFormatted) tokens (输入: \(inFormatted) · 输出: \(outFormatted) · 缓存: \(cacheFormatted) · 推理: \(reasoningFormatted)) · 占所选时段 \(Int(sharePercent.rounded()))%\(costPart)"
    }

    var body: some View {
        let percent = sharePercent
        let roundedPercent = Int(percent.rounded())
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                guard !agent.models.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    showModels.toggle()
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        AgentBrandLogo(agent: agent.agent, color: color, size: 15, showsBackground: true)

                        Text(agent.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        if !agent.models.isEmpty {
                            Text("\(agent.models.count) 个模型")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)

                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(showModels ? 180 : 0))
                        }
                    }

                    HStack(spacing: 5) {
                        Text("用量")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .leading)

                        AccountQuotaBar(percent: percent, style: .usage, tint: color)
                            .animation(.easeOut(duration: 0.45), value: percent)

                        Text(agent.tokens.total.tokenText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)

                        Text("\(roundedPercent)%")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(detailedHelpText)
            .accessibilityLabel(
                "\(agent.displayName)，\(agent.tokens.total.tokenText) Token，占所选时段 \(roundedPercent)%"
            )
            .accessibilityHint(agent.models.isEmpty ? "没有模型明细" : "展开或收起模型明细")

            if showModels, !agent.models.isEmpty {
                ModelBreakdownList(models: agent.models, total: agent.tokens.total, color: color)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ModelBreakdownList: View {
    let models: [ModelTokenUsage]
    let total: Int64
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            ForEach(models) { model in
                ModelUsageRow(model: model, total: total, color: color)
            }
        }
        .padding(.top, 2)
        .padding(.leading, 22)
    }
}

private struct ModelUsageRow: View {
    let model: ModelTokenUsage
    let total: Int64
    let color: Color

    private var sharePercent: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(model.tokens.total) / Double(total) * 100, 0), 100)
    }

    private var detailedHelpText: String {
        let totalFormatted = model.tokens.total.formattedWithSeparators
        let inFormatted = model.tokens.input.formattedWithSeparators
        let outFormatted = model.tokens.output.formattedWithSeparators
        let cacheFormatted = (model.tokens.cacheRead + model.tokens.cacheWrite).formattedWithSeparators
        let reasoningFormatted = model.tokens.reasoning.formattedWithSeparators
        return "\(model.name)：\(totalFormatted) tokens (输入: \(inFormatted) · 输出: \(outFormatted) · 缓存: \(cacheFormatted) · 推理: \(reasoningFormatted)) · 占该 Agent \(Int(sharePercent.rounded()))%"
    }

    var body: some View {
        let percent = sharePercent
        let roundedPercent = Int(percent.rounded())
        return HStack(spacing: 5) {
            Text(model.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 112, alignment: .leading)

            AccountQuotaBar(percent: percent, style: .usage, tint: color.opacity(0.8))
                .animation(.easeOut(duration: 0.45), value: percent)

            Text(model.tokens.total.tokenText)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)

            Text("\(roundedPercent)%")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 34, alignment: .trailing)
        }
        .help(detailedHelpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(model.name)，\(model.tokens.total.tokenText) Token，占该 Agent \(roundedPercent)%"
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

        let image: NSImage?
        if key == "antigravity" || key == "agy-cli" || key == "agy" || key == "antigravity-cli" {
            image = bundledBrandIcon(for: "antigravity") ?? installedApplicationIcon(for: "antigravity")
        } else {
            image = installedApplicationIcon(for: key) ?? bundledBrandIcon(for: key)
        }

        if let image {
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
        let resourceExtension: String
        switch agent {
        case "claude": resourceName = "claude"; resourceExtension = "svg"
        case "gemini": resourceName = "googlegemini"; resourceExtension = "svg"
        case "antigravity": resourceName = "antigravity"; resourceExtension = "icns"
        case "cursor": resourceName = "cursor"; resourceExtension = "svg"
        case "copilot": resourceName = "githubcopilot"; resourceExtension = "svg"
        case "opencode": resourceName = "opencode"; resourceExtension = "svg"
        case "kimi": resourceName = "moonshotai"; resourceExtension = "svg"
        case "zed": resourceName = "zedindustries"; resourceExtension = "svg"
        default: return nil
        }

        guard
            let url = Bundle.main.url(
                forResource: resourceName,
                withExtension: resourceExtension,
                subdirectory: "AgentLogos"
            ),
            let image = NSImage(contentsOf: url)
        else { return nil }

        image.isTemplate = resourceExtension == "svg" && agent != "opencode"
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
        case "agy-cli", "antigravity-cli", "agy": "terminal.fill"
        case "gemini": "diamond.fill"
        case "opencode": "terminal.fill"
        case "cursor": "cursorarrow.rays"
        case "copilot": "infinity"
        case "openclaw": "pawprint.fill"
        default: "cpu.fill"
        }
    }
}

/// 轻量级卡片容器修饰符：由于 NSPopover 窗口自身已具备系统毛玻璃背景，
/// 避免在每个卡片上重复创建独立的 NSVisualEffectView (.ultraThinMaterial) 与双重动态高斯阴影，显著降低 GPU 离屏合成负载。
private extension View {
    func tokenCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.055),
                            Color.primary.opacity(0.03),
                            Color.black.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.32),
                                    Color.white.opacity(0.10),
                                    Color.indigo.opacity(0.18),
                                    Color.primary.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )
                .shadow(color: Color.black.opacity(0.10), radius: 5, x: 0, y: 2)
        )
    }
}

private struct SpeedValue: View {
    let title: String
    let value: Double
    let color: Color
    let symbol: String

    var body: some View {
        let formattedSpeed = value.speedText
        return HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                Text(formattedSpeed)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)速度")
        .accessibilityValue(formattedSpeed)
    }
}

private struct MetricGauge: View {
    let title: String
    let value: Double
    let detail: String
    let color: Color
    let systemImage: String

    var body: some View {
        let formattedPercent = value.percentText
        return HStack(spacing: 12) {
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
            .accessibilityValue(formattedPercent)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formattedPercent)
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
    @State private var hoverLocation: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawGrid(in: &context, size: size)
                    draw(cpu, color: .blue, in: &context, size: size)
                    draw(memory, color: .orange, in: &context, size: size)
                    if let location = hoverLocation {
                        drawHoverIndicator(at: location, in: &context, size: size)
                    }
                }

                if let location = hoverLocation, let index = sampleIndex(at: location.x, width: geometry.size.width) {
                    let cpuVal = cpu.indices.contains(index) ? cpu[index] : 0
                    let memVal = memory.indices.contains(index) ? memory[index] : 0
                    let secondsAgo = (cpu.count - 1 - index)
                    let timeText = secondsAgo == 0 ? "现在" : "\(secondsAgo)s 前"

                    HStack(spacing: 6) {
                        Text(timeText)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text("CPU \(cpuVal.percentText)")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.blue)
                        Text("内存 \(memVal.percentText)")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                    .shadow(radius: 2)
                    .position(
                        x: min(max(location.x, 70), geometry.size.width - 70),
                        y: 12
                    )
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverLocation = location
                case .ended:
                    hoverLocation = nil
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("最近 3 分钟利用率")
        .accessibilityValue("CPU \(cpu.last?.percentText ?? "0%")，内存 \(memory.last?.percentText ?? "0%")")
    }

    private func sampleIndex(at x: CGFloat, width: CGFloat) -> Int? {
        guard width > 0, !cpu.isEmpty else { return nil }
        let ratio = max(0, min(1, x / width))
        return Int((ratio * CGFloat(cpu.count - 1)).rounded())
    }

    private func drawHoverIndicator(at location: CGPoint, in context: inout GraphicsContext, size: CGSize) {
        var line = Path()
        line.move(to: CGPoint(x: location.x, y: 0))
        line.addLine(to: CGPoint(x: location.x, y: size.height))
        context.stroke(line, with: .color(.primary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
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
        let countMinusOne = CGFloat(values.count - 1)
        for (index, value) in values.enumerated() {
            let x = size.width * CGFloat(index) / countMinusOne
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
    let scaleMaximum: Double
    @State private var hoverLocation: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawGrid(in: &context, size: size)
                    draw(download, color: .cyan, in: &context, size: size)
                    draw(upload, color: .purple, in: &context, size: size)
                    if let location = hoverLocation {
                        drawHoverIndicator(at: location, in: &context, size: size)
                    }
                }

                if let location = hoverLocation, let index = sampleIndex(at: location.x, width: geometry.size.width) {
                    let dlVal = download.indices.contains(index) ? download[index] : 0
                    let ulVal = upload.indices.contains(index) ? upload[index] : 0
                    let secondsAgo = (download.count - 1 - index)
                    let timeText = secondsAgo == 0 ? "现在" : "\(secondsAgo)s 前"

                    HStack(spacing: 6) {
                        Text(timeText)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text("↓ \(dlVal.speedText)")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.cyan)
                        Text("↑ \(ulVal.speedText)")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.purple)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                    .shadow(radius: 2)
                    .position(
                        x: min(max(location.x, 70), geometry.size.width - 70),
                        y: 12
                    )
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverLocation = location
                case .ended:
                    hoverLocation = nil
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("最近 3 分钟网络速度")
        .accessibilityValue(
            "下载 \(download.last?.speedText ?? "0 B/s")，上传 \(upload.last?.speedText ?? "0 B/s")"
        )
    }

    private func sampleIndex(at x: CGFloat, width: CGFloat) -> Int? {
        guard width > 0, !download.isEmpty else { return nil }
        let ratio = max(0, min(1, x / width))
        return Int((ratio * CGFloat(download.count - 1)).rounded())
    }

    private func drawHoverIndicator(at location: CGPoint, in context: inout GraphicsContext, size: CGSize) {
        var line = Path()
        line.move(to: CGPoint(x: location.x, y: 0))
        line.addLine(to: CGPoint(x: location.x, y: size.height))
        context.stroke(line, with: .color(.primary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
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

        // 在循环外提取常量，避免在 180 次循环内部重复遍历数组求 max() 的 O(N²) 性能陷阱
        let maxVal = max(scaleMaximum, 1)
        let countMinusOne = CGFloat(values.count - 1)
        var path = Path()

        for (index, value) in values.enumerated() {
            let x = size.width * CGFloat(index) / countMinusOne
            let ratio = min(max(value / maxVal, 0), 1)
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
            let y = size.height * (1 - CGFloat(min(max(last / maxVal, 0), 1)))
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
