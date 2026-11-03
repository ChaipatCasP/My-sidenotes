import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: NoteStore
    @EnvironmentObject private var state: PanelState

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if state.isShowingSettings {
            SettingsView()
        } else {
            routeContent
        }
    }

    @ViewBuilder
    private var routeContent: some View {
        switch state.route {
        case .folders:
            FoldersView()
        case .folder(let folderID):
            if store.folder(folderID) != nil {
                NotesListView(folderID: folderID)
            } else {
                FoldersView()
            }
        case .note(let folderID, let noteID):
            if store.note(noteID, in: folderID) != nil {
                NoteEditorView(folderID: folderID, noteID: noteID)
                    .id(noteID)
            } else if store.folder(folderID) != nil {
                NotesListView(folderID: folderID)
            } else {
                FoldersView()
            }
        }
    }
}
