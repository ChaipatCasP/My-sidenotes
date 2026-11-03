import SwiftUI

struct NoteEditorView: View {
    let folderID: Folder.ID
    let noteID: Note.ID

    @EnvironmentObject private var store: NoteStore
    @EnvironmentObject private var state: PanelState
    @StateObject private var editor = EditorController()

    private var text: Binding<String> {
        Binding(
            get: { store.note(noteID, in: folderID)?.text ?? "" },
            set: { store.setText($0, for: noteID, in: folderID) }
        )
    }

    var body: some View {
        if let folder = store.folder(folderID), let note = store.note(noteID, in: folderID) {
            PanelScaffold {
                CircleButton(systemName: "chevron.left", help: "กลับ (Esc)") {
                    state.route = .folder(folderID)
                }
                .padding(.leading, -6)
                Image(systemName: "folder")
                    .font(.system(size: 16))
                    .foregroundStyle(folder.color.color)
                Text(folder.name)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)
                Spacer()
                CircleButton(
                    systemName: note.isStarred ? "star.fill" : "star",
                    help: note.isStarred ? "เลิกติดดาว" : "ติดดาว",
                    tint: note.isStarred ? .yellow : nil
                ) {
                    store.toggleStar(noteID, in: folderID)
                }
                CircleMenu(systemName: "ellipsis", help: "ตัวเลือกโน้ต") {
                    NoteMenuItems(
                        store: store,
                        note: note,
                        folderID: folderID,
                        onMove: { target in state.route = .note(folder: target, note: noteID) },
                        onDelete: { state.route = .folder(folderID) }
                    )
                }
            } content: {
                NoteTextEditor(text: text, controller: editor)
            } toolbar: {
                CircleButton(systemName: "trash", size: 30, help: "ลบโน้ตนี้") {
                    state.route = .folder(folderID)
                    store.deleteNote(noteID, in: folderID)
                }
                PinButton()
                CircleButton(
                    systemName: "checklist",
                    size: 30,
                    help: "สลับเป็น checklist (⇧⌘L)",
                    shortcut: KeyboardShortcut("l", modifiers: [.command, .shift])
                ) {
                    editor.toggleChecklist()
                }
                Spacer()
                VStack(spacing: 1) {
                    Text("\(note.text.count) ตัวอักษร")
                    Text("แก้ไข \(note.updatedAt.relativeText)")
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                Spacer()
                SettingsButton()
            }
            .onDisappear {
                store.deleteNoteIfBlank(noteID, in: folderID)
            }
        }
    }
}
