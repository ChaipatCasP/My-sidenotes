import AppKit
import SwiftUI

/// Lets SwiftUI buttons (e.g. the checklist toolbar button) act on the live text view.
final class EditorController: ObservableObject {
    weak var textView: NoteTextView?

    @MainActor
    func toggleChecklist() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.toggleChecklist()
    }
}

struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: EditorController

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Built on TextKit 1 explicitly: checkbox hit-testing relies on NSLayoutManager.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = NoteTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: 14)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        textView.string = text
        NoteStyler.apply(to: textView)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        controller.textView = textView
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NoteTextView, textView.string != text else { return }
        textView.string = text
        NoteStyler.apply(to: textView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            NoteStyler.apply(to: textView)
        }
    }
}

@MainActor
enum NoteStyler {
    static let fontSize: CGFloat = 14

    static var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        return [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
    }

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Re-derives all styling from the plain text, so the stored note never carries formatting.
    static func apply(to textView: NSTextView) {
        guard !textView.hasMarkedText(), let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)
        let base = baseAttributes
        let checkboxFont = NSFont.systemFont(ofSize: fontSize + 3)

        storage.beginEditing()
        storage.setAttributes(base, range: full)
        text.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            guard let marker = ChecklistMarker.find(in: text, lineRange: lineRange) else { return }
            storage.addAttributes([
                .font: checkboxFont,
                .foregroundColor: marker.isChecked ? NSColor.secondaryLabelColor : NSColor.controlAccentColor,
                .cursor: NSCursor.pointingHand,
            ], range: marker.range)
            if marker.isChecked {
                let rest = NSRange(
                    location: NSMaxRange(marker.range),
                    length: NSMaxRange(lineRange) - NSMaxRange(marker.range)
                )
                storage.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: NSColor.secondaryLabelColor,
                ], range: rest)
            }
        }
        linkDetector?.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match, let url = match.url else { return }
            storage.addAttribute(.link, value: url, range: match.range)
        }
        storage.endEditing()
        textView.typingAttributes = base
    }
}

final class NoteTextView: NSTextView {
    private static let listMarkers = ["☐ ", "☑ ", "• ", "- ", "* "]
    private static let uncheckedShortcuts: Set<String> = ["[] ", "[ ] ", "- [ ] ", "- [] ", "-[] "]
    private static let checkedShortcuts: Set<String> = ["[x] ", "- [x] "]

    // MARK: Checkbox clicks

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let marker = checklistMarker(at: point) {
            replace(marker.range, with: marker.isChecked ? "☐" : "☑")
            return
        }
        super.mouseDown(with: event)
    }

    private func checklistMarker(at point: NSPoint) -> ChecklistMarker? {
        guard let layoutManager, let textContainer else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
        guard glyphRect.insetBy(dx: -4, dy: -2).contains(containerPoint) else { return nil }

        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let text = string as NSString
        guard charIndex < text.length else { return nil }
        let marker = ChecklistMarker.find(in: text, lineRange: text.lineRange(for: NSRange(location: charIndex, length: 0)))
        return marker?.range.location == charIndex ? marker : nil
    }

    // MARK: Checklist toggling (⇧⌘L / toolbar)

    func toggleChecklist() {
        let text = string as NSString
        let block = text.lineRange(for: selectedRange())
        let original = text.substring(with: block)
        let hasTrailingNewline = original.hasSuffix("\n")
        var lines = (hasTrailingNewline ? String(original.dropLast()) : original)
            .components(separatedBy: "\n")
        if lines.isEmpty { lines = [""] }

        let removing = lines.allSatisfy(Self.isChecklistLine)
        let updated = lines.map { line -> String in
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            var body = String(line.dropFirst(indent.count))
            if removing {
                if body.hasPrefix("☐ ") || body.hasPrefix("☑ ") {
                    body.removeFirst(2)
                } else if body.hasPrefix("☐") || body.hasPrefix("☑") {
                    body.removeFirst()
                }
                return indent + body
            }
            if Self.isChecklistLine(line) { return line }
            if let bullet = ["• ", "- ", "* "].first(where: body.hasPrefix) {
                body.removeFirst(bullet.count)
            }
            return indent + "☐ " + body
        }

        let result = updated.joined(separator: "\n")
        if replace(block, with: result + (hasTrailingNewline ? "\n" : "")) {
            setSelectedRange(NSRange(location: block.location + (result as NSString).length, length: 0))
        }
    }

    private static func isChecklistLine(_ line: String) -> Bool {
        let body = line.drop { $0 == " " || $0 == "\t" }
        return body.hasPrefix("☐") || body.hasPrefix("☑")
    }

    // MARK: List continuation and "[] " shortcuts

    override func insertNewline(_ sender: Any?) {
        let text = string as NSString
        let selection = selectedRange()
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: selection.location, length: 0))

        guard selection.length == 0, selection.location == contentsEnd else {
            super.insertNewline(sender)
            return
        }
        let line = text.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        let body = String(line.dropFirst(indent.count))

        guard let (marker, content) = Self.listPrefix(of: body) else {
            super.insertNewline(sender)
            return
        }
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            // Enter on an empty item ends the list, like most editors.
            replace(NSRange(location: lineStart, length: contentsEnd - lineStart), with: "")
            return
        }
        insertText("\n" + indent + Self.nextMarker(after: marker), replacementRange: selection)
    }

    private static func listPrefix(of body: String) -> (marker: String, content: Substring)? {
        if let marker = listMarkers.first(where: body.hasPrefix) {
            return (marker, body.dropFirst(marker.count))
        }
        let digits = body.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, body.dropFirst(digits.count).hasPrefix(". ") {
            let marker = String(digits) + ". "
            return (marker, body.dropFirst(marker.count))
        }
        return nil
    }

    private static func nextMarker(after marker: String) -> String {
        if marker == "☑ " { return "☐ " }
        if let number = Int(marker.dropLast(2)) { return "\(number + 1). " }
        return marker
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        let inserted = (string as? String) ?? (string as? NSAttributedString)?.string
        guard inserted == " " else { return }

        let text = self.string as NSString
        let caret = selectedRange().location
        let lineStart = text.lineRange(for: NSRange(location: caret, length: 0)).location
        let prefixRange = NSRange(location: lineStart, length: caret - lineStart)
        let prefix = text.substring(with: prefixRange)
        let indent = String(prefix.prefix { $0 == " " || $0 == "\t" })
        let typed = String(prefix.dropFirst(indent.count)).lowercased()

        if Self.uncheckedShortcuts.contains(typed) {
            replace(prefixRange, with: indent + "☐ ")
        } else if Self.checkedShortcuts.contains(typed) {
            replace(prefixRange, with: indent + "☑ ")
        }
    }

    // MARK: Editing helpers

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    /// Routes programmatic edits through the normal change path so they are undoable and reach the delegate.
    @discardableResult
    private func replace(_ range: NSRange, with replacement: String) -> Bool {
        guard shouldChangeText(in: range, replacementString: replacement) else { return false }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        return true
    }
}
