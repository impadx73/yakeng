import Cocoa
import SwiftUI
import Combine

// MARK: - Dữ liệu

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var color = "yellow"
    var x: Double = 200, y: Double = 300, w: Double = 280, h: Double = 220
    var collapsed = false
    var pinned = true           // luôn nổi trên cùng
    var createdAt = Date()

    var frame: NSRect {
        get { NSRect(x: x, y: y, width: w, height: h) }
        set { x = newValue.minX; y = newValue.minY; w = newValue.width; h = newValue.height }
    }
    /// Dòng đầu, dùng làm tiêu đề khi thu gọn
    var title: String {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let t = first.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Ghi chú" : t
    }
}

struct NoteColor: Identifiable {
    let name: String
    let label: String
    let bg: NSColor
    let bar: NSColor
    var id: String { name }
}

enum NoteColors {
    static let all: [NoteColor] = [
        NoteColor(name: "yellow", label: "Vàng",       bg: NSColor(red: 1.00, green: 0.96, blue: 0.62, alpha: 1), bar: NSColor(red: 0.98, green: 0.88, blue: 0.40, alpha: 1)),
        NoteColor(name: "green",  label: "Xanh lá",    bg: NSColor(red: 0.80, green: 0.96, blue: 0.74, alpha: 1), bar: NSColor(red: 0.62, green: 0.88, blue: 0.56, alpha: 1)),
        NoteColor(name: "blue",   label: "Xanh dương", bg: NSColor(red: 0.78, green: 0.90, blue: 1.00, alpha: 1), bar: NSColor(red: 0.58, green: 0.78, blue: 0.98, alpha: 1)),
        NoteColor(name: "pink",   label: "Hồng",       bg: NSColor(red: 1.00, green: 0.84, blue: 0.90, alpha: 1), bar: NSColor(red: 0.97, green: 0.66, blue: 0.80, alpha: 1)),
        NoteColor(name: "purple", label: "Tím",        bg: NSColor(red: 0.90, green: 0.84, blue: 1.00, alpha: 1), bar: NSColor(red: 0.78, green: 0.66, blue: 0.98, alpha: 1)),
        NoteColor(name: "orange", label: "Cam",        bg: NSColor(red: 1.00, green: 0.88, blue: 0.74, alpha: 1), bar: NSColor(red: 0.98, green: 0.72, blue: 0.46, alpha: 1)),
        NoteColor(name: "gray",   label: "Xám",        bg: NSColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1), bar: NSColor(red: 0.78, green: 0.78, blue: 0.78, alpha: 1)),
    ]
    static func bg(_ name: String) -> NSColor { all.first { $0.name == name }?.bg ?? all[0].bg }
    static func bar(_ name: String) -> NSColor { all.first { $0.name == name }?.bar ?? all[0].bar }
}

// MARK: - Quản lý

/// Ghi chú dán kiểu Simple Sticky Notes: cửa sổ nhỏ, luôn nổi trên cùng, thu gọn thành một thanh.
final class NotesManager: ObservableObject {
    @Published var notes: [Note] = []
    @Published var allHidden = false

    private var windows: [UUID: NoteWindow] = [:]
    private var saveWork: DispatchWorkItem?
    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Yakeng", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notes.json")
    }()

    static let barHeight: CGFloat = 30

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([Note].self, from: data) {
            notes = list
        }
    }

    /// Mở lại mọi ghi chú đã lưu (gọi khi app khởi động).
    func restore() {
        for n in notes { show(n) }
    }

    func createNote() {
        let cfg = Settings.shared.data
        var n = Note()
        n.pinned = cfg.notesDefaultPinned
        n.color = cfg.notesDefaultColor
        // Đặt chồng lệch so với ghi chú gần nhất, trong màn hình chính
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            let last = notes.last.map { $0.frame }
            var origin = last.map { NSPoint(x: $0.minX + 28, y: $0.maxY - 28 - n.h) }
                ?? NSPoint(x: v.midX - n.w / 2, y: v.midY - n.h / 2)
            if origin.x + n.w > v.maxX || origin.y < v.minY { origin = NSPoint(x: v.minX + 40, y: v.maxY - 40 - n.h) }
            n.x = origin.x; n.y = origin.y
        }
        notes.append(n)
        allHidden = false
        show(n, focus: true)
        save()
    }

    func toggleAll() {
        allHidden.toggle()
        for (_, w) in windows { if allHidden { w.orderOut(nil) } else { w.orderFront(nil) } }
    }

    func showAll() {
        allHidden = false
        for n in notes { show(n) }
    }

    func delete(_ id: UUID) {
        windows[id]?.orderOut(nil)
        windows[id] = nil
        notes.removeAll { $0.id == id }
        save()
    }

    func update(_ id: UUID, _ change: (inout Note) -> Void) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        change(&notes[i])
        windows[id]?.apply(notes[i])
        save()
    }

    func binding(for id: UUID) -> Binding<Note> {
        Binding(
            get: { self.notes.first { $0.id == id } ?? Note() },
            set: { new in self.update(id) { $0 = new } }
        )
    }

    private func show(_ n: Note, focus: Bool = false) {
        let w: NoteWindow
        if let existing = windows[n.id] {
            w = existing
        } else {
            w = NoteWindow(note: n, manager: self)
            windows[n.id] = w
        }
        w.apply(n)
        if !allHidden {
            if focus { w.makeKeyAndOrderFront(nil) } else { w.orderFront(nil) }
        }
    }

    /// Cửa sổ bị kéo/đổi cỡ
    func windowFrameChanged(_ id: UUID, _ frame: NSRect) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        if notes[i].collapsed {
            notes[i].x = frame.minX
            notes[i].y = frame.maxY - notes[i].h        // giữ cạnh trên
            notes[i].w = frame.width
        } else {
            notes[i].frame = frame
        }
        save()
    }

    func save() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, let data = try? JSONEncoder().encode(self.notes) else { return }
            try? data.write(to: self.fileURL, options: .atomic)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}

// MARK: - Cửa sổ

final class NoteWindow: NSPanel, NSWindowDelegate {
    let noteID: UUID
    private weak var manager: NotesManager?
    private var applying = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(note: Note, manager: NotesManager) {
        self.noteID = note.id
        self.manager = manager
        super.init(contentRect: note.frame,
                   styleMask: [.borderless, .resizable, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.managed, .fullScreenAuxiliary]
        minSize = NSSize(width: 160, height: NotesManager.barHeight)
        delegate = self
        contentView = NSHostingView(rootView: NoteView(manager: manager, noteID: note.id))
    }

    /// Đồng bộ cửa sổ với dữ liệu (màu, nổi, thu gọn, kích thước)
    func apply(_ n: Note) {
        applying = true
        defer { applying = false }
        level = n.pinned ? .floating : .normal
        let target = n.collapsed
            ? NSRect(x: n.x, y: n.y + n.h - NotesManager.barHeight, width: n.w, height: NotesManager.barHeight)
            : n.frame
        if frame != target { setFrame(target, display: true, animate: false) }
        styleMask = n.collapsed ? [.borderless, .nonactivatingPanel] : [.borderless, .resizable, .nonactivatingPanel]
    }

    func windowDidMove(_ notification: Notification) {
        guard !applying else { return }
        manager?.windowFrameChanged(noteID, frame)
    }
    func windowDidResize(_ notification: Notification) {
        guard !applying else { return }
        manager?.windowFrameChanged(noteID, frame)
    }
}

// MARK: - Giao diện

struct NoteView: View {
    @ObservedObject var manager: NotesManager
    let noteID: UUID

    private var note: Note { manager.notes.first { $0.id == noteID } ?? Note() }

    var body: some View {
        let n = note
        VStack(spacing: 0) {
            // Thanh tiêu đề: kéo để di chuyển, nút chức năng
            HStack(spacing: 6) {
                Menu {
                    ForEach(NoteColors.all) { c in
                        Button(c.label) { manager.update(noteID) { $0.color = c.name } }
                    }
                } label: {
                    Circle().fill(Color(nsColor: NoteColors.bar(n.color)).opacity(0.001))
                        .overlay(Image(systemName: "paintpalette").font(.system(size: 11)))
                        .frame(width: 18, height: 18)
                }
                .menuStyle(.borderlessButton).frame(width: 22)
                .help("Đổi màu")

                if n.collapsed {
                    Text(n.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        .foregroundColor(.black.opacity(0.75))
                }
                Spacer(minLength: 0)

                Button(action: { manager.createNote() }) { Image(systemName: "plus") }
                    .help("Ghi chú mới")
                Button(action: { manager.update(noteID) { $0.pinned.toggle() } }) {
                    Image(systemName: n.pinned ? "pin.fill" : "pin")
                }
                .help(n.pinned ? "Đang luôn nổi trên cùng" : "Luôn nổi trên cùng")
                Button(action: { manager.update(noteID) { $0.collapsed.toggle() } }) {
                    Image(systemName: n.collapsed ? "chevron.down" : "chevron.up")
                }
                .help(n.collapsed ? "Mở rộng" : "Thu gọn thành thanh")
                Button(action: { confirmDelete() }) { Image(systemName: "xmark") }
                    .help("Xoá ghi chú")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.black.opacity(0.6))
            .padding(.horizontal, 8)
            .frame(height: NotesManager.barHeight)
            .background(Color(nsColor: NoteColors.bar(n.color)))

            if !n.collapsed {
                NoteTextView(text: manager.binding(for: noteID).text,
                             background: NoteColors.bg(n.color))
            }
        }
        .background(Color(nsColor: NoteColors.bg(n.color)))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.12), lineWidth: 1))
    }

    private func confirmDelete() {
        let n = note
        if n.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            manager.delete(noteID); return
        }
        let alert = NSAlert()
        alert.messageText = "Xoá ghi chú này?"
        alert.informativeText = String(n.text.prefix(120))
        alert.addButton(withTitle: "Xoá")
        alert.addButton(withTitle: "Huỷ")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn { manager.delete(noteID) }
    }
}

/// NSTextView trong suốt (TextEditor của SwiftUI không đổi được nền trên macOS 12)
struct NoteTextView: NSViewRepresentable {
    @Binding var text: String
    var background: NSColor

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let tv = NSTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.font = NSFont.systemFont(ofSize: 14)
        tv.textColor = NSColor.black.withAlphaComponent(0.85)
        tv.drawsBackground = false
        tv.insertionPointColor = .black
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.allowsUndo = true
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.string = text
        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView
        init(_ p: NoteTextView) { parent = p }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
