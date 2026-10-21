import Cocoa

/// Event tap duy nhất của app: nhận mọi phím và phân phối cho các tính năng.
final class EventTap {
    static let shared = EventTap()

    /// Đánh dấu các sự kiện do chính Yakeng tạo ra, để không xử lý lại.
    static let magic: Int64 = 0x59414B45   // "YAKE"

    /// Event source riêng cho phím giả lập (cách OpenKey dùng): nhận ra sự kiện của mình qua sourceStateID.
    static let source = CGEventSource(stateID: .privateState)

    private var tap: CFMachPort?
    private let settings = Settings.shared

    let switcher = WindowSwitcher()
    let clipboard = ClipboardManager()
    let viet = VietInput()

    /// Tạm dừng xử lý (khi đang ghi phím tắt trong Cài đặt).
    var suspended = false

    var onVietToggled: (() -> Void)?

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue)

        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: yakengTapCallback,
            userInfo: nil
        ) else { return false }

        tap = t
        // Chạy tap trên luồng riêng, ưu tiên cao: mọi việc nặng trên luồng chính (SwiftUI, truy vấn
        // Accessibility tới app khác…) không làm trễ phím; nếu trễ >1s macOS sẽ tắt tap và phím thô lọt ra.
        let thread = Thread { [t] in
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: t, enable: true)
            CFRunLoopRun()
        }
        thread.name = "yakeng.eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()
        startFocusMonitor()
        return true
    }

    // MARK: - Theo dõi app/ô đang focus (chạy nền, tap chỉ đọc kết quả đã cache)

    private let monitorQueue = DispatchQueue(label: "yakeng.focus-monitor", qos: .utility)
    private var monitorTimer: DispatchSourceTimer?
    /// Bundle ID của app phía trước và việc con trỏ có ở giao diện trình duyệt (ngoài trang web) không.
    private(set) var frontBundleID = ""
    private(set) var browserChromeFocused = false

    private func startFocusMonitor() {
        let timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            self.frontBundleID = id
            if VietInput.browserBundleIDs.contains(id) {
                self.browserChromeFocused = VietInput.isBrowserChromeFocused()
            } else {
                self.browserChromeFocused = false
            }
        }
        timer.resume()
        monitorTimer = timer
    }

    var isRunning: Bool { tap != nil }

    // MARK: - Xử lý sự kiện

    /// Proxy của sự kiện đang xử lý – dùng để chèn phím giả lập đúng thứ tự.
    private var currentProxy: CGEventTapProxy?

    func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        currentProxy = proxy
        defer { currentProxy = nil }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == EventTap.magic {
            return Unmanaged.passUnretained(event)
        }
        if let src = EventTap.source, event.getIntegerValueField(.eventSourceStateID) == Int64(src.sourceStateID.rawValue) {
            return Unmanaged.passUnretained(event)
        }
        if suspended { return Unmanaged.passUnretained(event) }

        let cfg = settings.data
        let flags = event.flags

        if type == .keyDown { setHeld(event.getIntegerValueField(.keyboardEventKeycode), true) }
        if type == .keyUp { setHeld(event.getIntegerValueField(.keyboardEventKeycode), false) }

        switch type {
        case .leftMouseDown:
            viet.reset()
            switcher.noteFocusedWindow(after: 0.25)
            return Unmanaged.passUnretained(event)

        case .flagsChanged:
            if switcher.isVisible, !cfg.altTabHotkey.modifiersHeld(in: flags) {
                let sticky = cfg.altTabSticky
                DispatchQueue.main.async { if sticky { self.switcher.detach() } else { self.switcher.commit() } }
            }
            return Unmanaged.passUnretained(event)

        case .keyUp:
            return Unmanaged.passUnretained(event)

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            // Bật/tắt tiếng Việt
            if cfg.vietEnabled, cfg.vietToggleHotkey.matches(keyCode: keyCode, flags: flags) {
                viet.reset()
                DispatchQueue.main.async {
                    self.settings.data.vietActive.toggle()
                    self.onVietToggled?()
                }
                return nil
            }

            // Lịch sử clipboard
            if cfg.clipboardEnabled, cfg.clipboardHotkey.matches(keyCode: keyCode, flags: flags) {
                viet.reset()
                DispatchQueue.main.async { self.clipboard.togglePanel() }
                return nil
            }

            // Alt + Tab
            if cfg.altTabEnabled, cfg.altTabHotkey.matches(keyCode: keyCode, flags: flags, ignoringShift: true) {
                viet.reset()
                let backward = flags.contains(.maskShift)
                DispatchQueue.main.async { self.switcher.step(backward: backward) }
                return nil
            }
            if switcher.isVisible {
                if keyCode == 53 { DispatchQueue.main.async { self.switcher.cancel() } }   // Esc
                if keyCode == 36 || keyCode == 76 { DispatchQueue.main.async { self.switcher.commit() } }   // Enter
                if keyCode == 123 { DispatchQueue.main.async { self.switcher.step(backward: true) } }   // ←
                if keyCode == 124 { DispatchQueue.main.async { self.switcher.step(backward: false) } }  // →
                return nil
            }

            // Ctrl → Cmd
            if cfg.ctrlRemapEnabled,
               cfg.ctrlRemapKeys.contains(UInt16(keyCode)),
               flags.contains(.maskControl),
               !flags.contains(.maskCommand),
               !isExcludedAppActive() {
                var f = flags
                f.remove(.maskControl)
                f.insert(.maskCommand)
                event.flags = f
                viet.reset()
                return Unmanaged.passUnretained(event)
            }

            // Gõ tiếng Việt
            if cfg.vietEnabled, cfg.vietActive {
                viet.method = cfg.vietMethod
                viet.modernTone = cfg.vietModernTone
                viet.browserFix = cfg.vietBrowserFix
                viet.spellCheck = cfg.vietSpellMode
                if viet.handle(keyCode: keyCode, flags: flags, event: event) {
                    return nil
                }
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func isExcludedAppActive() -> Bool {
        settings.excludedBundleIDs.contains(frontBundleID)
    }

    // MARK: - Gửi phím giả lập

    /// Gửi sự kiện: nếu đang ở trong callback của tap thì chèn ngay sau sự kiện hiện tại
    /// (đúng thứ tự, không bị ứng dụng như Chrome xử lý lệch); nếu không thì đưa vào hàng đợi HID.
    static func post(_ e: CGEvent?) {
        guard let e = e else { return }
        e.setIntegerValueField(.eventSourceUserData, value: magic)
        if let proxy = shared.currentProxy {
            e.tapPostEvent(proxy)
        } else {
            e.post(tap: .cghidEventTap)
        }
    }

    static func sendKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags.union(.maskNonCoalesced)
        up?.flags = flags.union(.maskNonCoalesced)
        post(down)
        post(up)
    }

    static func sendBackspace() { sendKey(51) }

    /// Gửi từng ký tự một (mỗi sự kiện một ký tự, như OpenKey/Unikey).
    static func sendText(_ s: String) {
        for ch in s { sendCharacter(ch) }
    }

    /// Các phím vật lý đang được giữ (cập nhật trong tap).
    private var heldKeys = Set<Int64>()
    private let heldKeysLock = NSLock()

    fileprivate func setHeld(_ keyCode: Int64, _ down: Bool) {
        heldKeysLock.lock(); defer { heldKeysLock.unlock() }
        if down { heldKeys.insert(keyCode) } else { heldKeys.remove(keyCode) }
    }

    /// Mã phím cho ký tự giả lập. Phải là một phím chữ cái thật (Telegram/Qt bỏ qua mã phím lạ),
    /// nhưng KHÔNG được là phím người dùng đang giữ: nếu ngón tay còn giữ phím A (gõ nhanh "là", "đăng")
    /// mà ký tự thay thế cũng mang mã phím A, macOS coi đó là phím lặp và chặn (press-and-hold) → mất chữ.
    private static let letterKeyCodes: [Int64] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17]
    static func freeKeyCode() -> CGKeyCode {
        shared.heldKeysLock.lock(); defer { shared.heldKeysLock.unlock() }
        for k in letterKeyCodes where !shared.heldKeys.contains(k) { return CGKeyCode(k) }
        return 0
    }

    static func sendCharacter(_ ch: Character) {
        var units = Array(String(ch).utf16)
        let key = freeKeyCode()
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
        up?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
        down?.flags = .maskNonCoalesced
        up?.flags = .maskNonCoalesced
        post(down)
        post(up)
    }

    /// Bundle ID của app đang ở trước (đã cache, không gọi NSWorkspace trong tap).
    static var frontmostBundleID: String { shared.frontBundleID }
}

private func yakengTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    return EventTap.shared.handle(proxy: proxy, type: type, event: event)
}
