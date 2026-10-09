import Foundation

/// 键盘侧向净字数引擎提供「人确实敲了键」的证据。
///
/// 两个引擎都在主线程上运行，加锁只是为了不让正确性依赖这一点。
/// 这里只保存时间戳和一个抑制截止时间，不保存任何按键内容。
final class TypingActivity {

    static let shared = TypingActivity()

    /// 预算窗口：窗口内的按键数决定本次文本变化允许计入的体量。
    /// 要盖得住一次较长的拼音组合从起键到上屏的全过程。
    private let window: TimeInterval
    /// 粘贴、剪切、撤销、重做之后的抑制时长
    private let suppression: TimeInterval
    private let lock = NSLock()
    private var keyTimes: [Date] = []
    private var suppressedUntil: Date?
    private var keyboardAvailable = false

    init(window: TimeInterval = 5, suppression: TimeInterval = 0.6) {
        self.window = window
        self.suppression = suppression
    }

    /// 会改动文本的按键：可打印字符、删除、回车、Tab（含长按重复）
    func recordTextKey(at time: Date = Date()) {
        lock.lock()
        keyTimes.append(time)
        trim(now: time)
        lock.unlock()
    }

    /// 粘贴、剪切、撤销、重做：随后的文本变化不是逐键敲出来的
    func suppressTextDiff(at time: Date = Date()) {
        lock.lock()
        suppressedUntil = time.addingTimeInterval(suppression)
        lock.unlock()
    }

    /// 输入监控是否可用。不可用时引擎退回纯体量约束，而不是一律不计——
    /// 只授予辅助功能的用户仍然要能看到字数。
    func setKeyboardAvailable(_ available: Bool) {
        lock.lock()
        if keyboardAvailable != available {
            keyboardAvailable = available
            keyTimes.removeAll()
            suppressedUntil = nil
        }
        lock.unlock()
    }

    func witness(at now: Date = Date()) -> TypingWitness {
        lock.lock()
        defer { lock.unlock() }
        guard keyboardAvailable else { return .noKeyboard }
        trim(now: now)
        return TypingWitness(
            textKeys: keyTimes.count,
            sinceLastKey: keyTimes.last.map { now.timeIntervalSince($0) },
            suppressed: suppressedUntil.map { now < $0 } ?? false
        )
    }

    private func trim(now: Date) {
        let cutoff = now.addingTimeInterval(-window)
        if let keep = keyTimes.firstIndex(where: { $0 > cutoff }) {
            if keep > 0 { keyTimes.removeFirst(keep) }
        } else {
            keyTimes.removeAll()
        }
    }
}
