import Cocoa
import Combine

/// Toàn bộ cài đặt của app, lưu dưới dạng JSON trong UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()

    struct Config: Codable {
        // Ctrl → Cmd
        var ctrlRemapEnabled = true
        var ctrlRemapKeys: [UInt16] = [0, 8, 9, 7, 6]           // A, C, V, X, Z
        var ctrlRemapExcluded = "com.apple.Terminal, com.googlecode.iterm2"

        // Alt + Tab
        var altTabEnabled = true
        var altTabHotkey = Hotkey(keyCode: 48, modifiers: .option)          // ⌥⇥
        var altTabSticky = false        // thả ⌥ vẫn giữ bảng mở, chọn bằng chuột/Enter
        var altTabThumbnails = true     // hiện ảnh thu nhỏ cửa sổ

        // Clipboard
        var clipboardEnabled = true
        var clipboardHotkey = Hotkey(keyCode: 1, modifiers: [.command, .shift])  // ⇧⌘S
        var clipboardMaxItems = 50
        var clipboardPasteOnSelect = true

        // Tiếng Việt
        var vietEnabled = true
        var vietMethod = "telex"                                 // "telex" | "vni"
        var vietToggleHotkey = Hotkey(keyCode: 6, modifiers: .option)       // ⌥Z
        var vietActive = true
        var vietModernTone = false                               // hoà (true) / hòa (false)
        var vietSpellMode = "lenient"                            // "off" | "lenient" | "strict"
        var vietBrowserFix = true                                // sửa lỗi gợi ý thanh địa chỉ trình duyệt

        var launchAtLogin = false

        init() {}

        // Đọc từng trường nếu có, thiếu thì giữ mặc định → thêm trường mới không làm mất cài đặt cũ
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func get<T: Decodable>(_ key: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? def }
            ctrlRemapEnabled = get(.ctrlRemapEnabled, ctrlRemapEnabled)
            ctrlRemapKeys = get(.ctrlRemapKeys, ctrlRemapKeys)
            ctrlRemapExcluded = get(.ctrlRemapExcluded, ctrlRemapExcluded)
            altTabEnabled = get(.altTabEnabled, altTabEnabled)
            altTabHotkey = get(.altTabHotkey, altTabHotkey)
            altTabSticky = get(.altTabSticky, altTabSticky)
            altTabThumbnails = get(.altTabThumbnails, altTabThumbnails)
            clipboardEnabled = get(.clipboardEnabled, clipboardEnabled)
            clipboardHotkey = get(.clipboardHotkey, clipboardHotkey)
            clipboardMaxItems = get(.clipboardMaxItems, clipboardMaxItems)
            clipboardPasteOnSelect = get(.clipboardPasteOnSelect, clipboardPasteOnSelect)
            vietEnabled = get(.vietEnabled, vietEnabled)
            vietMethod = get(.vietMethod, vietMethod)
            vietToggleHotkey = get(.vietToggleHotkey, vietToggleHotkey)
            vietActive = get(.vietActive, vietActive)
            vietModernTone = get(.vietModernTone, vietModernTone)
            vietSpellMode = get(.vietSpellMode, vietSpellMode)
            vietBrowserFix = get(.vietBrowserFix, vietBrowserFix)
            launchAtLogin = get(.launchAtLogin, launchAtLogin)
        }
    }

    @Published var data: Config {
        didSet { save() }
    }

    private let key = "yakeng.settings"

    private init() {
        if let raw = UserDefaults.standard.data(forKey: key),
           var d = try? JSONDecoder().decode(Config.self, from: raw) {
            if d.ctrlRemapKeys == [0, 8, 9] { d.ctrlRemapKeys = [0, 8, 9, 7, 6] }   // nâng cấp mặc định cũ
            data = d
        } else {
            data = Config()
        }
    }

    private func save() {
        if let raw = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(raw, forKey: key)
        }
    }

    var excludedBundleIDs: Set<String> {
        Set(data.ctrlRemapExcluded.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
}
