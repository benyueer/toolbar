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

    static let exactTimeWithSeconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "HH:mm:ss"
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
    @Namespace private var sectionTabNamespace
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if popoverVisibility.isShown {
                content
            } else {
                Color.clear
            }
        }
        .frame(width: 432, height: 696)
    }

    private var content: some View {
        VStack(spacing: 0) {
            header

            subtleDivider

            Group {
                switch selectedSection {
                case .tokens:
                    TokenDashboardView(monitor: tokenUsage, isVisible: popoverVisibility.isShown)
                        .transition(.opacity)
                case .system:
                    SystemDashboardView(metrics: metrics)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.easeInOut(duration: 0.16), value: selectedSection)

            subtleDivider

            footer
        }
        .background(backgroundBackdrop)
        .background(keyboardShortcuts)
    }

    /// 适配深浅色模式的柔和氛围渐变底，轻量且不额外创建 NSVisualEffectView
    private var backgroundBackdrop: some View {
        let accentTint = selectedSection == .tokens ? Color.indigo : Color.cyan
        return LinearGradient(
            colors: colorScheme == .dark
                ? [
                    accentTint.opacity(0.055),
                    Color.white.opacity(0.015),
                    Color.black.opacity(0.08)
                ]
                : [
                    accentTint.opacity(0.045),
                    Color.white.opacity(0.18),
                    Color.black.opacity(0.025)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var subtleDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.08))
            .frame(height: 0.5)
    }

    /// 隐藏快捷键绑定：⌘R 刷新、⌘1/⌘2 快速切换面板
    private var keyboardShortcuts: some View {
        ZStack {
            Button("") {
                triggerRefresh()
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("") {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                    selectedSection = .tokens
                }
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("") {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                    selectedSection = .system
                }
            }
            .keyboardShortcut("2", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func triggerRefresh() {
        metrics.refresh()
        if !tokenUsage.isRefreshing {
            tokenUsage.refresh(forceAntigravitySync: false, forceQuotaRefresh: true)
        }
    }

    private var headerSubtitle: String {
        if selectedSection == .system {
            return "每秒实时采样"
        }
        if tokenUsage.isUsageRefreshing {
            return "正在同步用量…"
        }
        if tokenUsage.isQuotaRefreshing {
            return "正在刷新额度…"
        }
        if let lastRefresh = tokenUsage.lastUsageRefresh {
            return "更新于 \(QuotaDateFormatters.exactTimeWithSeconds.string(from: lastRefresh))"
        }
        return "消耗 3 分钟 · 额度 10 分钟"
    }

    private var header: some View {
        let isTokens = selectedSection == .tokens
        let accentColor: Color = isTokens ? .indigo : .cyan
        let isRefreshing = isTokens ? tokenUsage.isRefreshing : false

        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.24), accentColor.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(accentColor.opacity(0.28), lineWidth: 0.75)
                    )

                Image(systemName: selectedSection.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 32, height: 32)
            .animation(.easeInOut(duration: 0.2), value: selectedSection)

            VStack(alignment: .leading, spacing: 1.5) {
                Text(isTokens ? "Token 用量" : "系统与网速")
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.72)
                            .frame(width: 10, height: 10)
                    } else {
                        Circle()
                            .fill(isTokens ? Color.green.opacity(0.85) : Color.cyan.opacity(0.85))
                            .frame(width: 5, height: 5)
                    }
                    Text(headerSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            SlidingSectionPicker(
                selection: $selectedSection,
                namespace: sectionTabNamespace
            )

            HeaderRefreshButton(isRefreshing: isRefreshing) {
                triggerRefresh()
            }
            .help(
                isRefreshing
                    ? "正在刷新用量与额度…"
                    : (isTokens ? "立即刷新用量与额度 (⌘R)" : "立即刷新系统指标 (⌘R)")
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if selectedSection == .system {
                SystemUptimeLabel(metrics: metrics)
            } else {
                HStack(spacing: 5) {
                    Circle()
                        .fill(tokenUsage.snapshot.source == .embeddedCollector ? Color.green.opacity(0.8) : Color.orange.opacity(0.85))
                        .frame(width: 5.5, height: 5.5)
                    Text(tokenUsage.snapshot.source.label)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                    Text("⌘R 刷新")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .help("快捷键：⌘R 刷新用量与额度 · ⌘1/⌘2 切换视图 · 右键状态栏图标打开快捷菜单")
            }

            Spacer()

            FooterQuitButton {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

/// 自定义滑动胶囊顶栏分段切换器
private struct SlidingSectionPicker: View {
    @Binding var selection: DetailSection
    let namespace: Namespace.ID
    @State private var hoveredSection: DetailSection? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DetailSection.allCases) { section in
                let isSelected = selection == section
                let isHovered = hoveredSection == section

                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                        selection = section
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(section.shortTitle)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    }
                    .foregroundStyle(
                        isSelected
                            ? Color.primary
                            : (isHovered ? Color.primary.opacity(0.85) : Color.secondary)
                    )
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background {
                        tabBackground(isSelected: isSelected, isHovered: isHovered)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredSection = hovering ? section : (hoveredSection == section ? nil : hoveredSection)
                }
            }
        }
        .padding(2.5)
        .background(
            Capsule()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private func tabBackground(isSelected: Bool, isHovered: Bool) -> some View {
        if isSelected {
            let isDark = colorScheme == .dark
            Capsule()
                .fill(isDark ? Color.white.opacity(0.14) : Color.white.opacity(0.88))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            Color.white.opacity(isDark ? 0.16 : 0.9),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: Color.black.opacity(isDark ? 0.22 : 0.08), radius: 2, y: 1)
                .matchedGeometryEffect(id: "ActiveSectionTab", in: namespace)
        } else if isHovered {
            Capsule()
                .fill(Color.primary.opacity(0.05))
        }
    }
}

/// 顶栏刷新图标按钮（带悬停胶囊反馈）
private struct HeaderRefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void
    @State private var isHovered = false
    @State private var spinCount: Int = 0

    var body: some View {
        Button {
            spinCount += 1
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(isHovered && !isRefreshing ? Color.primary.opacity(0.09) : Color.primary.opacity(0.04))
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(isHovered ? 0.12 : 0.05), lineWidth: 0.5)
                    )

                if isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.82)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(isHovered ? .primary : .secondary)
                        .rotationEffect(.degrees(Double(spinCount) * 360))
                        .animation(.easeOut(duration: 0.45), value: spinCount)
                }
            }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
    }
}

/// 底栏退出按钮（带悬停微红反馈）
private struct FooterQuitButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "power")
                    .font(.system(size: 9.5, weight: .semibold))
                Text("退出")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isHovered ? Color.red : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                Capsule()
                    .fill(isHovered ? Color.red.opacity(0.12) : Color.clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - 系统与网速面板

private struct SystemDashboardView: View {
    @ObservedObject var metrics: SystemMetrics

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                gauges
                history
                networkHistory
                detailRows
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var gauges: some View {
        HStack(spacing: 10) {
            MetricGauge(
                title: "CPU",
                value: metrics.cpu.total,
                detail: "\(metrics.processorDescription) · 系统 \(metrics.cpu.system.percentText)",
                color: .blue,
                secondaryColor: .cyan,
                systemImage: "cpu"
            )

            MetricGauge(
                title: "内存",
                value: metrics.memory.utilization,
                detail: "已用 \(metrics.memory.used.byteText)",
                color: .orange,
                secondaryColor: .pink,
                systemImage: "memorychip"
            )
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("最近 3 分钟利用率", systemImage: "chart.xyaxis.line")
                    .font(.caption.weight(.semibold))
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
            .frame(height: 76)

            HStack {
                Text("3 分钟前")
                Spacer()
                Text("现在")
            }
            .font(.system(size: 8.5))
            .foregroundStyle(.tertiary)
        }
        .padding(12)
        .tokenCard()
    }

    private var networkHistory: some View {
        let maxScale = networkScaleMaximum
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("实时网速", systemImage: "network")
                    .font(.caption.weight(.semibold))
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

                Text("峰值 \(maxScale.speedText)")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.05), in: Capsule())
                    .padding(.top, 2)
            }
            .frame(height: 82)

            HStack {
                Text("3 分钟前")
                Spacer()
                Text("现在")
            }
            .font(.system(size: 8.5))
            .foregroundStyle(.tertiary)
        }
        .padding(12)
        .tokenCard()
    }

    private var detailRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("硬件与内存明细", systemImage: "memorychip")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    DetailLabel(title: "CPU 用户", value: metrics.cpu.user.percentText, dotColor: .blue)
                    DetailLabel(title: "CPU 空闲", value: metrics.cpu.idle.percentText, dotColor: .secondary)
                }
                Divider().opacity(0.45)
                HStack(spacing: 16) {
                    DetailLabel(title: "可用内存", value: metrics.memory.available.byteText, dotColor: .green)
                    DetailLabel(title: "压缩内存", value: metrics.memory.compressed.byteText, dotColor: .orange)
                }
                Divider().opacity(0.45)
                HStack(spacing: 16) {
                    DetailLabel(title: "内存总量", value: metrics.memory.total.byteText, dotColor: .indigo)
                    DetailLabel(title: "交换空间", value: metrics.memory.swapUsed.byteText, dotColor: .purple)
                }
            }
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
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.cyan)
            Text("已运行 \(metrics.uptimeText)")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private enum DetailSection: String, CaseIterable, Identifiable {
    case tokens
    case system

    var id: String { rawValue }
    var title: String { self == .tokens ? "Token" : "系统与网速" }
    var shortTitle: String { self == .tokens ? "Token" : "系统" }
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

private enum TokenBreakdownKind: String, CaseIterable, Identifiable {
    case input
    case output
    case cache
    case reasoning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .input: "输入"
        case .output: "输出"
        case .cache: "缓存"
        case .reasoning: "推理"
        }
    }

    var color: Color {
        switch self {
        case .input: .blue
        case .output: .mint
        case .cache: .purple
        case .reasoning: .orange
        }
    }

    func value(in tokens: TokenBreakdown) -> Int64 {
        switch self {
        case .input: tokens.input
        case .output: tokens.output
        case .cache: tokens.cacheRead + tokens.cacheWrite
        case .reasoning: tokens.reasoning
        }
    }
}

// MARK: - Token 仪表盘

private struct TokenDashboardView: View {
    @ObservedObject var monitor: TokenUsageMonitor
    let isVisible: Bool

    @State private var period: TokenPeriod? = .today
    @State private var selectedDateKey: String? = nil
    @State private var hoveredActivityDay: DailyTokenUsage? = nil
    @State private var hoveredBreakdownKind: TokenBreakdownKind? = nil
    @State private var quotaLabelWidth: CGFloat = 0
    @State private var currentTime = Date()
    @AppStorage("QuotaDisplayRemainingMode") private var showRemainingQuota = false
    @AppStorage("AgentUsageChartStyle") private var agentChartStyleRaw = AgentChartStyle.treemap.rawValue
    @Namespace private var periodNamespace

    private var agentChartStyle: AgentChartStyle {
        AgentChartStyle(rawValue: agentChartStyleRaw) ?? .treemap
    }

    private var agentChartStyleBinding: Binding<AgentChartStyle> {
        Binding(
            get: { AgentChartStyle(rawValue: agentChartStyleRaw) ?? .treemap },
            set: { agentChartStyleRaw = $0.rawValue }
        )
    }

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

    /// 当前激活展示的预估花费（O(1) 预计算读取）
    private var selectedEstimatedCost: Double? {
        if let day = activeSelectedDay {
            return day.estimatedCost
        }
        return snapshot.estimatedCost(last: period?.rawValue ?? 1)
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

    private var isViewingCustomHistoricalDay: Bool {
        guard let day = activeSelectedDay, let lastDayKey = snapshot.days.last?.dateKey else {
            return false
        }
        return day.dateKey != lastDayKey
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 12) {
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
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    /// 顶部 3 张舒展 KPI 卡片：信息层级清晰，点击支持快速切换今日 / 30 天视图
    private var summaryCards: some View {
        let todayTotal = snapshot.today.total
        let monthTotal = snapshot.last30Days.total
        let activeDayCount = max(snapshot.days.filter { $0.tokens.total > 0 }.count, 1)
        let dailyAverage = monthTotal / Int64(activeDayCount)
        let monthCostText = snapshot.last30DaysEstimatedCost.map { "30天 \($0.estimatedCostText)" } ?? "今日估算"
        let lastDayKey = snapshot.days.last?.dateKey

        return HStack(spacing: 8) {
            TokenStatCard(
                title: "今日 Token",
                value: todayTotal.tokenText,
                detail: dailyAverage > 0 ? "日均 \(dailyAverage.tokenText)" : "今日消耗",
                icon: "bolt.fill",
                accentColor: .indigo,
                isActive: period == .today && !isViewingCustomHistoricalDay,
                tooltip: "今日总用量：\(todayTotal.formattedWithSeparators) tokens（点击切回今日视图）"
            ) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    period = .today
                    selectedDateKey = lastDayKey
                }
            }

            TokenStatCard(
                title: "今日预估",
                value: snapshot.todayEstimatedCost?.estimatedCostText ?? "$0.00",
                detail: monthCostText,
                icon: "dollarsign.circle.fill",
                accentColor: .green,
                valueColor: Color(red: 0.20, green: 0.78, blue: 0.48),
                tooltip: "今日按模型阶梯单价估算费用；\(monthCostText)"
            )

            TokenStatCard(
                title: "30 天累计",
                value: monthTotal.tokenText,
                detail: "\(activeDayCount) 天活跃",
                icon: "calendar",
                accentColor: .cyan,
                isActive: period == .month && selectedDateKey == nil,
                tooltip: "最近 30 天累计用量：\(monthTotal.formattedWithSeparators) tokens（点击切换 30 天视图）"
            ) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    period = .month
                    selectedDateKey = nil
                }
            }
        }
    }

    private var accountQuotaSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("账户额度")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.9))

                if monitor.isQuotaRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.75)
                }

                Spacer()

                QuotaDisplayModeToggle(showRemaining: $showRemainingQuota)
            }

            VStack(spacing: 0) {
                let providers = snapshot.quotaProviders
                let lastProviderId = providers.last?.id
                ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                    ProviderQuotaGroupView(
                        provider: provider,
                        labelColumnWidth: quotaLabelWidth,
                        color: accountColor(provider.canonicalAgent, index: index),
                        currentTime: currentTime,
                        showRemaining: showRemainingQuota
                    )
                    .padding(.vertical, 10)

                    if provider.id != lastProviderId {
                        Divider().opacity(0.45)
                    }
                }
            }
            .padding(.horizontal, 12)
            .tokenCard()
        }
        .onPreferenceChange(QuotaLabelWidthKey.self) { width in
            let clamped = min(max(quotaLabelWidth, width), 72)
            if abs(clamped - quotaLabelWidth) > 0.5 {
                quotaLabelWidth = clamped
            }
        }
    }

    private var periodControl: some View {
        let lastDayKey = snapshot.days.last?.dateKey
        return HStack(spacing: 7) {
            Text("Agent 用量")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.9))

            if !snapshot.agents30Days.isEmpty {
                Text("\(snapshot.agents30Days.count)")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                    .help("最近 30 天已发现 \(snapshot.agents30Days.count) 个活跃 Agent")
            }

            Spacer()

            HStack(spacing: 2) {
                ForEach(TokenPeriod.allCases) { item in
                    let isSelected = period == item && (item != .today || !isViewingCustomHistoricalDay)
                    Button {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                            period = item
                            if item == .today {
                                selectedDateKey = lastDayKey
                            } else {
                                selectedDateKey = nil
                            }
                        }
                    } label: {
                        Text(item.title)
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.11))
                                        .matchedGeometryEffect(id: "ActivePeriodPill", in: periodNamespace)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color.primary.opacity(0.045), in: Capsule())
        }
        .padding(.top, 2)
    }

    private var activityStrip: some View {
        let currentDay = activeSelectedDay
        let lastDayKey = snapshot.days.last?.dateKey
        let maxTokens = snapshot.maxDailyTokens

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Label("最近 30 天", systemImage: "chart.bar.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let day = currentDay, day.dateKey != lastDayKey {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            selectedDateKey = lastDayKey
                            period = .today
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(formatTokenDateKey(day.dateKey))
                            Image(systemName: "xmark")
                                .font(.system(size: 7.5, weight: .bold))
                        }
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("点击清除选中日期并返回今日")
                    .transition(.scale.combined(with: .opacity))
                }

                Spacer()

                // 悬停某日柱子时在标题右侧直接平滑展示明细，彻底避免悬浮气泡遮挡内容
                if let hovered = hoveredActivityDay {
                    HStack(spacing: 5) {
                        Text(formatTokenDateKey(hovered.dateKey))
                            .foregroundStyle(.secondary)
                        Text(hovered.tokens.total.tokenText)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        if let cost = hovered.estimatedCost, cost > 0 {
                            Text(cost.estimatedCostText)
                                .fontWeight(.medium)
                                .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.48))
                        }
                    }
                    .font(.system(size: 10, design: .rounded))
                    .monospacedDigit()
                    .transition(.opacity)
                } else {
                    Text("峰值 \(maxTokens.tokenText)")
                        .font(.system(size: 10, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.14), value: hoveredActivityDay?.id)

            TokenActivityStrip(
                days: snapshot.days,
                maxTokens: max(maxTokens, 1),
                selectedDateKey: currentDay?.dateKey,
                hoveredDay: $hoveredActivityDay
            ) { day in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    if selectedDateKey == day.dateKey && day.dateKey != lastDayKey {
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
            .frame(height: 50)

            HStack {
                Text("30 天前")
                Spacer()
                Text("点击柱条筛选单日")
                    .foregroundStyle(.quaternary)
                Spacer()
                Text("今天")
            }
            .font(.system(size: 8.5))
            .foregroundStyle(.tertiary)
        }
        .padding(12)
        .tokenCard()
    }

    private var breakdown: some View {
        let tokens = selectedTokens
        let total = tokens.total

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(breakdownTitle)
                    .font(.caption.weight(.semibold))

                Spacer()

                if let cost = selectedEstimatedCost, cost > 0 {
                    Text(cost.estimatedCostText)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.48))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color.green.opacity(0.11), in: Capsule())
                        .contentTransition(.numericText())
                }

                Text(total.tokenText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.indigo)
                    .contentTransition(.numericText())
            }

            TokenCompositionBar(
                tokens: tokens,
                highlightedKind: hoveredBreakdownKind
            )

            HStack(spacing: 6) {
                ForEach(TokenBreakdownKind.allCases) { kind in
                    let value = kind.value(in: tokens)
                    let share = total > 0 ? Double(value) / Double(total) * 100 : 0
                    TokenBreakdownPill(
                        title: kind.title,
                        value: value,
                        sharePercent: share,
                        color: kind.color,
                        isHighlighted: hoveredBreakdownKind == kind
                    )
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.14)) {
                            hoveredBreakdownKind = hovering ? kind : (hoveredBreakdownKind == kind ? nil : hoveredBreakdownKind)
                        }
                    }
                }
            }
        }
        .padding(12)
        .tokenCard()
    }

    private var agentList: some View {
        let agents = selectedAgents
        let totalTokens = selectedTokens.total
        let currentDay = activeSelectedDay
        let inactiveAgents: [String] = {
            guard currentDay != nil else { return [] }
            let currentAgentKeys = Set(agents.map(\.agent))
            return snapshot.agents30Days.compactMap { item in
                currentAgentKeys.contains(item.agent) ? nil : item.displayName
            }
        }()
        let inactiveLabel = (currentDay?.dateKey == snapshot.days.last?.dateKey) ? "今日无消耗" : "当日无消耗"

        return VStack(spacing: 0) {
            if agents.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("这个时间范围内没有 Token 消耗记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
            } else {
                AgentUsageVisualizationSection(
                    agents: agents,
                    totalTokens: totalTokens,
                    chartStyle: agentChartStyleBinding,
                    colorForAgent: { agentKey, index in
                        agentColor(agentKey, index: index)
                    }
                )
                .padding(12)
            }

            if !agents.isEmpty, !inactiveAgents.isEmpty {
                Divider().opacity(0.42)
                HStack(spacing: 5) {
                    Text(inactiveLabel)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(inactiveAgents.joined(separator: " · "))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .tokenCard()
    }

    @ViewBuilder
    private var sourceNote: some View {
        if let note = snapshot.note {
            HStack(spacing: 5) {
                Image(systemName: "info.circle.fill")
                    .font(.caption2)
                Text(note)
                    .font(.caption2)
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
            Text("正在汇总各 Agent 的 Token 用量…")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text("首次扫描可能需要几秒")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.10))
                    .frame(width: 48, height: 48)
                Image(systemName: "bolt.slash")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.indigo)
            }
            Text("还没有找到 Token 记录")
                .font(.headline)
            Text("刷新后会自动汇总本机可用的 Agent 记录。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
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

// MARK: - KPI 汇总卡片

private struct TokenStatCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let accentColor: Color
    var valueColor: Color = .primary
    var isActive: Bool = false
    var tooltip: String? = nil
    var onTap: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        let cardContent = VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(accentColor)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText())

            Text(detail)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tokenCard(
            accent: (isActive || isHovered) ? accentColor : nil,
            isHighlighted: isActive || (isHovered && onTap != nil)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
        .help(tooltip ?? "\(title)：\(value)")
        .accessibilityElement(children: .combine)

        if let onTap {
            Button(action: onTap) {
                cardContent
            }
            .buttonStyle(.plain)
        } else {
            cardContent
        }
    }
}

// MARK: - 30 天柱状图

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
    @Binding var hoveredDay: DailyTokenUsage?
    var onSelectDay: ((DailyTokenUsage) -> Void)? = nil

    var body: some View {
        GeometryReader { geometry in
            let maximum = Double(max(maxTokens, 1))
            let gap: CGFloat = 2.5
            let totalGap = gap * CGFloat(max(days.count - 1, 0))
            let width = max(1, (geometry.size.width - totalGap) / CGFloat(max(days.count, 1)))
            let chartHeight = max(geometry.size.height - 8, 12)

            ZStack(alignment: .bottom) {
                // 中位 50% 极淡参考线 + 底部参考基线，呼应整体图表视觉语法
                VStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: 0.5)
                    Spacer()
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 0.5)
                }
                .padding(.top, 8)

                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(days) { day in
                        let ratio = Double(day.tokens.total) / maximum
                        let isHovered = hoveredDay?.id == day.id
                        let isSelected = selectedDateKey == day.dateKey
                        let barHeight = day.tokens.total == 0
                            ? 3
                            : max(4, chartHeight * CGFloat(ratio))

                        VStack(spacing: 3) {
                            Spacer(minLength: 0)

                            // 悬停或选中时在柱顶显示精巧高光圆点
                            Circle()
                                .fill(isSelected ? Color.cyan : Color.indigo)
                                .frame(width: 3.5, height: 3.5)
                                .opacity(isHovered || isSelected ? 1 : 0)

                            RoundedRectangle(cornerRadius: min(width / 2, 2.5), style: .continuous)
                                .fill(barFill(for: day, ratio: ratio, isHovered: isHovered, isSelected: isSelected))
                                .overlay(
                                    RoundedRectangle(cornerRadius: min(width / 2, 2.5), style: .continuous)
                                        .strokeBorder(
                                            day.tokens.total > 0
                                                ? (isSelected ? Color.cyan.opacity(0.65) : Color.indigo.opacity(isHovered ? 0.8 : 0.25))
                                                : Color.clear,
                                            lineWidth: 0.5
                                        )
                                )
                                .frame(width: width, height: barHeight)
                        }
                        .frame(width: width, height: geometry.size.height)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectDay?(day)
                        }
                        .onHover { hovering in
                            if hovering {
                                hoveredDay = day
                            } else if hoveredDay?.id == day.id {
                                hoveredDay = nil
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("最近 30 天 Token 活动")
    }

    private func barFill(
        for day: DailyTokenUsage,
        ratio: Double,
        isHovered: Bool,
        isSelected: Bool
    ) -> LinearGradient {
        if isSelected {
            let topOpacity = day.tokens.total == 0 ? 0.45 : 0.88
            let bottomOpacity = day.tokens.total == 0 ? 0.25 : 0.45
            return LinearGradient(
                colors: [Color.cyan.opacity(topOpacity), Color.blue.opacity(bottomOpacity)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        if day.tokens.total == 0 {
            let opacity = isHovered ? 0.20 : 0.07
            return LinearGradient(
                colors: [Color.primary.opacity(opacity), Color.primary.opacity(opacity)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        if isHovered {
            return LinearGradient(
                colors: [Color.indigo.opacity(0.92), Color.indigo.opacity(0.50)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        let topAlpha = 0.28 + ratio * 0.52
        return LinearGradient(
            colors: [Color.indigo.opacity(topAlpha), Color.indigo.opacity(topAlpha * 0.38)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Token 多段构成条与明细药丸

private struct TokenCompositionBar: View {
    let tokens: TokenBreakdown
    let highlightedKind: TokenBreakdownKind?

    var body: some View {
        let total = Double(max(tokens.total, 0))
        let segments: [(TokenBreakdownKind, Double)] = TokenBreakdownKind.allCases.compactMap { kind in
            let value = Double(kind.value(in: tokens))
            guard value > 0 else { return nil }
            return (kind, value)
        }

        GeometryReader { proxy in
            if total <= 0 || segments.isEmpty {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
            } else {
                let gap: CGFloat = 2
                let availableWidth = max(proxy.size.width - gap * CGFloat(max(segments.count - 1, 0)), 1)

                HStack(spacing: gap) {
                    ForEach(segments, id: \.0.id) { kind, value in
                        let fraction = value / total
                        let isDimmed = highlightedKind != nil && highlightedKind != kind
                        let isFocused = highlightedKind == kind

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [kind.color.opacity(0.95), kind.color.opacity(0.72)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(3, availableWidth * CGFloat(fraction)))
                            .opacity(isDimmed ? 0.28 : 1.0)
                            .scaleEffect(y: isFocused ? 1.28 : 1.0)
                    }
                }
                .animation(.easeOut(duration: 0.16), value: highlightedKind)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

private struct TokenBreakdownPill: View {
    let title: String
    let value: Int64
    let sharePercent: Double
    let color: Color
    var isHighlighted: Bool = false

    var body: some View {
        let roundedShare = Int(sharePercent.rounded())
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 5.5, height: 5.5)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isHighlighted ? .primary : .secondary)
                Spacer(minLength: 2)
                if value > 0 {
                    Text("\(roundedShare)%")
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isHighlighted ? AnyShapeStyle(color) : AnyShapeStyle(.tertiary))
                }
            }

            Text(value.tokenText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(isHighlighted ? 0.15 : 0.075))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(color.opacity(isHighlighted ? 0.42 : 0.12), lineWidth: 0.75)
                )
        )
        .help("\(title)：\(value.formattedWithSeparators) tokens（占比 \(roundedShare)%）")
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 账户额度区块

/// 账户额度「已用 / 剩余」口径快速切换器（支持一键对齐反重力等客户端的剩余百分比口径）
private struct QuotaDisplayModeToggle: View {
    @Binding var showRemaining: Bool

    var body: some View {
        HStack(spacing: 2) {
            modeButton(title: "已用", selected: !showRemaining) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showRemaining = false
                }
            }
            modeButton(title: "剩余", selected: showRemaining) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showRemaining = true
                }
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.055), in: Capsule())
        .help(showRemaining ? "当前显示剩余额度百分比（与客户端剩余口径一致），点击可切换为已用口径" : "当前显示已用额度百分比，点击可切换为剩余口径")
    }

    private func modeButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(selected ? Color.primary.opacity(0.11) : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ProviderQuotaGroupView: View {
    let provider: ProviderQuotaUsage
    let labelColumnWidth: CGFloat
    let color: Color
    let currentTime: Date
    let showRemaining: Bool

    var body: some View {
        let usageList = usageWindows
        let resetList = resetWindows

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                AgentBrandLogo(agent: provider.canonicalAgent, color: color, size: 15)
                    .frame(width: 15, height: 15)

                Text(provider.provider)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                if let plan = provider.plan, !plan.isEmpty {
                    Text(plan)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(color.opacity(0.13), in: Capsule())
                }

                Spacer()

                if provider.isCached {
                    let cachedTimeText = provider.cachedAt.map { QuotaDateFormatters.exactTime.string(from: $0) }
                    Text(cachedTimeText.map { "缓存 · \($0)" } ?? "缓存")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                        .help(cachedTimeText.map { "实时额度暂不可用，当前显示 \($0) 的历史缓存" } ?? "实时额度暂不可用，当前显示历史缓存")
                }
            }

            if !usageList.isEmpty {
                VStack(spacing: 3) {
                    ForEach(usageList) { window in
                        AccountQuotaRow(
                            window: window,
                            labelColumnWidth: labelColumnWidth,
                            currentTime: currentTime,
                            showRemaining: showRemaining
                        )
                    }
                }
            }

            if !resetList.isEmpty {
                Text("重置权益")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)

                VStack(spacing: 3) {
                    ForEach(resetList) { window in
                        AccountQuotaRow(
                            window: window,
                            labelColumnWidth: labelColumnWidth,
                            currentTime: currentTime,
                            showRemaining: showRemaining
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
    let showRemaining: Bool

    @State private var isHoveringRow = false
    @State private var isHoveringResetTime = false
    @State private var isPinnedExactTime = false

    private var clampedUsedPercent: Double {
        min(max(window.usedPercent, 0), 100)
    }

    private var displayedPercent: Double {
        if window.style == .resetCredit {
            return clampedUsedPercent
        }
        return showRemaining ? (100 - clampedUsedPercent) : clampedUsedPercent
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
        let usedRounded = Int(clampedUsedPercent.rounded())
        let displayRounded = Int(displayedPercent.rounded())
        let tooltip = resetTooltipText

        return HStack(spacing: 6) {
            Text(window.label)
                .font(.caption)
                .foregroundStyle(isHoveringRow ? .primary : .secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: QuotaLabelWidthKey.self, value: proxy.size.width)
                    }
                )
                .frame(width: labelColumnWidth > 0 ? labelColumnWidth : nil, alignment: .leading)

            AccountQuotaBar(
                percent: displayedPercent,
                usedPercent: clampedUsedPercent,
                style: window.style,
                isEmphasized: isHoveringRow
            )
            .animation(.easeOut(duration: 0.42), value: displayedPercent)

            if window.style == .resetCredit {
                let exp = expiryText
                Text(exp)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: 90, alignment: .trailing)
                    .help("\(window.label)：有效期至 \(exp)")
            } else {
                Text("\(displayRounded)%")
                    .font(.system(size: 11, weight: isHoveringRow ? .semibold : .medium, design: .monospaced))
                    .foregroundStyle(isHoveringRow ? .primary : .secondary)
                    .contentTransition(.numericText())
                    .frame(width: 36, alignment: .trailing)

                Text(displayResetText)
                    .font(.system(size: 10, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isHoveringResetTime || isPinnedExactTime ? .primary : .tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(
                        isHoveringResetTime
                            ? Color.primary.opacity(0.09)
                            : (isPinnedExactTime ? Color.indigo.opacity(0.14) : Color.clear),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
                    .frame(width: 50, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.14)) {
                            isHoveringResetTime = hovering
                        }
                    }
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            isPinnedExactTime.toggle()
                        }
                    }
                    .help("\(tooltip)（点击可固定显示精确重置时刻）")
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHoveringRow ? Color.primary.opacity(0.045) : Color.clear)
        )
        .padding(.horizontal, -5)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.14)) {
                isHoveringRow = hovering
            }
        }
        .help(makeHelpText(usedRounded: usedRounded, resetTooltip: tooltip))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(makeAccessibilityText(usedRounded: usedRounded))
    }

    private func makeHelpText(usedRounded: Int, resetTooltip: String) -> String {
        if window.style == .resetCredit {
            return "\(window.label)：有效期至 \(expiryText)"
        }
        let remainingRounded = max(0, 100 - usedRounded)
        var parts = ["\(window.label)：已用 \(usedRounded)% · 剩余 \(remainingRounded)%"]
        if let remaining = window.remainingLabel, !remaining.isEmpty {
            parts.append(remaining)
        }
        if window.resetsAt != nil {
            parts.append(resetTooltip)
        }
        return parts.joined(separator: " · ")
    }

    private func makeAccessibilityText(usedRounded: Int) -> String {
        if window.style == .resetCredit {
            return "\(window.label)，有效期至 \(expiryText)"
        }
        let remainingRounded = max(0, 100 - usedRounded)
        let resetDesc = window.resetsAt != nil
            ? "重置时间 \(exactTimeText)，约 \(resetCountdownText) 后"
            : "无重置时间"
        return "\(window.label)，已用 \(usedRounded)%，剩余 \(remainingRounded)%，\(resetDesc)"
    }
}

private struct AccountQuotaBar: View {
    let percent: Double
    var usedPercent: Double? = nil
    let style: QuotaWindowStyle
    var tint: Color? = nil
    var isEmphasized: Bool = false

    private var healthUsedPercent: Double {
        usedPercent ?? percent
    }

    private var gradientColors: [Color] {
        if let tint {
            return [tint.opacity(0.75), tint]
        }
        if style == .resetCredit {
            return [Color(red: 0.18, green: 0.72, blue: 0.56), Color(red: 0.28, green: 0.82, blue: 0.50)]
        }
        switch healthUsedPercent {
        case 80...:
            return [Color(red: 0.94, green: 0.36, blue: 0.34), Color(red: 0.88, green: 0.22, blue: 0.36)]
        case 60...:
            return [Color(red: 0.96, green: 0.68, blue: 0.22), Color(red: 0.94, green: 0.48, blue: 0.18)]
        default:
            return [Color(red: 0.20, green: 0.76, blue: 0.58), Color(red: 0.26, green: 0.82, blue: 0.46)]
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let fraction = min(max(percent / 100, 0), 1)
            let fillWidth = proxy.size.width * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.075))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
                    )

                if fillWidth > 0 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(fillWidth, 4))
                        .brightness(isEmphasized ? 0.05 : 0)
                }
            }
        }
        .frame(height: 6.5)
        .accessibilityHidden(true)
    }
}

private struct QuotaLabelWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Squarified 矩形树图引擎与视图

/// 单个矩形树图布局输入项
private struct TreemapInputItem {
    let id: String
    let weight: Double
}

/// 单个矩形树图布局结果
private struct TreemapLayoutRect: Identifiable {
    let id: String
    let rect: CGRect
}

/// 经典 Bruls-Huizing-van Wijk Squarified Treemap 布局算法：
/// 贪心沿当前剩余矩形的较短边排布行/列，使所有矩形尽量接近正方形，避免细长条。
private enum SquarifiedTreemapLayout {
    static func compute(
        items: [TreemapInputItem],
        in bounds: CGRect,
        minVisualFraction: Double = 0.022
    ) -> [TreemapLayoutRect] {
        guard bounds.width > 0.5, bounds.height > 0.5 else { return [] }
        let positive = items.filter { $0.weight > 0 }.sorted { $0.weight > $1.weight }
        guard !positive.isEmpty else { return [] }

        let rawTotal = positive.reduce(0) { $0 + $1.weight }
        guard rawTotal > 0 else { return [] }

        // 对极小占比施加克制的面积下限保护，确保 1% 以下模型依然可清晰识别与悬停，展示数值仍用真实值
        let effectiveMinFraction = min(minVisualFraction, 0.32 / Double(max(positive.count, 1)))
        let floorWeight = rawTotal * effectiveMinFraction
        let adjustedWeights = positive.map { max($0.weight, floorWeight) }
        let adjustedTotal = adjustedWeights.reduce(0, +)
        let totalArea = Double(bounds.width * bounds.height)
        let areas = adjustedWeights.map { ($0 / adjustedTotal) * totalArea }

        var results: [TreemapLayoutRect] = []
        results.reserveCapacity(positive.count)

        var remaining = bounds
        var cursor = 0

        while cursor < positive.count {
            let shortSide = Double(max(min(remaining.width, remaining.height), 0.001))
            var rowEnd = cursor + 1
            var rowSum = areas[cursor]
            var currentWorst = worstRatio(
                maxArea: areas[cursor],
                minArea: areas[cursor],
                sum: rowSum,
                side: shortSide
            )

            while rowEnd < positive.count {
                let candidateArea = areas[rowEnd]
                let nextSum = rowSum + candidateArea
                let nextWorst = worstRatio(
                    maxArea: areas[cursor],
                    minArea: candidateArea,
                    sum: nextSum,
                    side: shortSide
                )
                if nextWorst <= currentWorst {
                    rowSum = nextSum
                    currentWorst = nextWorst
                    rowEnd += 1
                } else {
                    break
                }
            }

            let isHorizontalSplit = remaining.width >= remaining.height
            if isHorizontalSplit {
                // 剩余矩形偏宽：沿左侧切出一竖列
                let colWidth = min(remaining.width, CGFloat(rowSum / Double(max(remaining.height, 0.001))))
                var curY = remaining.minY
                for idx in cursor..<rowEnd {
                    let isLastInRow = idx == rowEnd - 1
                    let itemHeight = isLastInRow
                        ? max(0, remaining.maxY - curY)
                        : CGFloat(areas[idx] / Double(max(colWidth, 0.001)))
                    let frame = CGRect(x: remaining.minX, y: curY, width: max(0, colWidth), height: max(0, itemHeight))
                    results.append(TreemapLayoutRect(id: positive[idx].id, rect: frame))
                    curY += itemHeight
                }
                remaining = CGRect(
                    x: remaining.minX + colWidth,
                    y: remaining.minY,
                    width: max(0, remaining.width - colWidth),
                    height: remaining.height
                )
            } else {
                // 剩余矩形偏高：沿顶部切出一横行
                let rowHeight = min(remaining.height, CGFloat(rowSum / Double(max(remaining.width, 0.001))))
                var curX = remaining.minX
                for idx in cursor..<rowEnd {
                    let isLastInRow = idx == rowEnd - 1
                    let itemWidth = isLastInRow
                        ? max(0, remaining.maxX - curX)
                        : CGFloat(areas[idx] / Double(max(rowHeight, 0.001)))
                    let frame = CGRect(x: curX, y: remaining.minY, width: max(0, itemWidth), height: max(0, rowHeight))
                    results.append(TreemapLayoutRect(id: positive[idx].id, rect: frame))
                    curX += itemWidth
                }
                remaining = CGRect(
                    x: remaining.minX,
                    y: remaining.minY + rowHeight,
                    width: remaining.width,
                    height: max(0, remaining.height - rowHeight)
                )
            }

            cursor = rowEnd
        }

        return results
    }

    /// 计算同一排矩形中的最差宽高比（利用已降序特性，O(1) 常数求解）
    private static func worstRatio(maxArea: Double, minArea: Double, sum: Double, side: Double) -> Double {
        guard minArea > 0, sum > 0, side > 0 else { return .greatestFiniteMagnitude }
        let sideSq = side * side
        let sumSq = sum * sum
        return max((sideSq * maxArea) / sumSq, sumSq / (sideSq * minArea))
    }
}

/// 矩形树图专属多阶协调色板：同一 Agent 保持统一色系家族，内部各模型通过细腻色阶区分
private enum TreemapPalette {
    static func modelGradient(for agentKey: String, modelIndex: Int, fallbackIndex: Int) -> (top: Color, bottom: Color, solid: Color) {
        let swatches = familySwatches(for: agentKey, fallbackIndex: fallbackIndex)
        let pair = swatches[modelIndex % swatches.count]
        return (pair.0, pair.1, pair.0)
    }

    static func agentHeaderTint(for agentKey: String, fallbackIndex: Int) -> Color {
        familySwatches(for: agentKey, fallbackIndex: fallbackIndex)[0].0
    }

    private static func familySwatches(for agentKey: String, fallbackIndex: Int) -> [(Color, Color)] {
        switch agentKey.lowercased() {
        case "antigravity":
            return [
                (Color(red: 0.34, green: 0.39, blue: 0.90), Color(red: 0.25, green: 0.29, blue: 0.76)),
                (Color(red: 0.48, green: 0.36, blue: 0.88), Color(red: 0.37, green: 0.26, blue: 0.74)),
                (Color(red: 0.25, green: 0.50, blue: 0.89), Color(red: 0.19, green: 0.39, blue: 0.75)),
                (Color(red: 0.23, green: 0.61, blue: 0.84), Color(red: 0.17, green: 0.49, blue: 0.70)),
                (Color(red: 0.56, green: 0.44, blue: 0.86), Color(red: 0.44, green: 0.33, blue: 0.72)),
            ]
        case "codex":
            return [
                (Color(red: 0.15, green: 0.66, blue: 0.44), Color(red: 0.10, green: 0.52, blue: 0.34)),
                (Color(red: 0.22, green: 0.72, blue: 0.53), Color(red: 0.15, green: 0.58, blue: 0.41)),
                (Color(red: 0.14, green: 0.58, blue: 0.52), Color(red: 0.09, green: 0.46, blue: 0.41)),
                (Color(red: 0.34, green: 0.71, blue: 0.38), Color(red: 0.24, green: 0.57, blue: 0.28)),
                (Color(red: 0.18, green: 0.64, blue: 0.60), Color(red: 0.12, green: 0.50, blue: 0.48)),
            ]
        case "claude":
            return [
                (Color(red: 0.86, green: 0.46, blue: 0.20), Color(red: 0.72, green: 0.34, blue: 0.13)),
                (Color(red: 0.88, green: 0.58, blue: 0.22), Color(red: 0.74, green: 0.45, blue: 0.14)),
                (Color(red: 0.82, green: 0.36, blue: 0.26), Color(red: 0.68, green: 0.26, blue: 0.18)),
                (Color(red: 0.79, green: 0.51, blue: 0.29), Color(red: 0.65, green: 0.39, blue: 0.20)),
                (Color(red: 0.86, green: 0.65, blue: 0.25), Color(red: 0.72, green: 0.52, blue: 0.16)),
            ]
        case "gemini":
            return [
                (Color(red: 0.19, green: 0.52, blue: 0.88), Color(red: 0.13, green: 0.40, blue: 0.74)),
                (Color(red: 0.22, green: 0.63, blue: 0.86), Color(red: 0.15, green: 0.50, blue: 0.72)),
                (Color(red: 0.28, green: 0.46, blue: 0.86), Color(red: 0.20, green: 0.35, blue: 0.72)),
                (Color(red: 0.16, green: 0.68, blue: 0.78), Color(red: 0.11, green: 0.54, blue: 0.64)),
            ]
        case "opencode":
            return [
                (Color(red: 0.14, green: 0.64, blue: 0.62), Color(red: 0.09, green: 0.50, blue: 0.49)),
                (Color(red: 0.20, green: 0.70, blue: 0.62), Color(red: 0.14, green: 0.56, blue: 0.49)),
                (Color(red: 0.16, green: 0.57, blue: 0.68), Color(red: 0.11, green: 0.44, blue: 0.55)),
                (Color(red: 0.25, green: 0.66, blue: 0.52), Color(red: 0.18, green: 0.52, blue: 0.40)),
            ]
        case "cursor":
            return [
                (Color(red: 0.62, green: 0.36, blue: 0.84), Color(red: 0.49, green: 0.26, blue: 0.70)),
                (Color(red: 0.74, green: 0.38, blue: 0.76), Color(red: 0.60, green: 0.28, blue: 0.62)),
                (Color(red: 0.52, green: 0.40, blue: 0.86), Color(red: 0.40, green: 0.30, blue: 0.72)),
                (Color(red: 0.80, green: 0.42, blue: 0.64), Color(red: 0.66, green: 0.31, blue: 0.50)),
            ]
        case "agy-cli", "antigravity-cli", "agy":
            return [
                (Color(red: 0.14, green: 0.60, blue: 0.78), Color(red: 0.09, green: 0.47, blue: 0.64)),
                (Color(red: 0.20, green: 0.68, blue: 0.82), Color(red: 0.14, green: 0.54, blue: 0.68)),
                (Color(red: 0.18, green: 0.52, blue: 0.78), Color(red: 0.12, green: 0.40, blue: 0.64)),
            ]
        default:
            let palettes: [[(Color, Color)]] = [
                [(Color(red: 0.22, green: 0.62, blue: 0.76), Color(red: 0.15, green: 0.49, blue: 0.62)),
                 (Color(red: 0.28, green: 0.68, blue: 0.80), Color(red: 0.20, green: 0.54, blue: 0.66))],
                [(Color(red: 0.82, green: 0.38, blue: 0.54), Color(red: 0.68, green: 0.28, blue: 0.42)),
                 (Color(red: 0.86, green: 0.48, blue: 0.58), Color(red: 0.72, green: 0.36, blue: 0.46))],
                [(Color(red: 0.54, green: 0.68, blue: 0.22), Color(red: 0.42, green: 0.55, blue: 0.15)),
                 (Color(red: 0.62, green: 0.74, blue: 0.28), Color(red: 0.49, green: 0.60, blue: 0.20))],
                [(Color(red: 0.78, green: 0.60, blue: 0.18), Color(red: 0.64, green: 0.48, blue: 0.12)),
                 (Color(red: 0.84, green: 0.68, blue: 0.24), Color(red: 0.70, green: 0.55, blue: 0.16))],
            ]
            return palettes[fallbackIndex % palettes.count]
        }
    }
}

/// Agent 用量支持的图表展示类型
private enum AgentChartStyle: String, CaseIterable, Identifiable {
    case treemap
    case donut
    case bar
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .treemap: "矩形树图"
        case .donut: "环形占比"
        case .bar: "排行柱状图"
        case .list: "分组列表"
        }
    }

    var symbol: String {
        switch self {
        case .treemap: "square.grid.2x2.fill"
        case .donut: "chart.pie.fill"
        case .bar: "chart.bar.xaxis"
        case .list: "list.bullet"
        }
    }
}

/// 4 种图表类型滑动胶囊选择器
private struct AgentChartStylePicker: View {
    @Binding var selection: AgentChartStyle
    @Namespace private var pickerNamespace
    @State private var hoveredStyle: AgentChartStyle? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(AgentChartStyle.allCases) { style in
                let isSelected = selection == style
                let isHovered = hoveredStyle == style

                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        selection = style
                    }
                } label: {
                    Image(systemName: style.symbol)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(
                            isSelected
                                ? Color.primary
                                : (isHovered ? Color.primary.opacity(0.82) : Color.secondary)
                        )
                        .frame(width: 22, height: 18)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.9))
                                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.08), radius: 1.5, y: 0.5)
                                    .matchedGeometryEffect(id: "ActiveChartStylePill", in: pickerNamespace)
                            } else if isHovered {
                                Capsule()
                                    .fill(Color.primary.opacity(0.06))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredStyle = hovering ? style : (hoveredStyle == style ? nil : hoveredStyle)
                }
                .help("\(style.title)视图")
            }
        }
        .padding(2)
        .background(
            Capsule()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.075 : 0.055))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}

/// 悬停检视目标数据模型（多图表共享）
private struct TreemapHoveredTarget: Equatable {
    let id: String
    let agentName: String
    let modelName: String?
    let tokens: TokenBreakdown
    let sharePercent: Double
    let estimatedCost: Double?
    let color: Color
}

/// 统一图表条目模型（供环形图、排行柱状图共享）
private struct AgentChartItem: Identifiable {
    let id: String
    let title: String
    let agentName: String
    let agentKey: String
    let drillAgentId: String?
    let tokens: TokenBreakdown
    let sharePercent: Double
    let estimatedCost: Double?
    let topColor: Color
    let bottomColor: Color
}

/// Agent 与模型多图表可视化容器（支持矩形树图 / 环形占比 / 排行柱状图 + 统一下钻与悬停检视）
private struct AgentUsageVisualizationSection: View {
    let agents: [AgentTokenUsage]
    let totalTokens: Int64
    @Binding var chartStyle: AgentChartStyle
    let colorForAgent: (String, Int) -> Color

    @State private var focusedAgentId: String? = nil
    @State private var hoveredTarget: TreemapHoveredTarget? = nil

    /// 当前实际聚焦的 Agent：仅 1 个 Agent 时自动直接展开其内部模型视图
    private var activeFocusedAgent: (agent: AgentTokenUsage, index: Int)? {
        if let focusedAgentId,
           let idx = agents.firstIndex(where: { $0.id == focusedAgentId }) {
            return (agents[idx], idx)
        }
        if agents.count == 1, let only = agents.first {
            return (only, 0)
        }
        return nil
    }

    private var isDrilledDown: Bool {
        agents.count > 1 && activeFocusedAgent != nil
    }

    /// 构造环形图和排行柱状图共用的归一化条目列表
    private var chartItems: [AgentChartItem] {
        if let focused = activeFocusedAgent {
            let models = resolvedModels(for: focused.agent)
            let denom = max(Double(focused.agent.tokens.total), 1)
            return models.enumerated().map { idx, model in
                let palette = TreemapPalette.modelGradient(
                    for: focused.agent.agent,
                    modelIndex: idx,
                    fallbackIndex: focused.index
                )
                return AgentChartItem(
                    id: "model|\(focused.agent.id)|\(model.id)",
                    title: model.name,
                    agentName: focused.agent.displayName,
                    agentKey: focused.agent.agent,
                    drillAgentId: nil,
                    tokens: model.tokens,
                    sharePercent: Double(model.tokens.total) / denom * 100,
                    estimatedCost: nil,
                    topColor: palette.top,
                    bottomColor: palette.bottom
                )
            }
        } else {
            let denom = max(Double(totalTokens), 1)
            return agents.enumerated().map { idx, agent in
                let palette = TreemapPalette.modelGradient(
                    for: agent.agent,
                    modelIndex: 0,
                    fallbackIndex: idx
                )
                return AgentChartItem(
                    id: "agent|\(agent.id)",
                    title: agent.displayName,
                    agentName: agent.displayName,
                    agentKey: agent.agent,
                    drillAgentId: agent.id,
                    tokens: agent.tokens,
                    sharePercent: Double(agent.tokens.total) / denom * 100,
                    estimatedCost: agent.estimatedCost,
                    topColor: palette.top,
                    bottomColor: palette.bottom
                )
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            headerBar

            Group {
                switch chartStyle {
                case .treemap:
                    treemapCanvas
                        .frame(height: 168)
                        .transition(.opacity)
                case .donut:
                    AgentDonutChartView(
                        items: chartItems,
                        centerTotalText: (activeFocusedAgent?.agent.tokens.total ?? totalTokens).tokenText,
                        centerSubtitle: activeFocusedAgent != nil
                            ? "\(chartItems.count) 个模型"
                            : "\(agents.count) 个 Agent",
                        isAgentLevel: activeFocusedAgent == nil,
                        hoveredTarget: $hoveredTarget
                    ) { agentId in
                        drillDown(to: agentId)
                    }
                    .frame(height: 168)
                    .transition(.opacity)
                case .bar:
                    AgentRankedBarChartView(
                        items: chartItems,
                        isAgentLevel: activeFocusedAgent == nil,
                        hoveredTarget: $hoveredTarget
                    ) { agentId in
                        drillDown(to: agentId)
                    }
                    .transition(.opacity)
                case .list:
                    unifiedListView
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: chartStyle)

            if chartStyle != .list {
                inspectorStrip
            }
        }
        .onChange(of: agents.map(\.id)) { _, newIds in
            if let focused = focusedAgentId, !newIds.contains(focused) {
                focusedAgentId = nil
            }
            hoveredTarget = nil
        }
        .onChange(of: chartStyle) { _, _ in
            hoveredTarget = nil
        }
    }

    /// 统一的列表视图：单 Agent / 下钻态直接展示清爽模型明细行（零重复头部），多 Agent 时展示可折叠分组
    @ViewBuilder
    private var unifiedListView: some View {
        if let focused = activeFocusedAgent {
            let models = resolvedModels(for: focused.agent)
            let denom = max(focused.agent.tokens.total, 1)
            VStack(spacing: 4) {
                ForEach(Array(models.enumerated()), id: \.element.id) { idx, model in
                    let palette = TreemapPalette.modelGradient(
                        for: focused.agent.agent,
                        modelIndex: idx,
                        fallbackIndex: focused.index
                    )
                    ModelUsageRow(model: model, total: denom, color: palette.top)
                }
            }
            .padding(.top, 2)
        } else {
            VStack(spacing: 0) {
                let lastAgentId = agents.last?.id
                ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
                    AgentUsageGroupView(
                        agent: agent,
                        color: colorForAgent(agent.agent, index),
                        total: totalTokens
                    )
                    .padding(.vertical, 4)

                    if agent.id != lastAgentId {
                        Divider().opacity(0.42)
                    }
                }
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 6) {
            if let focused = activeFocusedAgent {
                if isDrilledDown {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            focusedAgentId = nil
                            hoveredTarget = nil
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 8.5, weight: .bold))
                            Text("全部")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 2.5)
                        .background(Color.indigo.opacity(0.13), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("返回所有 Agent 总览")
                }

                AgentBrandLogo(
                    agent: focused.agent.agent,
                    color: colorForAgent(focused.agent.agent, focused.index),
                    size: 14,
                    showsBackground: true
                )

                Text(focused.agent.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                if let cost = focused.agent.estimatedCost, cost > 0 {
                    Text(cost.estimatedCostText)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.48))
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }

                Text("\(max(focused.agent.models.count, 1)) 模型")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            } else {
                Label(chartStyle.title, systemImage: chartStyle.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.9))

                Text("\(agents.count) 个 Agent")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            AgentChartStylePicker(selection: $chartStyle)
        }
    }

    private var treemapCanvas: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let bounds = CGRect(origin: .zero, size: size)

            if let focused = activeFocusedAgent {
                singleAgentModelsCanvas(
                    agent: focused.agent,
                    agentIndex: focused.index,
                    bounds: bounds
                )
            } else {
                multiAgentNestedCanvas(bounds: bounds)
            }
        }
    }

    /// 矩形树图统一坐标命中区域（使用未裁缝隙的原始矩形，保证划过 3px 间距不闪烁且 100% 像素精确）
    private struct TreemapHitRegion {
        let rect: CGRect
        let target: TreemapHoveredTarget
        let drillAgentId: String?
    }

    private struct SingleModelRenderTile: Identifiable {
        let id: String
        let targetId: String
        let title: String
        let tokensText: String
        let sharePercent: Double
        let rect: CGRect
        let topColor: Color
        let bottomColor: Color
    }

    private struct NestedModelRenderTile: Identifiable {
        let id: String
        let targetId: String
        let title: String
        let tokensText: String
        let sharePercent: Double
        let localRect: CGRect
        let topColor: Color
        let bottomColor: Color
    }

    private struct NestedAgentRenderGroup: Identifiable {
        let id: String
        let agent: AgentTokenUsage
        let groupRect: CGRect
        let groupShare: Double
        let headerColor: Color
        let showHeader: Bool
        let headerHeight: CGFloat
        let innerPadding: CGFloat
        let contentSize: CGSize
        let modelTiles: [NestedModelRenderTile]
        let compactTopColor: Color
        let compactBottomColor: Color
    }

    /// 单 Agent（或下钻后）全画幅模型矩形树图
    @ViewBuilder
    private func singleAgentModelsCanvas(
        agent: AgentTokenUsage,
        agentIndex: Int,
        bounds: CGRect
    ) -> some View {
        let models = resolvedModels(for: agent)
        let denom = max(Double(agent.tokens.total), 1)
        let inputs = models.map { TreemapInputItem(id: $0.id, weight: Double($0.tokens.total)) }
        let rects = SquarifiedTreemapLayout.compute(items: inputs, in: bounds, minVisualFraction: 0.025)
        let modelsById = Dictionary(uniqueKeysWithValues: models.enumerated().map { ($0.element.id, ($0.element, $0.offset)) })
        let spacing: CGFloat = 3

        let (tiles, hitRegions): ([SingleModelRenderTile], [TreemapHitRegion]) = {
            var renderTiles: [SingleModelRenderTile] = []
            var regions: [TreemapHitRegion] = []
            for layout in rects {
                guard let (model, modelIndex) = modelsById[layout.id] else { continue }
                let insetRect = insetTileRect(layout.rect, gap: spacing)
                let palette = TreemapPalette.modelGradient(
                    for: agent.agent,
                    modelIndex: modelIndex,
                    fallbackIndex: agentIndex
                )
                let share = Double(model.tokens.total) / denom * 100
                let targetId = "model|\(agent.id)|\(model.id)"
                renderTiles.append(
                    SingleModelRenderTile(
                        id: layout.id,
                        targetId: targetId,
                        title: model.name,
                        tokensText: model.tokens.total.tokenText,
                        sharePercent: share,
                        rect: insetRect,
                        topColor: palette.top,
                        bottomColor: palette.bottom
                    )
                )
                regions.append(
                    TreemapHitRegion(
                        rect: layout.rect,
                        target: TreemapHoveredTarget(
                            id: targetId,
                            agentName: agent.displayName,
                            modelName: model.name,
                            tokens: model.tokens,
                            sharePercent: share,
                            estimatedCost: nil,
                            color: palette.solid
                        ),
                        drillAgentId: nil
                    )
                )
            }
            return (renderTiles, regions)
        }()

        ZStack(alignment: .topLeading) {
            ForEach(tiles) { tile in
                let isHovered = hoveredTarget?.id == tile.targetId
                let isDimmed = hoveredTarget != nil && !isHovered

                TreemapModelTile(
                    title: tile.title,
                    tokensText: tile.tokensText,
                    sharePercent: tile.sharePercent,
                    size: tile.rect.size,
                    topColor: tile.topColor,
                    bottomColor: tile.bottomColor,
                    cornerRadius: 7,
                    isHovered: isHovered,
                    isDimmed: isDimmed
                )
                .frame(width: tile.rect.width, height: tile.rect.height)
                .offset(x: tile.rect.minX, y: tile.rect.minY)
            }
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .overlay {
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let matched = hitRegions.first { $0.rect.contains(location) }?.target
                        if hoveredTarget?.id != matched?.id {
                            withAnimation(.easeOut(duration: 0.12)) {
                                hoveredTarget = matched
                            }
                        }
                    case .ended:
                        if hoveredTarget != nil {
                            withAnimation(.easeOut(duration: 0.12)) {
                                hoveredTarget = nil
                            }
                        }
                    }
                }
        }
    }

    /// 多 Agent 两级嵌套矩形树图：外层按 Agent 分组，内层按模型比例细分，画布统一坐标命中与点击下钻
    @ViewBuilder
    private func multiAgentNestedCanvas(bounds: CGRect) -> some View {
        let totalDenom = max(Double(totalTokens), 1)
        let agentInputs = agents.map { TreemapInputItem(id: $0.id, weight: Double($0.tokens.total)) }
        let agentRects = SquarifiedTreemapLayout.compute(items: agentInputs, in: bounds, minVisualFraction: 0.055)
        let agentsById = Dictionary(uniqueKeysWithValues: agents.enumerated().map { ($0.element.id, ($0.element, $0.offset)) })
        let groupGap: CGFloat = 4

        let (groups, hitRegions): ([NestedAgentRenderGroup], [TreemapHitRegion]) = {
            var renderGroups: [NestedAgentRenderGroup] = []
            var regions: [TreemapHitRegion] = []

            for groupLayout in agentRects {
                guard let (agent, agentIndex) = agentsById[groupLayout.id] else { continue }
                let groupRect = insetTileRect(groupLayout.rect, gap: groupGap)
                let groupShare = Double(agent.tokens.total) / totalDenom * 100
                let headerColor = TreemapPalette.agentHeaderTint(for: agent.agent, fallbackIndex: agentIndex)
                let compactPalette = TreemapPalette.modelGradient(
                    for: agent.agent,
                    modelIndex: 0,
                    fallbackIndex: agentIndex
                )
                let models = resolvedModels(for: agent)
                let showHeader = groupRect.width >= 76 && groupRect.height >= 58
                let innerPadding: CGFloat = 3
                let headerHeight: CGFloat = 19

                if showHeader {
                    let contentWidth = max(groupRect.width - innerPadding * 2, 1)
                    let contentHeight = max(groupRect.height - headerHeight - innerPadding * 2, 1)
                    let contentOriginX = groupRect.minX + innerPadding
                    let contentOriginY = groupRect.minY + innerPadding + headerHeight
                    let modelInputs = models.map { TreemapInputItem(id: $0.id, weight: Double($0.tokens.total)) }
                    let modelRects = SquarifiedTreemapLayout.compute(
                        items: modelInputs,
                        in: CGRect(x: 0, y: 0, width: contentWidth, height: contentHeight),
                        minVisualFraction: 0.04
                    )
                    let modelsById = Dictionary(uniqueKeysWithValues: models.enumerated().map { ($0.element.id, ($0.element, $0.offset)) })

                    var childTiles: [NestedModelRenderTile] = []
                    for mLayout in modelRects {
                        guard let (model, modelIndex) = modelsById[mLayout.id] else { continue }
                        let mRect = insetTileRect(mLayout.rect, gap: 2)
                        let palette = TreemapPalette.modelGradient(
                            for: agent.agent,
                            modelIndex: modelIndex,
                            fallbackIndex: agentIndex
                        )
                        let overallShare = Double(model.tokens.total) / totalDenom * 100
                        let targetId = "model|\(agent.id)|\(model.id)"
                        childTiles.append(
                            NestedModelRenderTile(
                                id: mLayout.id,
                                targetId: targetId,
                                title: model.name,
                                tokensText: model.tokens.total.tokenText,
                                sharePercent: overallShare,
                                localRect: mRect,
                                topColor: palette.top,
                                bottomColor: palette.bottom
                            )
                        )
                        let globalHitRect = CGRect(
                            x: contentOriginX + mLayout.rect.minX,
                            y: contentOriginY + mLayout.rect.minY,
                            width: mLayout.rect.width,
                            height: mLayout.rect.height
                        )
                        regions.append(
                            TreemapHitRegion(
                                rect: globalHitRect,
                                target: TreemapHoveredTarget(
                                    id: targetId,
                                    agentName: agent.displayName,
                                    modelName: model.name,
                                    tokens: model.tokens,
                                    sharePercent: overallShare,
                                    estimatedCost: nil,
                                    color: palette.solid
                                ),
                                drillAgentId: agent.id
                            )
                        )
                    }

                    // 组头与外框其余部分命中整个 Agent
                    regions.append(
                        TreemapHitRegion(
                            rect: groupLayout.rect,
                            target: TreemapHoveredTarget(
                                id: "agent|\(agent.id)",
                                agentName: agent.displayName,
                                modelName: nil,
                                tokens: agent.tokens,
                                sharePercent: groupShare,
                                estimatedCost: agent.estimatedCost,
                                color: headerColor
                            ),
                            drillAgentId: agent.id
                        )
                    )

                    renderGroups.append(
                        NestedAgentRenderGroup(
                            id: groupLayout.id,
                            agent: agent,
                            groupRect: groupRect,
                            groupShare: groupShare,
                            headerColor: headerColor,
                            showHeader: true,
                            headerHeight: headerHeight,
                            innerPadding: innerPadding,
                            contentSize: CGSize(width: contentWidth, height: contentHeight),
                            modelTiles: childTiles,
                            compactTopColor: compactPalette.top,
                            compactBottomColor: compactPalette.bottom
                        )
                    )
                } else {
                    regions.append(
                        TreemapHitRegion(
                            rect: groupLayout.rect,
                            target: TreemapHoveredTarget(
                                id: "agent|\(agent.id)",
                                agentName: agent.displayName,
                                modelName: nil,
                                tokens: agent.tokens,
                                sharePercent: groupShare,
                                estimatedCost: agent.estimatedCost,
                                color: compactPalette.solid
                            ),
                            drillAgentId: agent.id
                        )
                    )

                    renderGroups.append(
                        NestedAgentRenderGroup(
                            id: groupLayout.id,
                            agent: agent,
                            groupRect: groupRect,
                            groupShare: groupShare,
                            headerColor: headerColor,
                            showHeader: false,
                            headerHeight: 0,
                            innerPadding: 0,
                            contentSize: groupRect.size,
                            modelTiles: [],
                            compactTopColor: compactPalette.top,
                            compactBottomColor: compactPalette.bottom
                        )
                    )
                }
            }
            return (renderGroups, regions)
        }()

        ZStack(alignment: .topLeading) {
            ForEach(groups) { group in
                if group.showHeader {
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            AgentBrandLogo(agent: group.agent.agent, color: group.headerColor, size: 11)
                            Text(group.agent.displayName)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.primary.opacity(0.92))
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text("\(Int(group.groupShare.rounded()))%")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: group.headerHeight - 2)
                        .padding(.horizontal, 4)

                        ZStack(alignment: .topLeading) {
                            ForEach(group.modelTiles) { tile in
                                let isHovered = hoveredTarget?.id == tile.targetId
                                let isDimmed = hoveredTarget != nil && !isHovered

                                TreemapModelTile(
                                    title: tile.title,
                                    tokensText: tile.tokensText,
                                    sharePercent: tile.sharePercent,
                                    size: tile.localRect.size,
                                    topColor: tile.topColor,
                                    bottomColor: tile.bottomColor,
                                    cornerRadius: 5,
                                    isHovered: isHovered,
                                    isDimmed: isDimmed
                                )
                                .frame(width: tile.localRect.width, height: tile.localRect.height)
                                .offset(x: tile.localRect.minX, y: tile.localRect.minY)
                            }
                        }
                        .frame(width: group.contentSize.width, height: group.contentSize.height, alignment: .topLeading)
                    }
                    .padding(group.innerPadding)
                    .frame(width: group.groupRect.width, height: group.groupRect.height)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(group.headerColor.opacity(0.11))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(group.headerColor.opacity(0.28), lineWidth: 0.75)
                            )
                    )
                    .offset(x: group.groupRect.minX, y: group.groupRect.minY)
                } else {
                    let targetId = "agent|\(group.agent.id)"
                    let isHovered = hoveredTarget?.id == targetId
                    let isDimmed = hoveredTarget != nil && !isHovered

                    TreemapModelTile(
                        title: group.agent.displayName,
                        tokensText: group.agent.tokens.total.tokenText,
                        sharePercent: group.groupShare,
                        size: group.groupRect.size,
                        topColor: group.compactTopColor,
                        bottomColor: group.compactBottomColor,
                        cornerRadius: 7,
                        isHovered: isHovered,
                        isDimmed: isDimmed
                    )
                    .frame(width: group.groupRect.width, height: group.groupRect.height)
                    .offset(x: group.groupRect.minX, y: group.groupRect.minY)
                }
            }
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .overlay {
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let matched = hitRegions.first { $0.rect.contains(location) }?.target
                        if hoveredTarget?.id != matched?.id {
                            withAnimation(.easeOut(duration: 0.12)) {
                                hoveredTarget = matched
                            }
                        }
                    case .ended:
                        if hoveredTarget != nil {
                            withAnimation(.easeOut(duration: 0.12)) {
                                hoveredTarget = nil
                            }
                        }
                    }
                }
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        if let drillId = hitRegions.first(where: { $0.rect.contains(value.location) })?.drillAgentId {
                            drillDown(to: drillId)
                        }
                    }
                )
        }
    }

    /// 底部常驻单行/双行实时检视条：悬停任意色块时无截断展示完整模型名、Token 与四维构成
    private var inspectorStrip: some View {
        Group {
            if let hovered = hoveredTarget {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(hovered.color)
                            .frame(width: 8, height: 8)

                        Text(hovered.modelName ?? hovered.agentName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if hovered.modelName != nil, activeFocusedAgent == nil {
                            Text(hovered.agentName)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.07), in: Capsule())
                        }

                        Spacer(minLength: 4)

                        if let cost = hovered.estimatedCost, cost > 0 {
                            Text(cost.estimatedCostText)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.48))
                        }

                        Text(hovered.tokens.total.tokenText)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.primary)

                        Text("\(formatSharePercent(hovered.sharePercent))")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }

                    HStack(spacing: 8) {
                        inspectorMiniMetric("输入", hovered.tokens.input, .blue)
                        inspectorMiniMetric("输出", hovered.tokens.output, .mint)
                        inspectorMiniMetric("缓存", hovered.tokens.cacheRead + hovered.tokens.cacheWrite, .purple)
                        if hovered.tokens.reasoning > 0 {
                            inspectorMiniMetric("推理", hovered.tokens.reasoning, .orange)
                        }
                        Spacer(minLength: 0)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: activeFocusedAgent == nil ? "cursorarrow.click.2" : "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text(
                        activeFocusedAgent == nil
                            ? "悬停色块查看全名与构成 · 点击色块下钻 Agent"
                            : "悬停任意模型色块查看完整名称与四维构成"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                    Spacer(minLength: 4)

                    Text((activeFocusedAgent?.agent.tokens.total ?? totalTokens).tokenText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.indigo)
                }
                .frame(minHeight: 28)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.038))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.5)
                )
        )
        .animation(.easeOut(duration: 0.12), value: hoveredTarget?.id)
    }

    private func inspectorMiniMetric(_ label: String, _ value: Int64, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 4.5, height: 4.5)
            Text(label)
                .foregroundStyle(.tertiary)
            Text(value.tokenText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.system(size: 9))
    }

    private func drillDown(to agentId: String) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            focusedAgentId = agentId
            hoveredTarget = nil
        }
    }

    private func resolvedModels(for agent: AgentTokenUsage) -> [ModelTokenUsage] {
        if !agent.models.isEmpty {
            return agent.models
        }
        return [ModelTokenUsage(name: agent.displayName, tokens: agent.tokens)]
    }

    private func insetTileRect(_ rect: CGRect, gap: CGFloat) -> CGRect {
        let half = gap / 2
        let width = max(rect.width - gap, 1)
        let height = max(rect.height - gap, 1)
        return CGRect(x: rect.minX + half, y: rect.minY + half, width: width, height: height)
    }

    private func formatSharePercent(_ share: Double) -> String {
        if share > 0 && share < 1 {
            return "<1%"
        }
        return "\(Int(share.rounded()))%"
    }

    private func modelTooltip(agent: AgentTokenUsage, model: ModelTokenUsage, share: Double) -> String {
        let cacheTotal = model.tokens.cacheRead + model.tokens.cacheWrite
        return "\(agent.displayName) · \(model.name)：\(model.tokens.total.formattedWithSeparators) tokens（输入 \(model.tokens.input.tokenText) · 输出 \(model.tokens.output.tokenText) · 缓存 \(cacheTotal.tokenText) · 推理 \(model.tokens.reasoning.tokenText)）· 占比 \(formatSharePercent(share))"
    }
}

/// 单个矩形树图色块：通透柔光玻璃质感（自适应深浅色模式），与毛玻璃面板视觉重量和谐统一
private struct TreemapModelTile: View {
    let title: String
    let tokensText: String
    let sharePercent: Double
    let size: CGSize
    let topColor: Color
    let bottomColor: Color
    let cornerRadius: CGFloat
    let isHovered: Bool
    let isDimmed: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var shareLabel: String {
        if sharePercent > 0 && sharePercent < 1 {
            return "<1%"
        }
        return "\(Int(sharePercent.rounded()))%"
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let isDark = colorScheme == .dark

        let fillTopOpacity: Double = isDark
            ? (isHovered ? 0.50 : 0.34)
            : (isHovered ? 0.28 : 0.17)
        let fillBottomOpacity: Double = isDark
            ? (isHovered ? 0.34 : 0.19)
            : (isHovered ? 0.16 : 0.08)

        let borderTopOpacity: Double = isDark
            ? (isHovered ? 0.92 : 0.52)
            : (isHovered ? 0.72 : 0.36)
        let borderBottomOpacity: Double = isDark
            ? (isHovered ? 0.55 : 0.20)
            : (isHovered ? 0.40 : 0.18)

        ZStack(alignment: .topLeading) {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            topColor.opacity(fillTopOpacity),
                            bottomColor.opacity(fillBottomOpacity)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                isHovered
                                    ? (isDark ? Color.white.opacity(0.75) : topColor.opacity(0.85))
                                    : topColor.opacity(borderTopOpacity),
                                topColor.opacity(borderBottomOpacity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isHovered ? 1.25 : 0.75
                    )
                )

            tileContent(isDark: isDark)
                .padding(.horizontal, size.width >= 60 ? 7 : 3)
                .padding(.vertical, size.height >= 44 ? 6 : 2)
        }
        .opacity(isDimmed ? 0.55 : 1.0)
        .shadow(
            color: isHovered ? topColor.opacity(isDark ? 0.32 : 0.18) : Color.clear,
            radius: isHovered ? 5 : 0,
            y: isHovered ? 1.5 : 0
        )
        .contentShape(shape)
    }

    @ViewBuilder
    private func tileContent(isDark: Bool) -> some View {
        let primaryText = isDark ? Color.white.opacity(0.95) : Color.primary
        let secondaryText = isDark ? Color.white.opacity(0.84) : Color.primary.opacity(0.75)

        if size.width >= 64 && size.height >= 54 {
            let isLarge = size.width >= 112
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: isLarge ? 11 : 9.5, weight: .semibold))
                    .foregroundStyle(secondaryText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 2)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(tokensText)
                        .font(.system(size: size.width >= 150 ? 16 : (isLarge ? 13 : 11), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(primaryText)
                        .lineLimit(1)

                    if isLarge {
                        Text(shareLabel)
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(primaryText)
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1.5)
                            .background(
                                topColor.opacity(isDark ? 0.32 : 0.18),
                                in: Capsule()
                            )
                    } else {
                        Text(shareLabel)
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(secondaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if size.width >= 56 && size.height >= 34 {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Text(tokensText)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                    Text(shareLabel)
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(secondaryText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if size.width >= 24 && size.height >= 18 {
            Text(shareLabel)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            EmptyView()
        }
    }
}

// MARK: - 环形占比图（纤细现代柔光 Donut Chart）

private struct AgentDonutChartView: View {
    let items: [AgentChartItem]
    let centerTotalText: String
    let centerSubtitle: String
    let isAgentLevel: Bool
    @Binding var hoveredTarget: TreemapHoveredTarget?
    let onDrillDown: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private struct DonutSlice: Identifiable {
        let id: String
        let item: AgentChartItem
        let startAngle: Double // 从 12 点钟方向顺时针起算，范围 [0, 2π]
        let endAngle: Double
    }

    private var slices: [DonutSlice] {
        let positive = items.filter { $0.tokens.total > 0 }
        let total = positive.reduce(0.0) { $0 + Double($1.tokens.total) }
        guard total > 0 else { return [] }

        let minAngle = positive.count > 1 ? min(0.075, (2 * .pi * 0.26) / Double(positive.count)) : 0
        let rawAngles = positive.map { (Double($0.tokens.total) / total) * 2 * .pi }
        let adjusted = rawAngles.map { max($0, minAngle) }
        let adjustedSum = adjusted.reduce(0, +)
        let scale = (2 * .pi) / max(adjustedSum, 0.0001)

        var result: [DonutSlice] = []
        var cursor: Double = 0
        for (idx, item) in positive.enumerated() {
            let sweep = adjusted[idx] * scale
            result.append(
                DonutSlice(
                    id: item.id,
                    item: item,
                    startAngle: cursor,
                    endAngle: cursor + sweep
                )
            )
            cursor += sweep
        }
        return result
    }

    private var activeHoveredItem: AgentChartItem? {
        guard let hoveredId = hoveredTarget?.id else { return nil }
        return items.first(where: { $0.id == hoveredId })
    }

    var body: some View {
        let computedSlices = slices

        HStack(spacing: 12) {
            donutRing(slices: computedSlices)
                .frame(width: 140, height: 140)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(items) { item in
                        donutLegendRow(item)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func donutRing(slices: [DonutSlice]) -> some View {
        let isDark = colorScheme == .dark
        return GeometryReader { geometry in
            let size = geometry.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerRadius = min(size.width, size.height) / 2 - 6
            let thickness: CGFloat = 14
            let innerRadius = max(outerRadius - thickness, 20)
            let gapRadians: Double = slices.count > 1 ? 0.038 : 0

            ZStack {
                Canvas { context, _ in
                    let trackRadius = outerRadius - thickness / 2
                    let trackRect = CGRect(
                        x: center.x - trackRadius,
                        y: center.y - trackRadius,
                        width: trackRadius * 2,
                        height: trackRadius * 2
                    )
                    context.stroke(
                        Path(ellipseIn: trackRect),
                        with: .color(Color.primary.opacity(0.065)),
                        lineWidth: thickness
                    )

                    for slice in slices {
                        let isHovered = hoveredTarget?.id == slice.id
                        let isDimmed = hoveredTarget != nil && !isHovered
                        let sweep = slice.endAngle - slice.startAngle
                        let effectiveGap = min(gapRadians, sweep * 0.25)
                        let sAngle = slice.startAngle + effectiveGap / 2 - .pi / 2
                        let eAngle = slice.endAngle - effectiveGap / 2 - .pi / 2
                        guard eAngle > sAngle else { continue }

                        let rOuter = outerRadius + (isHovered ? 3.5 : 0)
                        let rInner = innerRadius - (isHovered ? 0.5 : 0)

                        var path = Path()
                        path.addArc(
                            center: center,
                            radius: rOuter,
                            startAngle: .radians(sAngle),
                            endAngle: .radians(eAngle),
                            clockwise: false
                        )
                        path.addArc(
                            center: center,
                            radius: rInner,
                            startAngle: .radians(eAngle),
                            endAngle: .radians(sAngle),
                            clockwise: true
                        )
                        path.closeSubpath()

                        let baseAlpha = isDimmed ? 0.28 : (isHovered ? 0.92 : (isDark ? 0.72 : 0.78))
                        let tailAlpha = isDimmed ? 0.18 : (isHovered ? 0.76 : (isDark ? 0.50 : 0.56))
                        context.fill(
                            path,
                            with: .linearGradient(
                                Gradient(colors: [
                                    slice.item.topColor.opacity(baseAlpha),
                                    slice.item.bottomColor.opacity(tailAlpha)
                                ]),
                                startPoint: CGPoint(x: center.x - rOuter, y: center.y - rOuter),
                                endPoint: CGPoint(x: center.x + rOuter, y: center.y + rOuter)
                            )
                        )
                        context.stroke(
                            path,
                            with: .color(
                                isHovered
                                    ? Color.white.opacity(isDark ? 0.75 : 0.9)
                                    : slice.item.topColor.opacity(isDimmed ? 0.15 : 0.45)
                            ),
                            lineWidth: isHovered ? 1.1 : 0.6
                        )
                    }
                }
                .contentShape(Circle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let hit = hitSlice(
                            at: location,
                            center: center,
                            innerRadius: innerRadius - 8,
                            outerRadius: outerRadius + 8,
                            slices: slices
                        )
                        if hoveredTarget?.id != hit?.id {
                            withAnimation(.easeOut(duration: 0.12)) {
                                hoveredTarget = hit.map { makeHoveredTarget(from: $0.item) }
                            }
                        }
                    case .ended:
                        if hoveredTarget != nil {
                            withAnimation(.easeOut(duration: 0.12)) {
                                hoveredTarget = nil
                            }
                        }
                    }
                }
                .onTapGesture {
                    if let drillId = activeHoveredItem?.drillAgentId {
                        onDrillDown(drillId)
                    }
                }

                // 环中心实时读数
                VStack(spacing: 1.5) {
                    if let hovered = activeHoveredItem {
                        Text(formatPercent(hovered.sharePercent))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(hovered.topColor)
                            .contentTransition(.numericText())
                        Text(hovered.tokens.total.tokenText)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                        Text(hovered.title)
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 80)
                    } else {
                        Text(centerTotalText)
                            .font(.system(size: 16.5, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                        Text(centerSubtitle)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func donutLegendRow(_ item: AgentChartItem) -> some View {
        let isHovered = hoveredTarget?.id == item.id
        let isDimmed = hoveredTarget != nil && !isHovered

        return HStack(spacing: 6) {
            if isAgentLevel {
                AgentBrandLogo(agent: item.agentKey, color: item.topColor, size: 12)
            } else {
                Circle()
                    .fill(item.topColor)
                    .frame(width: 6.5, height: 6.5)
            }

            Text(item.title)
                .font(.system(size: 10.5, weight: isHovered ? .semibold : .regular))
                .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            Text(item.tokens.total.tokenText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(isHovered ? Color.primary : Color.secondary)

            Text(formatPercent(item.sharePercent))
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isHovered ? AnyShapeStyle(item.topColor) : AnyShapeStyle(.tertiary))
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4.5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? item.topColor.opacity(0.14) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isHovered ? item.topColor.opacity(0.32) : Color.clear, lineWidth: 0.6)
                )
        )
        .opacity(isDimmed ? 0.55 : 1.0)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                if hovering {
                    hoveredTarget = makeHoveredTarget(from: item)
                } else if hoveredTarget?.id == item.id {
                    hoveredTarget = nil
                }
            }
        }
        .onTapGesture {
            if let drillId = item.drillAgentId {
                onDrillDown(drillId)
            }
        }
    }

    private func hitSlice(
        at point: CGPoint,
        center: CGPoint,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        slices: [DonutSlice]
    ) -> DonutSlice? {
        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        let dist = sqrt(dx * dx + dy * dy)
        guard dist >= Double(innerRadius), dist <= Double(outerRadius) else { return nil }
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        return slices.first { angle >= $0.startAngle && angle <= $0.endAngle }
    }

    private func makeHoveredTarget(from item: AgentChartItem) -> TreemapHoveredTarget {
        TreemapHoveredTarget(
            id: item.id,
            agentName: item.agentName,
            modelName: isAgentLevel ? nil : item.title,
            tokens: item.tokens,
            sharePercent: item.sharePercent,
            estimatedCost: item.estimatedCost,
            color: item.topColor
        )
    }

    private func formatPercent(_ value: Double) -> String {
        if value > 0 && value < 1 { return "<1%" }
        return "\(Int(value.rounded()))%"
    }
}

// MARK: - 排行柱状图（自适应高度 + 柔光轨道柱）

private struct AgentRankedBarChartView: View {
    let items: [AgentChartItem]
    let isAgentLevel: Bool
    @Binding var hoveredTarget: TreemapHoveredTarget?
    let onDrillDown: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var maxTokens: Double {
        Double(max(items.map(\.tokens.total).max() ?? 1, 1))
    }

    var body: some View {
        let peak = maxTokens
        let content = VStack(spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                barRow(rank: idx + 1, item: item, maxVal: peak)
            }
        }
        .padding(.vertical, 2)

        if items.count > 5 {
            ScrollView(.vertical, showsIndicators: false) {
                content
            }
            .frame(height: 186)
        } else {
            content
        }
    }

    private func barRow(rank: Int, item: AgentChartItem, maxVal: Double) -> some View {
        let isHovered = hoveredTarget?.id == item.id
        let isDimmed = hoveredTarget != nil && !isHovered
        let isDark = colorScheme == .dark
        let relativeRatio = min(max(Double(item.tokens.total) / maxVal, 0), 1)
        let shareLabel = (item.sharePercent > 0 && item.sharePercent < 1)
            ? "<1%"
            : "\(Int(item.sharePercent.rounded()))%"

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(String(format: "%02d", rank))
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(rank <= 3 ? AnyShapeStyle(item.topColor) : AnyShapeStyle(.tertiary))
                    .frame(width: 16, alignment: .leading)

                if isAgentLevel {
                    AgentBrandLogo(agent: item.agentKey, color: item.topColor, size: 12)
                }

                Text(item.title)
                    .font(.system(size: 10.5, weight: isHovered ? .semibold : .medium))
                    .foregroundStyle(isHovered ? Color.primary : Color.primary.opacity(0.86))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if let cost = item.estimatedCost, cost > 0 {
                    Text(cost.estimatedCostText)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.48))
                }

                Text(item.tokens.total.tokenText)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(isHovered ? Color.primary : Color.secondary)

                Text(shareLabel)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isHovered ? AnyShapeStyle(item.topColor) : AnyShapeStyle(.tertiary))
                    .frame(width: 30, alignment: .trailing)
            }

            GeometryReader { proxy in
                let barWidth = max(6, proxy.size.width * CGFloat(relativeRatio))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.065))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.primary.opacity(0.045), lineWidth: 0.5)
                        )

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    item.topColor.opacity(isHovered ? 0.92 : (isDark ? 0.72 : 0.76)),
                                    item.bottomColor.opacity(isHovered ? 0.76 : (isDark ? 0.48 : 0.52))
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    isHovered
                                        ? Color.white.opacity(isDark ? 0.65 : 0.85)
                                        : item.topColor.opacity(0.42),
                                    lineWidth: isHovered ? 0.9 : 0.5
                                )
                        )
                        .frame(width: barWidth)
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4.5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovered ? item.topColor.opacity(0.11) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isHovered ? item.topColor.opacity(0.28) : Color.clear, lineWidth: 0.6)
                )
        )
        .opacity(isDimmed ? 0.52 : 1.0)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                if hovering {
                    hoveredTarget = TreemapHoveredTarget(
                        id: item.id,
                        agentName: item.agentName,
                        modelName: isAgentLevel ? nil : item.title,
                        tokens: item.tokens,
                        sharePercent: item.sharePercent,
                        estimatedCost: item.estimatedCost,
                        color: item.topColor
                    )
                } else if hoveredTarget?.id == item.id {
                    hoveredTarget = nil
                }
            }
        }
        .onTapGesture {
            if let drillId = item.drillAgentId {
                onDrillDown(drillId)
            }
        }
    }
}

// MARK: - Agent 用量分组与模型明细

private struct AgentUsageGroupView: View {
    @State private var showModels = false
    @State private var isHovered = false
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
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    showModels.toggle()
                }
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        AgentBrandLogo(agent: agent.agent, color: color, size: 15, showsBackground: true)

                        Text(agent.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 6)

                        if let cost = agent.estimatedCost, cost > 0 {
                            Text(cost.estimatedCostText)
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.48))
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 1.5)
                                .background(Color.green.opacity(0.11), in: Capsule())
                        }

                        if !agent.models.isEmpty {
                            HStack(spacing: 3) {
                                Text("\(agent.models.count) 模型")
                                    .font(.system(size: 9.5))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 7.5, weight: .bold))
                                    .rotationEffect(.degrees(showModels ? 180 : 0))
                            }
                            .foregroundStyle(isHovered ? .secondary : .tertiary)
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(isHovered ? 0.07 : 0.035), in: Capsule())
                        }
                    }

                    HStack(spacing: 6) {
                        Text("用量")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)

                        AccountQuotaBar(percent: percent, style: .usage, tint: color, isEmphasized: isHovered)
                            .animation(.easeOut(duration: 0.42), value: percent)

                        Text(agent.tokens.total.tokenText)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.85))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)

                        Text("\(roundedPercent)%")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHovered ? Color.primary.opacity(0.045) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.14)) {
                    isHovered = hovering
                }
            }
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
        VStack(spacing: 4) {
            ForEach(models) { model in
                ModelUsageRow(model: model, total: total, color: color)
            }
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color.opacity(0.32))
                .frame(width: 2)
                .padding(.vertical, 2)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.bottom, 4)
    }
}

private struct ModelUsageRow: View {
    let model: ModelTokenUsage
    let total: Int64
    let color: Color
    @State private var isHovered = false

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

        return HStack(spacing: 6) {
            Text(model.name)
                .font(.caption2)
                .foregroundStyle(isHovered ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 118, alignment: .leading)

            AccountQuotaBar(percent: percent, style: .usage, tint: color.opacity(0.82), isEmphasized: isHovered)
                .animation(.easeOut(duration: 0.42), value: percent)

            Text(model.tokens.total.tokenText)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)

            Text("\(roundedPercent)%")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2.5)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .help(detailedHelpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(model.name)，\(model.tokens.total.tokenText) Token，占该 Agent \(roundedPercent)%"
        )
    }
}

// MARK: - 品牌图标缓存与渲染

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
            showsBackground ? color.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
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

// MARK: - 轻量级自适应深浅色卡片容器

/// 轻量级卡片容器修饰符：由于 NSPopover 窗口自身已具备系统毛玻璃背景，
/// 避免在每个卡片上重复创建独立的 NSVisualEffectView (.ultraThinMaterial)，兼顾质感与低 GPU 负载。
private struct AdaptiveGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    var accent: Color? = nil
    var isHighlighted: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let isDark = colorScheme == .dark

        let fillGradient = LinearGradient(
            colors: isDark
                ? [
                    Color.white.opacity(isHighlighted ? 0.085 : 0.062),
                    Color.white.opacity(isHighlighted ? 0.045 : 0.030)
                ]
                : [
                    Color.white.opacity(isHighlighted ? 0.82 : 0.68),
                    Color.white.opacity(isHighlighted ? 0.62 : 0.46)
                ],
            startPoint: .top,
            endPoint: .bottom
        )

        let borderGradient = LinearGradient(
            colors: isDark
                ? [
                    (accent ?? Color.white).opacity(isHighlighted ? 0.45 : 0.18),
                    Color.white.opacity(0.06),
                    Color.white.opacity(0.03)
                ]
                : [
                    (accent ?? Color.white).opacity(isHighlighted ? 0.50 : 0.85),
                    Color.black.opacity(0.06),
                    Color.black.opacity(0.09)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        content.background(
            shape
                .fill(fillGradient)
                .overlay {
                    if let accent {
                        shape.fill(
                            LinearGradient(
                                colors: [accent.opacity(isDark ? 0.10 : 0.07), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                }
                .overlay(
                    shape.strokeBorder(borderGradient, lineWidth: isHighlighted ? 0.9 : 0.65)
                )
                .shadow(
                    color: Color.black.opacity(isDark ? 0.16 : 0.055),
                    radius: isHighlighted ? 6 : 4,
                    x: 0,
                    y: 2
                )
        )
    }
}

private extension View {
    func tokenCard(
        cornerRadius: CGFloat = 12,
        accent: Color? = nil,
        isHighlighted: Bool = false
    ) -> some View {
        modifier(AdaptiveGlassCardModifier(cornerRadius: cornerRadius, accent: accent, isHighlighted: isHighlighted))
    }
}

// MARK: - 系统图表与指标组件

private struct SpeedValue: View {
    let title: String
    let value: Double
    let color: Color
    let symbol: String

    var body: some View {
        let formattedSpeed = value.speedText
        return HStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.14))
                    .frame(width: 16, height: 16)
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                Text(formattedSpeed)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
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
    let secondaryColor: Color
    let systemImage: String

    @State private var isHovered = false

    var body: some View {
        let formattedPercent = value.percentText
        let clamped = min(max(value, 0), 1)

        return HStack(spacing: 11) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.14), lineWidth: 6.5)

                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [color, secondaryColor, color]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 6.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.35), value: clamped)

                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 52, height: 52)
            .accessibilityLabel(title)
            .accessibilityValue(formattedPercent)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(formattedPercent)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity)
        .tokenCard(accent: isHovered ? color : nil, isHighlighted: isHovered)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
    }
}

private struct HistoryChart: View {
    let cpu: [Double]
    let memory: [Double]
    @State private var hoverLocation: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let hoverIndex = hoverLocation.flatMap { sampleIndex(at: $0.x, width: geometry.size.width) }

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawGrid(in: &context, size: size)
                    drawSeries(cpu, color: .blue, in: &context, size: size)
                    drawSeries(memory, color: .orange, in: &context, size: size)
                    if let location = hoverLocation, let index = hoverIndex {
                        drawHoverIndicator(at: location, index: index, in: &context, size: size)
                    }
                }

                if let location = hoverLocation, let index = hoverIndex {
                    let cpuVal = cpu.indices.contains(index) ? cpu[index] : 0
                    let memVal = memory.indices.contains(index) ? memory[index] : 0
                    let secondsAgo = max(0, cpu.count - 1 - index)
                    let timeText = secondsAgo == 0 ? "现在" : "\(secondsAgo)s 前"

                    HStack(spacing: 6) {
                        Text(timeText)
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text("CPU \(cpuVal.percentText)")
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.blue)
                        Text("内存 \(memVal.percentText)")
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.regularMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
                    )
                    .position(
                        x: min(max(location.x, 78), geometry.size.width - 78),
                        y: 12
                    )
                    .allowsHitTesting(false)
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

    private func drawHoverIndicator(
        at location: CGPoint,
        index: Int,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let countMinusOne = CGFloat(max(cpu.count - 1, 1))
        let x = size.width * CGFloat(index) / countMinusOne

        var line = Path()
        line.move(to: CGPoint(x: x, y: 0))
        line.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(line, with: .color(.primary.opacity(0.28)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))

        if cpu.indices.contains(index) {
            let y = size.height * (1 - CGFloat(min(max(cpu[index], 0), 1)))
            drawHighlightDot(at: CGPoint(x: x, y: y), color: .blue, in: &context)
        }
        if memory.indices.contains(index) {
            let y = size.height * (1 - CGFloat(min(max(memory[index], 0), 1)))
            drawHighlightDot(at: CGPoint(x: x, y: y), color: .orange, in: &context)
        }
    }

    private func drawHighlightDot(at point: CGPoint, color: Color, in context: inout GraphicsContext) {
        let outer = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
        let inner = CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)
        context.fill(Path(ellipseIn: outer), with: .color(color.opacity(0.28)))
        context.fill(Path(ellipseIn: inner), with: .color(color))
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        for ratio in [0.25, 0.5, 0.75] {
            let y = size.height * ratio
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(path, with: .color(.secondary.opacity(0.13)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
    }

    private func drawSeries(
        _ values: [Double],
        color: Color,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard values.count > 1 else { return }

        var strokePath = Path()
        var areaPath = Path()
        let countMinusOne = CGFloat(values.count - 1)

        for (index, value) in values.enumerated() {
            let x = size.width * CGFloat(index) / countMinusOne
            let y = size.height * (1 - CGFloat(min(max(value, 0), 1)))
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                strokePath.move(to: point)
                areaPath.move(to: CGPoint(x: x, y: size.height))
                areaPath.addLine(to: point)
            } else {
                strokePath.addLine(to: point)
                areaPath.addLine(to: point)
            }
        }

        areaPath.addLine(to: CGPoint(x: size.width, y: size.height))
        areaPath.closeSubpath()

        context.fill(
            areaPath,
            with: .linearGradient(
                Gradient(colors: [color.opacity(0.18), color.opacity(0.0)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )
        context.stroke(strokePath, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }
}

private struct NetworkHistoryChart: View {
    let download: [Double]
    let upload: [Double]
    let scaleMaximum: Double
    @State private var hoverLocation: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let hoverIndex = hoverLocation.flatMap { sampleIndex(at: $0.x, width: geometry.size.width) }

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawGrid(in: &context, size: size)
                    drawSeries(download, color: .cyan, in: &context, size: size)
                    drawSeries(upload, color: .purple, in: &context, size: size)
                    if let location = hoverLocation, let index = hoverIndex {
                        drawHoverIndicator(at: location, index: index, in: &context, size: size)
                    }
                }

                if let location = hoverLocation, let index = hoverIndex {
                    let dlVal = download.indices.contains(index) ? download[index] : 0
                    let ulVal = upload.indices.contains(index) ? upload[index] : 0
                    let secondsAgo = max(0, download.count - 1 - index)
                    let timeText = secondsAgo == 0 ? "现在" : "\(secondsAgo)s 前"

                    HStack(spacing: 6) {
                        Text(timeText)
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text("↓ \(dlVal.speedText)")
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.cyan)
                        Text("↑ \(ulVal.speedText)")
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.purple)
                    }
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.regularMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
                    )
                    .position(
                        x: min(max(location.x, 82), geometry.size.width - 82),
                        y: 12
                    )
                    .allowsHitTesting(false)
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

    private func drawHoverIndicator(
        at location: CGPoint,
        index: Int,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let countMinusOne = CGFloat(max(download.count - 1, 1))
        let maxVal = max(scaleMaximum, 1)
        let x = size.width * CGFloat(index) / countMinusOne

        var line = Path()
        line.move(to: CGPoint(x: x, y: 0))
        line.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(line, with: .color(.primary.opacity(0.28)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))

        if download.indices.contains(index) {
            let ratio = min(max(download[index] / maxVal, 0), 1)
            let y = size.height * (1 - CGFloat(ratio))
            drawHighlightDot(at: CGPoint(x: x, y: y), color: .cyan, in: &context)
        }
        if upload.indices.contains(index) {
            let ratio = min(max(upload[index] / maxVal, 0), 1)
            let y = size.height * (1 - CGFloat(ratio))
            drawHighlightDot(at: CGPoint(x: x, y: y), color: .purple, in: &context)
        }
    }

    private func drawHighlightDot(at point: CGPoint, color: Color, in context: inout GraphicsContext) {
        let outer = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
        let inner = CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)
        context.fill(Path(ellipseIn: outer), with: .color(color.opacity(0.28)))
        context.fill(Path(ellipseIn: inner), with: .color(color))
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
            with: .color(.secondary.opacity(0.13)),
            style: StrokeStyle(lineWidth: 0.5, dash: [3, 3])
        )
    }

    private func drawSeries(
        _ values: [Double],
        color: Color,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard values.count > 1 else { return }

        // 在循环外提取常量，避免循环内重复遍历数组
        let maxVal = max(scaleMaximum, 1)
        let countMinusOne = CGFloat(values.count - 1)
        var strokePath = Path()
        var areaPath = Path()

        for (index, value) in values.enumerated() {
            let x = size.width * CGFloat(index) / countMinusOne
            let ratio = min(max(value / maxVal, 0), 1)
            let y = size.height * (1 - CGFloat(ratio))
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                strokePath.move(to: point)
                areaPath.move(to: CGPoint(x: x, y: size.height))
                areaPath.addLine(to: point)
            } else {
                strokePath.addLine(to: point)
                areaPath.addLine(to: point)
            }
        }

        areaPath.addLine(to: CGPoint(x: size.width, y: size.height))
        areaPath.closeSubpath()

        context.fill(
            areaPath,
            with: .linearGradient(
                Gradient(colors: [color.opacity(0.20), color.opacity(0.0)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )
        context.stroke(
            strokePath,
            with: .color(color),
            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
        )

        if let last = values.last {
            let y = size.height * (1 - CGFloat(min(max(last / maxVal, 0), 1)))
            let halo = CGRect(x: size.width - 4.5, y: y - 4.5, width: 9, height: 9)
            let marker = CGRect(x: size.width - 2.5, y: y - 2.5, width: 5, height: 5)
            context.fill(Path(ellipseIn: halo), with: .color(color.opacity(0.25)))
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
    var dotColor: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor.opacity(0.75))
                .frame(width: 5, height: 5)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }
}
