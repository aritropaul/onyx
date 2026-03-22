import Foundation

enum InlineStyle: String, Codable, Hashable {
    case bold, italic, code, strikethrough
}

struct InlineSpan: Codable, Equatable {
    var text: String
    var styles: Set<InlineStyle>
    var link: String?
    var wikiLink: String?

    init(text: String, styles: Set<InlineStyle> = [], link: String? = nil, wikiLink: String? = nil) {
        self.text = text
        self.styles = styles
        self.link = link
        self.wikiLink = wikiLink
    }

    static func plain(_ text: String) -> InlineSpan {
        InlineSpan(text: text)
    }
}
