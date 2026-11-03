import Foundation

@MainActor
final class PanelState: ObservableObject {
    enum Route: Equatable {
        case folders
        case folder(Folder.ID)
        case note(folder: Folder.ID, note: Note.ID)
    }

    @Published var route: Route = .folders
    @Published var isPinned = false
    @Published var isShowingSettings = false
    /// Global hotkeys are suspended while recording so the old combination can be captured too.
    @Published var isRecordingShortcut = false
    @Published var failedHotKeyIDs: Set<UInt32> = []

    var requestHide: () -> Void = {}
    var revealDataFile: () -> Void = {}
    var setLaunchAtLogin: (Bool) -> Void = { _ in }

    var currentFolderID: Folder.ID? {
        switch route {
        case .folders: nil
        case .folder(let id): id
        case .note(let id, _): id
        }
    }

    func goBack() {
        if isShowingSettings {
            isShowingSettings = false
            return
        }
        switch route {
        case .note(let folderID, _): route = .folder(folderID)
        case .folder: route = .folders
        case .folders: break
        }
    }
}
