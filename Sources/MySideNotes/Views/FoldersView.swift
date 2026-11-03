import SwiftUI

final class FoldersViewModel: ObservableObject {
    @Published var query = ""
    @Published var isSearching = false
    @Published var isDeleting = false
    @Published var renamingID: Folder.ID?
    @Published var draftName = ""
    @Published var pendingDelete: Folder?
    @Published var draggingID: Folder.ID?
}

struct FoldersView: View {
    @EnvironmentObject private var store: NoteStore
    @EnvironmentObject private var state: PanelState

    @StateObject private var model = FoldersViewModel()
    @FocusState private var renameFocused: Bool
    @FocusState private var searchFocused: Bool

    private var hasQuery: Bool {
        !model.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        PanelScaffold {
            if model.isSearching {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("ค้นหาโน้ต", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($searchFocused)
                CircleButton(systemName: "xmark", help: "ปิดการค้นหา") {
                    closeSearch()
                }
            } else {
                Text("SideNotes")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                CircleButton(systemName: "magnifyingglass", help: "ค้นหา") {
                    openSearch()
                }
                CircleButton(systemName: "plus", help: "เพิ่มโฟลเดอร์") {
                    addFolder()
                }
            }
        } content: {
            ScrollView {
                LazyVStack(spacing: hasQuery ? 8 : 2) {
                    if hasQuery {
                        searchResults
                    } else if store.folders.isEmpty {
                        EmptyState(systemImage: "folder", title: "ยังไม่มีโฟลเดอร์", actionTitle: "สร้างโฟลเดอร์") {
                            addFolder()
                        }
                    } else {
                        ForEach(store.folders) { folder in
                            folderRow(folder)
                        }
                    }
                }
                .padding(10)
            }
        } toolbar: {
            CircleButton(
                systemName: "trash",
                size: 30,
                help: model.isDeleting ? "เสร็จสิ้น" : "ลบโฟลเดอร์",
                isActive: model.isDeleting
            ) {
                withAnimation(.snappy(duration: 0.2)) { model.isDeleting.toggle() }
            }
            PinButton()
            Spacer()
            SettingsButton()
        }
        .alert(
            "ลบโฟลเดอร์ “\(model.pendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { model.pendingDelete != nil }, set: { if !$0 { model.pendingDelete = nil } }),
            presenting: model.pendingDelete
        ) { folder in
            Button("ลบ", role: .destructive) { store.deleteFolder(folder.id) }
            Button("ยกเลิก", role: .cancel) {}
        } message: { folder in
            Text("โน้ต \(folder.notes.count) รายการในโฟลเดอร์นี้จะถูกลบไปด้วย")
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let results = store.search(model.query)
        if results.isEmpty {
            EmptyState(systemImage: "magnifyingglass", title: "ไม่พบโน้ตที่ตรงกัน")
        } else {
            ForEach(results) { result in
                NoteCard(note: result.note, folder: result.folder) {
                    state.route = .note(folder: result.folder.id, note: result.note.id)
                }
            }
        }
    }

    private func folderRow(_ folder: Folder) -> some View {
        HStack(spacing: 12) {
            if model.isDeleting {
                DeleteBadge { requestDelete(folder) }
            }
            Image(systemName: "folder")
                .font(.system(size: 17))
                .foregroundStyle(folder.color.color)
            if model.renamingID == folder.id {
                TextField("ชื่อโฟลเดอร์", text: $model.draftName)
                    .textFieldStyle(.plain)
                    .focused($renameFocused)
                    .onSubmit(commitRename)
            } else {
                Text(folder.name)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(folder.notes.count)")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 15))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .modifier(HoverHighlight())
        .contentShape(Rectangle())
        .onTapGesture {
            guard model.renamingID != folder.id, !model.isDeleting else { return }
            state.route = .folder(folder.id)
        }
        .reorderable(
            id: folder.id,
            isEnabled: !model.isDeleting && model.renamingID == nil,
            dragging: $model.draggingID
        ) { dragged, target in
            store.moveFolder(dragged, onto: target)
        }
        .contextMenu {
            Button("เปลี่ยนชื่อ") { startRename(folder) }
            Menu("สี") {
                ForEach(FolderColor.allCases) { color in
                    Button {
                        store.setColor(color, for: folder.id)
                    } label: {
                        if color == folder.color {
                            Label(color.displayName, systemImage: "checkmark")
                        } else {
                            Text(color.displayName)
                        }
                    }
                }
            }
            Divider()
            Button("ลบโฟลเดอร์", role: .destructive) { requestDelete(folder) }
        }
        .onChange(of: renameFocused) { _, focused in
            if !focused, model.renamingID == folder.id {
                commitRename()
            }
        }
    }

    private func openSearch() {
        model.isSearching = true
        DispatchQueue.main.async { searchFocused = true }
    }

    private func closeSearch() {
        model.query = ""
        model.isSearching = false
    }

    private func requestDelete(_ folder: Folder) {
        if folder.notes.isEmpty {
            withAnimation(.snappy(duration: 0.2)) { store.deleteFolder(folder.id) }
        } else {
            model.pendingDelete = folder
        }
    }

    private func addFolder() {
        closeSearch()
        model.isDeleting = false
        let id = store.addFolder(named: "โฟลเดอร์ใหม่")
        if let folder = store.folder(id) {
            startRename(folder)
        }
    }

    private func startRename(_ folder: Folder) {
        model.renamingID = folder.id
        model.draftName = folder.name
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commitRename() {
        guard let id = model.renamingID else { return }
        store.renameFolder(id, to: model.draftName)
        model.renamingID = nil
    }
}
