import AppKit
import Carbon.HIToolbox

protocol TitledOption: CaseIterable, Identifiable, Hashable {
    var title: String { get }
}

enum AppearanceMode: String, Codable, TitledOption {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "ตามระบบ"
        case .light: "สว่าง"
        case .dark: "มืด"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum GlassStyle: String, Codable, TitledOption {
    case regular, clear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular: "ปกติ"
        case .clear: "ใส"
        }
    }
}

enum PanelEdge: String, Codable, TitledOption {
    case left, right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: "ซ้าย"
        case .right: "ขวา"
        }
    }
}

enum NoteSortMode: String, Codable, TitledOption {
    case manual, updated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: "จัดเอง"
        case .updated: "แก้ไขล่าสุด"
        }
    }
}

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String

    static let toggleDefault = Shortcut(
        keyCode: UInt32(kVK_ANSI_N),
        modifiers: UInt32(controlKey | optionKey),
        display: "⌃⌥N"
    )
    static let quickNoteDefault = Shortcut(
        keyCode: UInt32(kVK_ANSI_N),
        modifiers: UInt32(controlKey | optionKey | shiftKey),
        display: "⌃⌥⇧N"
    )

    init(keyCode: UInt32, modifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }

    /// Returns nil for combinations that would hijack normal typing (no ⌃/⌥/⌘ and not a function key).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        let keyCode = Int(event.keyCode)
        let isFunctionKey = Self.functionKeys[keyCode] != nil
        guard isFunctionKey || !flags.intersection([.control, .option, .command]).isEmpty else { return nil }

        var carbon = 0
        var symbols = ""
        if flags.contains(.control) { carbon |= controlKey; symbols += "⌃" }
        if flags.contains(.option) { carbon |= optionKey; symbols += "⌥" }
        if flags.contains(.shift) { carbon |= shiftKey; symbols += "⇧" }
        if flags.contains(.command) { carbon |= cmdKey; symbols += "⌘" }

        // Name keys by physical position so the label stays Latin even with a Thai input source.
        let name = Self.functionKeys[keyCode]
            ?? Self.specialKeys[keyCode]
            ?? Self.ansiKeys[keyCode]
            ?? (event.charactersIgnoringModifiers ?? "?").uppercased()

        self.init(keyCode: UInt32(keyCode), modifiers: UInt32(carbon), display: symbols + name)
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    private static let ansiKeys: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
    ]
}

struct Preferences: Codable, Equatable {
    var appearance: AppearanceMode = .system
    var glassStyle: GlassStyle = .regular
    var tintHex: String?
    var tintOpacity: Double = 0.3
    var panelOpacity: Double = 1
    var panelEdge: PanelEdge = .right
    var showsEdgeHandle = true
    var noteSort: NoteSortMode = .manual
    var toggleShortcut: Shortcut = .toggleDefault
    var quickNoteShortcut: Shortcut = .quickNoteDefault
    var quickNoteFolderID: UUID?

    init() {}

    // Tolerates missing keys so adding a preference never resets the others.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        appearance = (try? c.decodeIfPresent(AppearanceMode.self, forKey: .appearance)) ?? d.appearance
        glassStyle = (try? c.decodeIfPresent(GlassStyle.self, forKey: .glassStyle)) ?? d.glassStyle
        tintHex = (try? c.decodeIfPresent(String.self, forKey: .tintHex)) ?? d.tintHex
        tintOpacity = (try? c.decodeIfPresent(Double.self, forKey: .tintOpacity)) ?? d.tintOpacity
        panelOpacity = (try? c.decodeIfPresent(Double.self, forKey: .panelOpacity)) ?? d.panelOpacity
        panelEdge = (try? c.decodeIfPresent(PanelEdge.self, forKey: .panelEdge)) ?? d.panelEdge
        showsEdgeHandle = (try? c.decodeIfPresent(Bool.self, forKey: .showsEdgeHandle)) ?? d.showsEdgeHandle
        noteSort = (try? c.decodeIfPresent(NoteSortMode.self, forKey: .noteSort)) ?? d.noteSort
        toggleShortcut = (try? c.decodeIfPresent(Shortcut.self, forKey: .toggleShortcut)) ?? d.toggleShortcut
        quickNoteShortcut = (try? c.decodeIfPresent(Shortcut.self, forKey: .quickNoteShortcut)) ?? d.quickNoteShortcut
        quickNoteFolderID = (try? c.decodeIfPresent(UUID.self, forKey: .quickNoteFolderID)) ?? d.quickNoteFolderID
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private static let defaultsKey = "preferences.v1"

    @Published var prefs: Preferences {
        didSet {
            guard prefs != oldValue else { return }
            if let data = try? JSONEncoder().encode(prefs) {
                UserDefaults.standard.set(data, forKey: Self.defaultsKey)
            }
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(Preferences.self, from: data) {
            prefs = saved
        } else {
            prefs = Preferences()
        }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )
    }
}
