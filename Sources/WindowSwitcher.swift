import Cocoa
import SwiftUI

@_silgen_name("_AXUIElementGetWindow")
@discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

struct WinInfo: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let appName: String
    let icon: NSImage?
}

final class SwitcherModel: ObservableObject {
    @Published var windows: [WinInfo] = []
    @Published var index = 0
}

/// Bảng chuyển cửa sổ kiểu Windows: giữ ⌥, bấm ⇥ để duyệt, thả ⌥ để chọn.
final class WindowSwitcher {
    private var panel: NSPanel?
    private let model = SwitcherModel()

    var isVisible: Bool { panel != nil }

    func step(backward: Bool) {
        if panel == nil {
            model.windows = WindowSwitcher.fetchWindows()
            guard !model.windows.isEmpty else { return }
            model.index = model.windows.count > 1 ? (backward ? model.windows.count - 1 : 1) : 0
            show()
        } else {
            let n = model.windows.count
            guard n > 0 else { return }
            model.index = (model.index + (backward ? -1 : 1) + n) % n
        }
    }

    func commit() {
        guard panel != nil, model.index < model.windows.count else { cancel(); return }
        let w = model.windows[model.index]
        hide()
        WindowSwitcher.activate(w)
    }

    func cancel() { hide() }

    // MARK: - Giao diện

    private func show() {
        let view = SwitcherView(model: model)
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentView = host
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.midY - size.height / 2))
        }
        p.orderFrontRegardless()
        panel = p
    }

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Danh sách cửa sổ

    static func fetchWindows() -> [WinInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let myPid = ProcessInfo.processInfo.processIdentifier
        var result: [WinInfo] = []
        var iconCache: [pid_t: NSImage?] = [:]

        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != myPid,
                  let num = w[kCGWindowNumber as String] as? CGWindowID else { continue }
            let alpha = w[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0.1 else { continue }
            var bounds = CGRect.zero
            if let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b as CFDictionary) { bounds = r }
            guard bounds.width >= 100, bounds.height >= 60 else { continue }
            let title = (w[kCGWindowName as String] as? String) ?? ""
            let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
            let app = NSRunningApplication(processIdentifier: pid)
            guard app?.activationPolicy == .regular else { continue }
            if iconCache[pid] == nil { iconCache[pid] = app?.icon }
            result.append(WinInfo(id: num, pid: pid, title: title, appName: app?.localizedName ?? owner, icon: iconCache[pid] ?? nil))
        }
        return result
    }

    // MARK: - Kích hoạt cửa sổ

    static func activate(_ w: WinInfo) {
        let axApp = AXUIElementCreateApplication(w.pid)
        var value: CFTypeRef?
        var target: AXUIElement?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
           let wins = value as? [AXUIElement] {
            for ax in wins {
                var wid: CGWindowID = 0
                if _AXUIElementGetWindow(ax, &wid) == .success, wid == w.id { target = ax; break }
            }
            if target == nil, !w.title.isEmpty {
                for ax in wins {
                    var t: CFTypeRef?
                    if AXUIElementCopyAttributeValue(ax, kAXTitleAttribute as CFString, &t) == .success,
                       let s = t as? String, s == w.title { target = ax; break }
                }
            }
        }
        if let ax = target {
            AXUIElementSetAttributeValue(ax, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(ax, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(ax, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
        NSRunningApplication(processIdentifier: w.pid)?.activate(options: [.activateIgnoringOtherApps])
    }
}

// MARK: - SwiftUI

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel

    private let cell: CGFloat = 128
    private var perRow: Int { max(1, min(model.windows.count, 7)) }

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(cell), spacing: 10), count: perRow)
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(model.windows.enumerated()), id: \.offset) { i, w in
                VStack(spacing: 6) {
                    if let icon = w.icon {
                        Image(nsImage: icon).resizable().frame(width: 56, height: 56)
                    } else {
                        Image(systemName: "macwindow").resizable().frame(width: 48, height: 48)
                    }
                    Text(w.title.isEmpty ? w.appName : w.title)
                        .font(.caption).lineLimit(2).multilineTextAlignment(.center)
                    Text(w.appName).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
                .padding(8)
                .frame(width: cell, height: 124)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(i == model.index ? Color.accentColor.opacity(0.75) : Color.clear))
            }
        }
        .padding(18)
        .background(VisualEffectView())
        .cornerRadius(18)
        .frame(width: CGFloat(perRow) * (cell + 10) + 26)
    }
}

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
