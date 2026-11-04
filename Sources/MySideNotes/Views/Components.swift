import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// `@State` is a macro in recent SDKs whose plugin only ships with full Xcode,
/// so local view state lives in small `ObservableObject`s to keep Command Line Tools builds working.
final class HoverState: ObservableObject {
    @Published var isHovering = false
}

final class ExpandState: ObservableObject {
    @Published var isExpanded = false
}

// MARK: - Glass

struct GlassBackground: NSViewRepresentable {
    var cornerRadius: CGFloat
    var style: GlassStyle = .regular

    // NSGlassEffectView only exists in the macOS 26 SDK (Swift 6.2+); older toolchains build the blur fallback.
    func makeNSView(context: Context) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = style == .clear ? .clear : .regular
            glass.cornerRadius = cornerRadius
            return glass
        }
        #endif
        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.maskImage = Self.roundedMask(radius: cornerRadius)
        return blur
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), let glass = nsView as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
            glass.style = style == .clear ? .clear : .regular
        }
        #endif
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let size = NSSize(width: radius * 2 + 1, height: radius * 2 + 1)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

struct GlassCard: ViewModifier {
    let cornerRadius: CGFloat
    @EnvironmentObject private var settings: AppSettings

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let prefs = settings.prefs
        let tint = prefs.tintHex.flatMap(NSColor.init(hex:)).map(Color.init(nsColor:)) ?? .clear
        return content
            .clipShape(shape)
            .background(shape.fill(tint.opacity(prefs.tintHex == nil ? 0 : prefs.tintOpacity)))
            .background(GlassBackground(cornerRadius: cornerRadius, style: prefs.glassStyle))
            .overlay(shape.strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }

    func reorderable<ID: Hashable>(
        id: ID,
        isEnabled: Bool,
        dragging: Binding<ID?>,
        move: @escaping (ID, ID) -> Void
    ) -> some View {
        modifier(Reorderable(id: id, isEnabled: isEnabled, dragging: dragging, move: move))
    }
}

// MARK: - Drag to reorder

private struct Reorderable<ID: Hashable>: ViewModifier {
    let id: ID
    let isEnabled: Bool
    @Binding var dragging: ID?
    let move: (ID, ID) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onDrag {
                    dragging = id
                    return NSItemProvider(object: "\(id)" as NSString)
                }
                .onDrop(of: [.text], delegate: ReorderDropDelegate(targetID: id, dragging: $dragging, move: move))
        } else {
            content
        }
    }
}

private struct ReorderDropDelegate<ID: Hashable>: DropDelegate {
    let targetID: ID
    @Binding var dragging: ID?
    let move: (ID, ID) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != targetID else { return }
        withAnimation(.snappy(duration: 0.2)) {
            move(dragging, targetID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Header card on top, content card below with a toolbar capsule at its bottom.
struct PanelScaffold<Header: View, Content: View, Toolbar: View>: View {
    private let header: Header
    private let content: Content
    private let toolbar: Toolbar

    init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder toolbar: () -> Toolbar
    ) {
        self.header = header()
        self.content = content()
        self.toolbar = toolbar()
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) { header }
                .padding(.leading, 18)
                .padding(.trailing, 12)
                .frame(height: 62)
                .glassCard(cornerRadius: 26)

            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 8) { toolbar }
                    .padding(6)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.03))
                    )
                    .overlay(
                        Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
                    )
                    .padding(10)
            }
            .glassCard(cornerRadius: 28)
        }
        .padding(10)
    }
}

// MARK: - Buttons

struct CircleIcon: View {
    let systemName: String
    var size: CGFloat = 34
    var isActive = false
    var tint: Color?
    var isHovering = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .regular))
            .foregroundStyle(tint ?? (isActive ? Color.accentColor : Color.primary.opacity(0.7)))
            .frame(width: size, height: size)
            .background(
                Circle().fill(
                    isActive
                        ? Color.accentColor.opacity(0.18)
                        : Color.primary.opacity(isHovering ? 0.10 : 0.03)
                )
            )
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.75))
            .contentShape(Circle())
    }
}

struct CircleButton: View {
    let systemName: String
    var size: CGFloat = 34
    var help = ""
    var isActive = false
    var tint: Color?
    var shortcut: KeyboardShortcut?
    let action: () -> Void

    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            CircleIcon(systemName: systemName, size: size, isActive: isActive, tint: tint, isHovering: hover.isHovering)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut)
        .help(help)
        .onHover { hover.isHovering = $0 }
    }
}

struct CircleMenu<Items: View>: View {
    let systemName: String
    var size: CGFloat = 34
    var help = ""
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu(content: items) {
            CircleIcon(systemName: systemName, size: size)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
    }
}

struct PinButton: View {
    @EnvironmentObject private var state: PanelState

    var body: some View {
        CircleButton(
            systemName: state.isPinned ? "pin.fill" : "pin",
            size: 30,
            help: state.isPinned ? "เลิกค้างแผง" : "ค้างแผงไว้ (ไม่ซ่อนเมื่อคลิกที่อื่น)",
            isActive: state.isPinned
        ) {
            state.isPinned.toggle()
        }
    }
}

struct SettingsButton: View {
    @EnvironmentObject private var state: PanelState

    var body: some View {
        CircleButton(systemName: "gearshape", size: 30, help: "ตั้งค่า") {
            state.isShowingSettings = true
        }
    }
}

struct DeleteBadge: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 17))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
        }
        .buttonStyle(.plain)
        .help("ลบ")
        .transition(.move(edge: .leading).combined(with: .opacity))
    }
}

// MARK: - Rows

struct NoteCard: View {
    let note: Note
    var folder: Folder?
    let onOpen: () -> Void

    @StateObject private var hover = HoverState()
    @StateObject private var expand = ExpandState()

    var body: some View {
        let isExpanded = expand.isExpanded
        let showsToggle = hover.isHovering || isExpanded
        let detail = isExpanded ? note.details : note.preview
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if note.isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                }
                Text(note.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(isExpanded ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                // Kept in the layout while hidden so hovering doesn't shift the title.
                Button {
                    withAnimation(.snappy(duration: 0.2)) { expand.isExpanded.toggle() }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 18, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "ย่อ" : "ขยาย")
                .opacity(showsToggle ? 1 : 0)
                .disabled(!showsToggle)
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 4) {
                if let folder {
                    Image(systemName: "folder")
                        .foregroundStyle(folder.color.color)
                    Text(folder.name)
                    Text("·")
                }
                if let progress = note.checklistProgress {
                    Image(systemName: progress.done == progress.total ? "checkmark.circle.fill" : "checklist")
                        .foregroundStyle(progress.done == progress.total ? Color.green : Color.secondary)
                    Text("\(progress.done)/\(progress.total)")
                    Text("·")
                }
                Text(note.updatedAt.relativeText)
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(hover.isHovering ? 0.08 : 0.045))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hover.isHovering = $0 }
    }
}

/// Shared by the note card context menu and the editor's "…" menu.
struct NoteMenuItems: View {
    let store: NoteStore
    let note: Note
    let folderID: Folder.ID
    var onMove: ((Folder.ID) -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        Button(note.isStarred ? "เลิกติดดาว" : "ติดดาว (แสดงไว้บนสุด)") {
            store.toggleStar(note.id, in: folderID)
        }
        Button("คัดลอกข้อความ") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(note.text, forType: .string)
        }
        let otherFolders = store.folders.filter { $0.id != folderID }
        if !otherFolders.isEmpty {
            Menu("ย้ายไปโฟลเดอร์") {
                ForEach(otherFolders) { folder in
                    Button(folder.name) {
                        onMove?(folder.id)
                        store.moveNote(note.id, from: folderID, to: folder.id)
                    }
                }
            }
        }
        Divider()
        Button("ลบโน้ต", role: .destructive) {
            onDelete?()
            store.deleteNote(note.id, in: folderID)
        }
    }
}

struct EmptyState: View {
    let systemImage: String
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(title)
                .foregroundStyle(.secondary)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

struct HoverHighlight: ViewModifier {
    @StateObject private var hover = HoverState()

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(hover.isHovering ? 0.06 : 0))
            )
            .onHover { hover.isHovering = $0 }
    }
}
