import AppKit
import Combine

/// 全局键盘监听：只统计次数，绝不记录按键字符内容。
///
/// 除了自己的计数，还要把「会改动文本的按键」告诉 TypingActivity：
/// 净字数引擎靠这份证据区分人工输入和程序化写入。
final class KeyboardMonitor: ObservableObject {

    /// 今日可打印字符数（排除修饰键组合、方向键/功能键、回车/Tab/删除、长按重复）
    @Published private(set) var charCount = 0
    /// 今日总按键数（含修饰键切换）
    @Published private(set) var keyCount = 0
    /// 是否已获得「输入监控」权限
    @Published private(set) var hasPermission = false
    /// 本次会话敲键速度（敲键字符/分 = 最近 60s 滑窗计数）
    @Published private(set) var keySpeed = 0
    /// 今日最快一分钟（敲键字符/分）
    @Published private(set) var peakKeySpeed = 0

    /// 今日有敲键的分钟数（去重）
    var activeMinutes: Int { activeMinutesBase + activeMinuteSet.count }

    /// 24 小时分布（下标 = 小时）
    private(set) var hourBuckets = [Int](repeating: 0, count: 24)
    private(set) var firstTime: Date?
    private(set) var lastTime: Date?

    private var monitors: [Any] = []
    private var lifecycle = MonitoringLifecycle()
    private let activity: TypingActivity
    private var currentDay: String = DayKey.string()
    private var flushTimer: Timer?
    private var permissionTimer: Timer?
    private var speedTimer: Timer?
    /// 近 70s 的敲键时间戳（60s 滑窗 + 余量）
    private var keyTimes: [Date] = []
    /// 今日有敲键的分钟（minute-of-day），去重计活跃分钟
    private var activeMinuteSet = Set<Int>()
    /// 旧版快照只存了活跃分钟总数，无法与新分钟去重，只能作为基线叠加
    private var activeMinutesBase = 0

    private static let calendar = Calendar.autoupdatingCurrent
    private static let storeDir: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyCount", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    init(activity: TypingActivity = .shared) {
        self.activity = activity
        loadToday()
        refreshPermissionState()
        // 定期复查权限：用户在系统设置里勾选后，横幅能自动消失
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshPermissionState()
        }
        // 每 30s 兜底落盘，避免异常退出丢数据
        flushTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.persist()
        }
        // 每秒刷新敲键速度滑窗
        speedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateKeySpeed()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    deinit {
        flushTimer?.invalidate()
        permissionTimer?.invalidate()
        speedTimer?.invalidate()
        monitors.forEach { NSEvent.removeMonitor($0) }
    }

    // MARK: - 敲键速度（60s 滑动窗口）

    private func updateKeySpeed() {
        rolloverIfNeeded()
        let now = Date()
        let cutoff = now.timeIntervalSinceReferenceDate - 70   // 60s 窗 + 余量
        let keep = keyTimes.firstIndex { $0.timeIntervalSinceReferenceDate > cutoff }
            ?? keyTimes.count
        if keep > 0 { keyTimes.removeFirst(keep) }
        let windowStart = now.timeIntervalSinceReferenceDate - 60
        keySpeed = keyTimes.lazy.filter { $0.timeIntervalSinceReferenceDate > windowStart }.count
        peakKeySpeed = max(peakKeySpeed, keySpeed)
    }

    // MARK: - 事件监听

    private func installMonitors() {
        guard lifecycle.isRunning, monitors.isEmpty else { return }
        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.handle(event)
        }

        // 全局监听（其他 App 获得焦点时）。
        // 注意：无论有没有权限都会返回非 nil，没权限时只是收不到 keyDown 事件，
        // 权限状态必须用 CGPreflightListenEventAccess() 判断。
        let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .flagsChanged],
            handler: handler
        )
        if let global = global {
            monitors.append(global)
        }

        // 本 App 自身获得焦点时的按键也要计（全局监听不覆盖自身）
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged],
            handler: { ev in
                handler(ev)
                return ev
            }
        ) {
            monitors.append(local)
        }
    }

    private func handle(_ event: NSEvent) {
        guard lifecycle.isRunning else { return }
        rolloverIfNeeded()
        let now = Date()
        keyCount += 1

        if event.type != .flagsChanged {
            let effect = KeyClassifier.effect(of: Self.signal(of: event))
            if effect.suppressesTextDiff { activity.suppressTextDiff(at: now) }
            if effect.mutatesText { activity.recordTextKey(at: now) }
            if effect.countsAsCharacter {
                charCount += 1
                keyTimes.append(now)
                let parts = Self.calendar.dateComponents([.hour, .minute], from: now)
                activeMinuteSet.insert((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            }
            if Diag.enabled {
                Diag.log("KEY kc=\(event.keyCode) rep=\(event.isARepeat) "
                    + "char=\(effect.countsAsCharacter) text=\(effect.mutatesText) "
                    + "suppress=\(effect.suppressesTextDiff)")
            }
        }

        let hour = Self.calendar.component(.hour, from: now)
        if hourBuckets.indices.contains(hour) { hourBuckets[hour] += 1 }
        if firstTime == nil { firstTime = now }
        lastTime = now
    }

    /// NSEvent → 纯值。分类规则放在 KeyClassifier 里，可脱离 AppKit 验证。
    private static func signal(of event: NSEvent) -> KeySignal {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return KeySignal(
            characters: event.charactersIgnoringModifiers ?? "",
            hasCommand: flags.contains(.command),
            hasControl: flags.contains(.control),
            isRepeat: event.isARepeat
        )
    }

    private func rolloverIfNeeded() {
        let today = DayKey.string()
        guard today != currentDay else { return }
        persist()
        currentDay = today
        charCount = 0
        keyCount = 0
        keySpeed = 0
        peakKeySpeed = 0
        keyTimes = []
        activeMinuteSet = []
        activeMinutesBase = 0
        hourBuckets = [Int](repeating: 0, count: 24)
        firstTime = nil
        lastTime = nil
        loadToday()
    }

    @objc private func appWillTerminate() {
        _ = lifecycle.update(authorized: false)
        removeMonitors()
        persist()
    }

    // MARK: - 权限引导

    /// 定时复查，用户授权后面板横幅自动消失
    private func refreshPermissionState() {
        let authorization = AppInstallation.authorization()
        if authorization.inputMonitoring != hasPermission {
            hasPermission = authorization.inputMonitoring
        }
        // 没有按键证据时，净字数引擎要知道自己正在盲算
        activity.setKeyboardAvailable(authorization.allowsKeyboardMonitoring)
        switch lifecycle.update(authorized: authorization.allowsKeyboardMonitoring) {
        case .start:
            installMonitors()
        case .stop:
            removeMonitors()
            keyTimes.removeAll()
            keySpeed = 0
        case .none:
            break
        }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    // MARK: - 持久化

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var fileURL: URL {
        Self.storeDir.appendingPathComponent("\(currentDay).json")
    }

    private struct Snapshot: Codable {
        var chars: Int
        var keys: Int
        var hours: [String: Int]
        var first: String?
        var last: String?
        var peak: Int?      // v1.6 起记录：今日最快一分钟（敲键字符/分）
        var minutes: [Int]? // v1.6 起记录：活跃分钟明细，重启后才能继续去重累加
    }

    private func loadToday() {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        charCount = snap.chars
        keyCount = snap.keys
        peakKeySpeed = snap.peak ?? 0
        if let minutes = snap.minutes {
            activeMinuteSet = Set(minutes.filter { (0..<1440).contains($0) })
            activeMinutesBase = 0
        } else {
            activeMinutesBase = 0
        }
        firstTime = snap.first.flatMap { Self.timeFormatter.date(from: $0) }
        lastTime = snap.last.flatMap { Self.timeFormatter.date(from: $0) }
        for (k, v) in snap.hours {
            if let idx = Int(k), (0..<24).contains(idx) { hourBuckets[idx] = v }
        }
    }

    func persist() {
        guard AppInstallation.current.allowsPermissionRequests else { return }
        var hours: [String: Int] = [:]
        for (i, v) in hourBuckets.enumerated() where v > 0 {
            hours[String(format: "%02d", i)] = v
        }
        let snap = Snapshot(
            chars: charCount,
            keys: keyCount,
            hours: hours,
            first: firstTime.map { Self.timeFormatter.string(from: $0) },
            last: lastTime.map { Self.timeFormatter.string(from: $0) },
            peak: peakKeySpeed,
            minutes: activeMinuteSet.sorted()
        )
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
