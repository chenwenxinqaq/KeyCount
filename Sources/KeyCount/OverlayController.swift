import AppKit
import Combine
import SwiftUI

/// 置顶半透明悬浮窗的宿主。用一个不激活的 NSPanel 承载 SwiftUI 内容：
///
/// - `.nonactivatingPanel`：显示时不抢焦点。这一点对本应用是硬要求——
///   抢了焦点就会改变 `NSWorkspace.frontmostApplication`，净字数引擎会误判。
/// - `.floating` + `fullScreenAuxiliary`：浮在普通窗口与全屏之上。
/// - 透明背景 + `isMovableByWindowBackground`：拖动窗体任意处即可移动。
///
/// 内容复用 `LiveOverlayView`，窗口整体不透明度由 `alphaValue` 控制。
final class OverlayController: NSObject, ObservableObject, NSWindowDelegate {

    private var panel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []
    private var monitor: KeyboardMonitor?
    private var net: NetTextMonitor?
    private var preferences: AppPreferences?
    private var configured = false

    private static let originXKey = "overlayOriginX"
    private static let originYKey = "overlayOriginY"

    /// 由 App 在启动后注入依赖；重复调用无副作用。
    func configure(monitor: KeyboardMonitor, net: NetTextMonitor, preferences: AppPreferences) {
        guard !configured else { return }
        configured = true
        self.monitor = monitor
        self.net = net
        self.preferences = preferences

        preferences.$showOverlay
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in self?.setVisible(visible) }
            .store(in: &cancellables)
        preferences.$overlayOpacity
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] opacity in self?.panel?.alphaValue = CGFloat(opacity) }
            .store(in: &cancellables)
        preferences.$overlayClickThrough
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] through in self?.panel?.ignoresMouseEvents = through }
            .store(in: &cancellables)
    }

    private func setVisible(_ visible: Bool) {
        guard visible else {
            panel?.orderOut(nil)
            return
        }
        let panel = panel ?? makePanel()
        self.panel = panel
        guard let panel else { return }
        panel.alphaValue = CGFloat(preferences?.overlayOpacity ?? 0.9)
        panel.ignoresMouseEvents = preferences?.overlayClickThrough ?? false
        // orderFrontRegardless 而非 makeKey：accessory 应用据此显示且不激活。
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel? {
        guard let monitor, let net, let preferences else { return nil }
        let hosting = NSHostingView(
            rootView: LiveOverlayView(monitor: monitor, net: net, preferences: preferences))
        hosting.layout()
        let size = hosting.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.setFrameOrigin(startingOrigin(for: size))
        return panel
    }

    // MARK: - 位置记忆

    /// 优先用上次保存且仍在某块屏幕可见范围内的位置，否则回落右上角。
    private func startingOrigin(for size: NSSize) -> NSPoint {
        let defaults = preferences?.rawDefaults
        if let defaults,
           defaults.object(forKey: Self.originXKey) != nil,
           defaults.object(forKey: Self.originYKey) != nil {
            let saved = NSPoint(x: defaults.double(forKey: Self.originXKey),
                                y: defaults.double(forKey: Self.originYKey))
            let frame = NSRect(origin: saved, size: size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                return saved
            }
        }
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visible.maxX - size.width - 24, y: visible.maxY - size.height - 24)
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel, let defaults = preferences?.rawDefaults else { return }
        let origin = panel.frame.origin
        defaults.set(Double(origin.x), forKey: Self.originXKey)
        defaults.set(Double(origin.y), forKey: Self.originYKey)
    }
}
