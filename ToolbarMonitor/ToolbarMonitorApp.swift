import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let metrics = SystemMetrics()
    private let tokenUsage = TokenUsageMonitor()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var metricsObservation: AnyCancellable?
    private var tokenObservation: AnyCancellable?

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
        popover.contentSize = NSSize(width: 420, height: 680)
        popover.contentViewController = NSHostingController(
            rootView: SystemDetailsView(metrics: metrics, tokenUsage: tokenUsage)
        )
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
        metricsObservation = metrics.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusItem()
            }
        }
        tokenObservation = tokenUsage.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusItem()
            }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        let image = makeStatusImage()
        button.image = image
        statusItem?.length = image.size.width + 2
        let estimatedCostLabel = tokenUsage.snapshot.todayEstimatedCost.map {
            "，预估花费 \($0.estimatedCostText)"
        } ?? ""
        button.setAccessibilityLabel(
            "CPU \(metrics.cpu.total.percentText)，上传 \(metrics.network.uploadBytesPerSecond.speedText)，" +
            "内存 \(metrics.memory.utilization.percentText)，下载 \(metrics.network.downloadBytesPerSecond.speedText)，" +
            "今日 Token \(tokenUsage.snapshot.today.total.tokenText)\(estimatedCostLabel)"
        )
    }

    private func makeStatusImage() -> NSImage {
        let isInitialLoading = tokenUsage.isRefreshing && tokenUsage.snapshot.days.isEmpty
        let tokenText = isInitialLoading ? "···" : tokenUsage.snapshot.today.total.tokenText
        let costText = isInitialLoading
            ? "···"
            : tokenUsage.snapshot.todayEstimatedCost?.estimatedCostText ?? "—"

        let tokenTextSize = (tokenText as NSString).size(withAttributes: StatusDrawingStyles.tokenAttributes)
        let costTextSize = (costText as NSString).size(withAttributes: StatusDrawingStyles.costAttributes)
        let tokenWidth = max(35, ceil(max(tokenTextSize.width, costTextSize.width)) + 4)
        let totalWidth: CGFloat = 100 + tokenWidth
        let size = NSSize(width: totalWidth, height: 22)

        let image = NSImage(size: size, flipped: true) { [metrics, tokenText, costText] _ in
            let rowHeight = size.height / 2
            let percentageWidth: CGFloat = 25
            let arrowX: CGFloat = 27
            let arrowWidth: CGFloat = 8
            let speedX: CGFloat = 37
            let speedWidth: CGFloat = 55
            let dividerX: CGFloat = 95
            let tokenX: CGFloat = 100

            (metrics.cpu.total.percentText as NSString).draw(
                in: NSRect(x: 0, y: 0, width: percentageWidth, height: rowHeight),
                withAttributes: StatusDrawingStyles.attributes
            )
            ("↑" as NSString).draw(
                in: NSRect(x: arrowX, y: 0, width: arrowWidth, height: rowHeight),
                withAttributes: StatusDrawingStyles.attributes
            )
            (metrics.network.uploadBytesPerSecond.speedText as NSString).draw(
                in: NSRect(x: speedX, y: 0, width: speedWidth, height: rowHeight),
                withAttributes: StatusDrawingStyles.attributes
            )
            (metrics.memory.utilization.percentText as NSString).draw(
                in: NSRect(x: 0, y: rowHeight, width: percentageWidth, height: rowHeight),
                withAttributes: StatusDrawingStyles.attributes
            )
            ("↓" as NSString).draw(
                in: NSRect(x: arrowX, y: rowHeight, width: arrowWidth, height: rowHeight),
                withAttributes: StatusDrawingStyles.attributes
            )
            (metrics.network.downloadBytesPerSecond.speedText as NSString).draw(
                in: NSRect(x: speedX, y: rowHeight, width: speedWidth, height: rowHeight),
                withAttributes: StatusDrawingStyles.attributes
            )

            let divider = NSBezierPath()
            divider.move(to: NSPoint(x: dividerX, y: 3))
            divider.line(to: NSPoint(x: dividerX, y: size.height - 3))
            NSColor.black.withAlphaComponent(0.28).setStroke()
            divider.lineWidth = 0.5
            divider.stroke()

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
        } else {
            NSApp.activate()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            if let window = popover.contentViewController?.view.window {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.contentView?.wantsLayer = true
                window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
                popover.contentViewController?.view.wantsLayer = true
                popover.contentViewController?.view.layer?.backgroundColor = NSColor.clear.cgColor
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
