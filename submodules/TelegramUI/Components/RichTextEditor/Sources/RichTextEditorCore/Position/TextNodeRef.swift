import Foundation

/// Identifies an editable text node so a global position can be mapped back to model text.
public enum TextNodeRef: Equatable {
    /// The runs of a paragraph block (top-level or inside a table cell).
    case paragraph(BlockID)
    /// The caption runs of a media block.
    case caption(BlockID)
    /// The runs of a code block.
    case code(BlockID)
    /// The runs of a pull quote block.
    case pullQuote(BlockID)
    /// The author (attribution) runs of a block quote or pull quote.
    case quoteAuthor(BlockID)
}
