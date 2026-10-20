// Yakeng: ánh xạ Ctrl+A / Ctrl+C / Ctrl+V -> Cmd+A / Cmd+C / Cmd+V trên macOS
// Chạy nền, có icon nhỏ trên thanh menu để thoát.

import Cocoa

// Mã phím ảo (virtual keycode) trên bàn phím Mac: A = 0, C = 8, V = 9
let targetKeys: Set<Int64> = [0, 8, 9]

// Những app KHÔNG áp dụng (vì Ctrl+A/C trong terminal có ý nghĩa riêng)
let excludedBundleIDs: Set<String> = [
    "com.apple.Terminal",
    "com.googlecode.iterm2",
]

var eventTap: CFMachPort?

func isExcludedAppActive() -> Bool {
    guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
    return excludedBundleIDs.contains(id)
}

func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    var flags = event.flags

    if targetKeys.contains(keyCode),
       flags.contains(.maskControl),
       !flags.contains(.maskCommand),
       !isExcludedAppActive() {
        flags.remove(.maskControl)
        flags.insert(.maskCommand)
        event.flags = flags
    }
    return Unmanaged.passUnretained(event)
}

func startTap() -> Bool {
    let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(mask),
        callback: handleEvent,
        userInfo: nil
    ) else { return false }
    eventTap = tap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return true
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⌃→⌘"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Yakeng: Ctrl+A/C/V → Cmd+A/C/V", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Thoát", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        // Yêu cầu quyền Accessibility (hiện hộp thoại hệ thống nếu chưa cấp)
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts), startTap() { return }

        // Chưa có quyền: chờ người dùng bật trong System Settings rồi tự khởi động
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            if AXIsProcessTrusted(), startTap() {
                t.invalidate()
                self?.timer = nil
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // không hiện trong Dock
app.run()
