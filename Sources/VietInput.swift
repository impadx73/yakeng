import Cocoa

/// Bộ gõ tiếng Việt (Telex / VNI) hoạt động qua event tap:
/// theo dõi các phím của từ đang gõ, ghép thành chữ có dấu, rồi gửi backspace + chữ mới.
final class VietInput {
    var method = "telex"          // "telex" | "vni"
    var modernTone = false        // true: hoà, thuý; false: hòa, thúy

    private var raw: [Character] = []     // các phím đã gõ của từ hiện tại
    private var displayed = ""            // chuỗi đang hiển thị trên màn hình cho từ này

    func reset() {
        raw = []
        displayed = ""
    }

    /// Trả về true nếu sự kiện đã được xử lý (cần nuốt).
    func handle(keyCode: Int64, flags: CGEventFlags, event: CGEvent) -> Bool {
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            reset()
            return false
        }

        // Backspace
        if keyCode == 51 {
            guard !raw.isEmpty else { return false }
            raw.removeLast()
            let new = Composer.compose(raw, method: method, modernTone: modernTone)
            apply(new)
            return true
        }

        // Các phím điều hướng, Enter, Tab, Esc… → kết thúc từ
        if [36, 48, 53, 76, 123, 124, 125, 126, 115, 116, 119, 121, 117].contains(keyCode) {
            reset()
            return false
        }

        guard let ch = VietInput.character(of: event) else {
            reset()
            return false
        }

        let isWordKey = ch.isASCII && (ch.isLetter || (method == "vni" && ch.isNumber && !raw.isEmpty))
        guard isWordKey else {
            reset()
            return false
        }

        let candidate = raw + [ch]
        let new = Composer.compose(candidate, method: method, modernTone: modernTone)
        raw = candidate
        if new == displayed + String(ch) {
            // Không có gì thay đổi: để phím đi qua bình thường
            displayed = new
            return false
        }
        apply(new)
        return true
    }

    /// Gửi backspace + ký tự mới để màn hình khớp với `new`.
    private func apply(_ new: String) {
        let old = Array(displayed)
        let nw = Array(new)
        var common = 0
        while common < old.count, common < nw.count, old[common] == nw[common] { common += 1 }
        let del = old.count - common
        for _ in 0..<del { EventTap.sendBackspace() }
        let add = String(nw[common...])
        if !add.isEmpty { EventTap.sendText(add) }
        displayed = new
    }

    static func character(of event: CGEvent) -> Character? {
        var length = 0
        var buf = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &buf)
        guard length > 0 else { return nil }
        let s = String(utf16CodeUnits: buf, count: length)
        guard s.count == 1, let c = s.first else { return nil }
        return c
    }
}

// MARK: - Bộ ghép chữ

enum Composer {
    struct VChar {
        var base: Character   // chữ thường, không dấu: a e i o u y d b c ...
        var mod = 0           // 0: không; 1: mũ (â ê ô) / đ; 2: móc, trăng (ơ ư ă)
        var upper: Bool
        var loneW = false     // "ư" tạo từ phím w đứng một mình
    }

    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]

    // base+mod -> chữ cái; mỗi chữ có 6 dạng dấu: không, sắc, huyền, hỏi, ngã, nặng
    private static let toneTable: [String: [Character]] = [
        "a0": ["a", "á", "à", "ả", "ã", "ạ"],
        "a1": ["â", "ấ", "ầ", "ẩ", "ẫ", "ậ"],
        "a2": ["ă", "ắ", "ằ", "ẳ", "ẵ", "ặ"],
        "e0": ["e", "é", "è", "ẻ", "ẽ", "ẹ"],
        "e1": ["ê", "ế", "ề", "ể", "ễ", "ệ"],
        "i0": ["i", "í", "ì", "ỉ", "ĩ", "ị"],
        "o0": ["o", "ó", "ò", "ỏ", "õ", "ọ"],
        "o1": ["ô", "ố", "ồ", "ổ", "ỗ", "ộ"],
        "o2": ["ơ", "ớ", "ờ", "ở", "ỡ", "ợ"],
        "u0": ["u", "ú", "ù", "ủ", "ũ", "ụ"],
        "u2": ["ư", "ứ", "ừ", "ử", "ữ", "ự"],
        "y0": ["y", "ý", "ỳ", "ỷ", "ỹ", "ỵ"],
    ]

    static func compose(_ raw: [Character], method: String, modernTone: Bool) -> String {
        var chars: [VChar] = []
        var tone = 0

        for k in raw {
            let lower = Character(k.lowercased())
            let upper = k.isUppercase
            var handled = false

            // 1. Phím dấu thanh
            if let t = toneKey(lower, method: method), hasVowel(chars) {
                if t == 0 {
                    if tone != 0 { tone = 0; handled = true }
                } else if tone == t {
                    tone = 0            // gõ lại cùng dấu: bỏ dấu, chữ thành ký tự thường
                } else {
                    tone = t
                    handled = true
                }
            }

            // 2. Phím biến đổi chữ (â ê ô ơ ư ă đ)
            if !handled, let m = modKey(lower, method: method) {
                handled = applyMod(&chars, m, lower: lower, upper: upper)
            }

            // 3. Chữ thường
            if !handled {
                chars.append(VChar(base: lower, mod: 0, upper: upper))
            }
        }
        return render(chars, tone: tone, modernTone: modernTone)
    }

    // MARK: Bảng phím

    private static func toneKey(_ c: Character, method: String) -> Int? {
        if method == "vni" {
            switch c {
            case "1": return 1
            case "2": return 2
            case "3": return 3
            case "4": return 4
            case "5": return 5
            case "0": return 0
            default: return nil
            }
        }
        switch c {
        case "s": return 1
        case "f": return 2
        case "r": return 3
        case "x": return 4
        case "j": return 5
        case "z": return 0
        default: return nil
        }
    }

    private enum Mod { case circA, circE, circO, circAny, horn, breve, hornOrBreve, dd }

    private static func modKey(_ c: Character, method: String) -> Mod? {
        if method == "vni" {
            switch c {
            case "6": return .circAny
            case "7": return .horn
            case "8": return .breve
            case "9": return .dd
            default: return nil
            }
        }
        switch c {
        case "a": return .circA
        case "e": return .circE
        case "o": return .circO
        case "w": return .hornOrBreve
        case "d": return .dd
        default: return nil
        }
    }

    private static func hasVowel(_ chars: [VChar]) -> Bool {
        chars.contains { vowels.contains($0.base) }
    }

    // MARK: Áp dụng biến đổi

    private static func applyMod(_ chars: inout [VChar], _ m: Mod, lower: Character, upper: Bool) -> Bool {
        switch m {
        case .circA, .circE, .circO:
            // Telex: aa→â, ee→ê, oo→ô (phím phải ngay sau nguyên âm đó); gõ lần nữa thì trả lại
            guard let last = chars.last, last.base == lower else { return false }
            if last.mod == 0 {
                chars[chars.count - 1].mod = 1
                return true
            }
            if last.mod == 1 {
                chars[chars.count - 1].mod = 0
                return false    // thêm chữ thường phía sau
            }
            return false

        case .circAny:
            // VNI 6: mũ cho nguyên âm a/e/o cuối cùng
            if let i = chars.lastIndex(where: { ["a", "e", "o"].contains($0.base) }) {
                if chars[i].mod == 1 { chars[i].mod = 0; return false }
                chars[i].mod = 1
                return true
            }
            return false

        case .horn, .breve, .hornOrBreve:
            // Trả lại nếu phím w gõ 2 lần
            if m == .hornOrBreve, let last = chars.last, last.mod == 2 {
                if last.loneW { chars.removeLast() } else { chars[chars.count - 1].mod = 0 }
                return false
            }
            let targets: Set<Character> = (m == .horn) ? ["o", "u"] : (m == .breve) ? ["a"] : ["a", "o", "u"]
            if let i = chars.lastIndex(where: { targets.contains($0.base) && $0.mod == 0 }) {
                chars[i].mod = 2
                // "uo" + w → "ươ"
                if chars[i].base == "o", i > 0, chars[i - 1].base == "u", chars[i - 1].mod == 0 {
                    chars[i - 1].mod = 2
                }
                return true
            }
            if m == .hornOrBreve, !hasVowel(chars) {
                chars.append(VChar(base: "u", mod: 2, upper: upper, loneW: true))
                return true
            }
            return false

        case .dd:
            if lower == "9" {   // VNI
                if let i = chars.lastIndex(where: { $0.base == "d" }) {
                    chars[i].mod = (chars[i].mod == 1) ? 0 : 1
                    return chars[i].mod == 1
                }
                return false
            }
            guard let last = chars.last, last.base == "d" else { return false }
            if last.mod == 0 { chars[chars.count - 1].mod = 1; return true }
            chars[chars.count - 1].mod = 0
            return false
        }
    }

    // MARK: Kết xuất

    private static func render(_ chars: [VChar], tone: Int, modernTone: Bool) -> String {
        var out = ""
        let toneAt = tone == 0 ? nil : toneIndex(chars, modernTone: modernTone)
        for (i, c) in chars.enumerated() {
            var ch: Character
            if vowels.contains(c.base) {
                let key = "\(c.base)\(c.mod)"
                let forms = toneTable[key] ?? toneTable["\(c.base)0"]!
                ch = forms[(toneAt == i) ? tone : 0]
            } else if c.base == "d", c.mod == 1 {
                ch = "đ"
            } else {
                ch = c.base
            }
            out += c.upper ? String(ch).uppercased() : String(ch)
        }
        return out
    }

    /// Vị trí nguyên âm nhận dấu thanh.
    private static func toneIndex(_ chars: [VChar], modernTone: Bool) -> Int? {
        guard let lastV = chars.lastIndex(where: { vowels.contains($0.base) }) else { return nil }
        var start = lastV
        while start > 0, vowels.contains(chars[start - 1].base) { start -= 1 }

        // "qu" và "gi": u/i đóng vai phụ âm
        if start < lastV {
            if chars[start].base == "u", start > 0, chars[start - 1].base == "q" { start += 1 }
            else if chars[start].base == "i", start > 0, chars[start - 1].base == "g" { start += 1 }
        }

        let cluster = Array(start...lastV)
        if cluster.count == 1 { return cluster[0] }

        // Có nguyên âm mang dấu phụ (â ê ô ơ ư ă) → ưu tiên, lấy cái cuối (ươ → ơ, iê → ê)
        if let i = cluster.last(where: { chars[$0].mod != 0 }) { return i }

        let hasFinalConsonant = lastV < chars.count - 1
        if cluster.count >= 3 { return cluster[1] }
        if hasFinalConsonant { return cluster[1] }
        // Kiểu mới chỉ khác ở oa, oe, uy: hoà, khoẻ, thuý
        if modernTone {
            let pair = "\(chars[cluster[0]].base)\(chars[cluster[1]].base)"
            if ["oa", "oe", "uy"].contains(pair) { return cluster[1] }
        }
        return cluster[0]
    }
}
