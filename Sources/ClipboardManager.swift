import Cocoa
import SwiftUI

struct ClipItem: Identifiable {
    let id = UUID()
    let date: Date
    let text: String?
    let image: NSImage?

    var isImage: Bool { image != nil }
    var preview: String {
        if let t = text { return t.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let img = image { return "Ảnh \(Int(img.size.width))×\(Int(img.size.height))" }
        return ""
    }
}

/// Theo dõi clipboard, lưu lịch sử, hiển thị bảng chọn (⇧⌘S).
final class ClipboardManager: ObservableObject {
    @Published var items: [ClipItem] = []

    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var panel: NSPanel?
    private var previousApp: NSRunningApplication?
    private let storeKey = "yakeng.clipboard.texts"

    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: storeKey) {
            items = saved.map { ClipItem(date: Date(), text: $0, image: nil) }
        }
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount

        if let img = NSImage(pasteboard: pb) {
            add(ClipItem(date: Date(), text: nil, image: img))
        } else if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.removeAll { $0.text == s }
            add(ClipItem(date: Date(), text: s, image: nil))
        }
    }

    private func add(_ item: ClipItem) {
        items.insert(item, at: 0)
        let max = Settings.shared.data.clipboardMaxItems
        if items.count > max { items = Array(items.prefix(max)) }
        persist()
    }

    private func persist() {
        let texts = items.compactMap { $0.text }
        UserDefaults.standard.set(Array(texts.prefix(100)), forKey: storeKey)
    }

    func clear() {
        items = []
        persist()
    }

    func remove(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    // MARK: - Bảng chọn

    func togglePanel() {
        if panel != nil { hidePanel() } else { showPanel() }
    }

    func showPanel() {
        previousApp = NSWorkspace.shared.frontmostApplication
        let host = NSHostingView(rootView: ClipboardView(manager: self))
        let p = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
                             styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
                             backing: .buffered, defer: false)
        p.title = "Yakeng – Lịch sử clipboard"
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.contentView = host
        p.center()
        p.delegate = panelDelegate
        panelDelegate.onClose = { [weak self] in self?.panel = nil }
        panel = p
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hidePanel() {
        panel?.orderOut(nil)
        panel = nil
    }

    private let panelDelegate = PanelDelegate()

    func select(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let t = item.text { pb.setString(t, forType: .string) }
        else if let img = item.image { pb.writeObjects([img]) }
        lastChange = pb.changeCount
        // Đưa mục lên đầu
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        persist()

        hidePanel()
        let paste = Settings.shared.data.clipboardPasteOnSelect
        if let app = previousApp {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        if paste {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                EventTap.sendKey(9, flags: .maskCommand)   // ⌘V
            }
        }
    }

    /// Chụp một vùng màn hình vào clipboard (giống Win+Shift+S).
    func captureScreen() {
        hidePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let p = Process()
            p.launchPath = "/usr/sbin/screencapture"
            p.arguments = ["-i", "-c"]
            p.terminationHandler = { _ in
                DispatchQueue.main.async { self.poll() }
            }
            try? p.run()
        }
    }
}

final class PanelDelegate: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onClose?() }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
}

// MARK: - SwiftUI

struct ClipboardView: View {
    @ObservedObject var manager: ClipboardManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { manager.captureScreen() }) {
                    Label("Chụp màn hình", systemImage: "camera.viewfinder")
                }
                Spacer()
                Text("\(manager.items.count) mục").foregroundColor(.secondary).font(.caption)
                Button("Xoá tất cả") { manager.clear() }.disabled(manager.items.isEmpty)
            }
            .padding(10)
            Divider()
            if manager.items.isEmpty {
                Spacer()
                Text("Chưa có gì trong lịch sử.\nSao chép (⌘C / Ctrl+C) hoặc chụp màn hình để bắt đầu.")
                    .multilineTextAlignment(.center).foregroundColor(.secondary).padding()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(manager.items) { item in
                            ClipRow(item: item)
                                .contentShape(Rectangle())
                                .onTapGesture { manager.select(item) }
                                .contextMenu {
                                    Button("Dán") { manager.select(item) }
                                    Button("Xoá") { manager.remove(item) }
                                }
                        }
                    }
                    .padding(6)
                }
            }
            Divider()
            Text("Bấm vào một mục để dán. Esc để đóng.")
                .font(.caption).foregroundColor(.secondary).padding(6)
        }
        .frame(minWidth: 360, minHeight: 300)
    }
}

final class HoverState: ObservableObject {
    @Published var on = false
}

struct ClipRow: View {
    let item: ClipItem
    @ObservedObject private var hover = HoverState()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let img = item.image {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 120, maxHeight: 80)
                    .cornerRadius(4)
            } else {
                Image(systemName: "doc.text").foregroundColor(.secondary).frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.preview).lineLimit(3).font(.body)
                Text(item.date, style: .time).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(hover.on ? Color.accentColor.opacity(0.18) : Color.clear))
        .onHover { hover.on = $0 }
    }
}
