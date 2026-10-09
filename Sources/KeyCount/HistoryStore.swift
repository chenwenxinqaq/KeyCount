import Foundation

/// 按日落盘的文件名键。写入和读取必须用同一份实现：
/// 用默认 DateFormatter 的话，地区日历是佛历/和历时会写出 2569-10-02 这种年份，
/// 汇总侧按公历解析就对不上，当天数据会在历史图表里凭空消失。
enum DayKey {

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }()

    static func string(for date: Date = Date()) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 1, parts.day ?? 1)
    }

    /// 只认 yyyy-MM-dd；非法文件名直接跳过，不参与汇总
    static func date(from key: String) -> Date? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard key.count == 10, parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

/// 单日历史记录：文本侧（net-*.json）+ 键盘侧（*.json），由按日落盘文件汇总而来
struct DayRecord: Identifiable {
    let date: Date      // 当天 0 点
    /// 净字数：新增 − 删减
    var netChars = 0
    /// 上屏字数：累计新增
    var typed = 0
    /// 敲键字符
    var chars = 0
    /// 总按键
    var keys = 0
    var id: Date { date }
}

/// 读取历史数据。带短缓存：面板打开期间净字数高频刷新，避免每次重绘都扫目录
enum HistoryStore {

    private static let cacheTTL: TimeInterval = 10
    private static var cache: (at: Date, days: [DayRecord])?
    private static let lock = NSLock()

    private struct DailyTotals {
        var netChars = 0
        var typed = 0
        var chars = 0
        var keys = 0
    }

    private static let storeDir: URL = {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyCount", isDirectory: true)
    }()

    /// 近 n 天（含今天）的每日统计，无数据的天补 0，按日期升序返回
    static func recentDays(_ n: Int) -> [DayRecord] {
        lock.lock()
        if let c = cache, Date().timeIntervalSince(c.at) < cacheTTL {
            lock.unlock()
            return c.days
        }
        lock.unlock()

        let cal = Calendar.current

        // 一次扫目录建立 日期 → 各项数值 索引，再组装窗口期
        var totals = [String: DailyTotals]()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: storeDir, includingPropertiesForKeys: nil)) ?? []
        for url in files {
            var name = url.lastPathComponent
            let isNet = name.hasPrefix("net-")
            if isNet { name.removeFirst(4) }
            guard name.hasSuffix(".json") else { continue }
            let day = String(name.dropLast(5))
            guard DayKey.date(from: day) != nil else { continue }   // 只认合法日期文件
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            func number(_ key: String) -> Int? { (obj[key] as? NSNumber)?.intValue }
            var entry = totals[day] ?? DailyTotals()
            if isNet {
                guard let net = number("net") else { continue }
                entry.netChars = net
                // added 自 v1.2 起记录；旧文件只能由 net 推导出下限
                entry.typed = number("added") ?? max(net, 0)
            } else {
                guard let keys = number("keys") else { continue }
                entry.keys = keys
                entry.chars = number("chars") ?? 0
            }
            totals[day] = entry
        }

        let today = cal.startOfDay(for: Date())
        var days: [DayRecord] = []
        for offset in stride(from: n - 1, through: 0, by: -1) {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let entry = totals[DayKey.string(for: date)] ?? DailyTotals()
            days.append(DayRecord(date: date, netChars: entry.netChars, typed: entry.typed,
                                  chars: entry.chars, keys: entry.keys))
        }

        lock.lock()
        cache = (Date(), days)
        lock.unlock()
        return days
    }
}
