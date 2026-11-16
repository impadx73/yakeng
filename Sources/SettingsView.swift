import Cocoa
import SwiftUI
import Combine
import ServiceManagement

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, ctrl, altTab, clipboard, viet, notes
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "Chung"
        case .ctrl: return "Phím Ctrl"
        case .altTab: return "Alt+Tab"
        case .clipboard: return "Clipboard"
        case .viet: return "Tiếng Việt"
        case .notes: return "Ghi chú"
        }
    }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .ctrl: return "keyboard"
        case .altTab: return "macwindow.on.rectangle"
        case .clipboard: return "doc.on.clipboard"
        case .viet: return "character.cursor.ibeam"
        case .notes: return "note.text"
        }
    }
}

final class SettingsNav: ObservableObject {
    static let shared = SettingsNav()
    @Published var page: SettingsPage = .general
}

/// Thanh tab tự vẽ: luôn hiện đủ mọi tab (TabView trên macOS mới gom tab thừa vào nút »).
struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var nav = SettingsNav.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(SettingsPage.allCases) { p in
                    let selected = nav.page == p
                    Button(action: { nav.page = p }) {
                        VStack(spacing: 4) {
                            Image(systemName: p.icon).font(.system(size: 18)).frame(height: 22)
                            Text(p.title).font(.system(size: 11, weight: selected ? .semibold : .regular))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundColor(selected ? .accentColor : .primary)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(selected ? Color.accentColor.opacity(0.16) : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            Group {
                switch nav.page {
                case .general: GeneralTab(settings: settings)
                case .ctrl: CtrlTab(settings: settings)
                case .altTab: AltTabTab(settings: settings)
                case .clipboard: ClipboardTab(settings: settings)
                case .viet: VietTab(settings: settings)
                case .notes: NotesTab(settings: settings)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 620, height: 500)
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
            Text("Yakeng 2.17 – mã nguồn: github.com/impadx73/yakeng")
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
            Text("Có thể đặt ⌘⇥: Yakeng sẽ tự tắt bộ chuyển app gốc của macOS khi đang chạy và trả lại khi thoát.")
                .font(.caption).foregroundColor(.secondary)
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
            Picker("Kiểm tra chính tả:", selection: $settings.data.vietSpellMode) {
                Text("Tắt – luôn bỏ dấu (files → filé)").tag("off")
                Text("Nhẹ – chỉ chặn từ tiếng Anh rõ ràng (files, wifi), cho phép đk, đc, ko").tag("lenient")
                Text("Chặt – chỉ bỏ dấu cho âm tiết tiếng Việt chuẩn").tag("strict")
            }
            .pickerStyle(.radioGroup)
            Toggle("Sửa lỗi gợi ý trên thanh địa chỉ trình duyệt (Chrome, Safari…)", isOn: $settings.data.vietBrowserFix)
            Text("Biểu tượng trên thanh menu hiển thị VI/EN. Khi gõ tiếng Anh, tắt nhanh bằng phím tắt để tránh bị bỏ dấu (ví dụ \"files\" → \"filés\").")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

// MARK: - Ghi chú

struct NotesTab: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Bật ghi chú dán (sticky notes)", isOn: $settings.data.notesEnabled)
            HStack {
                Text("Tạo ghi chú mới:")
                HotkeyRecorder(hotkey: $settings.data.notesNewHotkey)
                Spacer().frame(width: 16)
                Text("Ẩn/hiện tất cả:")
                HotkeyRecorder(hotkey: $settings.data.notesToggleHotkey)
            }
            Toggle("Ghi chú mới luôn nổi trên cùng (always on top)", isOn: $settings.data.notesDefaultPinned)
            Picker("Màu mặc định:", selection: $settings.data.notesDefaultColor) {
                ForEach(NoteColors.all) { c in Text(c.label).tag(c.name) }
            }
            .frame(width: 220)
            Text("Mỗi ghi chú là một cửa sổ nhỏ: kéo thanh màu phía trên để di chuyển, kéo cạnh để đổi cỡ. Nhấp đúp thanh trên để thu gọn thành một thanh / mở rộng lại. Đặt tiêu đề trong nút bảng màu → \"Đặt tiêu đề…\" (chưa đặt thì dùng dòng đầu). Trên thanh còn có nút tạo mới, ghim nổi, thu gọn và xoá. Nội dung tự lưu, mở lại khi khởi động.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Tạo ghi chú ngay") { EventTap.shared.notes.createNote() }
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
    private var recording = false {
        didSet {
            refreshTitle()
            if recording {
                // Tạm tắt ⌘⇥ gốc của macOS để ghi được tổ hợp này; bắt phím qua event tap
                EventTap.setNativeCmdTab(enabled: false)
                EventTap.shared.recordingHandler = { [weak self] hk in
                    guard let self = self else { return }
                    self.current = hk
                    self.recording = false
                    self.onChange?(hk)
                }
                if !EventTap.shared.isRunning { EventTap.shared.suspended = true }
            } else {
                EventTap.shared.recordingHandler = nil
                EventTap.shared.suspended = false
                EventTap.shared.applyNativeCmdTabPolicy()
            }
        }
    }

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
        guard recording, !EventTap.shared.isRunning else { if !recording { super.keyDown(with: event) }; return }
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
