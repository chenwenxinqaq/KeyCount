import SwiftUI

@main
struct KeyCountApp: App {
    @StateObject private var monitor = KeyboardMonitor()
    @StateObject private var net = NetTextMonitor()
    @StateObject private var preferences = AppPreferences()
    @StateObject private var overlay = OverlayController()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(net)
                .environmentObject(preferences)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: MenuBarIcon.image)
                if preferences.showMenuBarCount {
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                }
            }
            .accessibilityLabel("KeyCount，\(statusText)")
            // 菜单栏标签在启动时即渲染，借此注入依赖并按偏好同步悬浮窗。
            .onAppear {
                overlay.configure(monitor: monitor, net: net, preferences: preferences)
            }
        }
        .menuBarExtraStyle(.window)
    }

    /// 状态栏主指标 = 净字数（作家助手模式）
    private var statusText: String {
        if AppInstallation.current == .readOnlyVolume { return "请先安装" }
        let metric = preferences.primaryMetric
        let authorized = metric.needsInputMonitoring ? monitor.hasPermission : net.hasPermission
        if !authorized { return "需授权" }
        switch metric {
        case .keystrokes: return CountFormatting.menuBar(monitor.charCount)
        case .typed: return CountFormatting.menuBar(net.added)
        case .net: return CountFormatting.menuBar(net.netChars)
        }
    }
}

/// A template image lets the system handle light/dark menus and selection.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let key = NSBezierPath(
                roundedRect: NSRect(x: 1.5, y: 2, width: 15, height: 14),
                xRadius: 3.5, yRadius: 3.5
            )
            key.lineWidth = 1.4
            key.stroke()
            let bars = NSBezierPath()
            bars.lineWidth = 1.55
            bars.lineCapStyle = .round
            for (x, top) in [(5.5, 8.0), (9.0, 10.0), (12.5, 12.0)] {
                bars.move(to: NSPoint(x: x, y: 5.5))
                bars.line(to: NSPoint(x: x, y: top))
            }
            bars.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "KeyCount"
        return image
    }()
}
