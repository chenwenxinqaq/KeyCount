import AppKit
import SwiftUI

/// Synthetic fixtures only. Does not instantiate monitors, load history, or
/// write application preferences. These PNGs are UI previews, not user data.
@main
enum PreviewRenderer {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let preferences = AppPreferences(defaults: nil)
        let netPreferences = AppPreferences(defaults: nil)
        netPreferences.primaryMetric = .net
        let today = Calendar.current.startOfDay(for: Date())
        let values = [1_180, 2_450, 1_760, -240, 2_930, 1_460, 1_284]
        let days = values.enumerated().map { index, value in
            DayRecord(
                date: Calendar.current.date(byAdding: .day, value: index - 6, to: today)!,
                netChars: value, typed: abs(value) + 240,
                chars: (abs(value) + 240) * 2, keys: (abs(value) + 240) * 3
            )
        }
        let sample = DashboardSnapshot(
            netChars: 1_284, added: 1_526, removed: 242, currentSpeed: 68,
            peakSpeed: 126, activeMinutes: 47, isIdle: false,
            characterCount: 3_826, keyCount: 4_218,
            keySpeed: 164, keyPeakSpeed: 288, keyActiveMinutes: 52,
            ignoredChanges: 37,
            hasAccessibility: true, hasInputMonitoring: true,
            hours: [0, 0, 0, 0, 0, 0, 0, 0, 72, 418, 530, 236,
                    84, 660, 895, 420, 568, 335, 0, 0, 0, 0, 0, 0],
            days: days
        )

        for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            try render(
                DashboardView(snapshot: sample, preferences: preferences),
                scheme: scheme, to: output.appendingPathComponent("dashboard-\(name).png")
            )
        }

        var empty = DashboardSnapshot()
        empty.days = days.map { DayRecord(date: $0.date, netChars: 0, keys: 0) }
        try render(
            DashboardView(snapshot: empty, preferences: preferences),
            scheme: .light, to: output.appendingPathComponent("onboarding.png")
        )
        var mounted = empty
        mounted.launchLocation = .readOnlyVolume
        try render(
            DashboardView(snapshot: mounted, preferences: preferences),
            scheme: .light, to: output.appendingPathComponent("onboarding-dmg.png")
        )
        var negative = sample
        negative.netChars = -320
        negative.added = 280
        negative.removed = 600
        negative.isIdle = true
        negative.days = days.enumerated().map {
            DayRecord(date: $0.element.date, netChars: -($0.offset + 1) * 80,
                      typed: 60, chars: 180, keys: 200)
        }
        try render(
            DashboardView(snapshot: negative, preferences: netPreferences),
            scheme: .light, to: output.appendingPathComponent("negative.png")
        )
        try render(
            DashboardView(snapshot: sample, preferences: netPreferences),
            scheme: .light, to: output.appendingPathComponent("dashboard-net.png")
        )
        var large = sample
        large.netChars = 123_456_789
        large.added = 130_000_000
        large.removed = 6_543_211
        try render(
            DashboardView(snapshot: large, preferences: preferences),
            scheme: .light, to: output.appendingPathComponent("large-count.png")
        )
        try render(
            SettingsView(snapshot: sample, preferences: preferences)
                .padding(.vertical, 18).frame(width: 384)
                .background(Theme.background).tint(Theme.accent),
            scheme: .light, to: output.appendingPathComponent("settings-light.png")
        )

        // 悬浮窗铺在渐变背景上，体现「置顶 + 半透明」的观感
        let overlayBackdrop = LinearGradient(
            colors: [Color(red: 0.11, green: 0.15, blue: 0.24), Color(red: 0.05, green: 0.07, blue: 0.11)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        try render(
            OverlayView(snapshot: sample, metric: .keystrokes)
                .padding(26)
                .background(overlayBackdrop),
            scheme: .dark, to: output.appendingPathComponent("overlay.png")
        )
    }

    @MainActor
    static func render<V: View>(_ view: V, scheme: ColorScheme, to url: URL) throws {
        NSApp.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        // Use a hosting view so native segmented controls render as well.
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            fatalError("Cannot allocate preview bitmap")
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Cannot encode preview")
        }
        try png.write(to: url, options: .atomic)
        print("\(url.lastPathComponent): \(Int(size.width))×\(Int(size.height)) pt")
    }
}
