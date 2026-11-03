import Carbon.HIToolbox

enum HotKeyID {
    static let toggle: UInt32 = 1
    static let quickNote: UInt32 = 2
}

/// System-wide shortcuts via Carbon, which (unlike NSEvent global monitors) needs no Accessibility permission.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private let signature = OSType(0x534E_4F54) // "SNOT"
    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]

    private init() {}

    /// Returns false when the combination can't be registered (usually taken by another app).
    @discardableResult
    func register(id: UInt32, shortcut: Shortcut, action: @escaping () -> Void) -> Bool {
        unregister(id: id)
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            EventHotKeyID(signature: signature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        hotKeyRefs[id] = ref
        actions[id] = action
        return true
    }

    func unregister(id: UInt32) {
        if let ref = hotKeyRefs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        actions[id] = nil
    }

    func unregisterAll() {
        hotKeyRefs.keys.forEach(unregister)
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                HotKeyCenter.shared.actions[hotKeyID.id]?()
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
    }
}
