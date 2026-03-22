import AppKit

final class MarkdownHighlighter {

    // MARK: - Theme colors

    private let textColor = NSColor.white.withAlphaComponent(0.9)
    private let dimColor = NSColor.white.withAlphaComponent(0.5)
    private let secondaryColor = NSColor.white.withAlphaComponent(0.5)
    private let accentColor = NSColor(red: 0.400, green: 0.520, blue: 1.0, alpha: 1.0)
    private let surfaceColor = NSColor.white.withAlphaComponent(0.06)
    private let bodyFont = NSFont.systemFont(ofSize: 14, weight: .regular)
    private let h1Font = NSFont.systemFont(ofSize: 24, weight: .bold)
    private let h2Font = NSFont.systemFont(ofSize: 20, weight: .semibold)
    private let h3Font = NSFont.systemFont(ofSize: 18, weight: .semibold)
    private let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private let monoFontBold = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)

    // MARK: - Paragraph styles (line height)

    private lazy var bodyParaStyle: NSMutableParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = ceil(bodyFont.pointSize * 1.5)  // 150%
        style.maximumLineHeight = ceil(bodyFont.pointSize * 1.5)
        return style
    }()

    private lazy var h1ParaStyle: NSMutableParagraphStyle = {
        let style = NSMutableParagraphStyle()
        let natural = h1Font.ascender - h1Font.descender + h1Font.leading
        let target = h1Font.pointSize * 1.2
        let lineHeight = ceil(max(natural, target))
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.paragraphSpacingBefore = 16
        return style
    }()

    private lazy var h2ParaStyle: NSMutableParagraphStyle = {
        let style = NSMutableParagraphStyle()
        let natural = h2Font.ascender - h2Font.descender + h2Font.leading
        let target = h2Font.pointSize * 1.2
        let lineHeight = ceil(max(natural, target))
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.paragraphSpacingBefore = 12
        return style
    }()

    private lazy var h3ParaStyle: NSMutableParagraphStyle = {
        let style = NSMutableParagraphStyle()
        let natural = h3Font.ascender - h3Font.descender + h3Font.leading
        let target = h3Font.pointSize * 1.2
        let lineHeight = ceil(max(natural, target))
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.paragraphSpacingBefore = 10
        return style
    }()

    private lazy var codeParaStyle: NSMutableParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = ceil(monoFont.pointSize * 1.5)
        style.maximumLineHeight = ceil(monoFont.pointSize * 1.5)
        style.headIndent = 16
        style.firstLineHeadIndent = 16
        style.tailIndent = -16
        return style
    }()

    /// Applied to the opening ``` fence line to push content away from text above (collapsed)
    private lazy var codeFenceTopStyle: NSMutableParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 16
        style.minimumLineHeight = 0.01
        style.maximumLineHeight = 0.01
        return style
    }()

    /// Applied to the closing ``` fence line to push content away from text below (collapsed)
    private lazy var codeFenceBottomStyle: NSMutableParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 16
        style.minimumLineHeight = 0.01
        style.maximumLineHeight = 0.01
        return style
    }()

    /// Revealed opening fence (cursor inside code block)
    private lazy var codeFenceTopRevealedStyle: NSMutableParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 8
        style.minimumLineHeight = ceil(monoFont.pointSize * 1.3)
        style.maximumLineHeight = ceil(monoFont.pointSize * 1.3)
        return style
    }()

    /// Revealed closing fence (cursor inside code block)
    private lazy var codeFenceBottomRevealedStyle: NSMutableParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 8
        style.minimumLineHeight = ceil(monoFont.pointSize * 1.3)
        style.maximumLineHeight = ceil(monoFont.pointSize * 1.3)
        return style
    }()

    private lazy var dividerParaStyle: NSMutableParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 20
        style.maximumLineHeight = 20
        style.paragraphSpacingBefore = 8
        style.paragraphSpacing = 8
        return style
    }()

    private let tableMonoFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private let tableMonoFontBold = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)

    private lazy var tableParaStyle: NSMutableParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 6
        style.paragraphSpacing = 6
        return style
    }()

    private lazy var tableHeaderParaStyle: NSMutableParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 30
        style.maximumLineHeight = 30
        style.lineBreakMode = .byTruncatingTail
        style.paragraphSpacingBefore = 4
        return style
    }()

    private lazy var tableDataParaStyle: NSMutableParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 30
        style.maximumLineHeight = 30
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    private lazy var tableSeparatorCollapsedStyle: NSMutableParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 0.01
        style.maximumLineHeight = 0.01
        return style
    }()

    /// Hidden delimiter attributes: near-zero font + transparent color
    private lazy var hiddenAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 0.01, weight: .regular),
        .foregroundColor: NSColor.clear
    ]

    /// Visible delimiter attributes: normal font, dimmed color (shown on active line)
    private lazy var visibleDelimiterAttrs: [NSAttributedString.Key: Any] = [
        .font: bodyFont,
        .foregroundColor: dimColor
    ]

    // MARK: - Regex patterns

    private static let h1Pattern = try! NSRegularExpression(pattern: "^(# )(.+)$", options: .anchorsMatchLines)
    private static let h2Pattern = try! NSRegularExpression(pattern: "^(## )(.+)$", options: .anchorsMatchLines)
    private static let h3Pattern = try! NSRegularExpression(pattern: "^(### )(.+)$", options: .anchorsMatchLines)
    private static let boldPattern = try! NSRegularExpression(pattern: "(\\*\\*)((?:(?!\\*\\*).)+)(\\*\\*)", options: [])
    private static let italicPattern = try! NSRegularExpression(pattern: "(?<!\\*)(\\*)((?:(?!\\*).)+)(\\*)(?!\\*)", options: [])
    private static let inlineCodePattern = try! NSRegularExpression(pattern: "(`)((?:(?!`).)+)(`)", options: [])
    private static let strikethroughPattern = try! NSRegularExpression(pattern: "(~~)((?:(?!~~).)+)(~~)", options: [])
    private static let codeBlockPattern = try! NSRegularExpression(pattern: "^(```(\\w*).*)$\\n([\\s\\S]*?)^(```)$", options: .anchorsMatchLines)
    private static let linkPattern = try! NSRegularExpression(pattern: "(\\[)((?:(?!\\]).)+)(\\]\\()((?:(?!\\)).)*)(\\))", options: [])
    private static let bulletPattern = try! NSRegularExpression(pattern: "^(\\s*)([-*+] )(.*)", options: .anchorsMatchLines)
    private static let numberedPattern = try! NSRegularExpression(pattern: "^(\\s*)(\\d+\\. )(.*)", options: .anchorsMatchLines)
    private static let blockquotePattern = try! NSRegularExpression(pattern: "^(> ?)(.*)", options: .anchorsMatchLines)
    private static let blockquoteGroupPattern = try! NSRegularExpression(pattern: "(?:^> ?.*\\n?)+", options: .anchorsMatchLines)
    private static let dividerPattern = try! NSRegularExpression(pattern: "^(---|\\*\\*\\*|___)$", options: .anchorsMatchLines)
    private static let angleBracketLinkPattern = try! NSRegularExpression(pattern: "(<)(https?://[^\\s>]+)(>)", options: [])
    private static let bareURLPattern = try! NSRegularExpression(pattern: "(?<!\\(|\\[|\"|<)(https?://[^\\s)\\]\">]+)", options: [])
    private static let wikiLinkPattern = try! NSRegularExpression(pattern: "(\\[\\[)((?:(?!\\]\\]).)+)(\\]\\])", options: [])
    private static let taskListPattern = try! NSRegularExpression(pattern: "^(\\s*)(- \\[)([ xX])(\\] )(.*)", options: .anchorsMatchLines)
    private static let tablePattern = try! NSRegularExpression(pattern: "^(\\|.+\\|)\\n(\\|[-:| ]+\\|)\\n((?:\\|.+\\|\\n?)+)", options: .anchorsMatchLines)

    // MARK: - Public API

    /// Full document highlight. `cursorLineRange` is the NSRange of the line the cursor is on —
    /// delimiters on that line are revealed (dimmed but visible), all others are hidden (zero-width).
    func highlightAll(_ textStorage: NSTextStorage, cursorLineRange: NSRange?, containerWidth: CGFloat = 0) {
        guard textStorage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.beginEditing()

        // Reset everything to body defaults
        textStorage.addAttributes([
            .font: bodyFont,
            .foregroundColor: textColor,
            .backgroundColor: NSColor.clear,
            .strikethroughStyle: 0,
            .underlineStyle: 0,
            .paragraphStyle: bodyParaStyle
        ], range: fullRange)

        // Clear custom attributes from previous pass
        textStorage.removeAttribute(.kern, range: fullRange)
        textStorage.removeAttribute(.codeBlock, range: fullRange)
        textStorage.removeAttribute(.inlineCode, range: fullRange)
        textStorage.removeAttribute(.blockquoteBar, range: fullRange)
        textStorage.removeAttribute(.dividerLine, range: fullRange)
        textStorage.removeAttribute(.markdownLink, range: fullRange)
        textStorage.removeAttribute(.wikiLink, range: fullRange)
        textStorage.removeAttribute(.taskCheckbox, range: fullRange)
        textStorage.removeAttribute(.tableRow, range: fullRange)
        textStorage.removeAttribute(.tableSeparator, range: fullRange)
        textStorage.removeAttribute(.tableColumnInfo, range: fullRange)
        textStorage.removeAttribute(.tableCollapsed, range: fullRange)

        let fullText = textStorage.string
        let fullDocRange = NSRange(location: 0, length: (fullText as NSString).length)
        let fmRange = self.frontmatterRange(in: fullText)

        // Code blocks — style content, hide/reveal fences, store language for label drawing
        Self.codeBlockPattern.enumerateMatches(in: fullText, range: fullDocRange) { match, _, _ in
            guard let match = match else { return }

            // Check if cursor is anywhere inside this code block
            let cursorInBlock: Bool
            if let cl = cursorLineRange {
                cursorInBlock = NSIntersectionRange(match.range, cl).length > 0
            } else {
                cursorInBlock = false
            }

            if cursorInBlock {
                // Reveal fences — dimmed text, normal line height, inside code block background
                textStorage.addAttributes([
                    .font: self.monoFont,
                    .foregroundColor: self.dimColor,
                    .codeBlock: "" as NSString,
                    .paragraphStyle: self.codeFenceTopRevealedStyle
                ], range: match.range(at: 1))
                textStorage.addAttributes([
                    .font: self.monoFont,
                    .foregroundColor: self.dimColor,
                    .codeBlock: "" as NSString,
                    .paragraphStyle: self.codeFenceBottomRevealedStyle
                ], range: match.range(at: 4))
            } else {
                // Collapse fences
                self.applyDelimiter(textStorage, range: match.range(at: 1), cursorLineRange: cursorLineRange)
                textStorage.addAttribute(.paragraphStyle, value: self.codeFenceTopStyle, range: match.range(at: 1))
                self.applyDelimiter(textStorage, range: match.range(at: 4), cursorLineRange: cursorLineRange)
                textStorage.addAttribute(.paragraphStyle, value: self.codeFenceBottomStyle, range: match.range(at: 4))
            }

            // Extract language identifier
            let langRange = match.range(at: 2)
            let language: String
            if langRange.location != NSNotFound && langRange.length > 0 {
                language = (fullText as NSString).substring(with: langRange)
            } else {
                language = ""
            }
            // Code content — store language as attribute value
            textStorage.addAttributes([
                .font: self.monoFont,
                .foregroundColor: self.textColor,
                .codeBlock: language as NSString,
                .paragraphStyle: self.codeParaStyle,
                .baselineOffset: -2
            ], range: match.range(at: 3))
        }

        // Headings
        self.applyHeading(textStorage, pattern: Self.h1Pattern, font: h1Font, paraStyle: h1ParaStyle, fullText: fullText, cursorLineRange: cursorLineRange)
        self.applyHeading(textStorage, pattern: Self.h2Pattern, font: h2Font, paraStyle: h2ParaStyle, fullText: fullText, cursorLineRange: cursorLineRange)
        self.applyHeading(textStorage, pattern: Self.h3Pattern, font: h3Font, paraStyle: h3ParaStyle, fullText: fullText, cursorLineRange: cursorLineRange)

        // Bold
        Self.boldPattern.enumerateMatches(in: fullText, range: fullDocRange) { match, _, _ in
            guard let match = match else { return }
            guard !self.isInsideCodeBlock(fullText: fullText, range: match.range) else { return }
            let boldFont = NSFontManager.shared.convert(self.bodyFont, toHaveTrait: .boldFontMask)
            textStorage.addAttribute(.font, value: boldFont, range: match.range(at: 2))
            self.applyDelimiter(textStorage, range: match.range(at: 1), cursorLineRange: cursorLineRange)
            self.applyDelimiter(textStorage, range: match.range(at: 3), cursorLineRange: cursorLineRange)
        }

        // Italic
        Self.italicPattern.enumerateMatches(in: fullText, range: fullDocRange) { match, _, _ in
            guard let match = match else { return }
            guard !self.isInsideCodeBlock(fullText: fullText, range: match.range) else { return }
            let italicFont = NSFontManager.shared.convert(self.bodyFont, toHaveTrait: .italicFontMask)
            textStorage.addAttribute(.font, value: italicFont, range: match.range(at: 2))
            self.applyDelimiter(textStorage, range: match.range(at: 1), cursorLineRange: cursorLineRange)
            self.applyDelimiter(textStorage, range: match.range(at: 3), cursorLineRange: cursorLineRange)
        }

        // Inline code
        Self.inlineCodePattern.enumerateMatches(in: fullText, range: fullDocRange) { match, _, _ in
            guard let match = match else { return }
            guard !self.isInsideCodeBlock(fullText: fullText, range: match.range) else { return }
            textStorage.addAttributes([
                .font: self.monoFont,
                .inlineCode: true,
                .baselineOffset: 1
            ], range: match.range(at: 2))
            self.applyDelimiter(textStorage, range: match.range(at: 1), cursorLineRange: cursorLineRange)
            self.applyDelimiter(textStorage, range: match.range(at: 3), cursorLineRange: cursorLineRange)
        }

        // Strikethrough
        Self.strikethroughPattern.enumerateMatches(in: fullText, range: fullDocRange) { match, _, _ in
            guard let match = match else { return }
            guard !self.isInsideCodeBlock(fullText: fullText, range: match.range) else { return }
            textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: match.range(at: 2))
            self.applyDelimiter(textStorage, range: match.range(at: 1), cursorLineRange: cursorLineRange)
            self.applyDelimiter(textStorage, range: match.range(at: 3), cursorLineRange: cursorLineRange)
        }

        // Links — store URL for Cmd+click
        Self.linkPattern.enumerateMatches(in: fullText, range: fullDocRange) { match, _, _ in
            guard let match = match else { return }
            guard !self.isInsideCodeBlock(fullText: fullText, range: match.range) else { return }
            let urlRange = match.range(at: 4)
            let url = (fullText as NSString).substring(with: urlRange)
            textStorage.addAttributes([
                .foregroundColor: self.accentColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .markdownLink: url
            ], range: match.range(at: 2))
            self.applyDelimiter(textStorage, range: match.range(at: 1), cursorLineRange: cursorLineRange)
            self.applyDelimiter(textStorage, range: match.range(at: 3), cursorLineRange: cursorLineRange)
            self.applyDelimiter(textStorage, range: match.range(at: 4), cursorLineRange: cursorLineRange)
            self.applyDelimiter(textStorage, range: match.range(at: 5), cursorLineRange: cursorLineRange)
        }

        // Autolinks — angle bracket <https://...>
        Self.angleBracketLinkPattern.enumerateMatches(in: fullText, range: fullDocRange) { match, _, _ in
            guard let match = match else { return }
            guard !self.isInsideCodeBlock(fullText: fullText, range: match.range) else { return }
            let url = (fullText as NSString).substring(with: match.range(at: 2))
            textStorage.addAttributes([
                .foregroundColor: self.accentColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .markdownLink: url
            ], range: match.range(at: 2))
            self.applyDelimiter(textStorage, range: match.range(at: 1), cursorLineRange: cursorLineRange)
            self.applyDelimiter(textStorage, range: match.range(at: 3), cursorLineRange: cursorLineRange)
        }

        // Autolinks — bare URLs (negative lookbehind avoids [text](url) and <url>)
        Self.bareURLPattern.enumerateMatches(in: fullText, range: fullDocRange) { match, _, _ in
            guard let match = match else { return }
            guard !self.isInsideCodeBlock(fullText: fullText, range: match.range) else { return }
            let url = (fullText as NSString).substring(with: match.range)
            textStorage.addAttributes([
                .foregroundColor: self.accentColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .markdownLink: url
            ], range: match.range)
        }

        // Wiki links — [[Document Name]]
        Self.wikiLinkPattern.enumerateMatches(in: fullText, range: fullDocRange) { match, _, _ in
            guard let match = match else { return }
            guard !self.isInsideCodeBlock(fullText: fullText, range: match.range) else { return }
            let titleRange = match.range(at: 2)
            let title = (fullText as NSString).substring(with: titleRange)
            textStorage.addAttributes([
                .foregroundColor: self.accentColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .wikiLink: title
            ], range: titleRange)
            self.applyDelimiter(textStorage, range: match.range(at: 1), cursorLineRange: cursorLineRange)
            self.applyDelimiter(textStorage, range: match.range(at: 3), cursorLineRange: cursorLineRange)
        }

        // Task lists — must run BEFORE bullet pattern
        Self.taskListPattern.enumerateMatches(in: fullText, range: fullDocRange) { match, _, _ in
            guard let match = match else { return }
            guard !self.isInsideCodeBlock(fullText: fullText, range: match.range) else { return }
            // Groups: 1=indent, 2="- [", 3=checkbox char, 4="] ", 5=content
            let checkboxCharRange = match.range(at: 3)
            let checkboxChar = (fullText as NSString).substring(with: checkboxCharRange)
            let isChecked = checkboxChar == "x" || checkboxChar == "X"

            // Mark the full "- [x] " span for custom checkbox drawing
            let delimStart = match.range(at: 2)
            let delimEnd = match.range(at: 4)
            let fullDelimRange = NSRange(
                location: delimStart.location,
                length: NSMaxRange(delimEnd) - delimStart.location
            )
            textStorage.addAttribute(.taskCheckbox, value: isChecked, range: fullDelimRange)

            // Make delimiter text transparent (custom drawing replaces it)
            let isCursorOnLine = cursorLineRange.map { $0.intersection(match.range) != nil } ?? false
            if !isCursorOnLine {
                textStorage.addAttribute(.foregroundColor, value: NSColor.clear, range: fullDelimRange)
            } else {
                self.applyDelimiter(textStorage, range: match.range(at: 2), cursorLineRange: cursorLineRange)
                self.applyDelimiter(textStorage, range: match.range(at: 4), cursorLineRange: cursorLineRange)
            }

            if isChecked {
                let contentRange = match.range(at: 5)
                textStorage.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: self.dimColor
                ], range: contentRange)
            }
        }

        // Bullet lists — skip task list lines
        Self.bulletPattern.enumerateMatches(in: fullText, range: fullDocRange) { match, _, _ in
            guard let match = match else { return }
            guard !self.isInsideCodeBlock(fullText: fullText, range: match.range) else { return }
            var isTaskLine = false
            textStorage.enumerateAttribute(.taskCheckbox, in: match.range, options: []) { value, _, stop in
                if value != nil { isTaskLine = true; stop.pointee = true }
            }
            guard !isTaskLine else { return }
            textStorage.addAttribute(.foregroundColor, value: self.accentColor, range: match.range(at: 2))
        }

        // Numbered lists
        Self.numberedPattern.enumerateMatches(in: fullText, range: fullDocRange) { match, _, _ in
            guard let match = match else { return }
            guard !self.isInsideCodeBlock(fullText: fullText, range: match.range) else { return }
            textStorage.addAttribute(.foregroundColor, value: self.accentColor, range: match.range(at: 2))
        }

        // Pre-compute table ranges so blockquotes can skip table content
        var tableRanges: [NSRange] = []
        Self.tablePattern.enumerateMatches(in: fullText, range: fullDocRange) { match, _, _ in
            guard let match = match else { return }
            tableRanges.append(match.range)
        }

        // Blockquotes — first find groups of consecutive > lines, then style each line
        Self.blockquoteGroupPattern.enumerateMatches(in: fullText, range: fullDocRange) { groupMatch, _, _ in
            guard let groupMatch = groupMatch else { return }
            let groupRange = groupMatch.range
            guard !self.isInsideCodeBlock(fullText: fullText, range: groupRange) else { return }
            guard !tableRanges.contains(where: { NSIntersectionRange($0, groupRange).length > 0 }) else { return }

            // Find individual lines within this group
            var lineRanges: [NSRange] = []
            Self.blockquotePattern.enumerateMatches(in: fullText, range: groupRange) { match, _, _ in
                guard let match = match else { return }
                lineRanges.append(match.range)
                self.applyDelimiter(textStorage, range: match.range(at: 1), cursorLineRange: cursorLineRange)
                textStorage.addAttributes([
                    .foregroundColor: self.textColor,
                    .blockquoteBar: self.accentColor
                ], range: match.range(at: 2))
            }

            let lineHeight = ceil(self.bodyFont.pointSize * 1.5)
            for (i, lineRange) in lineRanges.enumerated() {
                let paraStyle = NSMutableParagraphStyle()
                paraStyle.minimumLineHeight = lineHeight
                paraStyle.maximumLineHeight = lineHeight
                paraStyle.lineSpacing = 4
                paraStyle.headIndent = 12
                paraStyle.firstLineHeadIndent = 12
                if i == 0 { paraStyle.paragraphSpacingBefore = 20 }
                if i == lineRanges.count - 1 { paraStyle.paragraphSpacing = 20 }
                textStorage.addAttribute(.paragraphStyle, value: paraStyle, range: lineRange)
            }
        }

        // Dividers — skip code blocks and frontmatter
        Self.dividerPattern.enumerateMatches(in: fullText, range: fullDocRange) { match, _, _ in
            guard let match = match else { return }
            guard !self.isInsideCodeBlock(fullText: fullText, range: match.range) else { return }
            if let fm = fmRange, NSIntersectionRange(match.range, fm).length > 0 { return }
            self.applyDelimiter(textStorage, range: match.range, cursorLineRange: cursorLineRange)
            textStorage.addAttribute(.dividerLine, value: true, range: match.range)
            textStorage.addAttribute(.paragraphStyle, value: self.dividerParaStyle, range: match.range)
        }

        // Tables — kern-based column alignment
        Self.tablePattern.enumerateMatches(in: fullText, range: fullDocRange) { match, _, _ in
            guard let match = match else { return }
            guard !self.isInsideCodeBlock(fullText: fullText, range: match.range) else { return }
            let nsStr = fullText as NSString

            textStorage.removeAttribute(.blockquoteBar, range: match.range)

            let headerRange = match.range(at: 1)
            let headerLine = nsStr.substring(with: headerRange)
            let headerPipes = self.findPipeOffsets(headerLine)
            let columnCount = max(headerPipes.count - 1, 1)

            let dataRange = match.range(at: 3)
            let dataText = nsStr.substring(with: dataRange)

            struct RowInfo { let range: NSRange; let pipeOffsets: [Int] }
            var dataRows: [RowInfo] = []
            var lineStart = dataRange.location
            for line in dataText.components(separatedBy: "\n") {
                guard !line.isEmpty else { lineStart += 1; continue }
                let lineLen = (line as NSString).length
                let lineRange = NSRange(location: lineStart, length: lineLen)
                guard NSMaxRange(lineRange) <= nsStr.length else { break }
                dataRows.append(RowInfo(range: lineRange, pipeOffsets: self.findPipeOffsets(line)))
                lineStart += lineLen + 1
            }

            // Max width per column
            var maxWidths = Array(repeating: 0, count: columnCount)
            let allPipeSets = [headerPipes] + dataRows.map { $0.pipeOffsets }
            for pipes in allPipeSets {
                for col in 0..<min(columnCount, pipes.count - 1) {
                    maxWidths[col] = max(maxWidths[col], pipes[col + 1] - pipes[col] - 1)
                }
            }

            // Desired pipe positions
            var desiredPos = [0]
            for col in 0..<columnCount { desiredPos.append(desiredPos.last! + 1 + maxWidths[col]) }

            // Cap total width to prevent wrapping
            let cw = self.tableMonoFont.maximumAdvancement.width
            let effectiveContainerWidth = containerWidth > 10 ? containerWidth - 10 : 800
            let maxChars = Int(effectiveContainerWidth / cw) - 2
            let totalDesired = desiredPos.last!
            if totalDesired > maxChars && maxChars > columnCount + 1 {
                let scale = Double(maxChars - columnCount - 1) / Double(max(1, totalDesired - columnCount - 1))
                for col in 0..<columnCount { maxWidths[col] = max(1, Int(Double(maxWidths[col]) * scale)) }
                desiredPos = [0]
                for col in 0..<columnCount { desiredPos.append(desiredPos.last! + 1 + maxWidths[col]) }
            }

            // Header
            textStorage.addAttributes([
                .tableRow: "header", .font: self.tableMonoFontBold, .paragraphStyle: self.tableHeaderParaStyle,
                .baselineOffset: 6
            ], range: headerRange)
            self.applyTablePipeDelimiters(textStorage, lineRange: headerRange, text: nsStr, cursorLineRange: cursorLineRange)
            self.applyColumnKern(textStorage, lineRange: headerRange, pipeOffsets: headerPipes, desiredPositions: desiredPos)

            // Separator
            let sepRange = match.range(at: 2)
            let sepOnCursor: Bool
            if let cl = cursorLineRange { sepOnCursor = NSIntersectionRange(sepRange, cl).length > 0 }
            else { sepOnCursor = false }
            if sepOnCursor {
                textStorage.addAttributes([.font: self.tableMonoFont, .foregroundColor: self.dimColor, .paragraphStyle: self.tableDataParaStyle], range: sepRange)
            } else {
                textStorage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: 0.01, weight: .regular), .foregroundColor: NSColor.clear, .paragraphStyle: self.tableSeparatorCollapsedStyle], range: sepRange)
            }

            // Data rows
            for row in dataRows {
                textStorage.addAttributes([
                    .tableRow: "data", .font: self.tableMonoFont, .paragraphStyle: self.tableDataParaStyle,
                    .baselineOffset: 6
                ], range: row.range)
                self.applyTablePipeDelimiters(textStorage, lineRange: row.range, text: nsStr, cursorLineRange: cursorLineRange)
                self.applyColumnKern(textStorage, lineRange: row.range, pipeOffsets: row.pipeOffsets, desiredPositions: desiredPos)
            }
        }

        textStorage.endEditing()
    }

    // MARK: - Delimiter visibility

    /// If the delimiter range is on the cursor's line, show it dimmed. Otherwise, hide it (near-zero font + clear).
    private func applyDelimiter(_ textStorage: NSTextStorage, range: NSRange, cursorLineRange: NSRange?) {
        guard range.length > 0 else { return }
        let onCursorLine: Bool
        if let cursorLine = cursorLineRange {
            onCursorLine = NSIntersectionRange(range, cursorLine).length > 0
        } else {
            onCursorLine = false
        }

        if onCursorLine {
            textStorage.addAttributes(visibleDelimiterAttrs, range: range)
        } else {
            textStorage.addAttributes(hiddenAttrs, range: range)
        }
    }

    // MARK: - Heading helper

    private func applyHeading(_ textStorage: NSTextStorage, pattern: NSRegularExpression, font: NSFont, paraStyle: NSParagraphStyle, fullText: String, cursorLineRange: NSRange?) {
        let fullDocRange = NSRange(location: 0, length: (fullText as NSString).length)
        pattern.enumerateMatches(in: fullText, range: fullDocRange) { match, _, _ in
            guard let match = match else { return }
            guard !self.isInsideCodeBlock(fullText: fullText, range: match.range) else { return }
            // Apply paragraph style to full line first (so delimiter doesn't override it)
            textStorage.addAttribute(.paragraphStyle, value: paraStyle, range: match.range)
            self.applyDelimiter(textStorage, range: match.range(at: 1), cursorLineRange: cursorLineRange)
            textStorage.addAttribute(.font, value: font, range: match.range(at: 2))
        }
    }

    // MARK: - Table helpers

    private func findPipeOffsets(_ line: String) -> [Int] {
        var offsets: [Int] = []
        for (i, ch) in line.enumerated() {
            if ch == "|" { offsets.append(i) }
        }
        return offsets
    }

    /// Applies kern spacing to align pipe characters at desired column positions.
    private func applyColumnKern(_ textStorage: NSTextStorage, lineRange: NSRange, pipeOffsets: [Int], desiredPositions: [Int]) {
        let cw = tableMonoFont.maximumAdvancement.width
        var cumulativeKern: CGFloat = 0

        for k in 1..<min(pipeOffsets.count, desiredPositions.count) {
            let totalKernNeeded = CGFloat(desiredPositions[k] - pipeOffsets[k]) * cw
            let kernForThisPipe = totalKernNeeded - cumulativeKern

            if kernForThisPipe > 0.5 {
                // Apply kern to the character just before this pipe
                let charBeforePipe = pipeOffsets[k] - 1
                guard charBeforePipe >= 0 else { continue }
                let kernRange = NSRange(location: lineRange.location + charBeforePipe, length: 1)
                guard NSMaxRange(kernRange) <= textStorage.length else { continue }
                textStorage.addAttribute(.kern, value: kernForThisPipe, range: kernRange)
            }

            cumulativeKern = totalKernNeeded
        }
    }

    // MARK: - Table pipe styling

    /// Makes pipe `|` characters transparent but keeps their monospace width for column structure.
    /// On the cursor line, pipes are dimmed instead so the user can see the raw markdown.
    private func applyTablePipeDelimiters(_ textStorage: NSTextStorage, lineRange: NSRange, text: NSString, cursorLineRange: NSRange?) {
        let onCursorLine: Bool
        if let cl = cursorLineRange {
            onCursorLine = NSIntersectionRange(lineRange, cl).length > 0
        } else {
            onCursorLine = false
        }

        let line = text.substring(with: lineRange)
        var pipeOffsets: [Int] = []
        for (i, ch) in line.enumerated() {
            if ch == "|" {
                pipeOffsets.append(i)
                let pipeRange = NSRange(location: lineRange.location + i, length: 1)
                if onCursorLine {
                    textStorage.addAttribute(.foregroundColor, value: dimColor, range: pipeRange)
                } else {
                    textStorage.addAttribute(.foregroundColor, value: NSColor.clear, range: pipeRange)
                }
            }
        }

        // Store column info for grid drawing
        let columnCount = max(pipeOffsets.count - 1, 1)
        let info = TableColumnInfo(columnCount: columnCount, pipeOffsets: pipeOffsets)
        textStorage.addAttribute(.tableColumnInfo, value: info, range: lineRange)
    }

    // MARK: - Code block detection

    private func isInsideCodeBlock(fullText: String, range: NSRange) -> Bool {
        let nsString = fullText as NSString
        let beforeRange = NSRange(location: 0, length: range.location)
        let before = nsString.substring(with: beforeRange)
        let fenceCount = before.components(separatedBy: "```").count - 1
        return fenceCount % 2 == 1
    }

    // MARK: - Frontmatter range detection

    private func frontmatterRange(in text: String) -> NSRange? {
        let nsString = text as NSString
        guard nsString.length >= 3 else { return nil }
        let firstLine = nsString.lineRange(for: NSRange(location: 0, length: 0))
        let firstLineText = nsString.substring(with: firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
        guard firstLineText == "---" else { return nil }
        let searchStart = NSMaxRange(firstLine)
        guard searchStart < nsString.length else { return nil }
        let searchRange = NSRange(location: searchStart, length: nsString.length - searchStart)
        let closingRange = nsString.range(of: "---", options: [], range: searchRange)
        guard closingRange.location != NSNotFound else { return nil }
        let closingLineRange = nsString.lineRange(for: closingRange)
        return NSRange(location: 0, length: NSMaxRange(closingLineRange))
    }
}

// MARK: - Custom attributes

extension NSAttributedString.Key {
    static let blockquoteBar = NSAttributedString.Key("blockquoteBar")
    static let codeBlock = NSAttributedString.Key("codeBlock")
    static let inlineCode = NSAttributedString.Key("inlineCode")
    static let dividerLine = NSAttributedString.Key("dividerLine")
    static let markdownLink = NSAttributedString.Key("markdownLink")
    static let wikiLink = NSAttributedString.Key("wikiLink")
    static let taskCheckbox = NSAttributedString.Key("taskCheckbox")
    static let tableRow = NSAttributedString.Key("tableRow")
    static let tableSeparator = NSAttributedString.Key("tableSeparator")
    static let tableColumnInfo = NSAttributedString.Key("tableColumnInfo")
    static let tableCollapsed = NSAttributedString.Key("tableCollapsed")
}

// MARK: - Table column info

class TableColumnInfo: NSObject {
    let columnCount: Int
    let pipeOffsets: [Int] // character offsets of | chars within the line

    init(columnCount: Int, pipeOffsets: [Int]) {
        self.columnCount = columnCount
        self.pipeOffsets = pipeOffsets
    }
}

// MARK: - Layout manager

final class MarkdownLayoutManager: NSLayoutManager {
}
