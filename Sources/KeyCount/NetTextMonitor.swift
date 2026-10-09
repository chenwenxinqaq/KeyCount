import ApplicationServices
import AppKit
import Combine

/// 净字数引擎（作家助手模式）：跟随系统焦点文本控件，对文本做 diff 统计净字数。
///
/// 字数口径（Word 风格）：中文按字（含中文标点/全角），英文/数字按词。
/// 原理：AXValue 反映「上屏后的最终文本」。拼音组合即使被读到中间态，
/// 上屏时整体替换，权重数学上自洽：敲 nihao(+1 词) → 替换为 你好(-1 词 +2 字) ⇒ 净 +2。
///
/// 本类只负责「读到什么」：焦点、角色、文本、选中长度。
/// 「算不算」交给 NetCountEngine，并与 TypingActivity 的按键证据对账。
final class NetTextMonitor: ObservableObject {

    /// 今日净字数（负数 = 净删除多于新增）
    @Published private(set) var netChars = 0
    /// 今日累计新增 / 删减字数（净字数 = 新增 - 删减，可自行验算）
    @Published private(set) var added = 0
    @Published private(set) var removed = 0
    /// 当前打字速度（字/分 = 最近 60s 滑窗净增字数；停笔 30s 后视为空闲）
    @Published private(set) var currentSpeed = 0
    @Published private(set) var idle = true
    /// 今日最快一分钟（60s 滑窗峰值，字/分）
    @Published private(set) var peakSpeed = 0
    /// 今日有产出的分钟数（去重）
    var activeMinutes: Int { activeMinutesBase + activeMinuteSet.count }
    /// 辅助功能权限（即时生效，无需重启进程）
    @Published private(set) var hasPermission = false
    /// 本次运行里判定为非人工、因此没有计入的文本改动次数（面板自查用）。
    /// 不发布变更：终端刷屏时它会高频自增，没必要每次都驱动界面重绘。
    private(set) var ignoredChanges = 0

    /// 文本基线与计数判据
    private var engine = NetCountEngine<ElementKey>()
    private let activity: TypingActivity
    /// 已见过/已处理的 pid，避免重复设置 AXManualAccessibility
    private var seenPids: Set<pid_t> = []
    /// AXNOFOCUS 兜底重断言的节流记录
    private var lastForceAssert: (pid: pid_t, at: Date)?
    private var pollTimer: Timer?
    private var lifecycle = MonitoringLifecycle()
    private var permTimer: Timer?
    private var speedTimer: Timer?
    private var flushTimer: Timer?
    /// 近 70s 的产出事件（60s 滑窗 + 余量），用于速度计算
    private var speedEvents: [(t: Date, w: Int)] = []
    /// 今日有产出的分钟（minute-of-day），去重计活跃分钟
    private var activeMinuteSet = Set<Int>()
    /// 旧版快照只存了活跃分钟总数，无法与新分钟去重，只能作为基线叠加
    private var activeMinutesBase = 0
    private var currentDay = DayKey.string()
    /// 诊断模式的焦点签名（变化才记，防刷屏）
    private var lastDiagSig = ""
    private var hourBuckets = [Int](repeating: 0, count: 24)
    private(set) var firstTime: Date?
    private(set) var lastTime: Date?

    private static let pollInterval: TimeInterval = 0.15

    /// 只统计这些 role，避免滑条/表格等非文本 value 的干扰
    private static let textRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox"]
    /// 密码框：读得到也不该读
    private static let secureSubrole = "AXSecureTextField"
    private static let calendar = Calendar.autoupdatingCurrent

    /// 控件身份。CFHash 只用来分桶，相等性必须用 CFEqual：
    /// 两个不同控件撞上同一个哈希，就会共用基线并产生凭空的巨额 diff。
    private struct ElementKey: Hashable {
        let element: AXUIElement
        let pid: pid_t

        static func == (lhs: ElementKey, rhs: ElementKey) -> Bool {
            lhs.pid == rhs.pid && CFEqual(lhs.element, rhs.element)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(pid)
            hasher.combine(CFHash(element))
        }
    }

    private static let storeDir: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyCount", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    init(activity: TypingActivity = .shared) {
        self.activity = activity
        // Explain permissions in the panel; prompt only after an explicit click.
        refreshPermissionState()

        // 辅助功能权限可热生效：开启后自动开始统计
        permTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshPermissionState()
        }

        loadToday()
        flushTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.persist()
        }
        // 每秒刷新速度滑窗（窗口随事件过期自然滑落，峰值持续可观测）
        speedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateSpeed()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(persistNow),
            name: NSApplication.willTerminateNotification, object: nil)
    }

    deinit {
        pollTimer?.invalidate()
        permTimer?.invalidate()
        speedTimer?.invalidate()
        flushTimer?.invalidate()
    }

    // MARK: - 轮询与 diff

    private func refreshPermissionState() {
        let authorization = AppInstallation.authorization()
        if authorization.accessibility != hasPermission {
            hasPermission = authorization.accessibility
        }
        switch lifecycle.update(authorized: authorization.allowsTextMonitoring) {
        case .start:
            startPolling()
        case .stop:
            pollTimer?.invalidate()
            pollTimer = nil
            engine.forgetAll()
            seenPids.removeAll()
            lastForceAssert = nil
            speedEvents.removeAll()
            currentSpeed = 0
            idle = true
        case .none:
            break
        }
    }

    private func startPolling() {
        guard lifecycle.isRunning, pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: Self.pollInterval, repeats: true
        ) { [weak self] _ in
            self?.pollOnce()
        }
    }

    private func pollOnce() {
        // Do not keep accessing other apps between permission polls if access
        // was revoked. In particular, don't enter the Chromium retry path.
        guard lifecycle.isRunning, AXIsProcessTrusted() else {
            refreshPermissionState()
            return
        }
        rolloverIfNeeded()
        let sys = AXUIElementCreateSystemWide()

        // Electron/Chromium 系 App 默认不暴露无障碍树:必须先设置
        // AXManualAccessibility 才有焦点元素可查。若只对「已查到焦点」的 pid
        // 设置会死锁(不开树→查不到→学不到 pid),因此从前台 App 独立获取。
        if let front = NSWorkspace.shared.frontmostApplication {
            noteElectronAccessibility(front.processIdentifier)
        }

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            sys, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
            let fr = focusedRef,
            CFGetTypeID(fr) == AXUIElementGetTypeID() else {
            // 焦点查询失败:Chromium 会在无 AX 客户端时自动关树,
            // 对前台 App 周期性重断言(5s 节流),并记下失败的应用名
            if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier > 0 {
                let now = Date()
                let stale = lastForceAssert.map {
                    $0.pid != front.processIdentifier || now.timeIntervalSince($0.at) > 5
                } ?? true
                if stale {
                    lastForceAssert = (front.processIdentifier, now)
                    noteElectronAccessibility(front.processIdentifier, force: true)
                }
                diagFocus("AXNOFOCUS", front.processIdentifier, "-", nil)
            } else {
                diagFocus("AXNOFOCUS", 0, "-", nil)
            }
            return
        }
        let focused = fr as! AXUIElement

        var pid: pid_t = 0
        AXUIElementGetPid(focused, &pid)
        noteElectronAccessibility(pid)

        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused, kAXRoleAttribute as CFString, &roleRef) == .success,
            let role = roleRef as? String else {
            diagFocus("AXNOROLE", pid, "-", nil)
            return
        }
        guard Self.textRoles.contains(role) else {
            diagFocus("AXSKIP", pid, role, nil)   // 非文本控件不计
            return
        }

        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            focused, kAXSubroleAttribute as CFString, &subroleRef) == .success,
            let subrole = subroleRef as? String, subrole == Self.secureSubrole {
            diagFocus("AXSECURE", pid, role, nil)   // 密码框不读不计
            return
        }

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused, kAXValueAttribute as CFString, &valueRef) == .success else {
            diagFocus("AXNOVAL", pid, role, nil)
            return
        }

        // AXValue 可能是 String 或 NSAttributedString
        let text: String
        if let s = valueRef as? String {
            text = s
        } else if let a = valueRef as? NSAttributedString {
            text = a.string
        } else {
            diagFocus("AXVALTYPE", pid, role, nil)
            return
        }
        diagFocus("AXOK", pid, role, text.count)

        let now = Date()
        let decision = engine.observe(
            text: text,
            for: ElementKey(element: focused, pid: pid),
            selection: selectionLength(of: focused),
            at: now,
            witness: activity.witness(at: now)
        )
        switch decision {
        case .counted(let delta):
            apply(delta: delta, at: now)
        case .ignored(let reason):
            if decision.isIgnoredChange { ignoredChanges += 1 }
            if Diag.enabled { diagFocus("AXDROP-\(reason.rawValue)", pid, role, text.count) }
        case .baseline, .unchanged:
            break
        }
    }

    /// 计入一次人工编辑：净字数、增删、小时分布、速度滑窗、活跃分钟
    private func apply(delta: Int, at now: Date) {
        if delta > 0 { added += delta } else { removed -= delta }
        netChars += delta

        let components = Self.calendar.dateComponents([.hour, .minute], from: now)
        let hour = components.hour ?? 0
        if hourBuckets.indices.contains(hour) { hourBuckets[hour] += delta }
        activeMinuteSet.insert(hour * 60 + (components.minute ?? 0))

        speedEvents.append((now, delta))
        if firstTime == nil { firstTime = now }
        lastTime = now
    }

    /// 选中长度：一次按键可以替换或删掉整段选中文本，预算要把它算进去。
    private func selectionLength(of element: AXUIElement) -> Int {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
            let value = ref, CFGetTypeID(value) == AXValueGetTypeID() else { return 0 }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return 0 }
        return max(0, range.length)
    }

    /// 对 App 级设置无障碍开启标记。Electron 响应 AXManualAccessibility，
    /// Chrome/Chromium 亦响应 AXEnhancedUserInterface——双写无害，覆盖两端；
    /// 且 Chromium 会在无 AX 客户端时自动关树，失败路径下可 force 重断言。
    private func noteElectronAccessibility(_ pid: pid_t, force: Bool = false) {
        guard pid > 0, force || !seenPids.contains(pid) else { return }
        // 跑上几天会见到大量已退出的 pid，重新断言一次无害，不必一直留着
        if seenPids.count > 256 { seenPids.removeAll() }
        seenPids.insert(pid)
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(
            appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(
            appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        if Diag.enabled {
            var an = "pid\(pid)"
            if let app = NSRunningApplication(processIdentifier: pid) {
                an = app.localizedName ?? an
            }
            Diag.log("\(force ? "AXRETRY" : "AXENAB") app=\(an)")
        }
    }

    /// 诊断模式：记录焦点控件元数据（app/role/长度），签名变化才写
    private func diagFocus(_ tag: String, _ pid: pid_t, _ role: String, _ len: Int?) {
        guard Diag.enabled else { return }
        var appName = "pid\(pid)"
        if let app = NSRunningApplication(processIdentifier: pid) {
            appName = app.localizedName ?? appName
        }
        let sig = "\(tag) app=\(appName) role=\(role)" + (len.map { " len=\($0)" } ?? "")
        guard sig != lastDiagSig else { return }
        lastDiagSig = sig
        Diag.log(sig)
    }

    // MARK: - 打字速度（60s 滑动窗口）
    /// 每秒调用：清过期事件 → 算窗口净增 → 更新当前速度与峰值
    private func updateSpeed() {
        rolloverIfNeeded()
        let now = Date()
        let cutoff = now.timeIntervalSinceReferenceDate - 70   // 60s 窗 + 余量
        let keep = speedEvents.firstIndex { $0.t.timeIntervalSinceReferenceDate > cutoff }
            ?? speedEvents.count
        if keep > 0 { speedEvents.removeFirst(keep) }

        let windowStart = now.timeIntervalSinceReferenceDate - 60
        let windowSum = speedEvents.lazy
            .filter { $0.t.timeIntervalSinceReferenceDate > windowStart }
            .reduce(0) { $0 + $1.w }
        currentSpeed = max(0, windowSum)
        peakSpeed = max(peakSpeed, currentSpeed)
        idle = speedEvents.last.map { now.timeIntervalSince($0.t) > 30 } ?? true
    }

    // MARK: - 跨天

    private func rolloverIfNeeded() {
        let today = DayKey.string()
        guard today != currentDay else { return }
        persist()
        currentDay = today
        netChars = 0
        added = 0
        removed = 0
        currentSpeed = 0
        peakSpeed = 0
        idle = true
        speedEvents = []
        activeMinuteSet = []
        activeMinutesBase = 0
        hourBuckets = [Int](repeating: 0, count: 24)
        firstTime = nil
        lastTime = nil
        loadToday()
    }

    // MARK: - 持久化（独立文件 net-<date>.json，与按键数据互不干扰）

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var fileURL: URL {
        Self.storeDir.appendingPathComponent("net-\(currentDay).json")
    }

    private struct Snapshot: Codable {
        var net: Int
        var hours: [String: Int]
        var first: String?
        var last: String?
        var added: Int?     // v1.2 起记录；旧文件缺省时由 net 推导
        var removed: Int?
        var peak: Int?      // v1.3 起记录：今日最快一分钟（字/分）
        var activeMin: Int?
        var minutes: [Int]? // v1.5 起记录：活跃分钟明细，重启后才能继续去重累加
    }

    private func loadToday() {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        netChars = snap.net
        added = snap.added ?? max(snap.net, 0)
        removed = snap.removed ?? max(-snap.net, 0)
        peakSpeed = snap.peak ?? 0
        if let minutes = snap.minutes {
            activeMinuteSet = Set(minutes.filter { (0..<1440).contains($0) })
            activeMinutesBase = 0
        } else {
            // 旧文件只有总数：当作基线，之后新增的分钟叠加在上面
            activeMinutesBase = max(snap.activeMin ?? 0, 0)
        }
        firstTime = snap.first.flatMap { Self.timeFormatter.date(from: $0) }
        lastTime = snap.last.flatMap { Self.timeFormatter.date(from: $0) }
        for (k, v) in snap.hours {
            if let idx = Int(k), (0..<24).contains(idx) { hourBuckets[idx] = v }
        }
    }

    @objc private func persistNow() { persist() }

    func persist() {
        guard AppInstallation.current.allowsPermissionRequests else { return }
        var hours: [String: Int] = [:]
        for (i, v) in hourBuckets.enumerated() where v != 0 {
            hours[String(format: "%02d", i)] = v
        }
        let snap = Snapshot(
            net: netChars,
            hours: hours,
            first: firstTime.map { Self.timeFormatter.string(from: $0) },
            last: lastTime.map { Self.timeFormatter.string(from: $0) },
            added: added,
            removed: removed,
            peak: peakSpeed,
            activeMin: activeMinutes,
            minutes: activeMinuteSet.sorted()
        )
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
