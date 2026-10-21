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
    var thumbnail: NSImage?
}

final class SwitcherModel: ObservableObject {
    @Published var windows: [WinInfo] = []
    @Published var index = 0
    @Published var detached = false        // đã thả ⌥, bảng vẫn mở
    var onSelect: ((Int) -> Void)?
    var onHover: ((Int) -> Void)?
}

/// Bảng chuyển cửa sổ kiểu Windows: giữ ⌥, bấm ⇥ để duyệt, thả ⌥ để chọn.
/// Có thể dùng chuột (di để chọn, bấm để chuyển), ←/→, Enter, Esc.
final class WindowSwitcher {
    private var panel: NSPanel?
    private let model = SwitcherModel()

    /// Danh sách cửa sổ theo thứ tự dùng gần nhất (MRU), giống AltTab của lwouis:
    /// macOS không cập nhật z-order kịp khi chuyển cửa sổ trong cùng một app, nên tự theo dõi.
    private var mru: [CGWindowID] = []
    private var mruTimer: Timer?

    init() {
        model.onSelect = { [weak self] i in
            guard let self = self else { return }
            self.model.index = i
            self.commit()
        }
        model.onHover = { [weak self] i in self?.model.index = i }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.noteFocusedWindow(after: 0.15)
        }
        mruTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.noteFocusedWindow(after: 0)
        }
    }

    private let axQueue = DispatchQueue(label: "yakeng.mru-ax", qos: .utility)

    /// Ghi nhận cửa sổ đang có focus của app phía trước vào đầu danh sách MRU.
    /// Truy vấn Accessibility chạy ở luồng nền (app khác có thể trả lời chậm), kết quả đưa về luồng chính.
    func noteFocusedWindow(after delay: TimeInterval) {
        axQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.isVisible,
                  let app = NSWorkspace.shared.frontmostApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.3)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success,
                  let win = value else { return }
            let ax = win as! AXUIElement
            var wid: CGWindowID = 0
            guard _AXUIElementGetWindow(ax, &wid) == .success, wid != 0 else { return }
            DispatchQueue.main.async { self.touch(wid) }
        }
    }

    private func touch(_ id: CGWindowID) {
        if mru.first == id { return }
        mru.removeAll { $0 == id }
        mru.insert(id, at: 0)
        if mru.count > 200 { mru.removeLast() }
    }

    var isVisible: Bool { panel != nil }

    func step(backward: Bool) {
        if panel == nil {
            noteFocusedWindow(after: 0)
            // Hiện bảng ngay với icon; ảnh thu nhỏ chụp ở luồng nền rồi điền vào sau
            var list = WindowSwitcher.fetchWindows(thumbnails: false)
            // Sắp theo MRU; cửa sổ chưa từng thấy giữ nguyên z-order phía sau
            let rank = Dictionary(uniqueKeysWithValues: mru.enumerated().map { ($1, $0) })
            list = list.enumerated().sorted { a, b in
                let ra = rank[a.element.id] ?? (mru.count + a.offset)
                let rb = rank[b.element.id] ?? (mru.count + b.offset)
                return ra < rb
            }.map { $0.element }
            model.windows = list
            guard !model.windows.isEmpty else { return }
            model.detached = false
            model.index = model.windows.count > 1 ? (backward ? model.windows.count - 1 : 1) : 0
            show()
            if Settings.shared.data.altTabThumbnails { loadThumbnails(for: list.map { $0.id }) }
        } else {
            let n = model.windows.count
            guard n > 0 else { return }
            model.index = (model.index + (backward ? -1 : 1) + n) % n
        }
    }

    private let thumbQueue = DispatchQueue(label: "yakeng.thumbnails", qos: .userInitiated)
    private var thumbGeneration = 0

    private func loadThumbnails(for ids: [CGWindowID]) {
        thumbGeneration += 1
        let gen = thumbGeneration
        thumbQueue.async { [weak self] in
            for id in ids {
                guard let self = self, self.thumbGeneration == gen else { return }
                guard let img = WindowSwitcher.snapshot(of: id) else { continue }
                DispatchQueue.main.async {
                    guard self.thumbGeneration == gen, let i = self.model.windows.firstIndex(where: { $0.id == id }) else { return }
                    self.model.windows[i].thumbnail = img
                }
            }
        }
    }

    /// Thả phím bổ trợ ở chế độ "giữ bảng": không chuyển ngay, chờ chuột/Enter.
    func detach() { model.detached = true }

    func commit() {
        guard panel != nil, model.index < model.windows.count else { cancel(); return }
        let w = model.windows[model.index]
        hide()
        touch(w.id)
        WindowSwitcher.activate(w)
        noteFocusedWindow(after: 0.3)
    }

    func cancel() { hide() }

    // MARK: - Giao diện

    private func show() {
        let host = ClickableHostingView(rootView: SwitcherView(model: model))
        let size = host.fittingSize
        let p = SwitcherPanel(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        p.acceptsMouseMovedEvents = true
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isReleasedWhenClosed = false
        p.contentView = host
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.midY - size.height / 2))
        }
        p.makeKeyAndOrderFront(nil)
        p.orderFrontRegardless()
        panel = p
    }

    /// Gọi khi bảng đóng (chuyển/huỷ) để EventTap bỏ cờ switcherActive.
    var onHide: (() -> Void)?

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
        onHide?()
    }

    // MARK: - Danh sách cửa sổ

    static func fetchWindows(thumbnails: Bool) -> [WinInfo] {
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
            var info = WinInfo(id: num, pid: pid, title: title, appName: app?.localizedName ?? owner, icon: iconCache[pid] ?? nil, thumbnail: nil)
            if thumbnails { info.thumbnail = snapshot(of: num) }
            result.append(info)
            if result.count >= 24 { break }
        }
        return result
    }

    /// Ảnh thu nhỏ của một cửa sổ (cần quyền Ghi màn hình; nếu chưa có thì trả về nil).
    /// `CGWindowListCreateImage` bị SDK mới đánh dấu không dùng được khi biên dịch,
    /// nhưng vẫn tồn tại lúc chạy – gọi qua dlsym.
    private typealias CreateImageFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    private static let createImage: CreateImageFn? = {
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(sym, to: CreateImageFn.self)
    }()

    static func snapshot(of id: CGWindowID) -> NSImage? {
        guard let fn = createImage else { return nil }
        let optIncludingWindow: UInt32 = 1 << 3            // kCGWindowListOptionIncludingWindow
        let imgOpts: UInt32 = (1 << 0) | (1 << 4)          // boundsIgnoreFraming | nominalResolution
        guard let cg = fn(.null, optIncludingWindow, id, imgOpts)?.takeRetainedValue(),
              cg.width > 1, cg.height > 1 else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
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
            AXUIElementSetAttributeValue(ax, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        NSRunningApplication(processIdentifier: w.pid)?.activate(options: [.activateIgnoringOtherApps])
    }
}

/// Panel không kích hoạt app nhưng vẫn nhận được chuột/bàn phím.
final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// NSHostingView nhận click ngay cả khi cửa sổ không phải key window.
final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - SwiftUI

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel

    private let cellW: CGFloat = 208
    private let cellH: CGFloat = 176
    private var perRow: Int { max(1, min(model.windows.count, 5)) }

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(cellW), spacing: 10), count: perRow)
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(model.windows.enumerated()), id: \.offset) { pair in
                    let i = pair.offset
                    let w = pair.element
                    SwitcherTile(window: w, selected: i == model.index, width: cellW, height: cellH)
                        .onHover { if $0 { model.onHover?(i) } }
                        .onTapGesture { model.onSelect?(i) }
                }
            }
            Text(model.detached
                 ? "Bấm chuột hoặc Enter để chuyển · Esc để đóng"
                 : "Giữ ⌥ và bấm ⇥ / ←→ để chọn · thả ⌥ hoặc bấm chuột để chuyển")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(16)
        .background(VisualEffectView())
        .cornerRadius(18)
        .frame(width: CGFloat(perRow) * (cellW + 10) + 22)
    }
}

struct SwitcherTile: View {
    let window: WinInfo
    let selected: Bool
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                if let thumb = window.thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: width - 16, height: height - 56)
                        .cornerRadius(6)
                } else if let icon = window.icon {
                    Image(nsImage: icon).resizable()
                        .frame(width: 72, height: 72)
                        .frame(width: width - 16, height: height - 56)
                } else {
                    Image(systemName: "macwindow").resizable().frame(width: 48, height: 48)
                        .frame(width: width - 16, height: height - 56)
                }
                if window.thumbnail != nil, let icon = window.icon {
                    Image(nsImage: icon).resizable().frame(width: 28, height: 28).offset(x: 2, y: 4)
                }
            }
            Text(window.title.isEmpty ? window.appName : window.title)
                .font(.caption).lineLimit(1)
            Text(window.appName).font(.caption2).foregroundColor(.secondary).lineLimit(1)
        }
        .padding(8)
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(selected ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.06)))
        .contentShape(Rectangle())
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
