#if canImport(UIKit)
import UIKit
import RichTextEditorCore

/// Resolves a paragraph style name to concrete fonts/paragraph layout (UIKit-only, hence here
/// rather than in Core).
@available(iOS 13.0, *)
public struct StyleSheet {
    public init() {}
    public static let `default` = StyleSheet()
    /// A style sheet for content inside table cells: the body base size is reduced from the
    /// document's 17pt to 15pt (quotes are already a fixed 15pt; headings and captions keep their
    /// fixed sizes), so a table reads denser than surrounding body text. Selected per-cell via
    /// `AttributedStringMapper.tableCellVariant()`.
    public static let tableCells: StyleSheet = { var s = StyleSheet(); s.bodyBaseSize = 15; return s }()

    /// Base point size for body paragraphs — 17pt in the document body, 15pt inside table
    /// cells (see `tableCells`). Quotes (fixed 15pt), headings, and captions are independent of this.
    public var bodyBaseSize: CGFloat = 17
    /// Render-only line-height multiple for body & caption paragraphs. Default 1.10 (the reference
    /// document look); a compact host (the chat composer) sets 1.0 so text reads tight like a plain text
    /// field. An explicit per-paragraph `lineHeightMultiple` in the model still overrides this. Host-set
    /// via `RichTextEditorView.textLayoutMetrics`.
    public var bodyLineHeightMultiple: CGFloat = 1.10
    /// Paragraph spacing above each body & caption paragraph, in points. Default 0. Host-set via
    /// `RichTextEditorView.textLayoutMetrics`.
    public var bodyParagraphSpacingBefore: CGFloat = 0
    /// Paragraph spacing below each body & caption paragraph, in points. Default 8 (the document
    /// inter-paragraph gap); a compact host sets 0 so multi-line composer text reads tight. Host-set via
    /// `RichTextEditorView.textLayoutMetrics`.
    public var bodyParagraphSpacingAfter: CGFloat = 8
    /// Leading indent (points) of a quote paragraph's text past its fill's left edge — the gap that
    /// holds the quote bar. Default 16 (the reference design). Per-host via `QuoteStyle.leadingInset`.
    public var quoteIndent: CGFloat = 16
    /// Interior right padding (points) of a quote: the text container is narrowed by this so text wraps
    /// before the fill's trailing edge (the fill still spans the full content width). Default 0.
    /// Consumed by `BlockBox` (Task 2). Per-host via `QuoteStyle.trailingInset`.
    public var quoteTrailingInset: CGFloat = 0
    /// Paragraph spacing above each quote paragraph (points). Default 8. Per-host via `QuoteStyle.spacingBefore`.
    public var quoteSpacingBefore: CGFloat = 8
    /// Paragraph spacing below each quote paragraph (points). Default 8. Per-host via `QuoteStyle.spacingAfter`.
    public var quoteSpacingAfter: CGFloat = 8
    /// Interior TOP padding (points) of a top-level quote run — the gap between the fill's top edge and
    /// the first text line. `nil` (default) keeps the block-inset-derived value; a value overrides the
    /// quote block's `topInset` at the run's top edge (applied in `BlockStack.layout`). Per-host via
    /// `QuoteStyle.topInset`.
    public var quoteTopInset: CGFloat?
    /// Interior BOTTOM padding (points) of a top-level quote run — the gap between the last text line and
    /// the fill's bottom edge. `nil` (default) keeps the current behavior. Per-host via `QuoteStyle.bottomInset`.
    public var quoteBottomInset: CGFloat?

    /// Points of indentation per list nesting level (where each level's marker hangs).
    public static let listIndentStep: CGFloat = 24
    /// Horizontal gap reserved between a list marker and its text — the text hangs this far past the
    /// marker's column. Half the per-level indent step, so it's decoupled from nesting depth.
    public static let listMarkerSpacing: CGFloat = listIndentStep / 2
    /// Extra text inset applied to ORDERED (numbered) list items on top of `listMarkerSpacing`. A
    /// number marker ("1.", "iii.") is much wider than a bullet, so its text needs more breathing room
    /// after the marker than a bullet's does. The marker itself stays in its level's column; only the
    /// item text shifts right by this amount.
    public static let orderedListTextInset: CGFloat = 4
    /// The side length of the checklist checkbox, sized to the font's cap height so it scales per style
    /// and reads like a capital letter sitting on the baseline. (Tunable: switch capHeight→ascender for a
    /// larger box.) Returns the UNSCALED base — the vertical-center anchor used by both the geometry and
    /// the paragraph-indent computation.
    public static func checklistMarkerSize(for font: UIFont) -> CGFloat { font.capHeight.rounded() }
    /// Horizontal gap between the checkbox's right edge and the item text.
    public static let checklistMarkerGap: CGFloat = 6
    /// The checklist checkbox is drawn this many times its base (cap-height) size — it grows into the top,
    /// bottom, and right (the left edge stays anchored at the marker gutter). Tunable.
    public static let checklistMarkerScale: CGFloat = 1.4

    private func baseSize(_ style: ParagraphStyleName) -> CGFloat {
        switch style {
        case .heading1: return 24
        case .heading2: return 21
        case .heading3: return 19
        case .heading4: return 18
        case .heading5: return 17
        case .heading6: return 16
        case .body: return bodyBaseSize
        case .caption: return 15
        case .pullQuote: return 15   // pull quotes read at 15pt (like block quotes), not the ambient body size
        }
    }

    /// Render-only per-style spacing/line-height (model values are 0/1.0). Validated against the reference design.
    private struct StyleMetrics { var spacingBefore: CGFloat; var spacingAfter: CGFloat; var lineHeightMultiple: CGFloat }
    private func metrics(for style: ParagraphStyleName) -> StyleMetrics {
        switch style {
        case .heading1: return StyleMetrics(spacingBefore: 18, spacingAfter: 6, lineHeightMultiple: 1.05)
        case .heading2: return StyleMetrics(spacingBefore: 16, spacingAfter: 6, lineHeightMultiple: 1.05)
        case .heading3: return StyleMetrics(spacingBefore: 14, spacingAfter: 6, lineHeightMultiple: 1.05)
        case .heading4: return StyleMetrics(spacingBefore: bodyParagraphSpacingBefore, spacingAfter: bodyParagraphSpacingAfter, lineHeightMultiple: bodyLineHeightMultiple)
        case .heading5: return StyleMetrics(spacingBefore: bodyParagraphSpacingBefore, spacingAfter: bodyParagraphSpacingAfter, lineHeightMultiple: bodyLineHeightMultiple)
        case .heading6: return StyleMetrics(spacingBefore: bodyParagraphSpacingBefore, spacingAfter: bodyParagraphSpacingAfter, lineHeightMultiple: bodyLineHeightMultiple)
        case .body:     return StyleMetrics(spacingBefore: bodyParagraphSpacingBefore, spacingAfter: bodyParagraphSpacingAfter, lineHeightMultiple: bodyLineHeightMultiple)
        case .caption:  return StyleMetrics(spacingBefore: bodyParagraphSpacingBefore, spacingAfter: bodyParagraphSpacingAfter, lineHeightMultiple: bodyLineHeightMultiple)
        // Pull quote: tight, no inter-paragraph spacing (box insets provide padding); runs read close together.
        case .pullQuote: return StyleMetrics(spacingBefore: 0, spacingAfter: 0, lineHeightMultiple: 1.10)
        }
    }

    public func font(for style: ParagraphStyleName, attributes: CharacterAttributes) -> UIFont {
        let size = attributes.fontSize.map { CGFloat($0) } ?? baseSize(style)
        // Headings are NOT bold by default — they read as regular-weight serif at a larger size.
        // Bold is purely user emphasis (`CharacterAttributes.bold`), so it stays an independent toggle
        // that round-trips uniformly in every style (no style-injected weight to leak into the model).
        let bold = attributes.bold
        // Pull quotes force italic render — the italic is ambient (render-only), stripped on read-back.
        let italic = attributes.italic || style == .pullQuote
        let serif = style == .heading1 || style == .heading2 || style == .heading3 || style == .heading4 || style == .heading5 || style == .heading6
        return FontResolver.font(family: attributes.fontFamily, size: size, bold: bold, italic: italic, serif: serif)
    }

    public func paragraphStyle(for style: ParagraphStyleName, attributes: ParagraphAttributes,
                               list: ListMembership? = nil,
                               baseWritingDirection: NSWritingDirection = .natural) -> NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        switch attributes.alignment {
        case .natural: ps.alignment = .natural
        case .left: ps.alignment = .left
        case .center: ps.alignment = .center
        case .right: ps.alignment = .right
        case .justified: ps.alignment = .justified
        }
        // Pull quotes always render centered regardless of the user's alignment setting.
        if style == .pullQuote { ps.alignment = .center }
        ps.baseWritingDirection = baseWritingDirection
        ps.firstLineHeadIndent = CGFloat(attributes.firstLineIndent)
        ps.headIndent = CGFloat(attributes.headIndent)
        ps.paragraphSpacingBefore = CGFloat(attributes.paragraphSpacingBefore)
        ps.paragraphSpacing = CGFloat(attributes.paragraphSpacingAfter)
        ps.lineHeightMultiple = CGFloat(attributes.lineHeightMultiple)
        let m = metrics(for: style)
        ps.paragraphSpacingBefore += m.spacingBefore
        ps.paragraphSpacing += m.spacingAfter
        if ps.lineHeightMultiple == 1 { ps.lineHeightMultiple = m.lineHeightMultiple }
        var indent: CGFloat = 0
        if let list = list {
            // Marker sits at the level's indent; text hangs `listMarkerSpacing` past it. Ordered
            // (numbered) items get extra text inset since a number marker is wider than a bullet.
            indent += StyleSheet.listIndentStep * CGFloat(list.level) + StyleSheet.listMarkerSpacing
            if list.marker == .ordered { indent += StyleSheet.orderedListTextInset }
            else if list.marker == .checklist {
                let markerFont = self.font(for: style, attributes: .plain)
                let scaledSide = StyleSheet.checklistMarkerSize(for: markerFont) * StyleSheet.checklistMarkerScale
                indent += max(0, scaledSide + StyleSheet.checklistMarkerGap - StyleSheet.listMarkerSpacing)
            }
        }
        ps.firstLineHeadIndent += indent
        ps.headIndent += indent
        return ps
    }
}
#endif
