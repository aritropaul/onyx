import Foundation

struct ParsedTable {
    let fullRange: NSRange
    let headerRange: NSRange
    let separatorRange: NSRange
    let dataRange: NSRange
    let headers: [CellInfo]
    let alignments: [Alignment]
    let rows: [[CellInfo]]

    struct CellInfo {
        let text: String          // trimmed cell content
        let storageRange: NSRange // range in NSTextStorage (content between pipes)
    }

    enum Alignment {
        case left, center, right
    }
}

final class TableParser {

    private static let tablePattern = try! NSRegularExpression(
        pattern: "^(\\|.+\\|)\\n(\\|[-:| ]+\\|)\\n((?:\\|.+\\|\\n?)+)",
        options: .anchorsMatchLines
    )

    static func parse(in text: String) -> [ParsedTable] {
        let nsStr = text as NSString
        let fullRange = NSRange(location: 0, length: nsStr.length)
        var tables: [ParsedTable] = []

        tablePattern.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match = match else { return }

            let headerRange = match.range(at: 1)
            let sepRange = match.range(at: 2)
            let dataRange = match.range(at: 3)

            // Parse header cells
            let headerLine = nsStr.substring(with: headerRange)
            let headers = parseCells(headerLine, lineStart: headerRange.location)

            // Parse alignments from separator
            let sepLine = nsStr.substring(with: sepRange)
            let alignments = parseAlignments(sepLine, columnCount: headers.count)

            // Parse data rows
            let dataText = nsStr.substring(with: dataRange)
            var rows: [[ParsedTable.CellInfo]] = []
            var lineStart = dataRange.location
            for line in dataText.components(separatedBy: "\n") {
                guard !line.isEmpty else { lineStart += 1; continue }
                let cells = parseCells(line, lineStart: lineStart)
                if !cells.isEmpty { rows.append(cells) }
                lineStart += (line as NSString).length + 1
            }

            tables.append(ParsedTable(
                fullRange: match.range,
                headerRange: headerRange,
                separatorRange: sepRange,
                dataRange: dataRange,
                headers: headers,
                alignments: alignments,
                rows: rows
            ))
        }

        return tables
    }

    private static func parseCells(_ line: String, lineStart: Int) -> [ParsedTable.CellInfo] {
        var cells: [ParsedTable.CellInfo] = []
        let trimmed = line.trimmingCharacters(in: .newlines)
        guard trimmed.hasPrefix("|") && trimmed.hasSuffix("|") else { return [] }

        // Find pipe positions
        var pipePositions: [Int] = []
        for (i, ch) in trimmed.enumerated() {
            if ch == "|" { pipePositions.append(i) }
        }

        // Extract cells between consecutive pipes
        for i in 0..<pipePositions.count - 1 {
            let start = pipePositions[i] + 1
            let end = pipePositions[i + 1]
            guard end > start else {
                cells.append(ParsedTable.CellInfo(text: "", storageRange: NSRange(location: lineStart + start, length: 0)))
                continue
            }
            let cellContent = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: start)..<trimmed.index(trimmed.startIndex, offsetBy: end)])
            let trimmedContent = cellContent.trimmingCharacters(in: .whitespaces)
            cells.append(ParsedTable.CellInfo(
                text: trimmedContent,
                storageRange: NSRange(location: lineStart + start, length: end - start)
            ))
        }

        return cells
    }

    private static func parseAlignments(_ sepLine: String, columnCount: Int) -> [ParsedTable.Alignment] {
        let cells = sepLine.trimmingCharacters(in: .newlines)
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return (0..<columnCount).map { i in
            guard i < cells.count else { return .left }
            let cell = cells[i]
            let startsColon = cell.hasPrefix(":")
            let endsColon = cell.hasSuffix(":")
            if startsColon && endsColon { return .center }
            if endsColon { return .right }
            return .left
        }
    }
}
