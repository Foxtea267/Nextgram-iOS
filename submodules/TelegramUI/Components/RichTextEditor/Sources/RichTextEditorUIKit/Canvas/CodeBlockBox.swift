#if canImport(UIKit)
import UIKit
import RichTextEditorCore

/// One code block in the canvas: a monospace TextKit layout (multi-line; interior "\n"s) drawn inside a
/// filled rounded-rect background with an optional language label. Mirrors `BlockBox` but is a distinct
/// `Block.code` type and builds its own monospace attributed string (so no `ParagraphStyleName`/StyleSheet
/// change). Inline formatting is not represented inside a code block — runs are plain.
@available(iOS 13.0, *)
final class CodeBlockBox {
    let id: BlockID
    var language: String?
    let layout: BlockLayoutEngine
    let mapper: AttributedStringMapper

    var frame: CGRect = .zero
    var globalStart: Int = 0
    /// Host placeholder strings (stamped by the canvas in `stampListMarkers`). Drives the empty-code hint.
    var placeholders: RichTextEditorPlaceholders = .default
    /// Fallback interior top/bottom padding (points) when the host hasn't set a quote top/bottom inset.
    static let defaultVerticalInset: CGFloat = 8
    /// Monospace point size — matches the quote's 15pt so a code block reads at the same scale as a quote.
    static let fontSize: CGFloat = 15
    /// Interior LEFT padding (bar→text gap): the quote's leading indent, so code text clears the shared
    /// accent bar exactly like quote text. Read live from the quote StyleSheet (host-tunable via QuoteStyle).
    var leftInset: CGFloat { mapper.styleSheet.quoteIndent }
    /// Interior RIGHT padding: the quote's trailing inset — the text container narrows; the fill spans full width.
    var rightInset: CGFloat { mapper.styleSheet.quoteTrailingInset }
    var topInset: CGFloat = CodeBlockBox.defaultVerticalInset
    var bottomInset: CGFloat = CodeBlockBox.defaultVerticalInset

    static func codeAttributes() -> [NSAttributedString.Key: Any] {
        let ps = NSMutableParagraphStyle()
        ps.lineBreakMode = .byWordWrapping
        return [.font: UIFont.monospacedSystemFont(ofSize: CodeBlockBox.fontSize, weight: .regular),
                .paragraphStyle: ps]
    }

    static func attributedString(for code: CodeBlock) -> NSAttributedString {
        NSAttributedString(string: code.text, attributes: codeAttributes())
    }

    init(code: CodeBlock, mapper: AttributedStringMapper, width: CGFloat) {
        self.id = code.id
        self.language = code.language
        self.mapper = mapper
        self.topInset = mapper.styleSheet.quoteTopInset ?? CodeBlockBox.defaultVerticalInset
        self.bottomInset = mapper.styleSheet.quoteBottomInset ?? CodeBlockBox.defaultVerticalInset
        self.layout = makeBlockLayout(attributedString: CodeBlockBox.attributedString(for: code),
                                      width: max(width - mapper.styleSheet.quoteIndent - mapper.styleSheet.quoteTrailingInset, 1))
    }

    var length: Int { layout.length }
    var textOrigin: CGPoint { CGPoint(x: frame.minX + leftInset, y: frame.minY + topInset) }

    private var emptyLineHeight: CGFloat {
        guard layout.length == 0 else { return 0 }
        return ((CodeBlockBox.codeAttributes()[.font] as? UIFont) ?? UIFont.monospacedSystemFont(ofSize: CodeBlockBox.fontSize, weight: .regular)).lineHeight
    }

    /// Placeholder text for an empty code block, or nil when non-empty or the placeholder string is empty.
    var placeholderText: String? {
        guard layout.length == 0, !placeholders.codeBlock.isEmpty else { return nil }
        return placeholders.codeBlock
    }

    func currentCode() -> CodeBlock {
        CodeBlock(id: id, language: language, runs: [TextRun(text: layout.attributedString.string)])
    }
}

@available(iOS 13.0, *)
extension CodeBlockBox: CanvasBlock {
    var rendersAsBlockView: Bool { true }
    var nodeStart: Int { get { globalStart } set { globalStart = newValue } }
    var nodeSize: Int { length + 2 }
    var textLayout: BlockLayoutEngine { layout }
    var textStart: Int { globalStart }
    var textLength: Int { length }
    var textRef: TextNodeRef { .code(id) }
    var height: CGFloat { max(layout.boundingHeight, emptyLineHeight) + topInset + bottomInset }
    func measuredHeight(forWidth width: CGFloat) -> CGFloat {
        max(layout.boundingHeight(forWidth: max(width - leftInset - rightInset, 1)), emptyLineHeight) + topInset + bottomInset
    }
    func setWidth(_ width: CGFloat) { layout.setWidth(max(width - leftInset - rightInset, 1)) }
    func currentBlock() -> Block { .code(currentCode()) }
    func closestPosition(toCanvasPoint point: CGPoint) -> Int {
        textStart + layout.closestOffset(toPoint: CGPoint(x: point.x - textOrigin.x, y: point.y - textOrigin.y))
    }
    func leafRegions() -> [LeafTextRegion] {
        [LeafTextRegion(layout: layout, globalStart: globalStart, length: length,
                        ref: .code(id), canvasOrigin: textOrigin,
                        emptyLineLeadingIndent: 0, emptyLineHeight: emptyLineHeight)]
    }
    func draw(in ctx: CGContext, imageProvider: (String) -> UIImage?) {
        // Background (accent bar + tinted fill) is painted by the shared `BlockquoteUnderlay` — the same
        // way quotes render — via the `CodeBlockBox` case in `blockquoteDecorations()`. The backing view
        // stays clear; here we draw only the monospace text and the optional language label.
        layout.drawText(in: ctx, at: textOrigin)
        if let ph = placeholderText {
            NSAttributedString(string: ph, attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: CodeBlockBox.fontSize, weight: .regular),
                .foregroundColor: mapper.theme.containerPlaceholder
            ]).draw(at: textOrigin)
        }
        if let lang = language, !lang.isEmpty {
            NSAttributedString(string: lang, attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: mapper.theme.containerPlaceholder
            ]).draw(at: CGPoint(x: frame.maxX - 8 - 40, y: frame.minY + 2))
        }
    }
}
#endif
