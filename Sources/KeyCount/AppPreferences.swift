import Combine
import Foundation

final class AppPreferences: ObservableObject {
    static let defaultGoal = 2_000
    static let goalRange = 100...100_000
    static let opacityRange = 0.3...1.0
    private let defaults: UserDefaults?

    /// 悬浮窗位置等轻量状态直接存这里；预览/测试传 nil 时为空。
    var rawDefaults: UserDefaults? { defaults }

    @Published var goalEnabled: Bool {
        didSet { defaults?.set(goalEnabled, forKey: "goalEnabled") }
    }
    @Published var dailyGoal: Int {
        didSet {
            let clamped = Self.clampGoal(dailyGoal)
            if clamped != dailyGoal { dailyGoal = clamped }
            defaults?.set(clamped, forKey: "dailyGoal")
        }
    }
    @Published var showMenuBarCount: Bool {
        didSet { defaults?.set(showMenuBarCount, forKey: "showMenuBarCount") }
    }
    /// 面板与菜单栏的主指标。默认看敲键字符：只增不减，且所有应用都能统计。
    @Published var primaryMetric: PrimaryMetric {
        didSet { defaults?.set(primaryMetric.rawValue, forKey: "primaryMetric") }
    }
    /// 置顶半透明悬浮窗开关
    @Published var showOverlay: Bool {
        didSet { defaults?.set(showOverlay, forKey: "showOverlay") }
    }
    /// 悬浮窗整体不透明度（作用于窗口 alphaValue）
    @Published var overlayOpacity: Double {
        didSet {
            let clamped = Self.clampOpacity(overlayOpacity)
            if clamped != overlayOpacity { overlayOpacity = clamped }
            defaults?.set(clamped, forKey: "overlayOpacity")
        }
    }
    /// 鼠标穿透：开启后点击会落到下方窗口，悬浮窗不再可拖动
    @Published var overlayClickThrough: Bool {
        didSet { defaults?.set(overlayClickThrough, forKey: "overlayClickThrough") }
    }

    /// Pass nil for isolated previews and tests: no user preferences are touched.
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        goalEnabled = defaults?.object(forKey: "goalEnabled") as? Bool ?? true
        let savedGoal = defaults?.object(forKey: "dailyGoal") as? Int ?? Self.defaultGoal
        dailyGoal = Self.clampGoal(savedGoal)
        showMenuBarCount = defaults?.object(forKey: "showMenuBarCount") as? Bool ?? true
        let savedMetric = defaults?.object(forKey: "primaryMetric") as? String
        primaryMetric = savedMetric.flatMap(PrimaryMetric.init(rawValue:)) ?? .keystrokes
        showOverlay = defaults?.object(forKey: "showOverlay") as? Bool ?? false
        let savedOpacity = defaults?.object(forKey: "overlayOpacity") as? Double ?? 0.9
        overlayOpacity = Self.clampOpacity(savedOpacity)
        overlayClickThrough = defaults?.object(forKey: "overlayClickThrough") as? Bool ?? false
    }

    private static func clampGoal(_ value: Int) -> Int {
        min(max(value, goalRange.lowerBound), goalRange.upperBound)
    }

    private static func clampOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return 0.9 }
        return min(max(value, opacityRange.lowerBound), opacityRange.upperBound)
    }
}
