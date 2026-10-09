import Foundation

/// 计数回归：直接跑 CountingEngine.swift 与 TypingActivity.swift 里的真实实现，
/// 不复制一份算法（复制过的那份注定和线上行为漂移）。
@main
enum CountingTests {

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

    // MARK: - 回放

    /// 一次回放的按键环境。默认值 = 正在连续打字（5 秒窗口里约 25 次按键）。
    struct Keyboard {
        var keys = 25
        var sinceLastKey: TimeInterval? = 0.1
        var suppressed = false
        var unavailable = false

        static let silent = Keyboard(keys: 0, sinceLastKey: nil)
        static let noKeyboard = Keyboard(unavailable: true)

        var witness: TypingWitness {
            TypingWitness(
                textKeys: keys, sinceLastKey: sinceLastKey,
                suppressed: suppressed, unavailable: unavailable
            )
        }
    }

    struct Totals: Equatable {
        var added = 0
        var removed = 0
        var net: Int { added - removed }
    }

    /// 回放轮询依次看到的文本，返回 (增, 删)
    static func replay(
        _ texts: [String], keyboard: Keyboard = Keyboard(), selection: Int = 0
    ) -> Totals {
        var engine = NetCountEngine<Int>()
        let now = Date()
        var totals = Totals()
        for text in texts {
            let delta = engine.observe(
                text: text, for: 0, selection: selection, at: now, witness: keyboard.witness
            ).countedDelta
            if delta > 0 { totals.added += delta } else { totals.removed -= delta }
        }
        return totals
    }

    static func expect(
        _ name: String, _ texts: [String], keyboard: Keyboard = Keyboard(),
        selection: Int = 0, added: Int, removed: Int
    ) {
        let got = replay(texts, keyboard: keyboard, selection: selection)
        let want = Totals(added: added, removed: removed)
        if got != want {
            print("     \(name): 增\(got.added) 删\(got.removed) 净\(got.net)"
                + "（期望 增\(want.added) 删\(want.removed) 净\(want.net)）")
        }
        check(name, got == want)
    }

    // MARK: - 用例

    static let pinyin = "wojintianzaitushuguanliduwanglehenchangyidiandeshu"
    static let hanzi = "我今天在图书馆里读完了很长一点的书"   // 17 汉字
    static let longText = String(repeating: "字", count: 200)

    static func main() {
        weights()
        humanTyping()
        nonHumanChanges()
        selectionBudget()
        fallbackWithoutKeyboard()
        baselineHousekeeping()
        keyClassification()
        typingActivity()

        print("")
        print("通过 \(passed) / \(passed + failed)")
        exit(failed == 0 ? 0 : 1)
    }

    /// 字数口径
    static func weights() {
        check("汉字按字", WordWeight.weight("你好世界") == 4)
        check("英文按词", WordWeight.weight("hello world") == 2)
        check("连续字母算一词", WordWeight.weight("hello") == 1)
        check("中英混排", WordWeight.weight("第3章") == 3)
        check("中文标点计入", WordWeight.weight("好。") == 2)
        check("空格与标点不计", WordWeight.weight("  ,.!") == 0)
        check("emoji 不计", WordWeight.weight("👍") == 0)
        check("emoji 断词", WordWeight.weight("ab👍cd") == 2)
        check("新增片段只看新增侧",
              WordWeight.insertedWeight(from: "你好", to: "你好世界") == 2)
        check("删除时新增片段为零",
              WordWeight.insertedWeight(from: "你好世界", to: "你好") == 0)
        check("整句上屏只看新增侧",
              WordWeight.insertedWeight(from: pinyin, to: hanzi) == 17)
    }

    /// 人在打字：轮询粒度不能影响结果
    static func humanTyping() {
        let fine = replay(["", "w", "wo", "woj", "wojint", pinyin, hanzi])
        let coarse = replay(["", pinyin, hanzi])
        check("拼音整句上屏计 17 字", fine.net == 17)
        check("轮询粒度不影响结果", fine == coarse)

        expect("逐字打汉字", ["", "你", "你好", "你好世", "你好世界"], added: 4, removed: 0)
        expect("英文逐字母打 hello", ["", "h", "he", "hel", "hell", "hello", "hello "],
               added: 1, removed: 0)
        expect("英文改错字 teh→the", ["teh ", "the "], added: 0, removed: 0)
        expect("选词改写 world→你好", ["hello world", "hello 你好"], added: 1, removed: 0)
        expect("英文删到剩 1 词",
               ["hello world ", "ello world ", "hello world", "hello worl", "hello wor",
                "hello wo", "hello w", "hello ", "hello"],
               added: 0, removed: 1)
        expect("打 100 字后删 40 字",
               [""] + (1...100).map { String(repeating: "字", count: $0) }
                   + stride(from: 99, through: 60, by: -1).map { String(repeating: "字", count: $0) },
               added: 100, removed: 40)
        expect("聊天发送不扣减", ["", "今天心情不错", ""], added: 6, removed: 0)
        expect("清空命中发送豁免", ["你好" + longText, ""], added: 0, removed: 0)
        expect("文本无变化不计数", ["", "", ""], added: 0, removed: 0)
    }

    /// 不是人打的：必须既不加也不减
    static func nonHumanChanges() {
        expect("无按键佐证不计（流式输出/加载/同步）", ["", hanzi],
               keyboard: .silent, added: 0, removed: 0)
        expect("停手 3 秒后的变化不计", ["", hanzi],
               keyboard: Keyboard(keys: 0, sinceLastKey: 3), added: 0, removed: 0)
        expect("粘贴大段不计", ["", longText], added: 0, removed: 0)
        expect("粘贴快捷键窗口内不计", ["", "刚粘进来的一段话"],
               keyboard: Keyboard(suppressed: true), added: 0, removed: 0)
        expect("撤销窗口内不倒扣", ["刚打的一段话", ""],
               keyboard: Keyboard(suppressed: true), added: 0, removed: 0)

        // 同一个控件里切换文档：整篇被换掉，不能当成人工删除
        let document = String(repeating: "文", count: 5_000)
        expect("切换文档不倒扣", [document, "新文件"], added: 0, removed: 0)

        // 关键不变量：被忽略的改动不能留在基线里，否则下一次编辑会把它补算回来
        var engine = NetCountEngine<Int>()
        let now = Date()
        let keyboard = Keyboard().witness
        _ = engine.observe(text: document, for: 0, at: now, witness: keyboard)
        _ = engine.observe(text: "新文件", for: 0, at: now, witness: keyboard)
        let next = engine.observe(text: "新文件啊", for: 0, at: now, witness: keyboard)
        check("忽略后基线已推进", next == .counted(1))

        // 输出量在预算之内时仍会计入，但误差被限制在「这段时间手能打出来的量」
        let flood = engine.observe(
            text: "新文件啊" + String(repeating: "出", count: 500),
            for: 0, at: now, witness: keyboard
        )
        check("超预算的突增被判为非人工", flood == .ignored(.oversized))
    }

    /// 选中文本时，一次按键可以替换或删掉一整段
    static func selectionBudget() {
        let now = Date()
        let single = TypingWitness(textKeys: 1, sinceLastKey: 0.05)
        let paragraph = String(repeating: "段", count: 120)

        /// 上一次轮询读到的选中长度，决定这一次改动的预算
        func deleteParagraph(previousSelection: Int) -> CountDecision {
            var engine = NetCountEngine<Int>()
            _ = engine.observe(
                text: "开头" + paragraph, for: 0,
                selection: previousSelection, at: now, witness: single
            )
            return engine.observe(text: "开头", for: 0, selection: 0, at: now, witness: single)
        }
        check("选中 120 字后一键删除照扣", deleteParagraph(previousSelection: 120) == .counted(-120))
        check("没有选中时单键删不掉 120 字",
              deleteParagraph(previousSelection: 0) == .ignored(.oversized))

        var engine = NetCountEngine<Int>()
        _ = engine.observe(text: paragraph, for: 0, selection: 120, at: now, witness: single)
        check("全选后删到空仍走提交豁免",
              engine.observe(text: "", for: 0, at: now, witness: single) == .ignored(.commit))
    }

    /// 只授予辅助功能时无从佐证：退回体量约束，而不是一律不计
    static func fallbackWithoutKeyboard() {
        expect("无输入监控时正常计数", ["", hanzi],
               keyboard: .noKeyboard, added: 17, removed: 0)
        expect("无输入监控时仍拦住整篇替换",
               [String(repeating: "文", count: 5_000), "新文件"],
               keyboard: .noKeyboard, added: 0, removed: 0)
    }

    /// 基线必须回收，长期运行不能无上限增长
    static func baselineHousekeeping() {
        var limits = NetCountEngine<Int>.Limits()
        limits.maxBaselines = 4
        limits.baselineTTL = 60
        var engine = NetCountEngine<Int>(limits: limits)
        let now = Date()
        let witness = Keyboard().witness
        for key in 0..<10 {
            _ = engine.observe(text: "文本\(key)", for: key, at: now, witness: witness)
        }
        check("控件数量有上限", engine.trackedCount <= 4)

        var aging = NetCountEngine<Int>(limits: limits)
        _ = aging.observe(text: "旧控件", for: 1, at: now, witness: witness)
        _ = aging.observe(text: "新控件", for: 2, at: now.addingTimeInterval(600), witness: witness)
        check("过期基线被清掉", aging.trackedCount == 1)

        var forgotten = NetCountEngine<Int>()
        _ = forgotten.observe(text: "你好", for: 0, at: now, witness: witness)
        forgotten.forgetAll()
        check("撤销授权后基线清空", forgotten.trackedCount == 0)
        check("重新见到控件只记基线",
              forgotten.observe(text: "你好世界", for: 0, at: now, witness: witness) == .baseline)
    }

    /// 按键分类：哪些算字符、哪些算文本改动、哪些要抑制
    static func keyClassification() {
        func effect(
            _ characters: String, command: Bool = false,
            control: Bool = false, repeated: Bool = false
        ) -> KeyEffect {
            KeyClassifier.effect(of: KeySignal(
                characters: characters, hasCommand: command,
                hasControl: control, isRepeat: repeated
            ))
        }
        func scalar(_ value: UInt32) -> String {
            String(Character(Unicode.Scalar(value)!))
        }

        check("字母既算字符也算文本改动",
              effect("a") == KeyEffect(countsAsCharacter: true, mutatesText: true))
        check("汉字直接上屏同样计入",
              effect("好") == KeyEffect(countsAsCharacter: true, mutatesText: true))
        check("长按重复不重复计字符",
              effect("a", repeated: true) == KeyEffect(countsAsCharacter: false, mutatesText: true))
        check("删除键改动文本但不是字符",
              effect(scalar(0x7F)) == KeyEffect(mutatesText: true))
        check("向后删除也算文本改动",
              effect(scalar(0xF728)) == KeyEffect(mutatesText: true))
        check("回车改动文本但不是字符",
              effect(scalar(0x0D)) == KeyEffect(mutatesText: true))
        check("Tab 改动文本但不是字符",
              effect(scalar(0x09)) == KeyEffect(mutatesText: true))
        check("Esc 不计", effect(scalar(0x1B)) == KeyEffect())
        check("方向键不计", effect(scalar(0xF702)) == KeyEffect())
        check("功能键不计", effect(scalar(0xF704)) == KeyEffect())
        check("翻页键不计", effect(scalar(0xF72C)) == KeyEffect())
        check("空按键不计", effect("") == KeyEffect())
        check("粘贴要抑制随后的文本变化",
              effect("v", command: true) == KeyEffect(suppressesTextDiff: true))
        check("撤销要抑制", effect("z", command: true) == KeyEffect(suppressesTextDiff: true))
        check("重做要抑制", effect("y", command: true) == KeyEffect(suppressesTextDiff: true))
        check("剪切要抑制", effect("x", command: true) == KeyEffect(suppressesTextDiff: true))
        check("全选不抑制也不计", effect("a", command: true) == KeyEffect())
        check("命令键组合不算字符", effect("s", command: true) == KeyEffect())
        check("Ctrl 组合改文本但不算字符（终端/emacs 键位）",
              effect("k", control: true) == KeyEffect(mutatesText: true))
        check("Cmd+Ctrl 组合按命令键处理", effect("k", command: true, control: true) == KeyEffect())
    }

    /// 按键证据的时间窗口
    static func typingActivity() {
        let start = Date()
        let activity = TypingActivity(window: 5, suppression: 0.6)
        check("未授权输入监控时证据不可用", activity.witness(at: start).unavailable)

        activity.setKeyboardAvailable(true)
        let empty = activity.witness(at: start)
        check("授权后无按键则没有佐证", !empty.unavailable && empty.sinceLastKey == nil)

        activity.recordTextKey(at: start)
        activity.recordTextKey(at: start.addingTimeInterval(0.2))
        let fresh = activity.witness(at: start.addingTimeInterval(0.3))
        check("窗口内按键计入预算", fresh.textKeys == 2)
        check("记录距上次按键的时间",
              (fresh.sinceLastKey ?? 99) > 0.09 && (fresh.sinceLastKey ?? 0) < 0.11)

        let stale = activity.witness(at: start.addingTimeInterval(9))
        check("过期按键不再作为佐证", stale.textKeys == 0 && stale.sinceLastKey == nil)

        activity.suppressTextDiff(at: start)
        check("抑制窗口内生效", activity.witness(at: start.addingTimeInterval(0.3)).suppressed)
        check("抑制窗口会过期", !activity.witness(at: start.addingTimeInterval(1)).suppressed)

        activity.recordTextKey(at: start)
        activity.setKeyboardAvailable(false)
        check("撤销授权后证据失效", activity.witness(at: start).unavailable)
        activity.setKeyboardAvailable(true)
        check("重新授权不沿用旧按键", activity.witness(at: start).textKeys == 0)
    }
}
