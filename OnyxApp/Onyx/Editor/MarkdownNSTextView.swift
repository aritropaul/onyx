import AppKit

final class MarkdownNSTextView: NSTextView {

    var onTextChange: ((String) -> Void)?
    var onCursorChange: ((Int) -> Void)?
    var onWikiLinkClick: ((String) -> Void)?
    private var tableOverlays: [Int: NSView] = [:] // unused, kept for cleanup


    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isRichText = true
        allowsUndo = true
        usesFindPanel = true
        isEditable = true
        isSelectable = true
        drawsBackground = false
        textContainerInset = NSSize(width: 0, height: 0)

        if let textContainer = textContainer {
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    // MARK: - Mouse handling (Cmd+click links, checkbox toggle)

    override func mouseDown(with event: NSEvent) {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let textStorage = textStorage else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let textPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let charIndex = layoutManager.characterIndex(for: textPoint, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)

        guard charIndex < (string as NSString).length else {
            super.mouseDown(with: event)
            return
        }

        // Debug: write to file
        let attrs = textStorage.attributes(at: charIndex, effectiveRange: nil)
        let clickedChar = (string as NSString).substring(with: NSRange(location: charIndex, length: 1))
        let debugLine = "[Click] idx=\(charIndex) char='\(clickedChar)' attrs=\(attrs.keys.map(\.rawValue))\n"
        let logPath = "/tmp/onyx_debug.log"
        if let fh = FileHandle(forWritingAtPath: logPath) {
            fh.seekToEndOfFile()
            fh.write(debugLine.data(using: .utf8)!)
            fh.closeFile()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: debugLine.data(using: .utf8))
        }

        // Wiki links — click to navigate to local document
        if let title = textStorage.attribute(.wikiLink, at: charIndex, effectiveRange: nil) as? String {
            let wikiLine = "[WikiLink] Found: '\(title)', handler=\(onWikiLinkClick != nil)\n"
            if let fh = FileHandle(forWritingAtPath: logPath) {
                fh.seekToEndOfFile()
                fh.write(wikiLine.data(using: .utf8)!)
                fh.closeFile()
            }
            onWikiLinkClick?(title)
            return
        }

        // Cmd+click to follow external links
        if event.modifierFlags.contains(.command) {
            if let urlString = textStorage.attribute(.markdownLink, at: charIndex, effectiveRange: nil) as? String,
               let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
                return
            }
        }

        // Click on task checkbox to toggle
        var checkboxRange = NSRange(location: 0, length: 0)
        if textStorage.attribute(.taskCheckbox, at: charIndex, effectiveRange: &checkboxRange) != nil {
            // Find the actual checkbox char (space/x) between [ and ] within the range
            let rangeStr = (string as NSString).substring(with: checkboxRange)
            if let bracketOffset = rangeStr.range(of: "[")?.upperBound {
                let charOffset = rangeStr.distance(from: rangeStr.startIndex, to: bracketOffset)
                let checkCharIndex = checkboxRange.location + charOffset
                if checkCharIndex < (string as NSString).length {
                    let currentChar = (string as NSString).substring(with: NSRange(location: checkCharIndex, length: 1))
                    let newChar = (currentChar == " ") ? "x" : " "
                    if shouldChangeText(in: NSRange(location: checkCharIndex, length: 1), replacementString: newChar) {
                        textStorage.replaceCharacters(in: NSRange(location: checkCharIndex, length: 1), with: newChar)
                        didChangeText()
                    }
                }
            }
            return
        }

        super.mouseDown(with: event)
    }

    // MARK: - Keyboard shortcuts

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Cmd+B → bold
        if flags == .command && event.charactersIgnoringModifiers == "b" {
            toggleDelimiter("**")
            return
        }

        // Cmd+I → italic
        if flags == .command && event.charactersIgnoringModifiers == "i" {
            toggleDelimiter("*")
            return
        }

        // Cmd+E → inline code
        if flags == .command && event.charactersIgnoringModifiers == "e" {
            toggleDelimiter("`")
            return
        }

        // Cmd+Shift+S → strikethrough
        if flags == [.command, .shift] && event.charactersIgnoringModifiers == "s" {
            toggleDelimiter("~~")
            return
        }

        // Table keyboard handling — Tab, Shift+Tab, Enter on table lines
        if isOnTableLine() {
            if event.keyCode == 48 { // Tab
                if flags.contains(.shift) {
                    if handleTablePrevCell() { return }
                } else if flags.isEmpty {
                    if handleTableNextCell() { return }
                }
            }
            if event.keyCode == 36 && flags.isEmpty { // Enter
                if handleTableNewRow() { return }
            }
        }

        // Enter: list continuation
        if event.keyCode == 36 && flags.isEmpty {
            if handleListContinuation() { return }
        }

        // Tab / Shift+Tab in lists
        if event.keyCode == 48 { // Tab
            if flags.contains(.shift) {
                if handleListDedent() { return }
            } else if flags.isEmpty {
                if handleListIndent() { return }
            }
        }

        super.keyDown(with: event)
    }

    // MARK: - Notification-based formatting (from toolbar)

    @objc func handleToggleStyle(_ notification: Notification) {
        guard let style = notification.userInfo?["style"] as? String else { return }
        switch style {
        case "bold": toggleDelimiter("**")
        case "italic": toggleDelimiter("*")
        case "code": toggleDelimiter("`")
        case "strikethrough": toggleDelimiter("~~")
        default: break
        }
    }

    // MARK: - Delimiter toggling

    private func toggleDelimiter(_ delimiter: String) {
        let sel = selectedRange()
        let str = string as NSString

        guard sel.length > 0 else {
            // No selection: insert pair and place cursor between
            let pair = delimiter + delimiter
            insertText(pair, replacementRange: sel)
            setSelectedRange(NSRange(location: sel.location + delimiter.count, length: 0))
            return
        }

        let selected = str.substring(with: sel)
        let dLen = delimiter.count

        // Check if already wrapped
        if sel.location >= dLen && sel.location + sel.length + dLen <= str.length {
            let before = str.substring(with: NSRange(location: sel.location - dLen, length: dLen))
            let after = str.substring(with: NSRange(location: sel.location + sel.length, length: dLen))
            if before == delimiter && after == delimiter {
                // Unwrap
                let fullRange = NSRange(location: sel.location - dLen, length: sel.length + dLen * 2)
                insertText(selected, replacementRange: fullRange)
                setSelectedRange(NSRange(location: sel.location - dLen, length: sel.length))
                return
            }
        }

        // Wrap
        let wrapped = delimiter + selected + delimiter
        insertText(wrapped, replacementRange: sel)
        setSelectedRange(NSRange(location: sel.location + dLen, length: sel.length))
    }

    // MARK: - List continuation

    private func handleListContinuation() -> Bool {
        let str = string as NSString
        let sel = selectedRange()
        let lineRange = str.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = str.substring(with: lineRange)

        // Match list patterns — task list first to avoid bullet match
        let patterns: [(pattern: String, capture: Int)] = [
            ("^(\\s*- \\[[xX ]\\] )(.*)$", 1),
            ("^(\\s*[-*+] )(.*)$", 1),
            ("^(\\s*\\d+\\. )(.*)$", 1),
            ("^(\\s*> )(.*)$", 1),
        ]

        for (pattern, _) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.count)) else { continue }

            let prefix = (line as NSString).substring(with: match.range(at: 1))
            let content = (line as NSString).substring(with: match.range(at: 2))

            // Empty list item: remove the prefix and stop the list
            if content.trimmingCharacters(in: .whitespaces).isEmpty {
                let replaceRange = NSRange(location: lineRange.location, length: lineRange.length)
                insertText("\n", replacementRange: replaceRange)
                return true
            }

            // Continue the list with the same prefix
            var newPrefix = prefix

            // Task list: always continue with unchecked
            if prefix.contains("- [") {
                let indent = String(prefix.prefix(while: { $0 == " " || $0 == "\t" }))
                newPrefix = indent + "- [ ] "
            }
            // Increment numbered list
            else if let numRegex = try? NSRegularExpression(pattern: "^(\\s*)(\\d+)(\\. )$"),
               let numMatch = numRegex.firstMatch(in: prefix, range: NSRange(location: 0, length: prefix.count)) {
                let indent = (prefix as NSString).substring(with: numMatch.range(at: 1))
                let numStr = (prefix as NSString).substring(with: numMatch.range(at: 2))
                let dot = (prefix as NSString).substring(with: numMatch.range(at: 3))
                if let num = Int(numStr) {
                    newPrefix = indent + "\(num + 1)" + dot
                }
            }

            insertText("\n" + newPrefix, replacementRange: sel)
            return true
        }

        return false
    }

    // MARK: - List indent/dedent

    private func handleListIndent() -> Bool {
        let str = string as NSString
        let sel = selectedRange()
        let lineRange = str.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = str.substring(with: lineRange)

        guard line.trimmingCharacters(in: .whitespaces).hasPrefix("-") ||
              line.trimmingCharacters(in: .whitespaces).hasPrefix("*") ||
              line.trimmingCharacters(in: .whitespaces).hasPrefix("+") ||
              line.trimmingCharacters(in: .whitespaces).range(of: #"^\d+\."#, options: .regularExpression) != nil ||
              line.trimmingCharacters(in: .whitespaces).hasPrefix(">") else { return false }

        insertText("  " + line, replacementRange: lineRange)
        setSelectedRange(NSRange(location: sel.location + 2, length: 0))
        return true
    }

    private func handleListDedent() -> Bool {
        let str = string as NSString
        let sel = selectedRange()
        let lineRange = str.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = str.substring(with: lineRange)

        guard line.hasPrefix("  ") else { return false }

        let dedented = String(line.dropFirst(2))
        insertText(dedented, replacementRange: lineRange)
        setSelectedRange(NSRange(location: max(sel.location - 2, lineRange.location), length: 0))
        return true
    }

    // MARK: - Table helpers

    private func isOnTableLine() -> Bool {
        let str = string as NSString
        let sel = selectedRange()
        guard sel.location <= str.length else { return false }
        let lineRange = str.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = str.substring(with: lineRange).trimmingCharacters(in: .newlines)
        return line.hasPrefix("|") && line.hasSuffix("|")
    }

    private func currentTableLineRange() -> NSRange {
        let str = string as NSString
        return str.lineRange(for: NSRange(location: selectedRange().location, length: 0))
    }

    private func handleTableNextCell() -> Bool {
        let str = string as NSString
        let sel = selectedRange()
        let lineRange = str.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = str.substring(with: lineRange)

        // Find the next | after cursor position within this line
        let posInLine = sel.location - lineRange.location
        if let nextPipe = line.suffix(from: line.index(line.startIndex, offsetBy: min(posInLine + 1, line.count))).firstIndex(of: "|") {
            let nextPipeOffset = line.distance(from: line.startIndex, to: nextPipe)
            // If there's content after this pipe (not the trailing pipe), move into next cell
            if nextPipeOffset < line.count - 1 {
                let cellStart = lineRange.location + nextPipeOffset + 1
                // Find the end of the cell (next pipe or end of line)
                let remaining = line.suffix(from: line.index(after: nextPipe))
                if let endPipe = remaining.firstIndex(of: "|") {
                    let cellEnd = lineRange.location + nextPipeOffset + 1 + remaining.distance(from: remaining.startIndex, to: endPipe)
                    let cellText = str.substring(with: NSRange(location: cellStart, length: cellEnd - cellStart))
                    let trimmedStart = cellText.prefix(while: { $0 == " " }).count
                    let trimmedEnd = cellText.reversed().prefix(while: { $0 == " " }).count
                    let selectStart = cellStart + trimmedStart
                    let selectLen = max(0, (cellEnd - cellStart) - trimmedStart - trimmedEnd)
                    setSelectedRange(NSRange(location: selectStart, length: selectLen))
                    return true
                }
            }
        }

        // Move to next line's first cell (skip separator lines)
        let nextLineStart = NSMaxRange(lineRange)
        guard nextLineStart < str.length else { return true }
        var nextLineRange = str.lineRange(for: NSRange(location: nextLineStart, length: 0))
        var nextLine = str.substring(with: nextLineRange).trimmingCharacters(in: .newlines)

        // Skip separator line
        if nextLine.contains("---") || nextLine.contains(":--") || nextLine.contains("--:") {
            let afterSep = NSMaxRange(nextLineRange)
            guard afterSep < str.length else { return true }
            nextLineRange = str.lineRange(for: NSRange(location: afterSep, length: 0))
            nextLine = str.substring(with: nextLineRange).trimmingCharacters(in: .newlines)
        }

        if nextLine.hasPrefix("|") {
            // Move to first cell of next line
            if let firstPipe = nextLine.firstIndex(of: "|"),
               let secondPipe = nextLine[nextLine.index(after: firstPipe)...].firstIndex(of: "|") {
                let cellStart = nextLineRange.location + nextLine.distance(from: nextLine.startIndex, to: firstPipe) + 1
                let cellEnd = nextLineRange.location + nextLine.distance(from: nextLine.startIndex, to: secondPipe)
                let cellText = str.substring(with: NSRange(location: cellStart, length: cellEnd - cellStart))
                let trimmedStart = cellText.prefix(while: { $0 == " " }).count
                let trimmedEnd = cellText.reversed().prefix(while: { $0 == " " }).count
                let selectStart = cellStart + trimmedStart
                let selectLen = max(0, (cellEnd - cellStart) - trimmedStart - trimmedEnd)
                setSelectedRange(NSRange(location: selectStart, length: selectLen))
            }
        }
        return true
    }

    private func handleTablePrevCell() -> Bool {
        let str = string as NSString
        let sel = selectedRange()
        let lineRange = str.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = str.substring(with: lineRange)

        // Find the previous | before cursor
        let posInLine = sel.location - lineRange.location
        let beforeCursor = String(line.prefix(max(0, posInLine)))
        if let prevPipe = beforeCursor.lastIndex(of: "|") {
            let prevPipeOffset = beforeCursor.distance(from: beforeCursor.startIndex, to: prevPipe)
            // Find the pipe before that one (start of previous cell)
            let beforePrevPipe = String(beforeCursor.prefix(prevPipeOffset))
            if let startPipe = beforePrevPipe.lastIndex(of: "|") {
                let startOffset = beforePrevPipe.distance(from: beforePrevPipe.startIndex, to: startPipe)
                let cellStart = lineRange.location + startOffset + 1
                let cellEnd = lineRange.location + prevPipeOffset
                let cellText = str.substring(with: NSRange(location: cellStart, length: cellEnd - cellStart))
                let trimmedStart = cellText.prefix(while: { $0 == " " }).count
                let trimmedEnd = cellText.reversed().prefix(while: { $0 == " " }).count
                let selectStart = cellStart + trimmedStart
                let selectLen = max(0, (cellEnd - cellStart) - trimmedStart - trimmedEnd)
                setSelectedRange(NSRange(location: selectStart, length: selectLen))
                return true
            }
        }

        // Move to previous line's last cell (skip separator lines)
        guard lineRange.location > 0 else { return true }
        var prevLineRange = str.lineRange(for: NSRange(location: lineRange.location - 1, length: 0))
        var prevLine = str.substring(with: prevLineRange).trimmingCharacters(in: .newlines)

        // Skip separator line
        if prevLine.contains("---") || prevLine.contains(":--") || prevLine.contains("--:") {
            guard prevLineRange.location > 0 else { return true }
            prevLineRange = str.lineRange(for: NSRange(location: prevLineRange.location - 1, length: 0))
            prevLine = str.substring(with: prevLineRange).trimmingCharacters(in: .newlines)
        }

        if prevLine.hasPrefix("|") && prevLine.hasSuffix("|") {
            // Move to last cell of previous line
            let trimmed = prevLine.trimmingCharacters(in: .newlines)
            if let lastPipe = trimmed.dropLast().lastIndex(of: "|") {
                let lastPipeOffset = trimmed.distance(from: trimmed.startIndex, to: lastPipe)
                let cellStart = prevLineRange.location + lastPipeOffset + 1
                let cellEnd = prevLineRange.location + trimmed.count - 1
                let cellLen = cellEnd - cellStart
                guard cellLen > 0 else { return true }
                let cellText = str.substring(with: NSRange(location: cellStart, length: cellLen))
                let trimmedStart = cellText.prefix(while: { $0 == " " }).count
                let trimmedEnd = cellText.reversed().prefix(while: { $0 == " " }).count
                let selectStart = cellStart + trimmedStart
                let selectLen = max(0, cellLen - trimmedStart - trimmedEnd)
                setSelectedRange(NSRange(location: selectStart, length: selectLen))
            }
        }
        return true
    }

    private func handleTableNewRow() -> Bool {
        let str = string as NSString
        let sel = selectedRange()
        let lineRange = str.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = str.substring(with: lineRange).trimmingCharacters(in: .newlines)

        // Count columns by counting pipes
        let pipes = line.filter { $0 == "|" }
        let columnCount = max(pipes.count - 1, 1)

        // Build empty row: | | | | with matching columns
        let emptyRow = "|" + String(repeating: "  |", count: columnCount)

        // Insert at end of current line
        let insertPos = NSMaxRange(lineRange) - (str.substring(with: lineRange).hasSuffix("\n") ? 1 : 0)
        let insertion = "\n" + emptyRow
        if shouldChangeText(in: NSRange(location: insertPos, length: 0), replacementString: insertion) {
            textStorage?.replaceCharacters(in: NSRange(location: insertPos, length: 0), with: insertion)
            didChangeText()
            // Place cursor in first cell of new row
            setSelectedRange(NSRange(location: insertPos + 2, length: 0))
        }
        return true
    }

    // MARK: - Table context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        guard isOnTableLine() else { return super.menu(for: event) }

        let menu = NSMenu(title: "Table")

        menu.addItem(withTitle: "Insert Row Above", action: #selector(tableInsertRowAbove), keyEquivalent: "")
        menu.addItem(withTitle: "Insert Row Below", action: #selector(tableInsertRowBelow), keyEquivalent: "")
        menu.addItem(withTitle: "Delete Row", action: #selector(tableDeleteRow), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Insert Column Left", action: #selector(tableInsertColumnLeft), keyEquivalent: "")
        menu.addItem(withTitle: "Insert Column Right", action: #selector(tableInsertColumnRight), keyEquivalent: "")
        menu.addItem(withTitle: "Delete Column", action: #selector(tableDeleteColumn), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Align Left", action: #selector(tableAlignLeft), keyEquivalent: "")
        menu.addItem(withTitle: "Align Center", action: #selector(tableAlignCenter), keyEquivalent: "")
        menu.addItem(withTitle: "Align Right", action: #selector(tableAlignRight), keyEquivalent: "")

        return menu
    }

    // MARK: - Table row/column operations

    /// Find all lines belonging to the table around the cursor
    private func tableLines() -> (lines: [String], startIdx: Int, lineRanges: [NSRange])? {
        let str = string as NSString
        let sel = selectedRange()
        guard sel.location <= str.length else { return nil }

        var ranges: [NSRange] = []
        var lines: [String] = []

        // Find start of table (scan upward)
        var loc = sel.location
        while loc > 0 {
            let prevLineRange = str.lineRange(for: NSRange(location: loc - 1, length: 0))
            let prevLine = str.substring(with: prevLineRange).trimmingCharacters(in: .newlines)
            guard prevLine.hasPrefix("|") && prevLine.hasSuffix("|") else { break }
            loc = prevLineRange.location
        }

        // Now scan forward collecting all table lines
        let startLoc = loc
        while loc < str.length {
            let lineRange = str.lineRange(for: NSRange(location: loc, length: 0))
            let line = str.substring(with: lineRange).trimmingCharacters(in: .newlines)
            guard line.hasPrefix("|") && line.hasSuffix("|") else { break }
            ranges.append(lineRange)
            lines.append(line)
            let nextLoc = NSMaxRange(lineRange)
            if nextLoc == loc { break }
            loc = nextLoc
        }

        guard !lines.isEmpty else { return nil }

        // Find which line the cursor is on
        let cursorLineRange = str.lineRange(for: NSRange(location: sel.location, length: 0))
        let startIdx = ranges.firstIndex(where: { $0.location == cursorLineRange.location }) ?? 0

        return (lines, startIdx, ranges)
    }

    private func parsePipeLine(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .newlines)
        guard trimmed.hasPrefix("|") && trimmed.hasSuffix("|") else { return [] }
        let inner = String(trimmed.dropFirst().dropLast())
        return inner.components(separatedBy: "|")
    }

    private func buildPipeLine(_ cells: [String]) -> String {
        return "|" + cells.joined(separator: "|") + "|"
    }

    private func replaceTableLines(_ ranges: [NSRange], with newLines: [String]) {
        let str = string as NSString
        let fullStart = ranges.first!.location
        let fullEnd = NSMaxRange(ranges.last!)
        let fullRange = NSRange(location: fullStart, length: fullEnd - fullStart)
        let replacement = newLines.joined(separator: "\n") + (str.substring(with: ranges.last!).hasSuffix("\n") ? "\n" : "")
        if shouldChangeText(in: fullRange, replacementString: replacement) {
            textStorage?.replaceCharacters(in: fullRange, with: replacement)
            didChangeText()
        }
    }

    private func currentColumnIndex() -> Int {
        let str = string as NSString
        let sel = selectedRange()
        let lineRange = str.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = str.substring(with: lineRange)
        let posInLine = sel.location - lineRange.location
        let beforeCursor = String(line.prefix(posInLine))
        return max(0, beforeCursor.filter({ $0 == "|" }).count - 1)
    }

    @objc private func tableInsertRowAbove() {
        guard let (lines, idx, ranges) = tableLines() else { return }
        let cols = parsePipeLine(lines[idx])
        let emptyRow = buildPipeLine(cols.map { _ in "  " })
        var newLines = lines
        // Don't insert above header (idx 0) or separator (idx 1)
        let insertIdx = max(idx, 2)
        newLines.insert(emptyRow, at: insertIdx)
        replaceTableLines(ranges, with: newLines)
    }

    @objc private func tableInsertRowBelow() {
        guard let (lines, idx, ranges) = tableLines() else { return }
        let cols = parsePipeLine(lines[idx])
        let emptyRow = buildPipeLine(cols.map { _ in "  " })
        var newLines = lines
        let insertIdx = min(idx + 1, newLines.count)
        // Skip separator if we're on header
        let actualIdx = (insertIdx == 1 && lines.count > 1) ? 2 : insertIdx
        newLines.insert(emptyRow, at: min(actualIdx, newLines.count))
        replaceTableLines(ranges, with: newLines)
    }

    @objc private func tableDeleteRow() {
        guard let (lines, idx, ranges) = tableLines() else { return }
        guard lines.count > 3 else { return } // Keep at least header + separator + 1 data row
        guard idx >= 2 else { return } // Don't delete header or separator
        var newLines = lines
        newLines.remove(at: idx)
        replaceTableLines(ranges, with: newLines)
    }

    @objc private func tableInsertColumnLeft() {
        guard let (lines, _, ranges) = tableLines() else { return }
        let colIdx = currentColumnIndex()
        var newLines: [String] = []
        for (i, line) in lines.enumerated() {
            var cells = parsePipeLine(line)
            let insertAt = max(0, min(colIdx, cells.count))
            if i == 1 { // separator
                cells.insert(" --- ", at: insertAt)
            } else {
                cells.insert("  ", at: insertAt)
            }
            newLines.append(buildPipeLine(cells))
        }
        replaceTableLines(ranges, with: newLines)
    }

    @objc private func tableInsertColumnRight() {
        guard let (lines, _, ranges) = tableLines() else { return }
        let colIdx = currentColumnIndex()
        var newLines: [String] = []
        for (i, line) in lines.enumerated() {
            var cells = parsePipeLine(line)
            let insertAt = min(colIdx + 1, cells.count)
            if i == 1 { // separator
                cells.insert(" --- ", at: insertAt)
            } else {
                cells.insert("  ", at: insertAt)
            }
            newLines.append(buildPipeLine(cells))
        }
        replaceTableLines(ranges, with: newLines)
    }

    @objc private func tableDeleteColumn() {
        guard let (lines, _, ranges) = tableLines() else { return }
        let colIdx = currentColumnIndex()
        let cols = parsePipeLine(lines[0])
        guard cols.count > 1 else { return } // Keep at least 1 column
        var newLines: [String] = []
        for line in lines {
            var cells = parsePipeLine(line)
            if colIdx < cells.count {
                cells.remove(at: colIdx)
            }
            newLines.append(buildPipeLine(cells))
        }
        replaceTableLines(ranges, with: newLines)
    }

    private func tableSetAlignment(_ marker: String) {
        guard let (lines, _, ranges) = tableLines() else { return }
        guard lines.count > 1 else { return }
        let colIdx = currentColumnIndex()
        var cells = parsePipeLine(lines[1]) // separator line
        guard colIdx < cells.count else { return }
        cells[colIdx] = " " + marker + " "
        var newLines = lines
        newLines[1] = buildPipeLine(cells)
        replaceTableLines(ranges, with: newLines)
    }

    @objc private func tableAlignLeft() { tableSetAlignment(":---") }
    @objc private func tableAlignCenter() { tableSetAlignment(":---:") }
    @objc private func tableAlignRight() { tableSetAlignment("---:") }

    // MARK: - Table overlay management

    func updateTableOverlays() {
        // Clean up any leftover overlays
        for (_, overlay) in tableOverlays {
            overlay.removeFromSuperview()
        }
        tableOverlays.removeAll()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Use visibleRect for decorations so complete blocks are found during scrolling.
        // AppKit's clip path ensures only dirtyRect is actually rendered.
        let decoRect = visibleRect
        drawCodeBlockDecorations(in: decoRect)
        drawInlineCodeDecorations(in: decoRect)
        drawBlockquoteDecorations(in: decoRect)
        drawTableDecorations(in: decoRect)
        super.draw(dirtyRect)
        drawDividerDecorations(in: decoRect)
        drawTaskCheckboxes(in: decoRect)
    }

    // MARK: - Code block decorations (background + language label)

    private func drawCodeBlockDecorations(in dirtyRect: NSRect) {
        guard let textStorage = textStorage,
              let layoutManager = layoutManager,
              let textContainer = textContainer else { return }

        let origin = textContainerOrigin
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: dirtyRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        var codeLines: [(rect: NSRect, language: String)] = []

        textStorage.enumerateAttribute(.codeBlock, in: visibleCharRange, options: []) { value, range, _ in
            guard value != nil else { return }
            let language = (value as? NSString) as String? ?? ""
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
                codeLines.append((
                    rect: NSRect(
                        x: usedRect.origin.x + origin.x,
                        y: usedRect.origin.y + origin.y,
                        width: usedRect.width,
                        height: usedRect.height
                    ),
                    language: language
                ))
            }
        }

        guard !codeLines.isEmpty else { return }

        let sorted = codeLines.sorted { $0.rect.origin.y < $1.rect.origin.y }
        var groups: [(rect: NSRect, language: String)] = [(sorted[0].rect, sorted[0].language)]
        for i in 1..<sorted.count {
            let prev = groups[groups.count - 1]
            if sorted[i].rect.origin.y <= prev.rect.maxY + 2 {
                groups[groups.count - 1].rect = groups[groups.count - 1].rect.union(sorted[i].rect)
            } else {
                groups.append((sorted[i].rect, sorted[i].language))
            }
        }

        for group in groups {
            let leftEdge = origin.x
            let rightEdge = self.bounds.width - origin.x
            let bgRect = NSRect(
                x: leftEdge,
                y: group.rect.origin.y - 4,
                width: rightEdge - leftEdge,
                height: group.rect.height + 16
            )

            // Background
            NSColor.white.withAlphaComponent(0.04).setFill()
            NSBezierPath(roundedRect: bgRect, xRadius: 8, yRadius: 8).fill()

            // Subtle border
            NSColor.white.withAlphaComponent(0.08).setStroke()
            let borderPath = NSBezierPath(roundedRect: bgRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
            borderPath.lineWidth = 1
            borderPath.stroke()

            // Language label in top-right corner
            if !group.language.isEmpty {
                let labelFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
                let labelAttrs: [NSAttributedString.Key: Any] = [
                    .font: labelFont,
                    .foregroundColor: NSColor.white.withAlphaComponent(0.3)
                ]
                let labelStr = NSAttributedString(string: group.language, attributes: labelAttrs)
                let labelSize = labelStr.size()
                let labelPoint = NSPoint(
                    x: bgRect.maxX - labelSize.width - 12,
                    y: bgRect.origin.y + 6
                )
                labelStr.draw(at: labelPoint)
            }
        }
    }

    // MARK: - Inline code decorations

    private func drawInlineCodeDecorations(in dirtyRect: NSRect) {
        guard let textStorage = textStorage,
              let layoutManager = layoutManager,
              let textContainer = textContainer else { return }

        let origin = textContainerOrigin
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: dirtyRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let monoFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let fontHeight = monoFont.ascender - monoFont.descender

        textStorage.enumerateAttribute(.inlineCode, in: visibleCharRange, options: []) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)

            let padV: CGFloat = 2
            let codeHeight = fontHeight + padV * 2

            NSColor.white.withAlphaComponent(0.08).setFill()

            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, lineGlyphRange, _ in
                let intersect = NSIntersectionRange(glyphRange, lineGlyphRange)
                guard intersect.length > 0 else { return }
                let lineRect = layoutManager.boundingRect(forGlyphRange: intersect, in: textContainer)
                let yOffset = (lineRect.height - codeHeight) / 2

                let bgRect = NSRect(
                    x: lineRect.origin.x + origin.x - 3,
                    y: lineRect.origin.y + origin.y + yOffset,
                    width: lineRect.width + 6,
                    height: codeHeight
                )
                NSBezierPath(roundedRect: bgRect, xRadius: 4, yRadius: 4).fill()
            }
        }
    }

    // MARK: - Blockquote decorations

    private func drawBlockquoteDecorations(in dirtyRect: NSRect) {
        guard let textStorage = textStorage,
              let layoutManager = layoutManager,
              let textContainer = textContainer else { return }

        let origin = textContainerOrigin
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: dirtyRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        // Collect line rects for blockquote regions
        var lineRects: [NSRect] = []
        var barColor: NSColor?

        textStorage.enumerateAttribute(.blockquoteBar, in: visibleCharRange, options: []) { value, range, _ in
            guard let color = value as? NSColor else { return }
            if barColor == nil { barColor = color }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
                lineRects.append(NSRect(
                    x: usedRect.origin.x + origin.x,
                    y: usedRect.origin.y + origin.y,
                    width: usedRect.width,
                    height: usedRect.height
                ))
            }
        }

        guard !lineRects.isEmpty, let color = barColor else { return }

        // Merge adjacent lines into contiguous blocks
        let sorted = lineRects.sorted { $0.origin.y < $1.origin.y }
        var groups: [[NSRect]] = [[sorted[0]]]
        for i in 1..<sorted.count {
            let prev = groups[groups.count - 1].last!
            if sorted[i].origin.y <= prev.maxY + 2 {
                groups[groups.count - 1].append(sorted[i])
            } else {
                groups.append([sorted[i]])
            }
        }

        for group in groups {
            var blockRect = group[0]
            for rect in group.dropFirst() {
                blockRect = blockRect.union(rect)
            }

            // Background — full width from text container edge
            let leftEdge = origin.x
            let rightEdge = self.bounds.width - origin.x
            let bgRect = NSRect(
                x: leftEdge,
                y: blockRect.origin.y - 8,
                width: rightEdge - leftEdge,
                height: blockRect.height + 16
            )
            color.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bgRect, xRadius: 6, yRadius: 6).fill()

            // Left bar — at text container edge
            let barRect = NSRect(
                x: leftEdge,
                y: bgRect.origin.y,
                width: 3,
                height: bgRect.height
            )
            color.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    // MARK: - Divider decorations (horizontal rule)

    private func drawDividerDecorations(in dirtyRect: NSRect) {
        guard let textStorage = textStorage,
              let layoutManager = layoutManager,
              let textContainer = textContainer else { return }

        let origin = textContainerOrigin
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: dirtyRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        textStorage.enumerateAttribute(.dividerLine, in: visibleCharRange, options: []) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)

            let leftEdge = origin.x
            let rightEdge = self.bounds.width - origin.x
            let lineY = lineRect.midY + origin.y

            NSColor.white.withAlphaComponent(0.12).setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: leftEdge, y: lineY))
            path.line(to: NSPoint(x: rightEdge, y: lineY))
            path.lineWidth = 1
            path.stroke()
        }
    }

    // MARK: - Task checkbox decorations

    private func drawTaskCheckboxes(in dirtyRect: NSRect) {
        guard let textStorage = textStorage,
              let layoutManager = layoutManager,
              let textContainer = textContainer else { return }

        let origin = textContainerOrigin
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: dirtyRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let accentColor = NSColor(red: 0.400, green: 0.520, blue: 1.0, alpha: 1.0)

        textStorage.enumerateAttribute(.taskCheckbox, in: visibleCharRange, options: []) { value, range, _ in
            guard let isChecked = value as? Bool else { return }

            // Skip drawing if delimiters are visible (cursor on this line)
            if let fgColor = textStorage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor,
               fgColor != .clear {
                return
            }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

            let size: CGFloat = 14
            let x = glyphRect.origin.x + origin.x + 1
            let y = glyphRect.origin.y + origin.y + 5
            let checkboxRect = NSRect(x: x, y: y, width: size, height: size)

            if isChecked {
                // Filled checkbox with accent color
                accentColor.setFill()
                let bgPath = NSBezierPath(roundedRect: checkboxRect, xRadius: 3, yRadius: 3)
                bgPath.fill()

                // White checkmark
                NSColor.white.setStroke()
                let checkPath = NSBezierPath()
                checkPath.move(to: NSPoint(x: checkboxRect.minX + 3, y: checkboxRect.midY))
                checkPath.line(to: NSPoint(x: checkboxRect.minX + 5.5, y: checkboxRect.maxY - 3))
                checkPath.line(to: NSPoint(x: checkboxRect.maxX - 3, y: checkboxRect.minY + 4))
                checkPath.lineWidth = 1.5
                checkPath.lineCapStyle = .round
                checkPath.lineJoinStyle = .round
                checkPath.stroke()
            } else {
                // Empty checkbox outline
                NSColor.white.withAlphaComponent(0.3).setStroke()
                let outlinePath = NSBezierPath(roundedRect: checkboxRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
                outlinePath.lineWidth = 1
                outlinePath.stroke()
            }
        }
    }

    // MARK: - Table decorations (background, grid, header highlight)

    private func drawTableDecorations(in dirtyRect: NSRect) {
        guard let textStorage = textStorage,
              let layoutManager = layoutManager,
              let textContainer = textContainer else { return }

        let origin = textContainerOrigin
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: dirtyRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        struct TableLine {
            let rect: NSRect
            let type: String
            let range: NSRange
            let columnInfo: TableColumnInfo?
        }
        var tableLines: [TableLine] = []

        textStorage.enumerateAttribute(.tableRow, in: visibleCharRange, options: []) { value, range, _ in
            guard let type = value as? String else { return }
            let info = textStorage.attribute(.tableColumnInfo, at: range.location, effectiveRange: nil) as? TableColumnInfo
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
                tableLines.append(TableLine(
                    rect: NSRect(
                        x: usedRect.origin.x + origin.x,
                        y: usedRect.origin.y + origin.y,
                        width: usedRect.width,
                        height: usedRect.height
                    ),
                    type: type,
                    range: range,
                    columnInfo: info
                ))
            }
        }

        guard !tableLines.isEmpty else { return }

        let sorted = tableLines.sorted { $0.rect.origin.y < $1.rect.origin.y }

        struct TableBlock {
            var lines: [TableLine]
            var rect: NSRect
        }

        var blocks: [TableBlock] = [TableBlock(lines: [sorted[0]], rect: sorted[0].rect)]
        for i in 1..<sorted.count {
            let prev = blocks[blocks.count - 1]
            if sorted[i].rect.origin.y <= prev.rect.maxY + 4 {
                blocks[blocks.count - 1].lines.append(sorted[i])
                blocks[blocks.count - 1].rect = blocks[blocks.count - 1].rect.union(sorted[i].rect)
            } else {
                blocks.append(TableBlock(lines: [sorted[i]], rect: sorted[i].rect))
            }
        }

        let borderColor = NSColor.white.withAlphaComponent(0.08)
        let gridColor = NSColor.white.withAlphaComponent(0.06)

        for block in blocks {
            let leftEdge = origin.x
            let rightEdge = self.bounds.width - origin.x
            let bgRect = NSRect(
                x: leftEdge,
                y: block.rect.origin.y - 4,
                width: rightEdge - leftEdge,
                height: block.rect.height + 8
            )

            // Outer background
            NSColor.white.withAlphaComponent(0.03).setFill()
            NSBezierPath(roundedRect: bgRect, xRadius: 6, yRadius: 6).fill()

            // Outer border
            borderColor.setStroke()
            let borderPath = NSBezierPath(roundedRect: bgRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            borderPath.lineWidth = 1
            borderPath.stroke()

            // Header row highlight
            if let headerLine = block.lines.first, headerLine.type == "header" {
                let headerBg = NSRect(
                    x: leftEdge + 1,
                    y: headerLine.rect.origin.y - 4,
                    width: rightEdge - leftEdge - 2,
                    height: headerLine.rect.height + 4
                )
                NSColor.white.withAlphaComponent(0.04).setFill()
                NSBezierPath(roundedRect: headerBg, xRadius: 5, yRadius: 5).fill()
            }

            // Horizontal dividers between rows
            gridColor.setStroke()
            for i in 0..<block.lines.count - 1 {
                let lineBottom = block.lines[i].rect.maxY
                let nextTop = block.lines[i + 1].rect.origin.y
                let gridY = (lineBottom + nextTop) / 2

                let path = NSBezierPath()
                path.move(to: NSPoint(x: leftEdge + 1, y: gridY))
                path.line(to: NSPoint(x: rightEdge - 1, y: gridY))
                path.lineWidth = 1
                path.stroke()
            }

            // Vertical grid lines at pipe positions — scan text directly from header line
            if let refLine = block.lines.first(where: { $0.type == "header" }) ?? block.lines.first {
                let nsStr = textStorage.string as NSString
                guard NSMaxRange(refLine.range) <= nsStr.length else { continue }
                let lineText = nsStr.substring(with: refLine.range)
                for (i, ch) in lineText.enumerated() {
                    // Skip first and last pipe (table edges)
                    guard ch == "|" && i > 0 && i < lineText.count - 1 else { continue }
                    let charIndex = refLine.range.location + i
                    let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
                    let glyphRect = layoutManager.boundingRect(
                        forGlyphRange: NSRange(location: glyphIndex, length: 1),
                        in: textContainer
                    )
                    let pipeX = glyphRect.midX + origin.x

                    gridColor.setStroke()
                    let path = NSBezierPath()
                    path.move(to: NSPoint(x: pipeX, y: bgRect.origin.y + 1))
                    path.line(to: NSPoint(x: pipeX, y: bgRect.maxY - 1))
                    path.lineWidth = 1
                    path.stroke()
                }
            }
        }
    }

    // MARK: - Layout

    private var cachedContentHeight: CGFloat = 44

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: cachedContentHeight)
    }

    /// Recompute and cache content height. Call after text changes or highlighting.
    func updateContentHeight() {
        guard let layoutManager = layoutManager, let textContainer = textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let newHeight = usedRect.height + textContainerInset.height * 2
        guard abs(newHeight - cachedContentHeight) > 0.5 else { return }
        cachedContentHeight = newHeight
        invalidateIntrinsicContentSize()
    }

    override func didChangeText() {
        super.didChangeText()
        updateContentHeight()
        // Any edit clears search highlights (highlightAll resets attributes anyway)
        searchHighlightRanges = []
    }

    // MARK: - Search term highlighting

    private var searchHighlightRanges: [NSRange] = []

    func highlightSearchTerm(_ term: String) {
        clearSearchHighlights()
        guard !term.isEmpty, let textStorage = textStorage else { return }
        let nsString = string as NSString
        var ranges: [NSRange] = []
        var searchStart = 0
        while searchStart < nsString.length {
            let range = nsString.range(of: term, options: .caseInsensitive,
                                        range: NSRange(location: searchStart, length: nsString.length - searchStart))
            guard range.location != NSNotFound else { break }
            ranges.append(range)
            searchStart = range.location + max(range.length, 1)
        }
        guard !ranges.isEmpty else { return }

        let highlightColor = NSColor(red: 0.4, green: 0.52, blue: 1.0, alpha: 0.25)
        textStorage.beginEditing()
        for range in ranges {
            textStorage.addAttribute(.backgroundColor, value: highlightColor, range: range)
        }
        textStorage.endEditing()
        searchHighlightRanges = ranges

        scrollRangeToVisible(ranges[0])
        showFindIndicator(for: ranges[0])
    }

    func clearSearchHighlights() {
        guard let textStorage = textStorage, !searchHighlightRanges.isEmpty else { return }
        textStorage.beginEditing()
        for range in searchHighlightRanges {
            let safe = NSIntersectionRange(range, NSRange(location: 0, length: textStorage.length))
            if safe.length > 0 {
                textStorage.removeAttribute(.backgroundColor, range: safe)
            }
        }
        textStorage.endEditing()
        searchHighlightRanges = []
    }
}
