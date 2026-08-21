#if canImport(UIKit)
import UIKit

/// One paragraph block's TextKit 2 layout context (line layout only). All geometry is returned in
/// the block's own container coordinate space (origin 0,0); the document view offsets it.
@available(iOS 16.0, *)
final class BlockLayout: BlockLayoutEngine {
    let contentStorage: NSTextContentStorage
    let layoutManager: NSTextLayoutManager
    let container: NSTextContainer

    /// `BlockLayoutEngine` accessors abstracting the TextKit 2 internals the editor used to reach directly.
    var backingStorage: NSTextStorage? { contentStorage.textStorage }
    var containerWidth: CGFloat { container.size.width }

    /// Bumped on every change that affects what `drawText` produces (storage replacement or a
    /// display-only rendering attribute). A cheap, collision-free repaint signal — see
    /// `BlockBox.renderSignature`.
    private(set) var renderVersion = 0

    // Stateless measure: a reused scratch layout of THIS engine type (same container config), re-fed
    // per call, plus a 1-entry (width, renderVersion) memo. Separate from the live stack, so measuring
    // never disturbs what is displayed.
    private var measureScratch: BlockLayout?
    private var memoWidth: CGFloat = .nan
    private var memoRenderVersion: Int = -1
    private var memoHeight: CGFloat = 0

    /// The text range the inline-prediction ghost foreground was last applied to (nil = none). Tracked so
    /// `setGhostForeground` removes only ITS OWN range instead of blanket-clearing every `.foregroundColor`
    /// rendering attribute — which would wipe a coexisting spoiler hide (both use `.foregroundColor`).
    private var ghostRange: NSTextRange?
    /// The text ranges currently hidden as spoilers (display-only clear foreground). Tracked so a re-apply
    /// removes only these before re-adding, never touching the ghost range. The two are disjoint by
    /// construction (the ghost sits at the caret, which is outside any HIDDEN spoiler — a focused spoiler is
    /// revealed, not hidden).
    private var spoilerRanges: [NSTextRange] = []
    /// The LOCAL ranges last applied by `setSpoilerHidden`, kept ONLY for the no-op equality guard below
    /// (so a re-apply with identical ranges — the common per-caret-move case — skips the renderVersion bump
    /// and the paragraph doesn't needlessly repaint). Reset alongside `spoilerRanges` on any storage edit.
    private var spoilerLocalRanges: [NSRange] = []

    /// When set, `caretRect(atOffset:)` returns the trailing-edge position for EMPTY text, so an empty
    /// RTL-keyboard paragraph shows its caret on the right before the first keystroke. nil = default (0).
    var emptyTextCaretDirection: NSWritingDirection?

    init(attributedString: NSAttributedString, width: CGFloat) {
        contentStorage = NSTextContentStorage()
        layoutManager = NSTextLayoutManager()
        container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.textContainer = container
        contentStorage.addTextLayoutManager(layoutManager)
        contentStorage.textStorage = NSTextStorage(attributedString: attributedString)
    }

    var attributedString: NSAttributedString {
        get { contentStorage.textStorage ?? NSAttributedString() }
        set {
            contentStorage.textStorage?.setAttributedString(newValue); renderVersion &+= 1
            // Reset tracked rendering ranges on a STORAGE-LENGTH change (locations shift, so a stale
            // NSTextRange could mis-remove). Attribute-only mutations (e.g. applyCharacterToggle's direct
            // bumpRenderVersion) don't shift offsets, so they intentionally skip this reset.
            ghostRange = nil; spoilerRanges = []; spoilerLocalRanges = []
        }
    }

    /// Bump the render version after mutating `contentStorage.textStorage` directly (i.e. NOT through
    /// this type's `attributedString`/`replace`). Used by the character-format/link commands so a
    /// view-backed paragraph repaints when its attributes change. See `BlockBox.renderSignature`.
    func bumpRenderVersion() { renderVersion &+= 1 }

    var length: Int { contentStorage.textStorage?.length ?? 0 }

    func setWidth(_ width: CGFloat) {
        container.size = CGSize(width: width, height: .greatestFiniteMagnitude)
    }

    /// The paragraph's render line-height multiple (uniform per block — the `StyleSheet` injects 1.05–1.10);
    /// 1 when unset/absent. TextKit adds a `lineHeightMultiple`'s extra leading entirely ABOVE the glyphs, so
    /// without compensation the text sits low in the line/selection box. See `centeringDelta`.
    private var lineHeightMultiple: CGFloat {
        guard length > 0,
              let ps = attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle,
              ps.lineHeightMultiple > 1 else { return 1 }
        return ps.lineHeightMultiple
    }

    /// Half the extra leading `lineHeightMultiple` adds to a line of box height `lineHeight` — the amount to
    /// raise the glyphs by so they CENTER in the (full-height) line box instead of sitting against its bottom.
    /// The box height that caret/selection use is left untouched, so line spacing is preserved; only the glyph
    /// VISUALS + baseline-derived geometry (`drawText`, `attachmentBox`, `firstLineBaselineFromTop`) shift up.
    /// 0 when there is no multiple. Mirrored by `BlockLayoutTK1`'s layout-manager delegate. See
    /// `LineHeightCenteringTests` and the project CLAUDE.md.
    func centeringDelta(lineHeight: CGFloat) -> CGFloat {
        let m = lineHeightMultiple
        guard m > 1, lineHeight > 0 else { return 0 }
        return lineHeight * (1 - 1 / m) / 2
    }

    var boundingHeight: CGFloat {
        var maxY: CGFloat = 0
        layoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
            maxY = max(maxY, fragment.layoutFragmentFrame.maxY)
            return true
        }
        return maxY
    }

    func boundingHeight(forWidth width: CGFloat) -> CGFloat {
        if abs(width - container.size.width) < 0.5 { return boundingHeight }   // live width → live layout
        if memoRenderVersion == renderVersion && abs(memoWidth - width) < 0.5 { return memoHeight }
        let scratch: BlockLayout
        if let s = measureScratch { scratch = s }
        else { scratch = BlockLayout(attributedString: attributedString, width: width); measureScratch = scratch }
        // The reuse is allocation-only: we re-feed the current string + width and reflow each call (a
        // different width per call is the norm). The live layout is never touched.
        scratch.attributedString = attributedString
        scratch.setWidth(width)
        let h = scratch.boundingHeight
        memoWidth = width; memoRenderVersion = renderVersion; memoHeight = h
        return h
    }

    /// Y of the first laid-out text line's baseline, relative to the top of the layout (y = 0, i.e. the
    /// block's `textOrigin.y`). `nil` when there is no laid-out line (empty text — TextKit 2 lays out no
    /// fragment). Used to align a list marker (drawn outside the text storage) to the paragraph's first
    /// line, which `lineHeightMultiple` shifts below the natural top.
    var firstLineBaselineFromTop: CGFloat? {
        var result: CGFloat?
        layoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
            guard let line = fragment.textLineFragments.first else { return true }
            // Match the centered glyph baseline (drawn `centeringDelta` higher), so a list marker aligned to
            // this value tracks the centered text rather than the raw bottom-biased baseline.
            result = fragment.layoutFragmentFrame.minY + line.glyphOrigin.y
                   - self.centeringDelta(lineHeight: line.typographicBounds.height)
            return false
        }
        return result
    }

    func textRange(_ start: Int, _ end: Int) -> NSTextRange? {
        let docStart = contentStorage.documentRange.location
        guard let s = contentStorage.location(docStart, offsetBy: start),
              let e = contentStorage.location(docStart, offsetBy: end) else { return nil }
        return NSTextRange(location: s, end: e)
    }

    func caretRect(atOffset offset: Int) -> CGRect {
        // Empty text with direction override: position caret at the trailing edge for RTL so the user sees
        // the correct insertion side before the first keystroke.
        if length == 0, emptyTextCaretDirection == .rightToLeft {
            return CGRect(x: container.size.width - 2, y: 0, width: 2, height: 20)
        }
        guard let range = textRange(offset, offset) else { return CGRect(x: 0, y: 0, width: 2, height: 20) }
        var rect = CGRect(x: 0, y: 0, width: 2, height: 20)
        // Use the `.selection` segment, NOT `.standard`: for an RTL paragraph the `.standard` segment reports
        // the caret x in a non-right-aligned coordinate (text measured from the left), so it sits left of the
        // glyphs by the line's right-alignment displacement and — worse — FREEZES the end-of-text caret on a
        // wrapped RTL line (it doesn't track the text growing leftward as you type). `.selection` is the
        // glyph-accurate geometry the selection wash already trusts (`selectionRects`/`selectionFillRects`),
        // so the caret lands exactly where the glyphs and selection highlight are. Byte-identical in LTR.
        layoutManager.enumerateTextSegments(in: range, type: .selection, options: []) { _, frame, _, _ in
            rect = CGRect(x: frame.minX, y: frame.minY, width: 2, height: max(frame.height, 20))
            return false
        }
        return rect
    }

    func selectionRects(start: Int, end: Int) -> [CGRect] {
        guard start < end, let range = textRange(start, end) else { return [] }
        var rects: [CGRect] = []
        layoutManager.enumerateTextSegments(in: range, type: .selection, options: []) { _, frame, _, _ in
            rects.append(frame)
            return true
        }
        return rects
    }

    /// Selection rects styled like UITextView for the highlight WASH (not the glyph-hugging
    /// `selectionRects` used by the OS witness / edit-menu / spoiler / marked-text geometry): a line the
    /// selection covers from its END extends to the text container's trailing edge, and a line it covers
    /// from its BEGINNING extends to the leading edge (x = 0, the container's far left) — so an indented
    /// paragraph (quote / list) fills the full width on its covered lines instead of hugging the indented
    /// glyphs. A line is covered to its end when the selection continues onto the next line (its segment
    /// isn't the last) OR it is the last segment and `fillTrailingLine` (the selection continues past this
    /// layout's last character — the block's trailing newline / next block is selected). A line is covered
    /// from its beginning for every continuation line (i > 0) and, for the first line, when the selection
    /// starts at the layout's very beginning (`start == 0`, i.e. the whole first line is covered). The line
    /// where the selection genuinely begins / ends mid-text keeps hugging the glyphs on that side.
    func selectionFillRects(start: Int, end: Int, fillTrailingLine: Bool, isRTL: Bool) -> [CGRect] {
        guard start < end, let range = textRange(start, end) else { return [] }
        let edge = container.size.width
        var segs: [CGRect] = []
        layoutManager.enumerateTextSegments(in: range, type: .selection, options: []) { _, frame, _, _ in
            segs.append(frame)
            return true
        }
        let coveredFromStart = (start == 0)
        return segs.enumerated().map { i, seg in
            let toLeadingEdge = (i > 0) || coveredFromStart                  // covered from the line's beginning
            let toTrailingEdge = (i < segs.count - 1) || fillTrailingLine    // covered to the line's end
            // The line's "beginning" is the left edge in LTR but the right (container) edge in RTL; the
            // "end" is the opposite. Extend whichever physical edge corresponds to the covered logical side.
            let left: CGFloat
            let right: CGFloat
            if isRTL {
                right = toLeadingEdge ? max(seg.maxX, edge) : seg.maxX
                left = toTrailingEdge ? min(seg.minX, 0) : seg.minX
            } else {
                left = toLeadingEdge ? min(seg.minX, 0) : seg.minX
                right = toTrailingEdge ? max(seg.maxX, edge) : seg.maxX
            }
            return CGRect(x: left, y: seg.minY, width: right - left, height: seg.height)
        }
    }

    /// The on-screen box of the inline attachment occupying `[offset, offset+1)` — its true glyph box,
    /// derived from the attachment's own baseline-relative `attachmentBounds` and the line's baseline.
    /// NOT the full line-fragment rect `selectionRects` returns (which is `lineHeight × lineHeightMultiple`
    /// tall, so a host view sized to it stretches the emoji ~10% and pokes beyond the text). Returns nil
    /// when no glyph is laid out at the offset.
    func attachmentBox(at offset: Int) -> CGRect? {
        guard let range = textRange(offset, offset + 1),
              let attachment = attributedString.attribute(.attachment, at: offset, effectiveRange: nil) as? NSTextAttachment
        else { return nil }
        let attrs = attributedString.attributes(at: offset, effectiveRange: nil)
        var result: CGRect?
        // The selection segment gives the glyph's horizontal slot (minX) and its line fragment. `baselinePosition`
        // is the baseline measured from the FRAGMENT TOP (frame.minY), so the absolute baseline is
        // `frame.minY + baselinePosition` — using it raw would collapse every wrapped line onto line 1. The
        // attachment's own `attachmentBounds` is baseline-relative with +y up (bottom = descender, top =
        // ascender), so in container coords (y down) the box top = baseline − bounds.maxY.
        layoutManager.enumerateTextSegments(in: range, type: .selection, options: []) { _, frame, baselinePosition, container in
            // Raise the baseline by the line-centering delta so the inline attachment (emoji) tracks the
            // centered text glyphs, not the bottom-biased default position.
            let baseline = frame.minY + baselinePosition - self.centeringDelta(lineHeight: frame.height)
            let bounds = attachment.attachmentBounds(for: attrs, location: range.location,
                                                     textContainer: container, proposedLineFragment: frame,
                                                     position: CGPoint(x: frame.minX, y: baseline))
            var box = CGRect(x: frame.minX + bounds.minX, y: baseline - bounds.maxY,
                             width: bounds.width, height: bounds.height)
            // An emoji renders a touch larger than its reserved glyph box (`renderBoost`). Grow the VISIBLE
            // box symmetrically so it stays square and centered on the glyph — the reservation (and thus the
            // line height) is untouched, so the extra size bleeds into the line's leading.
            if let boost = (attachment as? EmojiTextAttachment)?.renderBoost, boost > 0 {
                box = box.insetBy(dx: -boost / 2, dy: -boost / 2)
            }
            result = box
            return false
        }
        return result
    }

    func closestOffset(toPoint point: CGPoint) -> Int {
        // Pick by line first, then by x within that line: a tap in a line's vertical band must map to
        // that line even if a longer line above has an end-caret that's horizontally nearer (e.g.
        // tapping the empty space to the right of a short last line). `dy` is the vertical distance to
        // the caret's line band (0 when the tap is inside it); ties on the same line break on `dx`.
        let ns = attributedString.string as NSString
        var best = 0
        var bestDy = CGFloat.greatestFiniteMagnitude
        var bestDx = CGFloat.greatestFiniteMagnitude
        for offset in 0...length {
            // Skip offsets INSIDE a composed character sequence (a surrogate-pair / ZWJ / variation-selector
            // emoji is ONE caret stop). A mid-cluster caret would let a later insert/delete split the cluster,
            // leaving a stray code unit (the "service character"). Endpoints (0, length) are always stops.
            if offset > 0, offset < length, ns.rangeOfComposedCharacterSequence(at: offset).location != offset {
                continue
            }
            let caret = caretRect(atOffset: offset)
            let dy = point.y < caret.minY ? caret.minY - point.y
                   : point.y > caret.maxY ? point.y - caret.maxY : 0
            let dx = abs(caret.midX - point.x)
            if dy < bestDy - 0.5 || (dy <= bestDy + 0.5 && dx < bestDx) {
                bestDy = dy; bestDx = dx; best = offset
            }
        }
        return best
    }

    /// Draws the laid-out text fragments into `ctx`, translated to `origin` (canvas coordinates).
    func drawText(in ctx: CGContext, at origin: CGPoint) {
        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y)
        layoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
            // Raise the fragment's glyphs by the line-centering delta so they sit centered in the line box
            // (whose height — caret/selection geometry — is untouched). The delta is uniform per paragraph,
            // so the first line's value applies to every wrapped line of the fragment.
            let delta = fragment.textLineFragments.first.map { self.centeringDelta(lineHeight: $0.typographicBounds.height) } ?? 0
            ctx.saveGState()
            ctx.translateBy(x: 0, y: -delta)
            fragment.draw(at: fragment.layoutFragmentFrame.origin, in: ctx)
            ctx.restoreGState()
            return true
        }
        ctx.restoreGState()
    }

    func replace(start: Int, end: Int, with string: NSAttributedString) {
        contentStorage.textStorage?.replaceCharacters(in: NSRange(location: start, length: end - start),
                                                       with: string)
        // Force a TK2 re-flow: a raw storage edit leaves the layout "valid", so a later measure at the SAME
        // container width returns the STALE height — an interior newline in a code / pull-quote block didn't
        // grow the box until a width change (rotation) forced a re-flow. Guarded by CodeBlockBoxTests
        // `test_codeBox_editAtSameWidth_reflowsHeight`.
        layoutManager.invalidateLayout(for: layoutManager.documentRange)
        renderVersion &+= 1
        ghostRange = nil; spoilerRanges = []; spoilerLocalRanges = []
    }

    /// Sets a DISPLAY-ONLY foreground colour over `[start, end)` via a TextKit 2 rendering attribute (the
    /// content storage / model is never touched) — used to grey an inline-prediction ghost. Removes only
    /// the PREVIOUS ghost range (not every `.foregroundColor`) so a coexisting spoiler hide survives. Pass
    /// `color == nil` to clear the ghost.
    func setGhostForeground(_ color: UIColor?, start: Int, end: Int) {
        if let prev = ghostRange { layoutManager.removeRenderingAttribute(.foregroundColor, for: prev) }
        ghostRange = nil
        renderVersion &+= 1
        guard let color, start < end, let range = textRange(start, end) else { return }
        layoutManager.addRenderingAttribute(.foregroundColor, value: color, for: range)
        ghostRange = range
    }

    /// Hides each LOCAL range as a spoiler by painting a DISPLAY-ONLY clear foreground over it (the glyphs
    /// stop drawing but still occupy layout, so all geometry is unchanged and nothing leaks into the model
    /// — the `setGhostForeground` precedent). Idempotent: removes the previously-hidden ranges first, so
    /// passing `[]` reveals everything. Disjoint from the ghost range, so the two never clobber.
    ///
    /// Performs a TRUE no-op (does NOT bump `renderVersion`) when the effective ranges are identical to the
    /// last call — covering both the empty→empty case (non-spoiler regions called each caret move) and the
    /// stable-hidden case (same hide on successive caret moves). After a storage edit `spoilerLocalRanges`
    /// is reset, so a re-call with the same logical ranges correctly re-applies the hide.
    /// Returns `true` iff the hidden set actually changed (so the caller can repaint the owning view — a
    /// reveal removes the clear foreground, and the paragraph must redraw to show the text again).
    @discardableResult
    func setSpoilerHidden(_ ranges: [NSRange]) -> Bool {
        let effective = ranges.filter { $0.length > 0 }
        if effective == spoilerLocalRanges { return false }   // no change → do NOT bump renderVersion (repaint gate)
        for prev in spoilerRanges { layoutManager.removeRenderingAttribute(.foregroundColor, for: prev) }
        spoilerRanges = []
        renderVersion &+= 1
        for r in effective {
            guard let tr = textRange(r.location, r.location + r.length) else { continue }
            layoutManager.addRenderingAttribute(.foregroundColor, value: UIColor.clear, for: tr)
            spoilerRanges.append(tr)
        }
        spoilerLocalRanges = effective
        return true
    }
}
#endif
