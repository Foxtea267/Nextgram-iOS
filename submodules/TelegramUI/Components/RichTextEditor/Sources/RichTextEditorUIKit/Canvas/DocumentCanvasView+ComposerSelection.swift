#if canImport(UIKit)
import UIKit
import RichTextEditorCore

@available(iOS 13.0, *)
extension DocumentCanvasView {
    /// One inline atom occurrence inside a paragraph region: `localOffset` is its global-axis offset within
    /// the region (the editor counts it as 1 `U+FFFC`); `flatLen` is the UTF-16 length the chat flat space
    /// counts instead (custom emoji alt text or formula LaTeX).
    private struct ComposerInlineAtom { let localOffset: Int; let flatLen: Int }

    /// One top-level paragraph's text region. `length` is the editor (global-axis) length (custom emoji = 1);
    /// `flatLength` is the chat flat length (custom emoji = its alt-string UTF-16 length); `flatStart` is the
    /// region's start in the composer's flat string. `atoms` are the region's expandable inline atoms, sorted.
    private struct ComposerParagraph {
        let globalStart: Int; let length: Int; let flatLength: Int; let flatStart: Int; let atoms: [ComposerInlineAtom]
    }

    /// Expandable inline atoms in a region, read from their `NSTextAttachment` over a one-`U+FFFC` run.
    /// Only atoms whose plain-text form is longer than 1 UTF-16 unit expand the flat space.
    private func composerInlineAtomOccurrences(in region: LeafTextRegion) -> [ComposerInlineAtom] {
        var result: [ComposerInlineAtom] = []
        let attr = region.layout.attributedString
        attr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attr.length), options: []) { value, range, _ in
            let flatText: String?
            if let att = value as? EmojiTextAttachment {
                flatText = att.ref.altText
            } else if let att = value as? FormulaTextAttachment {
                flatText = att.latex
            } else {
                flatText = nil
            }
            guard let flatText else {
                return
            }
            let flatLen = (flatText as NSString).length
            if flatLen > 1 {
                result.append(ComposerInlineAtom(localOffset: range.location, flatLen: flatLen))
            }
        }
        return result.sorted { $0.localOffset < $1.localOffset }
    }

    /// The document's top-level text blocks (paragraphs + code blocks) in order, each tagged with its start
    /// offset in the composer's flat UTF-16 string — the blocks' text joined by "\n", with each expandable
    /// inline atom expanded to its plain-text length. Non-text blocks (tables/images) contribute nothing,
    /// matching the bridge.
    ///
    /// An expanded `BlockQuoteBox` is transparent: its children are recursively inlined into the flat string
    /// (joined by "\n" like top-level paragraphs), matching `ComposerDocumentBridge.attributedString(from:)`.
    /// A collapsed `BlockQuoteBox` — like `CollapsedQuoteBox` — contributes exactly ONE flat placeholder char.
    private func composerParagraphs() -> [ComposerParagraph] {
        var result: [ComposerParagraph] = []
        var flat = 0

        /// Emit a 1-char flat atom for a non-editable block (collapsed quote / collapsedQuote).
        /// `length` stays 0: `composerFlatOffset` advances flat 1:1 with the global axis and can only EXPAND
        /// a region — it cannot compress an atom's multi-token global span to 1 flat unit. With length 0 the
        /// segment is a single global point at `nodeStart` (non-renderable, never a real caret), so it never
        /// steals a neighbor's position.
        func emitAtom(_ box: CanvasBlock) {
            if !result.isEmpty { flat += 1 }   // "\n" joining this atom to the previous block
            result.append(ComposerParagraph(globalStart: box.nodeStart, length: 0,
                                            flatLength: 1, flatStart: flat, atoms: []))
            flat += 1
        }

        func walk(_ boxes: [CanvasBlock]) {
            for box in boxes {
                if let bq = box as? BlockQuoteBox {
                    // Expanded → inline children into the flat string (like ComposerDocumentBridge recursing
                    // the children document); collapsed → 1-char atom matching collapsedQuote + the bridge.
                    if bq.collapsed { emitAtom(box) } else { walk(bq.children.boxes) }
                    continue
                }
                guard (box is BlockBox || box is CodeBlockBox || box is PullQuoteBox),
                      let region = box.leafRegions().first else { continue }
                if !result.isEmpty { flat += 1 }   // "\n" joining this paragraph to the previous one
                let atoms = composerInlineAtomOccurrences(in: region)
                let flatLength = region.length + atoms.reduce(0) { $0 + ($1.flatLen - 1) }
                result.append(ComposerParagraph(globalStart: region.globalStart, length: region.length,
                                                flatLength: flatLength, flatStart: flat, atoms: atoms))
                flat += flatLength
            }
        }

        walk(boxes)
        return result
    }

    /// Global axis → composer flat axis. An expandable inline atom at region-local offset `e.localOffset`
    /// adds `flatLen-1` flat units to every position *after* it (a global offset can only land before or
    /// after the `U+FFFC`).
    private func composerFlatOffset(forGlobal g: Int, in paragraphs: [ComposerParagraph]) -> Int {
        for p in paragraphs where g >= p.globalStart && g <= p.globalStart + p.length {
            let local = g - p.globalStart
            var flatLocal = local
            for e in p.atoms where e.localOffset < local { flatLocal += (e.flatLen - 1) }
            return p.flatStart + flatLocal
        }
        if let last = paragraphs.last { return last.flatStart + last.flatLength }
        return 0
    }

    /// Composer flat axis → global axis (the setter direction). Walks each region's plain runs (1:1) and
    /// inline atom spans (`flatLen` flat → 1 global); a flat offset landing *inside* an atom's plain-text span
    /// snaps to the nearest `U+FFFC` boundary (never mid-atom — carets snap to grapheme boundaries upstream).
    private func composerGlobal(forFlat f: Int, in paragraphs: [ComposerParagraph]) -> Int {
        for p in paragraphs where f >= p.flatStart && f <= p.flatStart + p.flatLength {
            let flatLocal = f - p.flatStart
            var globalLocal = 0
            var flatCursor = 0
            for e in p.atoms {
                let plainLen = e.localOffset - globalLocal
                if flatLocal <= flatCursor + plainLen {
                    return p.globalStart + globalLocal + (flatLocal - flatCursor)
                }
                flatCursor += plainLen
                globalLocal = e.localOffset
                if flatLocal < flatCursor + e.flatLen {
                    let into = flatLocal - flatCursor   // 1 ..< flatLen
                    return p.globalStart + globalLocal + (into * 2 >= e.flatLen ? 1 : 0)
                }
                flatCursor += e.flatLen
                globalLocal += 1
            }
            return p.globalStart + globalLocal + (flatLocal - flatCursor)
        }
        if let last = paragraphs.last { return last.globalStart + last.length }
        return 0
    }

    /// Selection rects for a chat-flat range (the composer's UTF-16 axis), in canvas content space.
    /// Maps both flat endpoints to the global axis via `composerGlobal(forFlat:)` — so custom-emoji
    /// alt-string expansion lines up — then unions the per-region glyph rects via `selectionRects`.
    /// The host (`RichTextEditorChatInputNode.firstSelectionRect`) anchors the emoji-suggestion popover
    /// at the first rect. Empty when the document has no text boxes or the range covers no glyphs.
    func composerSelectionRects(forFlatRange range: NSRange) -> [CGRect] {
        let paragraphs = composerParagraphs()
        guard !paragraphs.isEmpty else { return [] }
        let a = composerGlobal(forFlat: range.location, in: paragraphs)
        let b = composerGlobal(forFlat: range.location + range.length, in: paragraphs)
        return selectionRects(globalFrom: min(a, b), globalTo: max(a, b))
    }

    /// The caret rect at the selection end (`selectedTextRange.end` = `head`), in canvas content space,
    /// or nil when there is no caret / the rect is non-finite (e.g. a structural row/column selection
    /// hides the caret → `caretRect` returns `.zero`/non-finite). Port of the legacy `currentCaretRect`
    /// body minus the view convert (the facade converts to view space).
    func composerCaretRectInCanvas() -> CGRect? {
        guard let end = selectedTextRange?.end else { return nil }
        let rect = caretRect(for: end)
        guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite else {
            return nil
        }
        return rect
    }

    /// The first rect of the current selection (legacy `firstRect(for:)` semantics), in canvas content
    /// space; `bounds` when the selection covers no glyphs. Feeds the host's `selectionRect`, whose only
    /// consumer (the legacy format menu) is dead on iOS 17+ — implemented for contract-honesty.
    func composerSelectionBoundingRectInCanvas() -> CGRect {
        selectionRects(globalFrom: min(selFrom, selTo), globalTo: max(selFrom, selTo)).first ?? bounds
    }

    /// The selection expressed in the chat composer's flat UTF-16 coordinate space (see `composerParagraphs`).
    /// The host (`RichTextEditorChatInputNode.selectedRange`) reads this to track the caret and writes it to
    /// move the caret after a programmatic insert/replace. The flat axis collapses the editor's global axis
    /// (which carries non-renderable structural slots between blocks) down to one "\n" per paragraph break,
    /// so a multi-UTF-16-unit emoji and the paragraph separators line up 1:1 with what the host inserts.
    var composerSelectedRange: NSRange {
        get {
            let paragraphs = composerParagraphs()
            guard !paragraphs.isEmpty else { return NSRange(location: 0, length: 0) }
            let lo = composerFlatOffset(forGlobal: selFrom, in: paragraphs)
            let hi = composerFlatOffset(forGlobal: selTo, in: paragraphs)
            return NSRange(location: lo, length: max(0, hi - lo))
        }
        set {
            finalizeMarkedText()
            clearStructuralSelections()
            let paragraphs = composerParagraphs()
            let a = composerGlobal(forFlat: newValue.location, in: paragraphs)
            let h = composerGlobal(forFlat: newValue.location + newValue.length, in: paragraphs)
            // Programmatic selection move — bracket it so the OS keeps a fresh `selectedTextRange`.
            // Snap each global to the nearest renderable slot: a flat offset that lands on the "\n"
            // immediately after a collapsed quote maps via `composerGlobal` to a position INSIDE the
            // collapsed atom (non-renderable), causing the getter to fall through to end-of-document.
            // `snapToRenderable(_:forward:true)` is a no-op for already-renderable positions, so
            // existing round-trip tests are unaffected.
            textInputDelegate?.selectionWillChange(self)
            anchor = snapToRenderable(clampGlobal(a), forward: true)
            head   = snapToRenderable(clampGlobal(h), forward: true)
            textInputDelegate?.selectionDidChange(self)
            setNeedsDisplay(); refreshSelectionUI(); onSelectionChange?()
        }
    }
}
#endif
