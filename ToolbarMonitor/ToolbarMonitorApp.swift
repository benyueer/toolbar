import AppKit
import Combine
import SwiftUI

@MainActor
final class PopoverVisibility: ObservableObject {
    @Published var isShown = false
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let metrics = SystemMetrics()
    private let tokenUsage = TokenUsageMonitor()
    private let popover = NSPopover()
    private let popoverVisibility = PopoverVisibility()
    private var statusItem: NSStatusItem?
    private var tokenObservation: AnyCancellable?
    private var lastRenderedState: StatusDisplayState?

    // 缓存 Token 与花费文本对应的测量宽度，避免每秒因网速变化重绘时重复调用 CoreText 测量
    private var cachedTokenMeasureKey: String?
    private var cachedTokenWidth: CGFloat = 35
    private var hasConfiguredPopoverWindow = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard isSingleInstance() else {
            // 已有其他实例正在运行，自动退出避免重复常驻菜单栏
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        configurePopover()
        configureStatusItem()
        observeMetrics()
        updateStatusItem()
    }

    /// 校验是否为唯一运行中的实例
    private func isSingleInstance() -> Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else { return true }
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        return !runningApps.contains { $0.processIdentifier != currentPid }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 420, height: 680)
        popover.contentViewController = NSHostingController(
            rootView: SystemDetailsView(
                metrics: metrics,
                tokenUsage: tokenUsage,
                popoverVisibility: popoverVisibility
            )
        )
    }

    // MARK: - NSPopoverDelegate

    func popoverWillShow(_ notification: Notification) {
        metrics.isDashboardVisible = true
        popoverVisibility.isShown = true
        metrics.refresh()
    }

    func popoverDidClose(_ notification: Notification) {
        popoverVisibility.isShown = false
        metrics.isDashboardVisible = false
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.toolTip = "CPU / 内存 / 实时网速 / 今日 Token / 预估花费"
        statusItem = item
    }

    private func observeMetrics() {
        // 直接使用主线程同步回调，避免 Combine + DispatchQueue.main.async 双重异步派发
        metrics.onMetricsUpdated = { [weak self] in
            self?.updateStatusItem()
        }
        tokenObservation = tokenUsage.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusItem()
            }
        }
    }

    private struct StatusDisplayState: Equatable {
        let cpu: String
        let mem: String
        let up: String
        let down: String
        let token: String
        let cost: String
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        let isInitialLoading = tokenUsage.isRefreshing && tokenUsage.snapshot.days.isEmpty
        let tokenText = isInitialLoading ? "···" : tokenUsage.snapshot.today.total.tokenText
        let costText = isInitialLoading
            ? "···"
            : tokenUsage.snapshot.todayEstimatedCost?.estimatedCostText ?? "—"
        let cpuText = metrics.cpu.total.percentText
        let memText = metrics.memory.utilization.percentText
        let upText = metrics.network.uploadBytesPerSecond.speedText
        let downText = metrics.network.downloadBytesPerSecond.speedText

        let currentState = StatusDisplayState(
            cpu: cpuText,
            mem: memText,
            up: upText,
            down: downText,
            token: tokenText,
            cost: costText
        )

        // 仅在文本内容有变动时才重新绘制图片并更新菜单栏，避免每秒无意义重绘
        guard currentState != lastRenderedState else { return }
        lastRenderedState = currentState

        let tokenWidth = resolvedTokenWidth(tokenText: tokenText, costText: costText)
        let image = makeStatusImage(
            cpuText: cpuText,
            memText: memText,
            upText: upText,
            downText: downText,
            tokenText: tokenText,
            costText: costText,
            tokenWidth: tokenWidth
        )
        button.image = image

        let targetLength = image.size.width + 2
        if let statusItem, abs(statusItem.length - targetLength) > 0.1 {
            statusItem.length = targetLength
        }

        let estimatedCostLabel = tokenUsage.snapshot.todayEstimatedCost.map {
            "，预估花费 \($0.estimatedCostText)"
        } ?? ""
        button.setAccessibilityLabel(
            "CPU \(cpuText)，上传 \(upText)，" +
            "内存 \(memText)，下载 \(downText)，" +
            "今日 Token \(tokenText)\(estimatedCostLabel)"
        )
    }

    private func resolvedTokenWidth(tokenText: String, costText: String) -> CGFloat {
        let key = "\(tokenText)|\(costText)"
        if key == cachedTokenMeasureKey {
            return cachedTokenWidth
        }
        let tokenTextSize = (tokenText as NSString).size(withAttributes: StatusDrawingStyles.tokenAttributes)
        let costTextSize = (costText as NSString).size(withAttributes: StatusDrawingStyles.costAttributes)
        let width = max(35, ceil(max(tokenTextSize.width, costTextSize.width)) + 4)
        cachedTokenMeasureKey = key
        cachedTokenWidth = width
        return width
    }

    private func makeStatusImage(
        cpuText: String,
        memText: String,
        upText: String,
        downText: String,
        tokenText: String,
        costText: String,
        tokenWidth: CGFloat
    ) -> NSImage {
        let totalWidth: CGFloat = 100 + tokenWidth
        let size = NSSize(width: totalWidth, height: 22)

        let image = NSImage(size: size, flipped: true) { _ in
            let rowHeight = size.height / 2
            let percentageWidth: CGFloat = 25
            let arrowX: CGFloat = 27
            let arrowWidth: CGFloat = 8
            let speedX: CGFloat = 37
            let speedWidth: CGFloat = 55
            let dividerX: CGFloat = 95
            let tokenX: CGFloat = 100

            (cpuText as NSString).draw(
                in: NSRect(x: 0, y: 0, width: percentageWidth, height: rowHeight),
                withAttributes: StatusDrawingStyles.attributes
            )
            ("↑" as NSString).draw(
                in: NSRect(x: arrowX, y: 0, width: arrowWidth, height: rowHeight),
                withAttributes: StatusDrawingStyles.attributes
            )
            (upText as NSString).draw(
                in: NSRect(x: speedX, y: 0, width: speedWidth, height: rowHeight),
                withAttributes: StatusDrawingStyles.attributes
            )
            (memText as NSString).draw(
                in: NSRect(x: 0, y: rowHeight, width: percentageWidth, height: rowHeight),
                withAttributes: StatusDrawingStyles.attributes
            )
            ("↓" as NSString).draw(
                in: NSRect(x: arrowX, y: rowHeight, width: arrowWidth, height: rowHeight),
                withAttributes: StatusDrawingStyles.attributes
            )
            (downText as NSString).draw(
                in: NSRect(x: speedX, y: rowHeight, width: speedWidth, height: rowHeight),
                withAttributes: StatusDrawingStyles.attributes
            )

            StatusDrawingStyles.dividerColor.setFill()
            NSRect(x: dividerX - 0.25, y: 3, width: 0.5, height: size.height - 6).fill()

            (tokenText as NSString).draw(
                in: NSRect(x: tokenX, y: 0, width: tokenWidth, height: 13),
                withAttributes: StatusDrawingStyles.tokenAttributes
            )
            (costText as NSString).draw(
                in: NSRect(x: tokenX, y: 12, width: tokenWidth, height: 10),
                withAttributes: StatusDrawingStyles.costAttributes
            )
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc
    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            popoverVisibility.isShown = false
            metrics.isDashboardVisible = false
        } else {
            metrics.isDashboardVisible = true
            popoverVisibility.isShown = true
            metrics.refresh()
            NSApp.activate()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            if let window = popover.contentViewController?.view.window {
                if !hasConfiguredPopoverWindow {
                    window.isOpaque = false
                    window.backgroundColor = .clear
                    window.contentView?.wantsLayer = true
                    window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
                    popover.contentViewController?.view.wantsLayer = true
                    popover.contentViewController?.view.layer?.backgroundColor = NSColor.clear.cgColor
                    hasConfiguredPopoverWindow = true
                }
                window.makeKey()
            }
        }
    }
}

/// 菜单栏 StatusItem 绘图重用样式
@MainActor
private enum StatusDrawingStyles {
    static let font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)
    static let tokenFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
    static let costFont = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .bold)
    static let dividerColor = NSColor.black.withAlphaComponent(0.28)

    static let textStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.lineBreakMode = .byClipping
        return style
    }()

    static let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.black,
        .paragraphStyle: textStyle,
    ]

    static let tokenAttributes: [NSAttributedString.Key: Any] = [
        .font: tokenFont,
        .foregroundColor: NSColor.black,
        .paragraphStyle: stackedMetricTextStyle,
    ]

    static let costAttributes: [NSAttributedString.Key: Any] = [
        .font: costFont,
        .foregroundColor: NSColor.black.withAlphaComponent(0.92),
        .paragraphStyle: stackedMetricTextStyle,
    ]

    private static let stackedMetricTextStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byClipping
        return style
    }()
}

@main
@MainActor
struct ToolbarMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
