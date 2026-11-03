import Foundation

@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var folders: [Folder] = []

    let fileURL: URL
    private var saveWorkItem: DispatchWorkItem?

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    nonisolated static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("MySideNotes", isDirectory: true)
            .appendingPathComponent("notes.json")
    }

    init(fileURL: URL = NoteStore.defaultFileURL) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            folders = Self.starterFolders()
            saveNow()
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            folders = try decoder.decode(NotesFile.self, from: data).folders
        } catch {
            // Keep the unreadable file so the next save can't destroy the user's notes.
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("notes-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            NSLog("MySideNotes: could not read \(fileURL.path): \(error). Backup at \(backup.path)")
            folders = Self.starterFolders()
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        do {
            let data = try encoder.encode(NotesFile(version: 1, folders: folders))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("MySideNotes: save failed: \(error)")
        }
    }

    private static func starterFolders() -> [Folder] {
        let welcome = Note(text: """
        ยินดีต้อนรับสู่ My SideNotes

        • กด ⌃⌥N (Control + Option + N) เพื่อเปิด/ปิดแผงโน้ตได้จากทุกแอป
        • คลิกแถบเล็ก ๆ ที่ขอบขวาของจอไหนก็ได้ แผงจะเปิดบนจอนั้น
        • คลิกที่อื่นหรือกด Esc เพื่อซ่อน
        • กดปุ่มหมุดด้านล่างเพื่อค้างแผงไว้ไม่ให้ซ่อน
        • ปุ่มเฟืองด้านล่างหรือคลิกขวาที่ไอคอนบนแถบเมนูเพื่อตั้งค่า
        • คลิกขวาที่โฟลเดอร์หรือโน้ตเพื่อดูตัวเลือกเพิ่มเติม
        • ลากโฟลเดอร์หรือโน้ตเพื่อจัดลำดับ

        ☐ พิมพ์ [] ตามด้วยเว้นวรรคเพื่อสร้าง checklist
        ☑ คลิกที่ช่องเพื่อติ๊ก
        ☐ หรือกด ⇧⌘L เพื่อสลับบรรทัดเป็น checklist
        """)
        return [
            Folder(name: "ทั่วไป", color: .yellow, notes: [welcome]),
            Folder(name: "งาน", color: .blue),
        ]
    }

    // MARK: - Queries

    func folder(_ id: Folder.ID) -> Folder? {
        folders.first { $0.id == id }
    }

    func note(_ noteID: Note.ID, in folderID: Folder.ID) -> Note? {
        folder(folderID)?.notes.first { $0.id == noteID }
    }

    /// Starred notes always come first; within each group the order is either the stored (manual) one or by edit time.
    func sortedNotes(in folderID: Folder.ID, mode: NoteSortMode) -> [Note] {
        var notes = folder(folderID)?.notes ?? []
        if mode == .updated {
            notes.sort { $0.updatedAt > $1.updatedAt }
        }
        return notes.filter(\.isStarred) + notes.filter { !$0.isStarred }
    }

    func search(_ query: String) -> [SearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return folders
            .flatMap { folder in
                folder.notes
                    .filter { $0.text.localizedCaseInsensitiveContains(q) || folder.name.localizedCaseInsensitiveContains(q) }
                    .map { SearchResult(folder: folder, note: $0) }
            }
            .sorted { $0.note.updatedAt > $1.note.updatedAt }
    }

    private func folderIndex(_ id: Folder.ID) -> Int? {
        folders.firstIndex { $0.id == id }
    }

    private func indices(of noteID: Note.ID, in folderID: Folder.ID) -> (Int, Int)? {
        guard let f = folderIndex(folderID),
              let n = folders[f].notes.firstIndex(where: { $0.id == noteID })
        else { return nil }
        return (f, n)
    }

    // MARK: - Folders

    @discardableResult
    func addFolder(named name: String) -> Folder.ID {
        let palette = FolderColor.allCases
        let folder = Folder(name: name, color: palette[folders.count % palette.count])
        folders.append(folder)
        scheduleSave()
        return folder.id
    }

    func renameFolder(_ id: Folder.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let f = folderIndex(id) else { return }
        folders[f].name = trimmed
        scheduleSave()
    }

    func setColor(_ color: FolderColor, for id: Folder.ID) {
        guard let f = folderIndex(id) else { return }
        folders[f].color = color
        scheduleSave()
    }

    func deleteFolder(_ id: Folder.ID) {
        folders.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Moves the folder into the target's slot (after it when dragging down, before it when dragging up).
    func moveFolder(_ id: Folder.ID, onto targetID: Folder.ID) {
        guard id != targetID, let from = folderIndex(id), let to = folderIndex(targetID) else { return }
        let folder = folders.remove(at: from)
        folders.insert(folder, at: to)
        scheduleSave()
    }

    // MARK: - Notes

    @discardableResult
    func addNote(to folderID: Folder.ID, text: String = "") -> Note.ID? {
        guard let f = folderIndex(folderID) else { return nil }
        let note = Note(text: text)
        folders[f].notes.insert(note, at: 0)
        scheduleSave()
        return note.id
    }

    func setText(_ text: String, for noteID: Note.ID, in folderID: Folder.ID) {
        guard case let (f, n)? = indices(of: noteID, in: folderID),
              folders[f].notes[n].text != text
        else { return }
        folders[f].notes[n].text = text
        folders[f].notes[n].updatedAt = Date()
        scheduleSave()
    }

    func toggleStar(_ noteID: Note.ID, in folderID: Folder.ID) {
        guard case let (f, n)? = indices(of: noteID, in: folderID) else { return }
        folders[f].notes[n].isStarred.toggle()
        scheduleSave()
    }

    func deleteNote(_ noteID: Note.ID, in folderID: Folder.ID) {
        guard case let (f, n)? = indices(of: noteID, in: folderID) else { return }
        folders[f].notes.remove(at: n)
        scheduleSave()
    }

    func deleteNoteIfBlank(_ noteID: Note.ID, in folderID: Folder.ID) {
        guard let note = note(noteID, in: folderID), note.isBlank else { return }
        deleteNote(noteID, in: folderID)
    }

    func moveNote(_ noteID: Note.ID, onto targetID: Note.ID, in folderID: Folder.ID) {
        guard noteID != targetID,
              case let (f, from)? = indices(of: noteID, in: folderID),
              let to = folders[f].notes.firstIndex(where: { $0.id == targetID })
        else { return }
        let note = folders[f].notes.remove(at: from)
        folders[f].notes.insert(note, at: to)
        scheduleSave()
    }

    func moveNote(_ noteID: Note.ID, from source: Folder.ID, to target: Folder.ID) {
        guard source != target,
              case let (f, n)? = indices(of: noteID, in: source),
              let t = folderIndex(target)
        else { return }
        let note = folders[f].notes.remove(at: n)
        folders[t].notes.insert(note, at: 0)
        scheduleSave()
    }
}
