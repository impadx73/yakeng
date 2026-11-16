import Cocoa
import SwiftUI
import Combine

// MARK: - Dữ liệu

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""               // tiêu đề người dùng đặt
    var text = ""
    var color = "yellow"
    var x: Double = 200, y: Double = 300, w: Double = 280, h: Double = 220
    var collapsed = false
    var pinned = true           // luôn nổi trên cùng
    var createdAt = Date()

    init() {}

    /// Đọc khoan dung: ghi chú lưu từ bản cũ (chưa có "name") vẫn mở được
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "yellow"
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 200
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 300
        w = try c.decodeIfPresent(Double.self, forKey: .w) ?? 280
        h = try c.decodeIfPresent(Double.self, forKey: .h) ?? 220
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? true
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    var frame: NSRect {
        get { NSRect(x: x, y: y, width: w, height: h) }
        set { x = newValue.minX; y = newValue.minY; w = newValue.width; h = newValue.height }
    }
    /// Dòng đầu của nội dung
    var firstLine: String {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return first.trimmingCharacters(in: .whitespaces)
    }
    /// Tiêu đề hiển thị: tên đã đặt, nếu chưa có thì dòng đầu
    var title: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { return n }
        return firstLine.isEmpty ? "Ghi chú" : firstLine
    }
}

extension Notification.Name {
    static let yakengEditNoteTitle = Notification.Name("yakeng.editNoteTitle")
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

    /// Yakeng là app thanh menu (không có menu Sửa) và ghi chú là panel không kích hoạt app,
    /// nên ⌘V/⌘C/⌘X/⌘A/⌘Z phải tự chuyển cho ô đang gõ (nội dung hoặc tiêu đề).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.type == .keyDown, flags.contains(.command),
              !flags.contains(.control), !flags.contains(.option),
              let responder = firstResponder else {
            return super.performKeyEquivalent(with: event)
        }
        let shift = flags.contains(.shift)
        var action: Selector?
        switch event.keyCode {
        case 9:  action = shift ? #selector(NSTextView.pasteAsPlainText(_:)) : #selector(NSText.paste(_:))   // V
        case 8:  action = #selector(NSText.copy(_:))        // C
        case 7:  action = #selector(NSText.cut(_:))         // X
        case 0:  action = #selector(NSText.selectAll(_:))   // A
        case 6:                                             // Z / ⇧Z
            if let um = responder.undoManager {
                if shift { if um.canRedo { um.redo() } } else if um.canUndo { um.undo() }
                return true
            }
        default: break
        }
        if let a = action, responder.tryToPerform(a, with: self) { return true }
        return super.performKeyEquivalent(with: event)
    }

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
            // Thanh tiêu đề: kéo để di chuyển, nhấp đúp tiêu đề để đổi tên, nút chức năng
            HStack(spacing: 6) {
                Menu {
                    Button("Đặt tiêu đề…") {
                        NotificationCenter.default.post(name: .yakengEditNoteTitle, object: noteID)
                    }
                    Divider()
                    ForEach(NoteColors.all) { c in
                        Button(c.label) { manager.update(noteID) { $0.color = c.name } }
                    }
                } label: {
                    Circle().fill(Color(nsColor: NoteColors.bar(n.color)).opacity(0.001))
                        .overlay(Image(systemName: "paintpalette").font(.system(size: 11)))
                        .frame(width: 18, height: 18)
                }
                .menuStyle(.borderlessButton).frame(width: 22)
                .help("Đổi màu, đặt tiêu đề")

                NoteTitleField(noteID: noteID,
                               title: n.name,
                               placeholder: n.firstLine.isEmpty ? "Ghi chú" : n.firstLine,
                               onCommit: { newName in
                                   manager.update(noteID) { $0.name = newName.trimmingCharacters(in: .whitespaces) }
                               },
                               onDoubleClick: { manager.update(noteID) { $0.collapsed.toggle() } })
                    .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18)

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
            // vùng trống của thanh: kéo để di chuyển, nhấp đúp để thu gọn/mở rộng
            .background(WindowDragArea(onDoubleClick: { manager.update(noteID) { $0.collapsed.toggle() } }))
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

// MARK: - Kéo cửa sổ & tiêu đề

/// NSHostingView không cho kéo cửa sổ theo nền, nên thanh trên dùng NSView riêng gọi performDrag.
struct WindowDragArea: NSViewRepresentable {
    var onDoubleClick: () -> Void
    func makeNSView(context: Context) -> DragHandleView { DragHandleView() }
    func updateNSView(_ v: DragHandleView, context: Context) { v.onDoubleClick = onDoubleClick }
}

final class DragHandleView: NSView {
    var onDoubleClick: (() -> Void)?
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?(); return }
        window?.performDrag(with: event)
    }
}

/// Ô tiêu đề trên thanh ghi chú: kéo = di chuyển, nhấp đúp = thu gọn/mở rộng.
/// Đổi tên qua menu bảng màu "Đặt tiêu đề…": Enter/nhấp ra ngoài = lưu, Esc = huỷ.
struct NoteTitleField: NSViewRepresentable {
    let noteID: UUID
    var title: String
    var placeholder: String
    var onCommit: (String) -> Void
    var onDoubleClick: () -> Void

    func makeNSView(context: Context) -> NoteTitleNSField {
        let f = NoteTitleNSField(noteID: noteID)
        f.stringValue = title
        return f
    }

    func updateNSView(_ f: NoteTitleNSField, context: Context) {
        f.onCommit = onCommit
        f.onDoubleClick = onDoubleClick
        if f.currentEditor() == nil, f.stringValue != title { f.stringValue = title }
        if f.placeholderString != placeholder {
            f.placeholderString = placeholder
            f.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
                .foregroundColor: NSColor.black.withAlphaComponent(0.45),
                .font: NoteTitleNSField.titleFont,
            ])
        }
    }
}

final class NoteTitleNSField: NSTextField, NSTextFieldDelegate {
    static let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    let noteID: UUID
    var onCommit: ((String) -> Void)?
    var onDoubleClick: (() -> Void)?
    private var original = ""
    private var cancelled = false
    private var observer: NSObjectProtocol?

    init(noteID: UUID) {
        self.noteID = noteID
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        font = NoteTitleNSField.titleFont
        textColor = NSColor.black.withAlphaComponent(0.8)
        lineBreakMode = .byTruncatingTail
        cell?.usesSingleLineMode = true
        cell?.wraps = false
        cell?.isScrollable = true
        delegate = self
        toolTip = "Kéo để di chuyển · nhấp đúp để thu gọn/mở rộng"
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        observer = NotificationCenter.default.addObserver(forName: .yakengEditNoteTitle, object: nil, queue: .main) { [weak self] n in
            guard let self = self, (n.object as? UUID) == self.noteID else { return }
            self.beginEditing()
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } }

    override var mouseDownCanMoveWindow: Bool { currentEditor() == nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if currentEditor() != nil { super.mouseDown(with: event); return }
        if event.clickCount == 2 { onDoubleClick?(); return }
        window?.performDrag(with: event)
    }

    func beginEditing() {
        guard currentEditor() == nil, let w = window else { return }
        original = stringValue
        cancelled = false
        isEditable = true
        isSelectable = true
        w.makeKeyAndOrderFront(nil)
        if w.makeFirstResponder(self) { currentEditor()?.selectAll(nil) }
    }

    // Esc huỷ, Enter lưu
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            cancelled = true
            stringValue = original
            window?.makeFirstResponder(nil)
            return true
        }
        if sel == #selector(NSResponder.insertNewline(_:)) {
            window?.makeFirstResponder(nil)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        isEditable = false
        isSelectable = false
        if !cancelled { onCommit?(stringValue) }
        cancelled = false
    }
}
