import Foundation

/// 面板与菜单栏的主指标。
///
/// 净字数会减掉删掉的部分，看的是「今天留下了多少」；
/// 敲键字符和上屏字数都只增不减，看的是「今天打了多少」。
/// 敲键字符只依赖输入监控，所有应用都能统计；上屏字数与净字数依赖
/// 辅助功能读取文本，Word、旧版 Electron 等读不到的应用会统计不到。
enum PrimaryMetric: String, CaseIterable, Identifiable {

    /// 敲出来的可打印字符数：拼音的每个字母各算一次
    case keystrokes
    /// 上屏字数：累计新增，不减删除（中文按字，英文与数字按词）
    case typed
    /// 净字数：新增 − 删减
    case net

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keystrokes: return "今日敲键字符"
        case .typed: return "今日上屏字数"
        case .net: return "今日净字数"
        }
    }

    var shortTitle: String {
        switch self {
        case .keystrokes: return "敲键字符"
        case .typed: return "上屏字数"
        case .net: return "净字数"
        }
    }

    var unit: String { self == .keystrokes ? "字符" : "字" }

    var speedUnit: String { self == .keystrokes ? "字符 / 分" : "字 / 分" }

    var explanation: String {
        switch self {
        case .keystrokes:
            return "每敲出一个可打印字符算一次，拼音的每个字母都算。只需输入监控，所有应用都能统计。"
        case .typed:
            return "实际上屏的字数，只增不减。中文按字，英文与数字按词。"
        case .net:
            return "上屏字数减去删掉的字数，可能为负，反映今天净留下多少。"
        }
    }

    /// 这个指标靠哪项权限。敲键字符靠输入监控，另两个靠辅助功能。
    var needsInputMonitoring: Bool { self == .keystrokes }

    /// 只有净字数会小于零，其余两个单调不减
    var canGoNegative: Bool { self == .net }

    func value(in snapshot: DashboardSnapshot) -> Int {
        switch self {
        case .keystrokes: return snapshot.characterCount
        case .typed: return snapshot.added
        case .net: return snapshot.netChars
        }
    }

    func value(in day: DayRecord) -> Int {
        switch self {
        case .keystrokes: return day.chars
        case .typed: return day.typed
        case .net: return day.netChars
        }
    }

    func currentSpeed(in snapshot: DashboardSnapshot) -> Int {
        self == .keystrokes ? snapshot.keySpeed : snapshot.currentSpeed
    }

    func peakSpeed(in snapshot: DashboardSnapshot) -> Int {
        self == .keystrokes ? snapshot.keyPeakSpeed : snapshot.peakSpeed
    }

    func activeMinutes(in snapshot: DashboardSnapshot) -> Int {
        self == .keystrokes ? snapshot.keyActiveMinutes : snapshot.activeMinutes
    }

    func isIdle(in snapshot: DashboardSnapshot) -> Bool {
        self == .keystrokes ? snapshot.keySpeed == 0 : snapshot.isIdle
    }

    /// 主指标所需权限是否到位
    func isAuthorized(in snapshot: DashboardSnapshot) -> Bool {
        needsInputMonitoring ? snapshot.hasInputMonitoring : snapshot.hasAccessibility
    }
}

struct DashboardSnapshot {
    var date = Date()
    var netChars = 0
    var added = 0
    var removed = 0
    var currentSpeed = 0
    var peakSpeed = 0
    var activeMinutes = 0
    var isIdle = true
    var characterCount = 0
    var keyCount = 0
    var keySpeed = 0
    var keyPeakSpeed = 0
    var keyActiveMinutes = 0
    /// 判定为非人工、没有计入的文本改动次数（本次运行）
    var ignoredChanges = 0
    var hasAccessibility = false
    var hasInputMonitoring = false
    var hours = [Int](repeating: 0, count: 24)
    var days: [DayRecord] = []
    var launchLocation = AppLaunchLocation.applications

    func status(for metric: PrimaryMetric) -> String {
        if launchLocation == .readOnlyVolume { return "请先安装" }
        if !metric.isAuthorized(in: self) { return "等待授权" }
        return metric.isIdle(in: self) ? "等待落笔" : "正在统计"
    }

    func weeklyTotal(for metric: PrimaryMetric) -> Int {
        days.reduce(0) { $0 + metric.value(in: $1) }
    }
}

enum CountFormatting {
    /// Short enough for the menu bar; the panel always shows the full count.
    static func menuBar(_ value: Int) -> String {
        let magnitude = Double(value).magnitude
        if magnitude >= 100_000_000 {
            return String(format: "%.1f亿", Double(value) / 100_000_000)
        }
        if magnitude >= 10_000 {
            return String(format: "%.1f万", Double(value) / 10_000)
        }
        return value.formatted()
    }

    static func goalProgress(count: Int, goal: Int) -> Double {
        guard goal > 0 else { return 0 }
        return min(max(Double(count) / Double(goal), 0), 1)
    }
}

/// A shared zero baseline is essential: net deletions must extend downward.
struct ActivityScale {
    let upper: Double
    let lower: Double

    init(values: [Int]) {
        lower = min(Double(values.min() ?? 0), 0)
        // With no values, retain the usual bottom baseline instead of floating
        // seven zero bars at the top of the plot.
        upper = max(Double(values.max() ?? 0), lower < 0 ? 0 : 1)
    }

    var span: Double { max(upper - lower, 1) }
    var zeroPosition: Double { upper / span }

    func position(for value: Int) -> Double {
        (upper - Double(value)) / span
    }
}
