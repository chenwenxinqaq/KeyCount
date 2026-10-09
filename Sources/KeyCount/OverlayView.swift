import SwiftUI

/// 置顶悬浮窗的内容。纯快照驱动，便于预览与测试，不触碰任何监控器。
/// 窗口整体的半透明由 NSPanel 的 alphaValue 控制；这里只负责内容与材质。
struct OverlayView: View {
    let snapshot: DashboardSnapshot
    let metric: PrimaryMetric

    private var value: Int { metric.value(in: snapshot) }
    private var authorized: Bool { metric.isAuthorized(in: snapshot) }
    private var idle: Bool { metric.isIdle(in: snapshot) }

    private var stateText: String {
        if snapshot.launchLocation == .readOnlyVolume { return "请先安装" }
        if !authorized { return "需授权" }
        if idle { return "待落笔" }
        return "\(metric.currentSpeed(in: snapshot).formatted()) \(metric.speedUnit)"
    }

    private var stateColor: Color {
        if snapshot.launchLocation == .readOnlyVolume || !authorized { return Theme.warning }
        return idle ? .secondary : Theme.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(nsImage: Theme.appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 15, height: 15)
                    .accessibilityHidden(true)
                Text(metric.shortTitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Circle().fill(stateColor).frame(width: 5, height: 5)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.formatted())
                    .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(value < 0 ? Theme.warning : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(metric.unit)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text(stateText)
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(stateColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(width: 132, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title) \(value.formatted()) \(metric.unit)，\(stateText)")
    }
}

/// 实时包装：把三套监控器的当前值组装成快照喂给 OverlayView。
/// 悬浮窗不需要历史，故不读 HistoryStore，省去每秒刷新时的扫盘。
struct LiveOverlayView: View {
    @ObservedObject var monitor: KeyboardMonitor
    @ObservedObject var net: NetTextMonitor
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        OverlayView(snapshot: snapshot, metric: preferences.primaryMetric)
    }

    private var snapshot: DashboardSnapshot {
        DashboardSnapshot(
            netChars: net.netChars, added: net.added, removed: net.removed,
            currentSpeed: net.currentSpeed, peakSpeed: net.peakSpeed,
            activeMinutes: net.activeMinutes, isIdle: net.idle,
            characterCount: monitor.charCount, keyCount: monitor.keyCount,
            keySpeed: monitor.keySpeed, keyPeakSpeed: monitor.peakKeySpeed,
            keyActiveMinutes: monitor.activeMinutes,
            hasAccessibility: net.hasPermission, hasInputMonitoring: monitor.hasPermission,
            launchLocation: AppInstallation.current
        )
    }
}
