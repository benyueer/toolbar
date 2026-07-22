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
        NSApp.setActivationPolicy(.accessory)
        configurePopover()
        configureStatusItem()
        observeMetrics()
        updateStatusItem()
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
        let item = NSStatusBar.system.statusItem(withLength: 136)
        guard let button = item.button else { return }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.toolTip = "CPU / 内存 / 实时网速 / 今日 Token"
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

        button.image = makeStatusImage()
        button.setAccessibilityLabel(
            "CPU \(metrics.cpu.total.percentText)，上传 \(metrics.network.uploadBytesPerSecond.speedText)，" +
            "内存 \(metrics.memory.utilization.percentText)，下载 \(metrics.network.downloadBytesPerSecond.speedText)，" +
            "今日 Token \(tokenUsage.snapshot.today.total.tokenText)"
        )
    }

    private func makeStatusImage() -> NSImage {
        let size = NSSize(width: 134, height: 22)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)
        let textStyle = NSMutableParagraphStyle()
        textStyle.alignment = .left
        textStyle.lineBreakMode = .byClipping

        let tokenTextStyle = NSMutableParagraphStyle()
        tokenTextStyle.alignment = .left
        tokenTextStyle.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: textStyle,
        ]

        let tokenAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: tokenTextStyle,
        ]

        let image = NSImage(size: size, flipped: true) { [metrics, tokenUsage] _ in
            let rowHeight = size.height / 2
            let percentageWidth: CGFloat = 25
            let arrowX: CGFloat = 27
            let arrowWidth: CGFloat = 8
            let speedX: CGFloat = 37
            let speedWidth: CGFloat = 55
            let dividerX: CGFloat = 95
            let tokenX: CGFloat = 100
            let tokenWidth = size.width - tokenX

            (metrics.cpu.total.percentText as NSString).draw(
                in: NSRect(x: 0, y: 0, width: percentageWidth, height: rowHeight),
                withAttributes: attributes
            )
            ("↑" as NSString).draw(
                in: NSRect(x: arrowX, y: 0, width: arrowWidth, height: rowHeight),
                withAttributes: attributes
            )
            (metrics.network.uploadBytesPerSecond.speedText as NSString).draw(
                in: NSRect(x: speedX, y: 0, width: speedWidth, height: rowHeight),
                withAttributes: attributes
            )
            (metrics.memory.utilization.percentText as NSString).draw(
                in: NSRect(x: 0, y: rowHeight, width: percentageWidth, height: rowHeight),
                withAttributes: attributes
            )
            ("↓" as NSString).draw(
                in: NSRect(x: arrowX, y: rowHeight, width: arrowWidth, height: rowHeight),
                withAttributes: attributes
            )
            (metrics.network.downloadBytesPerSecond.speedText as NSString).draw(
                in: NSRect(x: speedX, y: rowHeight, width: speedWidth, height: rowHeight),
                withAttributes: attributes
            )

            let divider = NSBezierPath()
            divider.move(to: NSPoint(x: dividerX, y: 3))
            divider.line(to: NSPoint(x: dividerX, y: size.height - 3))
            NSColor.black.withAlphaComponent(0.28).setStroke()
            divider.lineWidth = 0.5
            divider.stroke()

            let tokenText = tokenUsage.isRefreshing && tokenUsage.snapshot.days.isEmpty
                ? "···"
                : tokenUsage.snapshot.today.total.tokenText
            (tokenText as NSString).draw(
                in: NSRect(x: tokenX, y: 5, width: tokenWidth, height: 13),
                withAttributes: tokenAttributes
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
            popover.contentViewController?.view.window?.makeKey()
        }
    }
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
