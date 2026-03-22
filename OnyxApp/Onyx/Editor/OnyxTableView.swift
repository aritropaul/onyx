import AppKit

final class OnyxTableView: NSView {

    var tableData: ParsedTable?
    var onCellClicked: ((NSRange) -> Void)?

    // Theme
    private let headerFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    private let bodyFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    private let textColor = NSColor.white.withAlphaComponent(0.85)
    private let headerBgColor = NSColor.white.withAlphaComponent(0.06)
    private let tableBgColor = NSColor.white.withAlphaComponent(0.03)
    private let borderColor = NSColor.white.withAlphaComponent(0.08)
    private let gridColor = NSColor.white.withAlphaComponent(0.06)
    private let cellPadding: CGFloat = 8
    private let rowPadding: CGFloat = 6

    // Computed layout
    private var columnWidths: [CGFloat] = []
    private var rowHeights: [CGFloat] = []
    private var headerHeight: CGFloat = 0

    override var isFlipped: Bool { true }

    func configure(with table: ParsedTable, availableWidth: CGFloat) {
        self.tableData = table
        computeLayout(availableWidth: availableWidth)
        let totalHeight = headerHeight + rowHeights.reduce(0, +)
        self.frame.size = NSSize(width: availableWidth, height: totalHeight)
    }

    // MARK: - Layout computation

    private func computeLayout(availableWidth: CGFloat) {
        guard let table = tableData else { return }

        let columnCount = table.headers.count
        guard columnCount > 0 else { return }

        // Measure natural content widths
        var maxContentWidths = Array(repeating: CGFloat(0), count: columnCount)
        for (i, header) in table.headers.enumerated() {
            let w = measureText(header.text, font: headerFont).width + cellPadding * 2
            maxContentWidths[i] = max(maxContentWidths[i], w)
        }
        for row in table.rows {
            for (i, cell) in row.enumerated() where i < columnCount {
                let w = measureText(cell.text, font: bodyFont).width + cellPadding * 2
                maxContentWidths[i] = max(maxContentWidths[i], w)
            }
        }

        // Distribute widths proportionally to available space
        let totalNatural = maxContentWidths.reduce(0, +)
        if totalNatural > 0 && totalNatural > availableWidth {
            // Scale down proportionally, with minimum 60pt per column
            let minWidth: CGFloat = 60
            let totalMin = minWidth * CGFloat(columnCount)
            let distributable = max(0, availableWidth - totalMin)
            let totalExcess = totalNatural - totalMin
            columnWidths = maxContentWidths.map { w in
                if totalExcess > 0 {
                    return minWidth + (w - minWidth) / totalExcess * distributable
                }
                return availableWidth / CGFloat(columnCount)
            }
        } else if totalNatural > 0 {
            // Expand proportionally to fill available width
            let scale = availableWidth / totalNatural
            columnWidths = maxContentWidths.map { $0 * scale }
        } else {
            columnWidths = Array(repeating: availableWidth / CGFloat(columnCount), count: columnCount)
        }

        // Compute header height
        headerHeight = computeRowHeight(cells: table.headers.map { $0.text }, font: headerFont)

        // Compute data row heights
        rowHeights = table.rows.map { row in
            computeRowHeight(cells: row.map { $0.text }, font: bodyFont)
        }
    }

    private func computeRowHeight(cells: [String], font: NSFont) -> CGFloat {
        var maxH: CGFloat = font.pointSize + rowPadding * 2
        for (i, text) in cells.enumerated() where i < columnWidths.count {
            let constraintWidth = columnWidths[i] - cellPadding * 2
            let textHeight = measureText(text, font: font, constrainedWidth: max(20, constraintWidth)).height
            maxH = max(maxH, textHeight + rowPadding * 2)
        }
        return ceil(maxH)
    }

    private func measureText(_ text: String, font: NSFont, constrainedWidth: CGFloat = .greatestFiniteMagnitude) -> NSSize {
        guard !text.isEmpty else { return NSSize(width: 0, height: font.pointSize) }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let str = NSAttributedString(string: text, attributes: attrs)
        let rect = str.boundingRect(
            with: NSSize(width: constrainedWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return NSSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let table = tableData else { return }

        let bounds = self.bounds

        // Outer background
        tableBgColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()

        // Outer border
        borderColor.setStroke()
        let borderPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        borderPath.lineWidth = 1
        borderPath.stroke()

        // Header background
        let headerRect = NSRect(x: 1, y: 0, width: bounds.width - 2, height: headerHeight)
        headerBgColor.setFill()
        let headerPath = NSBezierPath(roundedRect: headerRect, xRadius: 5, yRadius: 5)
        headerPath.fill()

        // Draw header cells
        var x: CGFloat = 0
        for (i, header) in table.headers.enumerated() where i < columnWidths.count {
            let cellRect = NSRect(x: x + cellPadding, y: rowPadding, width: columnWidths[i] - cellPadding * 2, height: headerHeight - rowPadding * 2)
            drawText(header.text, in: cellRect, font: headerFont, alignment: table.alignments[safe: i] ?? .left)
            x += columnWidths[i]
        }

        // Header bottom border (slightly thicker)
        borderColor.setStroke()
        let headerBottomPath = NSBezierPath()
        headerBottomPath.move(to: NSPoint(x: 1, y: headerHeight))
        headerBottomPath.line(to: NSPoint(x: bounds.width - 1, y: headerHeight))
        headerBottomPath.lineWidth = 1.5
        headerBottomPath.stroke()

        // Draw data rows
        var y = headerHeight
        for (rowIdx, row) in table.rows.enumerated() {
            let rowH = rowHeights[safe: rowIdx] ?? 28
            x = 0
            for (colIdx, cell) in row.enumerated() where colIdx < columnWidths.count {
                let cellRect = NSRect(x: x + cellPadding, y: y + rowPadding, width: columnWidths[colIdx] - cellPadding * 2, height: rowH - rowPadding * 2)
                drawText(cell.text, in: cellRect, font: bodyFont, alignment: table.alignments[safe: colIdx] ?? .left)
                x += columnWidths[colIdx]
            }

            // Horizontal grid line below this row
            if rowIdx < table.rows.count - 1 {
                gridColor.setStroke()
                let gridPath = NSBezierPath()
                gridPath.move(to: NSPoint(x: 1, y: y + rowH))
                gridPath.line(to: NSPoint(x: bounds.width - 1, y: y + rowH))
                gridPath.lineWidth = 1
                gridPath.stroke()
            }

            y += rowH
        }

        // Vertical grid lines
        x = 0
        for i in 0..<columnWidths.count - 1 {
            x += columnWidths[i]
            gridColor.setStroke()
            let gridPath = NSBezierPath()
            gridPath.move(to: NSPoint(x: x, y: 1))
            gridPath.line(to: NSPoint(x: x, y: bounds.height - 1))
            gridPath.lineWidth = 1
            gridPath.stroke()
        }
    }

    private func drawText(_ text: String, in rect: NSRect, font: NSFont, alignment: ParsedTable.Alignment) {
        let paraStyle = NSMutableParagraphStyle()
        switch alignment {
        case .left: paraStyle.alignment = .left
        case .center: paraStyle.alignment = .center
        case .right: paraStyle.alignment = .right
        }
        paraStyle.lineBreakMode = .byWordWrapping

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paraStyle
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        str.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    // MARK: - Click handling

    override func mouseDown(with event: NSEvent) {
        guard let table = tableData else { super.mouseDown(with: event); return }

        let point = convert(event.locationInWindow, from: nil)

        // Find which cell was clicked
        var y: CGFloat = 0

        // Check header
        if point.y < headerHeight {
            var x: CGFloat = 0
            for (i, header) in table.headers.enumerated() where i < columnWidths.count {
                if point.x >= x && point.x < x + columnWidths[i] {
                    onCellClicked?(header.storageRange)
                    return
                }
                x += columnWidths[i]
            }
        }

        y = headerHeight
        for (rowIdx, row) in table.rows.enumerated() {
            let rowH = rowHeights[safe: rowIdx] ?? 28
            if point.y >= y && point.y < y + rowH {
                var x: CGFloat = 0
                for (colIdx, cell) in row.enumerated() where colIdx < columnWidths.count {
                    if point.x >= x && point.x < x + columnWidths[colIdx] {
                        onCellClicked?(cell.storageRange)
                        return
                    }
                    x += columnWidths[colIdx]
                }
            }
            y += rowH
        }

        super.mouseDown(with: event)
    }
}

// MARK: - Safe array subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        index >= 0 && index < count ? self[index] : nil
    }
}
