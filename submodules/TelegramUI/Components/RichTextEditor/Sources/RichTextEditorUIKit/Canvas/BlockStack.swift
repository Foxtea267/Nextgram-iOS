#if canImport(UIKit)
import UIKit
import RichTextEditorCore

/// A vertical run of `CanvasBlock`s — the shared engine for the document body and for each table
/// cell. Owns span math (relative to a `baseOffset`) and vertical layout (relative to an origin).
@available(iOS 13.0, *)
final class BlockStack {
    var boxes: [CanvasBlock]
    private(set) var baseOffset: Int = 0
    private(set) var contentHeight: CGFloat = 0

    init(boxes: [CanvasBlock] = []) { self.boxes = boxes }

    /// Assigns each box's `nodeStart` (= running tokens + 1, relative to `baseOffset`) and returns
    /// the stack's total token size.
    @discardableResult
    func recompute(baseOffset: Int) -> Int {
        self.baseOffset = baseOffset
        var pos = baseOffset
        for box in boxes {
            box.nodeStart = pos + 1
            pos += box.nodeSize
        }
        return pos - baseOffset
    }

    /// Extra inset a block reserves on the side facing a block that draws its own bounded background or
    /// border — a quote's fill, a collapsed quote's fill, a code block's fill, or a table's grid — so that
    /// framed block has visible separation from its neighbors. Lives on the neighbor (external to the framed
    /// block), since a quote/code/table fills its own frame; the framed block's own inset is its internal padding.
    private static let framedNeighborMargin: CGFloat = 8

    /// The external inset any block reserves on the side facing an adjacent media (image/video/audio/
    /// location) block — the body↔image spacing rule. Kept as its own constant, DECOUPLED from
    /// `verticalInsetBase` (the inter-paragraph gap), so tuning body↔body spacing never moves body↔image.
    /// The media block itself keeps its own internal `MediaBlockBox.verticalInset` padding around the image.
    private static let mediaNeighborInset: CGFloat = 6

    /// A block that draws its own bounded fill and is NOT a `BlockBox`, so `facingInset` never runs for
    /// it: a code block, a table, a pull quote, or a block-quote box. Its own top/bottom insets are INTERNAL
    /// padding (fill→text), not external margin — so two of these adjacent would sit with their fills flush.
    private static func isFramedAtom(_ box: CanvasBlock) -> Bool {
        box is CodeBlockBox || box is TableBlockBox || box is PullQuoteBox || box is BlockQuoteBox
    }

    /// The inset for `box` on the side facing `neighbor` (or the stack edge, when nil). The facing
    /// insets of two adjacent blocks together make their gap: list items stack tight (0); two body
    /// paragraphs sit at half the default; a block facing a quote or table reserves extra margin;
    /// otherwise the default.
    /// The base inter-block vertical inset (each side; two facing insets make a gap). Defaults to the
    /// document metric (`BlockBox.defaultVerticalInset`, 8pt). A compact host (chat composer) sets the root
    /// stack's base to 0 so a lone paragraph hugs its text height; nested (table-cell) stacks keep the default.
    var verticalInsetBase: CGFloat = BlockBox.defaultVerticalInset

    private func facingInset(of box: BlockBox, toward neighbor: CanvasBlock?) -> CGFloat {
        let base = self.verticalInsetBase
        // A table, a code block, a pull quote, and a block-quote box all draw their own bounded fill,
        // so a neighbor reserves extra framed margin for visible separation.
        if neighbor is TableBlockBox || neighbor is CodeBlockBox || neighbor is PullQuoteBox || neighbor is BlockQuoteBox { return base + BlockStack.framedNeighborMargin }
        // Any block facing a media (image/video/audio/location) block uses the dedicated body↔image inset,
        // independent of `base`. (Media is not a `BlockBox`, so it would otherwise fall through to `base`.)
        if neighbor is MediaBlockBox { return BlockStack.mediaNeighborInset }
        guard let n = neighbor as? BlockBox else { return base }
        // Two list items stack tight (0).
        if box.listMembership != nil && n.listMembership != nil { return 0 }
        // Any two adjacent body-style flow boxes stack tight (no inter-paragraph gap) — this covers a plain
        // body↔body pair, a body↔list-item boundary, and body-styled list items. The visible break is the
        // line advance alone, not a block inset. The document's outer top/bottom margins are unaffected
        // (they face a nil neighbor → `base`), and non-body flows (headings, quotes) keep `base`.
        if box.style == .body && n.style == .body { return 0 }
        return base
    }

    /// Lays boxes out top-to-bottom from `origin` at the given content `width`; returns total height.
    @discardableResult
    func layout(origin: CGPoint, width: CGFloat) -> CGFloat {
        var y = origin.y
        for i in boxes.indices {
            let box = boxes[i]
            if let b = box as? BlockBox {
                let prev: CanvasBlock? = i > 0 ? boxes[i - 1] : nil
                let next: CanvasBlock? = i + 1 < boxes.count ? boxes[i + 1] : nil
                b.topInset = facingInset(of: b, toward: prev)
                b.bottomInset = facingInset(of: b, toward: next)
            }
            box.setWidth(width)
            // Two adjacent framed atoms (code / table / collapsed quote) both fill their whole frames,
            // so neither's internal padding separates the two fills. Insert an external gap between them
            // — matching the separation a `BlockBox` neighbor reserves toward a framed atom
            // (`facingInset` rule 1: base + framed margin), so it scales with the host's block inset.
            if i > 0, BlockStack.isFramedAtom(boxes[i - 1]), BlockStack.isFramedAtom(box) {
                y += self.verticalInsetBase + BlockStack.framedNeighborMargin
            }
            box.frame = CGRect(x: origin.x, y: y, width: width, height: box.height)
            y += box.height
        }
        contentHeight = y - origin.y
        return contentHeight
    }

    /// Stateless total height at content `width` — the measure analogue of `layout`'s returned height.
    /// Reads each box's structural insets (width-independent); never mutates a box. Reused by the
    /// document root and by each table cell.
    func measuredHeight(forWidth width: CGFloat) -> CGFloat {
        var total: CGFloat = 0
        for (i, box) in boxes.enumerated() {
            // Mirror the external gap `layout` inserts between two adjacent framed atoms, so the
            // stateless measure matches the laid-out height (otherwise the host sizes the field short).
            if i > 0, BlockStack.isFramedAtom(boxes[i - 1]), BlockStack.isFramedAtom(box) {
                total += self.verticalInsetBase + BlockStack.framedNeighborMargin
            }
            total += box.measuredHeight(forWidth: width)
        }
        return total
    }

    func leafRegions() -> [LeafTextRegion] { boxes.flatMap { $0.leafRegions() } }
    func draw(in ctx: CGContext, imageProvider: (String) -> UIImage?) { for b in boxes { b.draw(in: ctx, imageProvider: imageProvider) } }

    func closestPosition(toCanvasPoint point: CGPoint) -> Int {
        guard !boxes.isEmpty else { return baseOffset }
        let box = boxes.first(where: { point.y < $0.frame.maxY }) ?? boxes[boxes.count - 1]
        return box.closestPosition(toCanvasPoint: point)
    }
}
#endif
