import SwiftUI
import AppKit

enum EditorMode {
    case edit
    case view
}

struct MarkdownEditorField: NSViewRepresentable {
    @Binding var text: String
    var mode: EditorMode
    var onTextChange: (String) -> Void
    var onCursorChange: (Int) -> Void
    var onWikiLinkClick: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> MarkdownNSTextView {
        let textStorage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        layoutManager.allowsNonContiguousLayout = false
        textStorage.addLayoutManager(layoutManager)

        let containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        let textContainer = NSTextContainer(containerSize: containerSize)
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = MarkdownNSTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 64, height: 8)
        textView.drawsBackground = false
        textView.insertionPointColor = NSColor.white.withAlphaComponent(0.9)
        textView.isEditable = (mode == .edit)

        let bodyFont = NSFont.systemFont(ofSize: 14, weight: .regular)
        let textColor = NSColor.white.withAlphaComponent(0.9)
        textView.typingAttributes = [
            .font: bodyFont,
            .foregroundColor: textColor
        ]

        textView.delegate = context.coordinator
        textView.onTextChange = { newText in
            context.coordinator.parent.onTextChange(newText)
        }
        textView.onCursorChange = { offset in
            context.coordinator.parent.onCursorChange(offset)
        }
        textView.onWikiLinkClick = { title in
            context.coordinator.parent.onWikiLinkClick?(title)
        }

        context.coordinator.textView = textView
        context.coordinator.currentMode = mode

        // Set initial text and highlight
        textView.string = text
        context.coordinator.isHighlighting = true
        context.coordinator.fullHighlight()
        context.coordinator.isHighlighting = false
        textView.updateContentHeight()

        // Listen for toolbar format notifications
        NotificationCenter.default.addObserver(
            textView,
            selector: #selector(MarkdownNSTextView.handleToggleStyle(_:)),
            name: .onyxToggleInlineStyle,
            object: nil
        )

        // Deferred re-highlight after initial layout so paragraph styles render correctly
        DispatchQueue.main.async {
            context.coordinator.isHighlighting = true
            context.coordinator.fullHighlight()
            context.coordinator.isHighlighting = false
            textView.updateContentHeight()
            textView.needsDisplay = true
        }

        return textView
    }

    func updateNSView(_ textView: MarkdownNSTextView, context: Context) {
        textView.isEditable = (mode == .edit)

        if textView.string != text && !context.coordinator.isEditing {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            context.coordinator.isHighlighting = true
            context.coordinator.fullHighlight()
            context.coordinator.isHighlighting = false
            textView.selectedRanges = selectedRanges
            textView.updateContentHeight()
            textView.needsDisplay = true
        }

        // Re-highlight if mode changed
        if context.coordinator.currentMode != mode {
            context.coordinator.currentMode = mode
            context.coordinator.isHighlighting = true
            context.coordinator.fullHighlight()
            context.coordinator.isHighlighting = false
            textView.updateContentHeight()
            textView.needsDisplay = true
        }

    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorField
        weak var textView: MarkdownNSTextView?
        let highlighter = MarkdownHighlighter()
        var isEditing = false
        var currentMode: EditorMode = .edit
        var isHighlighting = false
        private var lastCursorLineRange: NSRange?

        init(_ parent: MarkdownEditorField) {
            self.parent = parent
        }

        func fullHighlight() {
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }
            let cursorLineRange = computeCursorLineRange()
            lastCursorLineRange = cursorLineRange
            let containerWidth = textView.textContainer?.containerSize.width ?? 0
            textView.undoManager?.disableUndoRegistration()
            highlighter.highlightAll(textStorage, cursorLineRange: cursorLineRange, containerWidth: containerWidth)
            textView.undoManager?.enableUndoRegistration()
            textView.updateTableOverlays()
        }

        private func computeCursorLineRange() -> NSRange? {
            guard currentMode == .edit,
                  let textView = textView else { return nil }
            let sel = textView.selectedRange()
            guard sel.location != NSNotFound else { return nil }
            let str = textView.string as NSString
            guard sel.location <= str.length else { return nil }
            return str.lineRange(for: NSRange(location: sel.location, length: 0))
        }

        func textDidChange(_ notification: Notification) {
            guard !isHighlighting else { return }
            guard let textView = notification.object as? NSTextView,
                  let textStorage = textView.textStorage else { return }

            isEditing = true
            isHighlighting = true

            let newText = textView.string
            parent.text = newText
            parent.onTextChange(newText)

            let cursorLineRange = computeCursorLineRange()
            lastCursorLineRange = cursorLineRange
            let cw = textView.textContainer?.containerSize.width ?? 0
            textView.undoManager?.disableUndoRegistration()
            highlighter.highlightAll(textStorage, cursorLineRange: cursorLineRange, containerWidth: cw)
            textView.undoManager?.enableUndoRegistration()

            isHighlighting = false
            isEditing = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownNSTextView else { return }
            let offset = textView.selectedRange().location
            parent.onCursorChange(offset)
            textView.onCursorChange?(offset)

            // Re-highlight only if cursor moved to a different line
            guard !isHighlighting else { return }
            let newLineRange = computeCursorLineRange()
            guard newLineRange != lastCursorLineRange else { return }
            lastCursorLineRange = newLineRange

            guard let textStorage = textView.textStorage else { return }
            let containerWidth = textView.textContainer?.containerSize.width ?? 0
            isHighlighting = true
            textView.undoManager?.disableUndoRegistration()
            highlighter.highlightAll(textStorage, cursorLineRange: newLineRange, containerWidth: containerWidth)
            textView.undoManager?.enableUndoRegistration()
            textView.needsDisplay = true
            isHighlighting = false
        }
    }
}
