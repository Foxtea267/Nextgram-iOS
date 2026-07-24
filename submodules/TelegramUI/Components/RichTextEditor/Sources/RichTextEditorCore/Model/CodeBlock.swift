import Foundation

/// A fenced code block (Telegram `.Pre`): one block holding multi-line text (interior "\n"s) plus an
/// optional language. Unlike a paragraph, its runs may contain "\n" — the whole block is one editable
/// unit. Inline formatting is not represented inside a code block (a `.Pre` carries no nested entities),
/// so its runs are plain text.
public struct CodeBlock: Codable, Equatable {
    public var id: BlockID
    public var language: String?
    public var runs: [TextRun]

    public init(id: BlockID, language: String? = nil, runs: [TextRun] = []) {
        self.id = id
        self.language = language
        self.runs = runs
    }

    /// The plain text of the block (runs concatenated; may contain "\n").
    public var text: String { runs.map(\.text).joined() }

    /// Total UTF-16 length of the block's text.
    public var utf16Count: Int { runs.reduce(0) { $0 + $1.utf16Count } }
}
