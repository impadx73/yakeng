import Cocoa
import Combine

/// Toàn bộ cài đặt của app, lưu dưới dạng JSON trong UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()

    struct Config: Codable {
        // Ctrl → Cmd
        var ctrlRemapEnabled = true
        var ctrlRemapKeys: [UInt16] = [0, 8, 9]                 // A, C, V
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

        var launchAtLogin = false
    }

    @Published var data: Config {
        didSet { save() }
    }

    private let key = "yakeng.settings"

    private init() {
        if let raw = UserDefaults.standard.data(forKey: key),
           let d = try? JSONDecoder().decode(Config.self, from: raw) {
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
