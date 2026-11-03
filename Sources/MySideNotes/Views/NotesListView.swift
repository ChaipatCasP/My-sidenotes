import SwiftUI

final class NotesListViewModel: ObservableObject {
    @Published var isDeleting = false
    @Published var draggingID: Note.ID?
}

struct NotesListView: View {
    let folderID: Folder.ID

    @EnvironmentObject private var store: NoteStore
    @EnvironmentObject private var state: PanelState
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model = NotesListViewModel()

    var body: some View {
        if let folder = store.folder(folderID) {
            let sortMode = settings.prefs.noteSort
            let notes = store.sortedNotes(in: folderID, mode: sortMode)
            PanelScaffold {
                CircleButton(systemName: "chevron.left", help: "กลับ") {
                    state.route = .folders
                }
                .padding(.leading, -6)
                Image(systemName: "folder")
                    .font(.system(size: 16))
                    .foregroundStyle(folder.color.color)
                Text(folder.name)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)
                Spacer()
                CircleButton(systemName: "plus", help: "โน้ตใหม่ (⌘N)", shortcut: KeyboardShortcut("n")) {
                    newNote()
                }
            } content: {
                if notes.isEmpty {
                    EmptyState(systemImage: "note.text", title: "ยังไม่มีโน้ตในโฟลเดอร์นี้", actionTitle: "สร้างโน้ตใหม่") {
                        newNote()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(notes) { note in
                                HStack(spacing: 8) {
                                    if model.isDeleting {
                                        DeleteBadge {
                                            withAnimation(.snappy(duration: 0.2)) {
                                                store.deleteNote(note.id, in: folderID)
                                            }
                                        }
                                    }
                                    NoteCard(note: note) {
                                        guard !model.isDeleting else { return }
                                        state.route = .note(folder: folderID, note: note.id)
                                    }
                                    .contextMenu {
                                        NoteMenuItems(store: store, note: note, folderID: folderID)
                                    }
                                }
                                .reorderable(
                                    id: note.id,
                                    isEnabled: sortMode == .manual && !model.isDeleting,
                                    dragging: $model.draggingID
                                ) { dragged, target in
                                    store.moveNote(dragged, onto: target, in: folderID)
                                }
                            }
                        }
                        .padding(10)
                    }
                }
            } toolbar: {
                CircleButton(
                    systemName: "trash",
                    size: 30,
                    help: model.isDeleting ? "เสร็จสิ้น" : "ลบโน้ต",
                    isActive: model.isDeleting
                ) {
                    withAnimation(.snappy(duration: 0.2)) { model.isDeleting.toggle() }
                }
                PinButton()
                Spacer()
                Text("\(notes.count) โน้ต")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                SettingsButton()
            }
        }
    }

    private func newNote() {
        model.isDeleting = false
        if let noteID = store.addNote(to: folderID) {
            state.route = .note(folder: folderID, note: noteID)
        }
    }
}
