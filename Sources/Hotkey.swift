import Cocoa

/// Một phím tắt: mã phím + các phím bổ trợ (⌘ ⌥ ⌃ ⇧).
struct Hotkey: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt   // NSEvent.ModifierFlags.rawValue

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask).rawValue
    }

    var flags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection([.command, .option, .control, .shift])
    }

    /// Chuyển cờ của CGEvent sang ModifierFlags (chỉ 4 phím bổ trợ chính).
    static func relevant(_ f: CGEventFlags) -> NSEvent.ModifierFlags {
        var m: NSEvent.ModifierFlags = []
        if f.contains(.maskCommand)   { m.insert(.command) }
        if f.contains(.maskAlternate) { m.insert(.option) }
        if f.contains(.maskControl)   { m.insert(.control) }
        if f.contains(.maskShift)     { m.insert(.shift) }
        return m
    }

    func matches(keyCode kc: Int64, flags f: CGEventFlags, ignoringShift: Bool = false) -> Bool {
        guard Int64(keyCode) == kc else { return false }
        var have = Hotkey.relevant(f)
        var want = flags
        if ignoringShift { have.remove(.shift); want.remove(.shift) }
        return have == want
    }

    /// Các phím bổ trợ của hotkey có còn được giữ không (dùng cho Alt+Tab).
    func modifiersHeld(in f: CGEventFlags) -> Bool {
        var want = flags
        want.remove(.shift)
        return Hotkey.relevant(f).isSuperset(of: want)
    }

    var display: String {
        var s = ""
        let f = flags
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option)  { s += "⌥" }
        if f.contains(.shift)   { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        return s + KeyNames.name(for: keyCode)
    }
}

enum KeyNames {
    static let map: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
        32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
        42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`",
        51: "⌫", 53: "⎋", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 109: "F10", 111: "F12", 118: "F4", 120: "F2", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
    static func name(for code: UInt16) -> String { map[code] ?? "Key\(code)" }

    /// Các phím chữ hay dùng cho tính năng Ctrl→Cmd.
    static let letterKeys: [(UInt16, String, String)] = [
        (0, "A", "Chọn tất cả"), (8, "C", "Sao chép"), (9, "V", "Dán"), (7, "X", "Cắt"),
        (6, "Z", "Hoàn tác"), (16, "Y", "Làm lại"), (1, "S", "Lưu"), (3, "F", "Tìm"),
        (45, "N", "Mới"), (17, "T", "Tab mới"), (13, "W", "Đóng"), (35, "P", "In"),
        (15, "R", "Tải lại"), (37, "L", "Thanh địa chỉ"), (11, "B", "Đậm"), (34, "I", "Nghiêng"),
        (32, "U", "Gạch chân"),
    ]
}
