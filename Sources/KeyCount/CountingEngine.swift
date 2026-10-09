import Foundation

// MARK: - 字数口径

/// 字数口径（Word 风格）：中文按字（含中文标点/全角），英文与数字按词。
enum WordWeight {

    /// CJK 判定：汉字 + 中文标点 + 全角符号 + 假名/谚文（宽进）
    static func isCJK(_ c: Character) -> Bool {
        guard c.unicodeScalars.count == 1, let s = c.unicodeScalars.first else {
            return false   // emoji 等多标量字符不算
        }
        switch s.value {
        case 0x4E00...0x9FFF,   // CJK 统一表意（汉字）
             0x3400...0x4DBF,   // 扩展 A
             0x3000...0x303F,   // 中文标点 。、「」
             0xFF00...0xFFEF,   // 全角 ！？，
             0x3040...0x30FF,   // 平假名/片假名
             0xAC00...0xD7AF:   // 谚文
            return true
        default:
            return false
        }
    }

    /// 中文按字，连续的 ASCII 字母数字串算 1 词；空格、标点、emoji 断词。
    static func weight<S: Sequence>(_ chars: S) -> Int where S.Element == Character {
        var cjk = 0
        var words = 0
        var inWord = false
        for c in chars {
            if isCJK(c) {
                cjk += 1
                inWord = false
            } else if c.isASCII && (c.isLetter || c.isNumber) {
                if !inWord {
                    words += 1
                    inWord = true
                }
            } else {
                inWord = false
            }
        }
        return cjk + words
    }

    /// 本次改动新增片段的字数：剥离公共前后缀后只看新增侧。
    /// 用索引推进而不是先 Array(text)，长文档下每次轮询都要走这一步。
    static func insertedWeight(from old: String, to new: String) -> Int {
        var oldStart = old.startIndex
        var newStart = new.startIndex
        while oldStart < old.endIndex, newStart < new.endIndex, old[oldStart] == new[newStart] {
            old.formIndex(after: &oldStart)
            new.formIndex(after: &newStart)
        }
        var oldEnd = old.endIndex
        var newEnd = new.endIndex
        while oldEnd > oldStart, newEnd > newStart {
            let o = old.index(before: oldEnd)
            let n = new.index(before: newEnd)
            guard old[o] == new[n] else { break }
            oldEnd = o
            newEnd = n
        }
        return weight(new[newStart..<newEnd])
    }
}

// MARK: - 按键分类

/// 按键的纯值描述。把分类规则和 NSEvent 分开，规则才能在测试里直接验。
struct KeySignal: Equatable {
    /// charactersIgnoringModifiers：方向键、F 键在这里是私有使用区标量
    var characters = ""
    var hasCommand = false
    var hasControl = false
    var isRepeat = false
}

/// 一次按键对统计的影响
struct KeyEffect: Equatable {
    /// 计入「敲键字符」：只有真正可打印的字符，长按重复不重复计
    var countsAsCharacter = false
    /// 会改动文本：作为净字数的人工佐证（含长按重复、删除、回车）
    var mutatesText = false
    /// 粘贴、剪切、撤销、重做：随后的文本变化不是逐键敲出来的
    var suppressesTextDiff = false
}

enum KeyClassifier {

    /// 命令键组合里会整块改写文本的几个
    private static let rewritingShortcuts: Set<Character> = ["v", "x", "z", "y"]

    static func effect(of key: KeySignal) -> KeyEffect {
        if key.hasCommand {
            let letter = key.characters.lowercased().first
            return KeyEffect(suppressesTextDiff: letter.map(rewritingShortcuts.contains) ?? false)
        }
        if key.hasControl {
            // 终端与 emacs 键位里 Ctrl+W/K/D 会改文本，预算要认；但不是可打印字符
            return KeyEffect(mutatesText: true)
        }
        guard let scalar = key.characters.unicodeScalars.first else { return KeyEffect() }
        switch scalar.value {
        case 0xF728:                        // 向后删除（fn + delete）
            return KeyEffect(mutatesText: true)
        case 0xF700...0xF8FF:               // 方向键、F1–F12、Home/End、翻页等
            return KeyEffect()
        case 0x08, 0x7F:                    // 退格 / 删除
            return KeyEffect(mutatesText: true)
        case 0x03, 0x09, 0x0A, 0x0D:        // 小键盘回车 / Tab / 换行 / 回车
            return KeyEffect(mutatesText: true)
        case 0x00...0x1F:                   // Esc 及其余控制字符
            return KeyEffect()
        default:
            return KeyEffect(countsAsCharacter: !key.isRepeat, mutatesText: true)
        }
    }
}

// MARK: - 人工佐证

/// 文本改动发生的那一刻，键盘侧能给出的证据。
struct TypingWitness: Equatable {
    /// 预算窗口内会改动文本的按键数
    var textKeys = 0
    /// 距上一次会改动文本的按键有多久；nil 表示窗口内没有按键
    var sinceLastKey: TimeInterval?
    /// 仍在粘贴/剪切/撤销/重做的抑制窗口内
    var suppressed = false
    /// 键盘侧不可用（未授予输入监控）：无从佐证，只能退回体量约束
    var unavailable = false

    static let noKeyboard = TypingWitness(unavailable: true)
}

/// 一次文本变化的处置结果
enum CountDecision: Equatable {

    /// 计入净字数（可正可负）
    case counted(Int)
    /// 首次见到该控件，只记基线
    case baseline
    /// 文本没变，或字数口径下没有变化
    case unchanged
    case ignored(IgnoreReason)

    enum IgnoreReason: String, Equatable {
        /// 没有人工按键佐证：流式输出、文档加载、同步、自动格式化
        case programmatic
        /// 体量超出这段时间的按键能产生的量：粘贴、整篇替换、切换文档
        case oversized
        /// 粘贴、剪切、撤销、重做快捷键窗口内
        case shortcut
        /// 非空 → 空：聊天发送等提交动作，不扣已上屏的字
        case commit
    }

    var countedDelta: Int {
        if case .counted(let delta) = self { return delta }
        return 0
    }

    /// 是否属于「看着像输入但判定不是人打的」，用于面板自查
    var isIgnoredChange: Bool {
        switch self {
        case .ignored(.programmatic), .ignored(.oversized), .ignored(.shortcut):
            return true
        default:
            return false
        }
    }
}

/// 净字数引擎：对每个焦点控件维护文本基线，用「全文字数差」计净增减。
///
/// 准不准的关键不在 diff 算法，而在于判断一次文本变化到底是不是人打出来的。
/// AXValue 变化的来源还包括：AI 流式输出、文档加载、云同步、自动格式化、
/// 在同一个控件里切换文档、以及虚拟化编辑器只把可见部分放进 AXValue。
/// 这些都必须排除，否则计数会凭空暴涨或暴跌。判据有两条：
///   1. 佐证：改动前后必须有会改动文本的按键，否则视为程序化改动；
///   2. 预算：计入的字数不能超过这段时间的按键加上一次选中所能产生的量。
struct NetCountEngine<Key: Hashable> {

    struct Limits {
        /// 单次新增的硬上限，与按键数无关：超过即视为粘贴或程序化写入
        var maxInsertWeight = 150
        /// 一次按键最多能上屏多少字（拼音整句上屏时一次回车可上屏多字）
        var weightPerKey = 4
        /// 固定余量：容忍轮询与按键的时间错位
        var baseAllowance = 8
        /// 距上次按键超过这个时间的文本变化视为程序化
        var corroborationWindow: TimeInterval = 2
        /// 键盘侧不可用时的单次体量上限
        var unwitnessedLimit = 150
        /// 控件基线的保留时长
        var baselineTTL: TimeInterval = 900
        /// 同时跟踪的控件数上限，超出按最久未见淘汰
        var maxBaselines = 32
    }

    private struct Baseline {
        var text: String
        var weight: Int
        /// 上一次轮询时的选中长度：一次按键可以替换掉整段选中文本
        var selection: Int
        var seenAt: Date
    }

    var limits: Limits
    private var baselines: [Key: Baseline] = [:]

    init(limits: Limits = Limits()) {
        self.limits = limits
    }

    var trackedCount: Int { baselines.count }

    mutating func forgetAll() {
        baselines.removeAll()
    }

    mutating func observe(
        text: String,
        for key: Key,
        selection: Int = 0,
        at now: Date,
        witness: TypingWitness
    ) -> CountDecision {
        let newWeight = WordWeight.weight(text)
        let current = Baseline(text: text, weight: newWeight, selection: selection, seenAt: now)

        guard let previous = baselines[key] else {
            evictIfNeeded(now: now, incoming: key)
            baselines[key] = current
            return .baseline
        }
        // 基线总是推进：被忽略的改动不能留在基线里，否则下一次 diff 会把它一起算进来
        baselines[key] = current

        guard previous.text != text else { return .unchanged }
        if witness.suppressed { return .ignored(.shortcut) }
        if !previous.text.isEmpty && text.isEmpty { return .ignored(.commit) }
        guard WordWeight.insertedWeight(from: previous.text, to: text) <= limits.maxInsertWeight else {
            return .ignored(.oversized)
        }

        let delta = newWeight - previous.weight
        guard delta != 0 else { return .unchanged }

        if witness.unavailable {
            // 没有输入监控：无从佐证，只能靠体量拦住明显不是手打的改动
            let limit = limits.unwitnessedLimit + previous.selection
            return abs(delta) <= limit ? .counted(delta) : .ignored(.oversized)
        }
        guard let since = witness.sinceLastKey, since <= limits.corroborationWindow else {
            return .ignored(.programmatic)
        }
        let budget = limits.baseAllowance
            + limits.weightPerKey * witness.textKeys
            + previous.selection
        return abs(delta) <= budget ? .counted(delta) : .ignored(.oversized)
    }

    /// 基线必须回收：长期运行下控件会不断出现，字典不能无上限增长。
    private mutating func evictIfNeeded(now: Date, incoming key: Key) {
        baselines = baselines.filter { now.timeIntervalSince($0.value.seenAt) <= limits.baselineTTL }
        var overflow = baselines.count - limits.maxBaselines + 1
        while overflow > 0, let oldest = oldestKey(excluding: key) {
            baselines.removeValue(forKey: oldest)
            overflow -= 1
        }
    }

    private func oldestKey(excluding key: Key) -> Key? {
        baselines.lazy
            .filter { $0.key != key }
            .min { $0.value.seenAt < $1.value.seenAt }?
            .key
    }
}
