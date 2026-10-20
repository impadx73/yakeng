// Yakeng – bộ công cụ bàn phím kiểu Windows cho macOS
// Ctrl→Cmd · Alt+Tab · Lịch sử clipboard & chụp màn hình · Gõ tiếng Việt
import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var permissionTimer: Timer?
    private let tap = EventTap.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        tap.onVietToggled = { [weak self] in self?.refreshStatusTitle() }
        tap.clipboard.start()

        // Quyền Accessibility
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts), tap.start() {
            refreshStatusTitle()
        } else {
            refreshStatusTitle()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
                guard let self = self else { return }
                if AXIsProcessTrusted(), self.tap.start() {
                    t.invalidate()
                    self.permissionTimer = nil
                    self.refreshStatusTitle()
                }
            }
            if UserDefaults.standard.object(forKey: "yakeng.settings") == nil {
                openSettings()   // lần đầu chạy: mở cài đặt để hướng dẫn cấp quyền
            }
        }
    }

    // MARK: - Thanh menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func refreshStatusTitle() {
        guard let b = statusItem.button else { return }
        let cfg = Settings.shared.data
        if !tap.isRunning {
            b.title = "Y!"
            b.toolTip = "Yakeng: chưa có quyền Accessibility"
        } else if cfg.vietEnabled {
            b.title = cfg.vietActive ? "VI" : "EN"
            b.toolTip = "Yakeng – gõ tiếng Việt: \(cfg.vietActive ? "bật" : "tắt")"
        } else {
            b.title = "Y"
            b.toolTip = "Yakeng"
        }
    }

    @objc private func toggleViet() {
        Settings.shared.data.vietActive.toggle()
        tap.viet.reset()
        refreshStatusTitle()
    }

    @objc private func showClipboard() { tap.clipboard.togglePanel() }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "Yakeng – Cài đặt"
            w.contentView = NSHostingView(rootView: SettingsView())
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let cfg = Settings.shared.data

        let head = NSMenuItem(title: tap.isRunning ? "Yakeng đang chạy" : "Yakeng: chưa có quyền Accessibility", action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        menu.addItem(.separator())

        if cfg.vietEnabled {
            let v = NSMenuItem(title: "Gõ tiếng Việt (\(cfg.vietToggleHotkey.display))", action: #selector(toggleViet), keyEquivalent: "")
            v.state = cfg.vietActive ? .on : .off
            v.target = self
            menu.addItem(v)
        }
        if cfg.clipboardEnabled {
            let c = NSMenuItem(title: "Lịch sử clipboard… (\(cfg.clipboardHotkey.display))", action: #selector(showClipboard), keyEquivalent: "")
            c.target = self
            menu.addItem(c)
        }
        menu.addItem(.separator())
        let s = NSMenuItem(title: "Cài đặt…", action: #selector(openSettings), keyEquivalent: ",")
        s.target = self
        menu.addItem(s)
        menu.addItem(.separator())
        let q = NSMenuItem(title: "Thoát Yakeng", action: #selector(quit), keyEquivalent: "q")
        q.target = self
        menu.addItem(q)

        refreshStatusTitle()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // không hiện trong Dock
app.run()
