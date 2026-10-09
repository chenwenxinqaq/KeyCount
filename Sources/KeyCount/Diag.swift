import Foundation

/// 可选诊断模式：存在 diag.flag 时，把轮询/键盘事件的元数据写入 diag.log。
/// 用于定位「某场景不计数」类问题；只记录 app/role/长度/计数等元数据，
/// 绝不记录文本内容本身。平时无 flag，除一次 fileExists 外零开销。
enum Diag {

    private static let storeDir: URL = {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyCount", isDirectory: true)
    }()

    static var flagURL: URL { storeDir.appendingPathComponent("diag.flag") }

    static var enabled: Bool {
        FileManager.default.fileExists(atPath: flagURL.path)
    }

    static func log(_ line: String) {
        guard enabled else { return }
        let ts = DateFormatter()
        ts.dateFormat = "HH:mm:ss.SSS"
        let text = "\(ts.string(from: Date())) \(line)\n"
        let url = storeDir.appendingPathComponent("diag.log")
        if let h = FileHandle(forWritingAtPath: url.path) {
            h.seekToEndOfFile()
            h.write(text.data(using: .utf8)!)
            try? h.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// CJK 标量计数（与 NetTextMonitor 口径一致的宽进版）
    static func cjkCount<S: Sequence>(_ scalars: S) -> Int where S.Element == Unicode.Scalar {
        scalars.filter { s in
            (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value)
                || (0x3000...0x303F).contains(s.value) || (0xFF00...0xFFEF).contains(s.value)
                || (0x3040...0x30FF).contains(s.value) || (0xAC00...0xD7AF).contains(s.value)
        }.count
    }
}
