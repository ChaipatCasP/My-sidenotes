import AppKit
import SwiftUI

final class SidePanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53, !isComposingText {
            onEscape?()
            return
        }
        super.sendEvent(event)
    }

    // An accessory app has no Edit menu, so standard editing shortcuts must be routed by hand.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let action: Selector? = switch (key, flags) {
        case ("x", [.command]): #selector(NSText.cut(_:))
        case ("c", [.command]): #selector(NSText.copy(_:))
        case ("v", [.command]): #selector(NSText.paste(_:))
        case ("a", [.command]): #selector(NSText.selectAll(_:))
        case ("z", [.command]): Selector(("undo:"))
        case ("z", [.command, .shift]): Selector(("redo:"))
        default: nil
        }
        if let action, NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private var isComposingText: Bool {
        (firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }
}

@MainActor
final class SidePanelController: NSObject, NSWindowDelegate {
    private let panel: SidePanel
    private let state: PanelState
    private let width: CGFloat = 370
    private let slideDistance: CGFloat = 40

    private(set) var isVisible = false
    private(set) var currentDisplayID: CGDirectDisplayID?
    private var lastHiddenAt = Date.distantPast
    private var outsideClickMonitor: Any?
    private var edge: PanelEdge = .right
    private var targetAlpha: CGFloat = 1

    /// Called with the display showing the panel, or nil once it hides.
    var onVisibilityChange: ((CGDirectDisplayID?) -> Void)?

    init(store: NoteStore, state: PanelState, settings: AppSettings) {
        self.state = state
        panel = SidePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.handleEscape() }

        let hosting = NSHostingView(
            rootView: RootView()
                .environmentObject(store)
                .environmentObject(state)
                .environmentObject(settings)
        )
        hosting.sizingOptions = []
        panel.contentView = hosting

        state.requestHide = { [weak self] in self?.hide() }
    }

    func apply(_ prefs: Preferences) {
        panel.appearance = prefs.appearance.nsAppearance
        targetAlpha = prefs.panelOpacity
        if isVisible {
            panel.alphaValue = targetAlpha
        }
        if prefs.panelEdge != edge {
            edge = prefs.panelEdge
            if isVisible, let screen = currentScreen {
                panel.setFrame(shownFrame(on: screen), display: true)
            }
        }
    }

    /// Toggles on the screen under the mouse.
    func toggle() {
        if isVisible {
            hide()
        } else if Date().timeIntervalSince(lastHiddenAt) > 0.25 {
            show()
        }
    }

    func show(on screen: NSScreen? = nil) {
        let screen = screen ?? Self.screenUnderMouse()
        if isVisible, screen.displayID == currentDisplayID {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let frame = shownFrame(on: screen)
        panel.setFrame(frame.offsetBy(dx: slideOffset, dy: 0), display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)

        isVisible = true
        currentDisplayID = screen.displayID
        onVisibilityChange?(currentDisplayID)
        startOutsideClickMonitor()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = targetAlpha
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        currentDisplayID = nil
        lastHiddenAt = Date()
        stopOutsideClickMonitor()
        onVisibilityChange?(nil)

        let end = panel.frame.offsetBy(dx: slideOffset, dy: 0)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(end, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isVisible else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func handleEscape() {
        if state.isShowingSettings {
            state.isShowingSettings = false
        } else if case .note = state.route {
            state.goBack()
        } else {
            hide()
        }
    }

    private var slideOffset: CGFloat {
        edge == .right ? slideDistance : -slideDistance
    }

    private var currentScreen: NSScreen? {
        NSScreen.screens.first { $0.displayID == currentDisplayID }
    }

    private static func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func shownFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let x = edge == .right ? visible.maxX - width : visible.minX
        return NSRect(x: x, y: visible.minY, width: width, height: visible.height)
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.state.isPinned else { return }
                self.hide()
            }
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isVisible, !self.state.isPinned else { return }
                // A sheet/alert of our own panel keeps the app's key window non-nil.
                if NSApp.keyWindow == nil {
                    self.hide()
                }
            }
        }
    }
}
