import Foundation

@main
enum DashboardTests {
    static var passed = 0
    static var failed = 0

    static func check(_ name: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            passed += 1
            print("PASS \(name)")
        } else {
            failed += 1
            print("FAIL \(name)")
        }
    }

    static func main() {
        check("zero progress", CountFormatting.goalProgress(count: 0, goal: 2_000) == 0)
        check("negative progress clamps to zero", CountFormatting.goalProgress(count: -500, goal: 2_000) == 0)
        check("halfway progress", CountFormatting.goalProgress(count: 1_000, goal: 2_000) == 0.5)
        check("complete progress", CountFormatting.goalProgress(count: 2_000, goal: 2_000) == 1)
        check("excess progress clamps to one", CountFormatting.goalProgress(count: 3_000, goal: 2_000) == 1)
        check("invalid target is safe", CountFormatting.goalProgress(count: 100, goal: 0) == 0)
        check("zero menu label", CountFormatting.menuBar(0) == "0")
        check("ten thousand menu label", CountFormatting.menuBar(12_340) == "1.2万")
        check("negative menu label", CountFormatting.menuBar(-12_340) == "-1.2万")
        check("hundred million menu label", CountFormatting.menuBar(123_400_000) == "1.2亿")
        check("minimum integer doesn't overflow", !CountFormatting.menuBar(Int.min).isEmpty)

        let mixed = ActivityScale(values: [-50, 0, 100])
        check("mixed chart zero baseline", abs(mixed.zeroPosition - 2.0 / 3) < 0.0001)
        check("positive reaches top", mixed.position(for: 100) == 0)
        check("negative reaches bottom", mixed.position(for: -50) == 1)
        check("positive is above zero", mixed.position(for: 20) < mixed.zeroPosition)
        check("negative is below zero", mixed.position(for: -20) > mixed.zeroPosition)
        let positive = ActivityScale(values: [10, 20])
        check("positive-only baseline at bottom", positive.zeroPosition == 1)
        let negative = ActivityScale(values: [-10, -20])
        check("negative-only baseline at top", negative.zeroPosition == 0)
        let empty = ActivityScale(values: [])
        check("empty chart has finite scale", empty.zeroPosition.isFinite && empty.position(for: 0).isFinite)
        let zeros = ActivityScale(values: [0, 0, 0])
        check("zero chart has finite scale", zeros.span == 1)
        check("zero chart uses bottom baseline", zeros.zeroPosition == 1)

        let preferences = AppPreferences(defaults: nil)
        check("default goal", preferences.dailyGoal == 2_000 && preferences.goalEnabled)
        check("default menu count", preferences.showMenuBarCount)
        check("default metric is keystrokes", preferences.primaryMetric == .keystrokes)
        check("overlay off by default", !preferences.showOverlay)
        check("default overlay opacity", preferences.overlayOpacity == 0.9)
        check("overlay click-through off by default", !preferences.overlayClickThrough)
        preferences.overlayOpacity = 5
        check("overlay opacity clamps high", preferences.overlayOpacity == 1.0)
        preferences.overlayOpacity = 0
        check("overlay opacity clamps low", preferences.overlayOpacity == 0.3)
        preferences.dailyGoal = -1
        check("negative goal normalized", preferences.dailyGoal == 100)
        preferences.dailyGoal = Int.max
        check("excessive goal normalized", preferences.dailyGoal == 100_000)
        preferences.dailyGoal = 3_400
        check("custom goal retained", preferences.dailyGoal == 3_400)

        let suite = "KeyCount.Tests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        let first = AppPreferences(defaults: store)
        first.dailyGoal = 5_000
        first.showMenuBarCount = false
        first.goalEnabled = false
        first.primaryMetric = .net
        first.showOverlay = true
        first.overlayOpacity = 0.6
        first.overlayClickThrough = true
        let restored = AppPreferences(defaults: store)
        check("goal persisted", restored.dailyGoal == 5_000)
        check("menu preference persisted", !restored.showMenuBarCount)
        check("goal visibility persisted", !restored.goalEnabled)
        check("metric persisted", restored.primaryMetric == .net)
        check("overlay visibility persisted", restored.showOverlay)
        check("overlay opacity persisted", restored.overlayOpacity == 0.6)
        check("overlay click-through persisted", restored.overlayClickThrough)
        store.set("nonsense", forKey: "primaryMetric")
        check("corrupt metric falls back", AppPreferences(defaults: store).primaryMetric == .keystrokes)
        store.set(0, forKey: "dailyGoal")
        check("corrupt saved goal normalized", AppPreferences(defaults: store).dailyGoal == 100)

        var snapshot = DashboardSnapshot()
        check("onboarding state", snapshot.status(for: .net) == "等待授权")
        snapshot.hasAccessibility = true
        check("idle state", snapshot.status(for: .net) == "等待落笔")
        snapshot.isIdle = false
        check("active state", snapshot.status(for: .net) == "正在统计")

        // 敲键字符看的是输入监控，不是辅助功能
        check("keystroke metric waits for input monitoring",
              snapshot.status(for: .keystrokes) == "等待授权")
        snapshot.hasInputMonitoring = true
        check("keystroke metric idle without keys",
              snapshot.status(for: .keystrokes) == "等待落笔")
        snapshot.keySpeed = 180
        check("keystroke metric active with keys",
              snapshot.status(for: .keystrokes) == "正在统计")

        snapshot.characterCount = 3_000
        snapshot.added = 1_200
        snapshot.netChars = 900
        check("keystroke metric reads character count",
              PrimaryMetric.keystrokes.value(in: snapshot) == 3_000)
        check("typed metric reads additions", PrimaryMetric.typed.value(in: snapshot) == 1_200)
        check("net metric reads net count", PrimaryMetric.net.value(in: snapshot) == 900)
        check("only net can go negative",
              PrimaryMetric.net.canGoNegative && !PrimaryMetric.typed.canGoNegative
                  && !PrimaryMetric.keystrokes.canGoNegative)
        check("metric units", PrimaryMetric.keystrokes.unit == "字符"
              && PrimaryMetric.net.unit == "字")

        snapshot.days = [
            DayRecord(date: Date(), netChars: 300, typed: 400, chars: 1_000, keys: 1_500),
            DayRecord(date: Date(), netChars: -100, typed: 50, chars: 200, keys: 300)
        ]
        check("weekly net includes deletions", snapshot.weeklyTotal(for: .net) == 200)
        check("weekly typed never subtracts", snapshot.weeklyTotal(for: .typed) == 450)
        check("weekly keystrokes sum", snapshot.weeklyTotal(for: .keystrokes) == 1_200)

        // 文件名键必须固定公历：地区日历换成佛历时写入与汇总不能错开
        var thai = Calendar(identifier: .buddhist)
        thai.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let noon = thai.date(from: DateComponents(year: 2569, month: 10, day: 2, hour: 12))!
        check("day key uses the gregorian calendar", DayKey.string(for: noon) == "2026-10-02")
        check("day key round trips", DayKey.string(for: DayKey.date(from: "2026-10-02")!) == "2026-10-02")
        check("day key rejects junk", DayKey.date(from: "diag") == nil)
        check("day key rejects short input", DayKey.date(from: "2026-1-2") == nil)
        check("day key rejects impossible month", DayKey.date(from: "2026-13-02") == nil)

        print("\nDashboard: \(passed)/\(passed + failed) passed")
        exit(failed == 0 ? 0 : 1)
    }
}
