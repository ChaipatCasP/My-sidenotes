import SwiftUI

enum FolderColor: String, Codable, CaseIterable, Identifiable {
    case yellow, orange, red, pink, purple, blue, teal, green, gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .yellow: .yellow
        case .orange: .orange
        case .red: .red
        case .pink: .pink
        case .purple: .purple
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .gray: .gray
        }
    }

    var displayName: String {
        switch self {
        case .yellow: "เหลือง"
        case .orange: "ส้ม"
        case .red: "แดง"
        case .pink: "ชมพู"
        case .purple: "ม่วง"
        case .blue: "น้ำเงิน"
        case .teal: "ฟ้าอมเขียว"
        case .green: "เขียว"
        case .gray: "เทา"
        }
    }
}

struct Note: Identifiable, Codable, Hashable {
    var id = UUID()
    var text = ""
    var isStarred = false
    var createdAt = Date()
    var updatedAt = Date()

    private var nonEmptyLines: [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var title: String {
        guard let first = nonEmptyLines.first else { return "โน้ตใหม่" }
        let stripped = first.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        return String((stripped.isEmpty ? first : stripped).prefix(100))
    }

    var preview: String {
        String(nonEmptyLines.dropFirst().joined(separator: " ").prefix(240))
    }

    /// Everything after the title, one line per line, for an expanded card.
    var details: String {
        nonEmptyLines.dropFirst().joined(separator: "\n")
    }

    var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var checklistProgress: (done: Int, total: Int)? {
        var done = 0
        var total = 0
        for line in text.split(whereSeparator: \.isNewline) {
            switch line.first(where: { $0 != " " && $0 != "\t" }) {
            case ChecklistMarker.checkedSymbol: done += 1; total += 1
            case ChecklistMarker.uncheckedSymbol: total += 1
            default: break
            }
        }
        return total > 0 ? (done, total) : nil
    }
}

struct ChecklistMarker {
    static let uncheckedSymbol: Character = "☐"
    static let checkedSymbol: Character = "☑"
    private static let unchecked: unichar = 0x2610
    private static let checked: unichar = 0x2611

    let range: NSRange
    let isChecked: Bool

    /// The checkbox glyph if it's the first non-whitespace character of the line.
    static func find(in text: NSString, lineRange: NSRange) -> ChecklistMarker? {
        var index = lineRange.location
        let end = NSMaxRange(lineRange)
        while index < end, [0x20, 0x09].contains(text.character(at: index)) {
            index += 1
        }
        guard index < end else { return nil }
        let char = text.character(at: index)
        guard char == unchecked || char == checked else { return nil }
        return ChecklistMarker(range: NSRange(location: index, length: 1), isChecked: char == checked)
    }
}

struct Folder: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var color: FolderColor
    var notes: [Note] = []
}

struct NotesFile: Codable {
    var version: Int
    var folders: [Folder]
}

extension Date {
    var relativeText: String {
        formatted(Date.RelativeFormatStyle(presentation: .named).locale(Locale(identifier: "th_TH")))
    }
}

struct SearchResult: Identifiable {
    let folder: Folder
    let note: Note
    var id: Note.ID { note.id }
}
