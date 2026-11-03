import AppKit
import Combine
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = NoteStore()
    private let state = PanelState()
    private let settings = AppSettings()
    private var panel: SidePanelController!
    private var edgeHandles: EdgeHandles!
    private var statusItem: NSStatusItem!
    private var registeredToggle: Shortcut?
    private var registeredQuickNote: Shortcut?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            NSApp.terminate(nil)
            return
        }

        panel = SidePanelController(store: store, state: state, settings: settings)
        edgeHandles = EdgeHandles { [weak self] screen in
            self?.panel.show(on: screen)
        }
        panel.onVisibilityChange = { [weak self] displayID in
            self?.edgeHandles.activeDisplayID = displayID
        }

        state.revealDataFile = { [weak self] in self?.revealDataFile() }
        state.setLaunchAtLogin = { [weak self] enabled in self?.setLaunchAtLogin(enabled) }

        settings.$prefs
            .sink { [weak self] prefs in self?.apply(prefs) }
            .store(in: &cancellables)
        state.$isRecordingShortcut
            .removeDuplicates()
            .sink { [weak self] recording in
                guard let self else { return }
                if recording {
                    HotKeyCenter.shared.unregisterAll()
                    registeredToggle = nil
                    registeredQuickNote = nil
                } else {
                    registerHotKeys(settings.prefs)
                }
            }
            .store(in: &cancellables)

        setUpStatusItem()

        if CommandLine.arguments.contains("--show") {
            panel.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    private func apply(_ prefs: Preferences) {
        edgeHandles.configure(enabled: prefs.showsEdgeHandle, edge: prefs.panelEdge)
        panel.apply(prefs)
        if !state.isRecordingShortcut {
            registerHotKeys(prefs)
        }
    }

    private func registerHotKeys(_ prefs: Preferences) {
        guard prefs.toggleShortcut != registeredToggle || prefs.quickNoteShortcut != registeredQuickNote else { return }

        var failed: Set<UInt32> = []
        let toggleOK = HotKeyCenter.shared.register(id: HotKeyID.toggle, shortcut: prefs.toggleShortcut) { [weak self] in
            self?.panel.toggle()
        }
        if !toggleOK { failed.insert(HotKeyID.toggle) }
        let quickOK = HotKeyCenter.shared.register(id: HotKeyID.quickNote, shortcut: prefs.quickNoteShortcut) { [weak self] in
            self?.quickNote()
        }
        if !quickOK { failed.insert(HotKeyID.quickNote) }

        registeredToggle = prefs.toggleShortcut
        registeredQuickNote = prefs.quickNoteShortcut
        state.failedHotKeyIDs = failed
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "My SideNotes")
        button.toolTip = "My SideNotes — คลิกเพื่อเปิด, คลิกขวาเพื่อดูเมนู"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            statusItem.menu = makeMenu()
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            panel.toggle()
        }
    }

    private func makeMenu() -> NSMenu {
        let prefs = settings.prefs
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "แสดง/ซ่อนโน้ต   \(prefs.toggleShortcut.display)", action: #selector(togglePanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "จดโน้ตด่วน   \(prefs.quickNoteShortcut.display)", action: #selector(quickNote), keyEquivalent: ""))
        menu.addItem(.separator())

        let edgeItem = NSMenuItem(title: "แสดงแถบที่ขอบจอ", action: #selector(toggleEdgeHandle), keyEquivalent: "")
        edgeItem.state = prefs.showsEdgeHandle ? .on : .off
        menu.addItem(edgeItem)
        menu.addItem(NSMenuItem(title: "ตั้งค่า…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "ออกจาก My SideNotes", action: #selector(quit), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        return menu
    }

    // MARK: - Actions

    @objc private func togglePanel() {
        panel.toggle()
    }

    @objc private func quickNote() {
        let preferred = settings.prefs.quickNoteFolderID.flatMap { store.folder($0) }?.id
        let folderID = preferred
            ?? state.currentFolderID
            ?? store.folders.first?.id
            ?? store.addFolder(named: "ทั่วไป")
        guard let noteID = store.addNote(to: folderID) else { return }
        state.isShowingSettings = false
        state.route = .note(folder: folderID, note: noteID)
        panel.show()
    }

    @objc private func openSettings() {
        state.isShowingSettings = true
        panel.show()
    }

    @objc private func toggleEdgeHandle() {
        settings.prefs.showsEdgeHandle.toggle()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "ตั้งค่าเปิดอัตโนมัติไม่สำเร็จ"
            alert.informativeText = "ต้องรันจากไฟล์ .app (สร้างด้วย scripts/build-app.sh) ไม่ใช่จาก swift run\n\n\(error.localizedDescription)"
            alert.runModal()
        }
        state.objectWillChange.send()
    }

    @objc private func revealDataFile() {
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
