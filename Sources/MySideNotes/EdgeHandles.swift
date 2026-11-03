import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

/// A small visible tab on the panel's edge of every connected screen; clicking it opens the panel on that screen.
@MainActor
final class EdgeHandles {
    private var isEnabled = false
    private var edge: PanelEdge = .right

    /// The display currently showing the panel; its handle is hidden so it doesn't peek out beside the panel.
    var activeDisplayID: CGDirectDisplayID? {
        didSet { updateVisibility() }
    }

    private let onActivate: (NSScreen) -> Void
    private var handles: [(displayID: CGDirectDisplayID?, window: NSPanel)] = []
    private var screenObserver: NSObjectProtocol?

    private let handleSize = NSSize(width: 10, height: 100)

    init(onActivate: @escaping (NSScreen) -> Void) {
        self.onActivate = onActivate
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    func configure(enabled: Bool, edge: PanelEdge) {
        guard enabled != isEnabled || edge != self.edge else { return }
        isEnabled = enabled
        self.edge = edge
        rebuild()
    }

    private func rebuild() {
        handles.forEach { $0.window.orderOut(nil) }
        handles = []
        guard isEnabled else { return }

        for screen in NSScreen.screens {
            let visible = screen.visibleFrame
            let rect = NSRect(
                x: edge == .right ? screen.frame.maxX - handleSize.width : screen.frame.minX,
                y: visible.midY - handleSize.height / 2,
                width: handleSize.width,
                height: handleSize.height
            )
            let window = NSPanel(
                contentRect: rect,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = false
            // Fully transparent pixels let clicks fall through, so keep a barely-visible fill for the hit area.
            window.backgroundColor = NSColor(white: 0, alpha: 0.01)
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.contentView = EdgeHandleView(edge: edge) { [weak self, weak screen] in
                guard let screen else { return }
                self?.onActivate(screen)
            }
            handles.append((screen.displayID, window))
        }
        updateVisibility()
    }

    private func updateVisibility() {
        for handle in handles {
            if activeDisplayID != nil, handle.displayID == activeDisplayID {
                handle.window.orderOut(nil)
            } else {
                handle.window.orderFrontRegardless()
            }
        }
    }
}

private final class EdgeHandleView: NSView {
    private let pill = NSView()
    private let edge: PanelEdge
    private let onClick: () -> Void
    private var isHovering = false {
        didSet { updatePill(animated: true) }
    }

    init(edge: PanelEdge, onClick: @escaping () -> Void) {
        self.edge = edge
        self.onClick = onClick
        super.init(frame: .zero)
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 4
        pill.layer?.cornerCurve = .continuous
        pill.layer?.maskedCorners = edge == .right
            ? [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            : [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        pill.layer?.borderWidth = 0.5
        addSubview(pill)
        toolTip = "เปิด SideNotes"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updatePill(animated: false)
    }

    private func updatePill(animated: Bool) {
        let width: CGFloat = isHovering ? bounds.width : 6
        let frame = NSRect(
            x: edge == .right ? bounds.maxX - width : 0,
            y: 0,
            width: width,
            height: bounds.height
        )
        pill.layer?.backgroundColor = NSColor(white: 0.5, alpha: isHovering ? 0.75 : 0.5).cgColor
        pill.layer?.borderColor = NSColor(white: 1, alpha: 0.4).cgColor
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                pill.animator().frame = frame
            }
        } else {
            pill.frame = frame
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) { isHovering = true }

    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick()
        }
    }
}
