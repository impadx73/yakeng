import Cocoa
import SwiftUI
import Combine
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("Chung", systemImage: "gearshape") }
            CtrlTab(settings: settings)
                .tabItem { Label("Phím Ctrl", systemImage: "keyboard") }
            AltTabTab(settings: settings)
                .tabItem { Label("Alt+Tab", systemImage: "macwindow.on.rectangle") }
            ClipboardTab(settings: settings)
                .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
            VietTab(settings: settings)
                .tabItem { Label("Tiếng Việt", systemImage: "character.cursor.ibeam") }
        }
        .padding(16)
        .frame(width: 560, height: 460)
    }
}

// MARK: - Chung

final class PermissionState: ObservableObject {
    @Published var granted = AXIsProcessTrusted()
    private var timer: Timer?
    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            let g = AXIsProcessTrusted()
            if g != self?.granted { self?.granted = g }
        }
    }
    deinit { timer?.invalidate() }
}

struct GeneralTab: View {
    @ObservedObject var settings: Settings
    @ObservedObject var perm = PermissionState()
    private var axGranted: Bool { perm.granted }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Quyền truy cập") {
                HStack {
                    Image(systemName: axGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(axGranted ? .green : .orange)
                    Text(axGranted ? "Đã cấp quyền Accessibility." : "Chưa có quyền Accessibility – các tính năng phím tắt sẽ không hoạt động.")
                    Spacer()
                    if !axGranted {
                        Button("Mở Cài đặt hệ thống") {
                            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                            AXIsProcessTrustedWithOptions(opts)
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                .padding(6)
            }

            GroupBox("Khởi động") {
                VStack(alignment: .leading) {
                    Toggle("Tự chạy khi đăng nhập", isOn: Binding(
                        get: { settings.data.launchAtLogin },
                        set: { v in settings.data.launchAtLogin = v; LoginItem.set(v) }))
                    if #available(macOS 13, *) {} else {
                        Text("Cần macOS 13 trở lên; với bản cũ hơn hãy thêm Yakeng vào Login Items thủ công.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(6)
            }

            GroupBox("Tính năng") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Ctrl + phím → Cmd + phím (A, C, V…)", isOn: $settings.data.ctrlRemapEnabled)
                    Toggle("Alt + Tab chuyển cửa sổ kiểu Windows", isOn: $settings.data.altTabEnabled)
                    Toggle("Lịch sử clipboard & chụp màn hình", isOn: $settings.data.clipboardEnabled)
                    Toggle("Gõ tiếng Việt", isOn: $settings.data.vietEnabled)
                }
                .padding(6)
            }
            Spacer()
            Text("Yakeng 2.8 – mã nguồn: github.com/impadx73/yakeng")
                .font(.caption).foregroundColor(.secondary)
        }
    }
}

enum LoginItem {
    static func set(_ on: Bool) {
        if #available(macOS 13, *) {
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("LoginItem error: \(error)")
            }
        }
    }
}

// MARK: - Ctrl

struct CtrlTab: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Bật Ctrl → Cmd", isOn: $settings.data.ctrlRemapEnabled)
            Text("Chọn các phím mà khi bấm cùng Ctrl sẽ được hiểu như Cmd:")
            let cols = [GridItem(.adaptive(minimum: 150))]
            LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
                ForEach(KeyNames.letterKeys, id: \.0) { item in
                    let key = item.0
                    Toggle("\(item.1)  –  \(item.2)", isOn: Binding(
                        get: { settings.data.ctrlRemapKeys.contains(key) },
                        set: { on in
                            if on { if !settings.data.ctrlRemapKeys.contains(key) { settings.data.ctrlRemapKeys.append(key) } }
                            else { settings.data.ctrlRemapKeys.removeAll { $0 == key } }
                        }))
                }
            }
            Divider()
            Text("Không áp dụng trong các app sau (bundle ID, cách nhau bằng dấu phẩy):")
            TextField("com.apple.Terminal, com.googlecode.iterm2", text: $settings.data.ctrlRemapExcluded)
                .textFieldStyle(.roundedBorder)
            Text("Mẹo: trong Terminal, Ctrl+C dùng để ngắt lệnh nên mặc định được loại trừ.")
                .font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .disabled(false)
    }
}

// MARK: - Alt+Tab

struct AltTabTab: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Bật Alt + Tab", isOn: $settings.data.altTabEnabled)
            HStack {
                Text("Phím tắt:")
                HotkeyRecorder(hotkey: $settings.data.altTabHotkey)
                Text("(giữ phím bổ trợ, bấm phím chính để duyệt, thêm ⇧ để lùi)")
                    .font(.caption).foregroundColor(.secondary)
            }
            Toggle("Hiện ảnh thu nhỏ của cửa sổ (cần quyền Ghi màn hình)", isOn: $settings.data.altTabThumbnails)
            Toggle("Thả ⌥ vẫn giữ bảng mở – chọn bằng chuột, ←→ hoặc Enter", isOn: $settings.data.altTabSticky)
            Text("Giữ ⌥ và bấm ⇥ để duyệt qua *từng cửa sổ* đang mở (không phải từng app như ⌘⇥ của macOS). Có thể di chuột và bấm vào cửa sổ muốn chuyển. Thả ⌥ để chuyển sang cửa sổ được chọn, Esc để huỷ.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

// MARK: - Clipboard

struct ClipboardTab: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Bật lịch sử clipboard", isOn: $settings.data.clipboardEnabled)
            HStack {
                Text("Phím mở bảng:")
                HotkeyRecorder(hotkey: $settings.data.clipboardHotkey)
            }
            Stepper("Số mục lưu tối đa: \(settings.data.clipboardMaxItems)", value: $settings.data.clipboardMaxItems, in: 5...200, step: 5)
            Toggle("Tự dán ngay khi chọn một mục", isOn: $settings.data.clipboardPasteOnSelect)
            Text("Bảng hiển thị mọi thứ bạn đã sao chép (chữ và ảnh). Nút \"Chụp màn hình\" trong bảng cho phép kéo chọn một vùng màn hình, ảnh sẽ được đưa vào clipboard và lịch sử. Lần đầu dùng, macOS sẽ hỏi quyền Ghi màn hình.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

// MARK: - Tiếng Việt

struct VietTab: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Bật bộ gõ tiếng Việt", isOn: $settings.data.vietEnabled)
            Picker("Kiểu gõ:", selection: $settings.data.vietMethod) {
                Text("Telex (aa=â, aw=ă, dd=đ, s/f/r/x/j)").tag("telex")
                Text("VNI (a6=â, a8=ă, d9=đ, 1/2/3/4/5)").tag("vni")
            }
            .pickerStyle(.radioGroup)
            HStack {
                Text("Phím bật/tắt nhanh:")
                HotkeyRecorder(hotkey: $settings.data.vietToggleHotkey)
                Text("Trạng thái hiện tại:")
                Text(settings.data.vietActive ? "VI" : "EN").bold()
                    .foregroundColor(settings.data.vietActive ? .green : .secondary)
            }
            Toggle("Đặt dấu kiểu mới (hoà, khoẻ, thuý thay vì hòa, khỏe, thúy)", isOn: $settings.data.vietModernTone)
            Toggle("Kiểm tra chính tả – từ không phải tiếng Việt giữ nguyên (files, laptop…)", isOn: $settings.data.vietSpellCheck)
            Toggle("Sửa lỗi gợi ý trên thanh địa chỉ trình duyệt (Chrome, Safari…)", isOn: $settings.data.vietBrowserFix)
            Text("Biểu tượng trên thanh menu hiển thị VI/EN. Khi gõ tiếng Anh, tắt nhanh bằng phím tắt để tránh bị bỏ dấu (ví dụ \"files\" → \"filés\").")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

// MARK: - Ghi phím tắt

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: Hotkey

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let v = HotkeyRecorderView()
        v.onChange = { hotkey = $0 }
        v.current = hotkey
        return v
    }

    func updateNSView(_ v: HotkeyRecorderView, context: Context) {
        v.current = hotkey
        v.needsDisplay = true
    }
}

final class HotkeyRecorderView: NSButton {
    var onChange: ((Hotkey) -> Void)?
    var current: Hotkey? { didSet { refreshTitle() } }
    private var recording = false { didSet { refreshTitle(); EventTap.shared.suspended = recording } }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 110, height: 24))
        bezelStyle = .rounded
        target = self
        action = #selector(toggleRecording)
        refreshTitle()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 24) }
    override var acceptsFirstResponder: Bool { true }

    private func refreshTitle() {
        title = recording ? "Nhấn phím…" : (current?.display ?? "Chưa đặt")
    }

    @objc private func toggleRecording() {
        recording.toggle()
        if recording { window?.makeFirstResponder(self) }
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { recording = false; return }   // Esc: huỷ
        let hk = Hotkey(keyCode: event.keyCode, modifiers: event.modifierFlags)
        current = hk
        recording = false
        onChange?(hk)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recording { keyDown(with: event); return true }
        return super.performKeyEquivalent(with: event)
    }
}
