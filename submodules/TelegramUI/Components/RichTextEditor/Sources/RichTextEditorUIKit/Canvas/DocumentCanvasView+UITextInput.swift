#if canImport(UIKit)
import UIKit
import RichTextEditorCore

@available(iOS 13.0, *)
extension DocumentCanvasView: UITextInput {
    private func clamp(_ n: Int) -> Int { clampGlobal(n) }

    func text(in range: UITextRange) -> String? {
        guard let r = range as? DocumentTextRange else { return nil }
        let lo = clamp(min(r.from.offset, r.to.offset)), hi = clamp(max(r.from.offset, r.to.offset))
        var result = ""
        // The global position axis carries NO newline character between top-level blocks — only a
        // structural token gap. A real UITextView returns "\n" there, and the system keyboard depends on
        // it: the Hangul/CJK IME reads document context through `text(in:)` (it does NOT drive marked text
        // on this view — it composes via insert + ranged delete/replace), and without the separator it
        // sees two stacked paragraphs as one continuous line and recomposes a syllable ACROSS the invisible
        // line break — the reported bug where a trailing consonant from the lower line migrates onto the
        // line above. So emit "\n" for each top-level paragraph boundary the range crosses, including a
        // range that lands entirely inside the inter-block gap (the read the keyboard makes immediately
        // before a lower line's first character). Table-cell boundaries stay glued: a table is one editing
        // surface, cells don't compose marked text, and cross-cell `text(in:)` is relied on un-separated.
        var prevTopLevelEnd: Int? = nil
        for region in allLeafRegions() {
            let rStart = region.globalStart, rEnd = region.globalStart + region.length
            let topLevel = !isInsideTable(rStart)
            if topLevel, let prevEnd = prevTopLevelEnd, lo < rStart, hi > prevEnd {
                result += "\n"   // the requested range covers this paragraph break
            }
            defer { prevTopLevelEnd = topLevel ? rEnd : nil }
            let a = max(lo, rStart), b = min(hi, rEnd)
            guard a < b else { continue }
            let attr = region.layout.attributedString
            let ns = attr.string as NSString
            let slice = NSRange(location: a - rStart, length: b - a)
            // Replace inline atoms with their plain-text forms; copy every other span verbatim.
            attr.enumerateAttribute(.attachment, in: slice, options: []) { value, sub, _ in
                if let att = value as? EmojiTextAttachment {
                    result += att.ref.altText ?? ""
                } else if let att = value as? FormulaTextAttachment {
                    result += att.latex
                } else {
                    result += ns.substring(with: sub)
                }
            }
        }
        return result
    }

    func replace(_ range: UITextRange, withText text: String) {
        guard let r = range as? DocumentTextRange else { return }
        let lo = min(r.from.offset, r.to.offset)
        let hi = max(r.from.offset, r.to.offset)
        // A keyboard autocorrection arrives here as `replace(word, correction)` — capture the original BEFORE the
        // edit so we can flag the corrected word (below) with a "Revert to …" affordance.
        let autocorrectOriginal = detectAutocorrection(oldText: self.text(in: range), newText: text)
        // Route through the 3-way selection logic, not applyReplace directly: a system-initiated
        // replacement (autocorrect/dictation/marked-text) can span a table boundary, which the
        // same-stack-guarded applyReplace would silently drop.
        // System-initiated replacement (autocorrect / dictation / marked-text spanning). Kept .none
        // (its own undo step) — coalescing is scoped to insertText/deleteBackward typing/deleting, so a
        // dictation utterance is one undo step. Intentional, not an oversight.
        editing { applySelectionReplace(globalFrom: lo, globalTo: hi, text: text) }
        if let original = autocorrectOriginal, isSpellCheckingEnabled {
            applyCorrectionFlag(global: NSRange(location: lo, length: (text as NSString).length), original: original)
        }
    }

    func typingAttributeDict(region: LeafTextRegion, atLocal location: Int) -> [NSAttributedString.Key: Any] {
        let storage = region.layout.attributedString
        if storage.length == 0 {
            // An empty image caption is render-only centered (not in the model), so the next typed
            // character must carry that centered paragraph style explicitly or it would land left-aligned.
            if let img = boxes.compactMap({ $0 as? MediaBlockBox }).first(where: { region.ref == .caption($0.id) }) {
                return img.captionTypingAttributes()
            }
            // An empty code block types the monospace code attributes, not the body default — without this the
            // first character typed into a just-created (empty) code block lands non-monospace at body size.
            if case .code = region.ref { return CodeBlockBox.codeAttributes() }
            // An empty pull quote types the italic/centered pull-quote attributes — without this the first
            // character typed into an empty pull quote lands body-upright-left instead of italic/centered.
            if case .pullQuote = region.ref { return PullQuoteBox.pullQuoteTypingAttributes(mapper) }
            // An empty quote author types the BOLD caption attributes — without this the first character typed
            // into an empty author lands body-styled (17pt, non-bold), which then pollutes the model on read-back.
            if case .quoteAuthor = region.ref, let attrs = authorTypingAttributes(forRegion: region.ref) {
                return attrs
            }
            // Recover the owning paragraph — top-level OR nested in a table cell (via the active stack)
            // — so an empty styled/listed/cell paragraph keeps its paragraph style AND its box's mapper
            // on the next typed character. A table cell's mapper renders body text at a smaller base
            // size, so reading the box's own mapper (not the canvas one) keeps the first char on size.
            let p = boxes.compactMap { $0 as? BlockBox }.first { region.ref == .paragraph($0.id) }
                ?? (activeStack(at: region.globalStart + location).flatMap { $0.box as? BlockBox })
            let m = p?.mapper ?? mapper
            let style = p?.style ?? .body
            let para = p?.paragraphAttributes ?? .default
            let list = p?.listMembership
            var attrs = m.attributes(for: CharacterAttributes(), style: style)
            attrs[.paragraphStyle] = m.styleSheet.paragraphStyle(for: style, attributes: para, list: list,
                                                                   baseWritingDirection: m.baseWritingDirection)
            return attrs
        }
        var attrs = storage.attributes(at: min(max(0, location - 1), storage.length - 1), effectiveRange: nil)
        // A formula is an atomic inline value, not a typing style. At either edge of the atom the normal
        // "inherit from the preceding character" rule picks up its semantic marker; NSTextStorage removes
        // an attachment from newly-inserted non-U+FFFC text, but leaves our custom rtFormula attribute in
        // place. That makes the text look plain while read-back/send serializes it as another formula.
        // Strip only the atom-specific metadata, preserving its ambient font/colour/paragraph attributes.
        attrs.removeValue(forKey: .rtFormula)
        if attrs[.attachment] is FormulaTextAttachment {
            attrs.removeValue(forKey: .attachment)
        }
        return attrs
    }

    /// Bold caption typing attributes for an empty quote author region: resolves the owning PullQuoteBox /
    /// BlockQuoteBox (recursing nested block quotes) by id and returns its `authorTypingAttributes()`.
    func authorTypingAttributes(forRegion ref: TextNodeRef) -> [NSAttributedString.Key: Any]? {
        guard case let .quoteAuthor(id) = ref else { return nil }
        func search(_ list: [CanvasBlock]) -> [NSAttributedString.Key: Any]? {
            for b in list {
                if let pq = b as? PullQuoteBox, pq.id == id { return pq.authorTypingAttributes() }
                if let bq = b as? BlockQuoteBox {
                    if bq.id == id { return bq.authorTypingAttributes() }
                    if let hit = search(bq.children.boxes) { return hit }
                }
            }
            return nil
        }
        return search(boxes)
    }

    /// Typing attributes for the caret at a global position: the leaf region's attributes, or body
    /// defaults at a structural boundary (no region). Used by the structural-edit engine.
    func typingAttributesAtGlobal(_ pos: Int) -> [NSAttributedString.Key: Any] {
        if let (region, local) = leafRegion(containingGlobal: clamp(pos)) {
            return typingAttributeDict(region: region, atLocal: local)
        }
        return mapper.attributes(for: CharacterAttributes(), style: .body)
    }

    var selectedTextRange: UITextRange? {
        get { DocumentTextRange(DocumentTextPosition(anchor), DocumentTextPosition(head)) }
        set {
            // During a floating-cursor (spacebar-trackpad) gesture, the floating handlers
            // (updateFloatingCursor → moveFloatingCaret) own the caret. iOS ALSO pushes selection RANGES
            // anchored at the gesture's start position through this setter; applying them turns the cursor
            // MOVE into a text SELECTION. Ignore them while the gesture owns the caret.
            if floatingCursorActive { return }
            // iOS sets the object-replacement RANGE for a tap-selected media right before its Backspace.
            // `clearStructuralSelections()` below drops `imageSelection`; stash it so `deleteBackward` can
            // still recognise the structural-delete intent (its object geometry doesn't cover the media node).
            imageObjectDeletePending = imageSelection
            finalizeMarkedText()     // a deliberate selection move commits a composition / dismisses a prediction
            clearStructuralSelections()
            dismissEditMenuForSelectionOrTextChange()   // system-driven move (keyboard cursor-drag / autocorrect) closes the menu too
            let r = newValue as? DocumentTextRange
            anchor = clamp(r?.from.offset ?? 0); head = clamp(r?.to.offset ?? 0)
            setNeedsDisplay(); refreshSelectionUI()
            onSelectionChange?()     // host scrolls the (possibly off-screen) caret into view — e.g. arrow-key nav up out of a tall image
        }
    }

    var inputDelegate: UITextInputDelegate? {
        get { textInputDelegate }
        set { textInputDelegate = newValue }
    }
    var tokenizer: UITextInputTokenizer {
        if let t = inputTokenizer { return t }
        let t = DocumentTokenizer(canvas: self)
        inputTokenizer = t
        return t
    }

    // The first/last positions the caret can occupy must be RENDERABLE (a leaf region start/end or an
    // image gap), not the document's structural open/close token slots (0 / documentSize) — otherwise
    // "move to start/end of document" would hide the caret.
    var beginningOfDocument: UITextPosition { DocumentTextPosition(snapToRenderable(0, forward: true)) }
    var endOfDocument: UITextPosition { DocumentTextPosition(snapToRenderable(documentSize, forward: false)) }

    // Optional iOS-18 UITextInput member: tells the system the view supports editing so Writing Tools
    // can apply results in place (vs treating content as read-only). Together with our `UIEditMenuInteraction`
    // (the non-UITextInteraction path, WWDC24 #10168), this surfaces the system Writing Tools item on
    // Apple-Intelligence hardware.
    @available(iOS 18.0, *)
    var isEditable: Bool { true }

    func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        guard let f = fromPosition as? DocumentTextPosition, let t = toPosition as? DocumentTextPosition else { return nil }
        return f.offset <= t.offset ? DocumentTextRange(f, t) : DocumentTextRange(t, f)
    }

    func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        guard let p = position as? DocumentTextPosition else { return nil }
        let n = p.offset + offset
        guard n >= 0, n <= documentSize else { return nil }
        // The system tokenizer (Option+Arrow word nav, double-tap select, …) steps through positions
        // via this primitive; snap to a renderable slot so it can never park the caret on a structural
        // token (which would be invisible). No-op for positions already renderable.
        return DocumentTextPosition(snapToRenderable(n, forward: offset >= 0))
    }

    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        let a = (position as? DocumentTextPosition)?.offset ?? 0
        let b = (other as? DocumentTextPosition)?.offset ?? 0
        return a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }

    func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        ((toPosition as? DocumentTextPosition)?.offset ?? 0) - ((from as? DocumentTextPosition)?.offset ?? 0)
    }

    func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        guard let r = range as? DocumentTextRange else { return nil }
        return (direction == .left || direction == .up) ? r.start : r.end
    }

    func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
        guard let p = position as? DocumentTextPosition else { return nil }
        return (direction == .left || direction == .up)
            ? DocumentTextRange(DocumentTextPosition(0), p)
            : DocumentTextRange(p, DocumentTextPosition(documentSize))
    }

    func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection {
        guard let p = position as? DocumentTextPosition else { return typingWritingDirection }
        return resolvedDirection(forGlobal: p.offset)
    }
    // No-op by design: the whole-document override (`layoutDirectionModel`) is the single manual control,
    // so we do not honor per-range UIKit writing-direction writes (which would imply per-paragraph control
    // we deliberately did not build).
    func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {}

    func firstRect(for range: UITextRange) -> CGRect {
        guard let r = range as? DocumentTextRange else { return .zero }
        return selectionRects(globalFrom: min(r.from.offset, r.to.offset),
                              globalTo: max(r.from.offset, r.to.offset)).first ?? .zero
    }

    func caretRect(for position: UITextPosition) -> CGRect {
        // A structural row/column selection hides the caret entirely (the outline is the indicator).
        // An image atom selection does NOT zero the caret here: `caretRect` must keep reporting the gap
        // geometry so the OS can run arrow-key navigation OUT of a tap-selected image — vertical arrows
        // read the caret's rect to step a line, so a `.zero` rect strands them (the reported "Up does
        // nothing / caret vanishes" bug). The VISIBLE caret is suppressed separately in `updateCaretView`
        // (the image tint is the selection indicator), so no blinking caret shows over a selected image.
        if tableSelection != nil { return .zero }
        guard let p = position as? DocumentTextPosition else { return .zero }
        let pos = clamp(p.offset)
        if let (r, local) = leafRegion(containingGlobal: pos) {
            // `emptyLineLeadingIndent`/`emptyLineHeight` only matter on an empty line, whose caret TextKit
            // would otherwise place at x=0 with a fixed 20pt height (no glyphs to carry the indent/metrics).
            return r.caretRect(atLocal: local)
                .offsetBy(dx: r.canvasOrigin.x + r.emptyLineLeadingIndent - tableContentOffsetX(forGlobal: pos),
                          dy: r.canvasOrigin.y)
        }
        // An image gap is a real caret slot but not a text leaf. Report a vertical bar at the image's
        // leading edge; `updateCaretView` renders the app's own caret there (and this geometry also feeds the
        // loupe / hit-test / edit menu). (This returned .zero before, which is why draw(_:) used to hand-draw
        // a custom GapCursor bar.)
        if let img = mediaBox(atGap: pos) {
            let rr = img.mediaRect()
            return CGRect(x: rr.minX, y: rr.minY, width: 2, height: rr.height)
        }
        // A collapsed quote's leading gap is a real caret slot (no text leaf) — a bar at the folded preview's
        // leading edge, so the caret focused on a collapsed quote is visible. Mirrors the media-gap branch.
        if let bq = collapsedBlockQuoteBox(atGap: pos) {
            return bq.collapsedCaretRect
        }
        return .zero
    }

    func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        guard let r = range as? DocumentTextRange else { return [] }
        let rects = selectionRects(globalFrom: min(r.from.offset, r.to.offset),
                                   globalTo: max(r.from.offset, r.to.offset))
        return rects.enumerated().map { index, frame in
            DocumentSelectionRect(rect: frame, containsStart: index == 0, containsEnd: index == rects.count - 1)
        }
    }

    func closestPosition(to point: CGPoint) -> UITextPosition? {
        DocumentTextPosition(closestGlobalPosition(to: point))
    }

    func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        guard let p = closestPosition(to: point) as? DocumentTextPosition, let r = range as? DocumentTextRange else { return nil }
        return DocumentTextPosition(min(max(p.offset, r.from.offset), r.to.offset))
    }

    func characterRange(at point: CGPoint) -> UITextRange? {
        guard let p = closestPosition(to: point) as? DocumentTextPosition else { return nil }
        return DocumentTextRange(p, DocumentTextPosition(min(p.offset + 1, documentSize)))
    }
}

@available(iOS 13.0, *)
extension DocumentCanvasView: UIKeyInput {
    var hasText: Bool { documentSize > 0 }

    func insertText(_ text: String) {
        // MARK: NAGRAM — A software Return may send instead of inserting a paragraph break.
        if text == "\n", !(onSoftwareReturn?() ?? true) {
            return
        }
        imageObjectDeletePending = nil   // a non-delete edit cancels a pending structural-media delete
        // A committing keystroke while composing: replace the WHOLE marked range with `text`, then
        // finalize the composition as one undo step. (The system delivers a confirming char this way.)
        if let m = markedRange {
            textInputDelegate?.textWillChange(self)
            applyReplace(globalFrom: m.from, globalTo: m.to, text: text)   // in place; caret → end
            textInputDelegate?.textDidChange(self)
            commitMarkedText()
            notifyContentSizeChanged(); setNeedsDisplay(); refreshSelectionUI()
            onSelectionChange?()   // committing a composition moves the caret — scroll it into view too
            return
        }
        clearStructuralSelections()
        // Caret on an image's gap cursor → open a new body paragraph immediately before the image
        // (Enter inserts an empty one), rather than letting the text fall into the caption. Symmetric
        // to deleteBackward's gap branch below.
        if selFrom == selTo, let img = mediaBox(atGap: head), let i = boxIndex(of: img) {
            editing { insertBodyParagraph(beforeBoxAt: i, text: text == "\n" ? "" : text) }
            return
        }
        // Caret focused on a COLLAPSED quote's gap → open a body paragraph immediately before the folded
        // quote (the atom holds no editable text), so a keystroke there isn't swallowed. Mirrors the media gap.
        if selFrom == selTo, let bq = collapsedBlockQuoteBox(atGap: head), let i = boxIndex(of: bq) {
            editing { insertBodyParagraph(beforeBoxAt: i, text: text == "\n" ? "" : text) }
            return
        }
        if text == "\n" {
            // Return in a quote AUTHOR line splits the author at the caret (like a media caption): the head runs
            // stay as the author, the tail runs become a NEW body paragraph immediately after the quote (caret
            // there). Handled here, at the TOP of the "\n" dispatch, because a caret in the author resolves
            // through neither activeStack (off the child stack) nor resolveBox (outside the container's
            // degenerate/pull-text extent), so the code/pull-quote/block-quote branches below (and the general
            // insertParagraphBreak() fallback) would mis-route the break into the following sibling block.
            if selFrom == selTo, let (region, authorLocal) = leafRegion(containingGlobal: head),
               case .quoteAuthor = region.ref, let (quoteBox, parentStack, index) = enclosingQuote(at: head) {
                let authorRuns: [TextRun]
                let rebuildQuote: ([TextRun]) -> Block
                switch quoteBox.currentBlock() {
                case .pullQuote(let pq):
                    authorRuns = pq.author
                    rebuildQuote = { .pullQuote(PullQuote(id: pq.id, runs: pq.runs, author: $0)) }
                case .blockQuote(let bq):
                    authorRuns = bq.author
                    rebuildQuote = { .blockQuote(BlockQuote(id: bq.id, children: bq.children, collapsed: bq.collapsed, author: $0)) }
                default:
                    return
                }
                editing {
                    let tmp = ParagraphBlock(id: BlockID.generate(), style: .caption, runs: authorRuns)
                    let parts = tmp.split(at: authorLocal, newID: BlockID.generate())   // .0 = head (author), .1 = tail (new paragraph)
                    guard let newQuoteBox = makeBox(for: rebuildQuote(parts.0.runs), mapper: mapper, quoteStyle: quoteStyle,
                                                    pullQuoteStyle: pullQuoteStyle, expandImage: quoteCollapseIcons?.expand,
                                                    collapseImage: quoteCollapseIcons?.collapse, width: effectiveWidth) else { return }
                    let bodyBox = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), style: .body, runs: parts.1.runs),
                                           mapper: mapper, width: effectiveWidth)
                    parentStack.boxes.replaceSubrange(index...index, with: [newQuoteBox, bodyBox])
                    recomputeSpans()
                    anchor = bodyBox.textStart; head = bodyBox.textStart
                }
                return
            }
            if let active = activeStack(at: head), active.box is CodeBlockBox {
                // Double-return (Enter on an empty line) EXITS the code block: trailing → after, first →
                // before, wholly-empty → un-code. A MIDDLE blank line and a non-empty line just insert a
                // literal newline (no paragraph split). A selection always replaces-with-newline — only a
                // collapsed caret can exit.
                if selFrom == selTo, let exit = codeBlockDoubleReturnExit(active) {
                    switch exit {
                    case .after:  exitCodeBlockToBodyParagraph(active)
                    case .before: exitCodeBlockToBodyParagraphBefore(active)
                    case .uncode: uncodeEmptyCodeBlock(active)
                    }
                } else {
                    insertCodeBlockNewline()
                }
            } else if let active = activeStack(at: head), active.box is PullQuoteBox {
                // Double-return EXITS the pull quote: trailing → after, first → before, wholly-empty → unmake.
                // A MIDDLE blank line and a non-empty line just insert an interior newline. A selection always
                // replaces-with-newline — only a collapsed caret can exit.
                if selFrom == selTo, let exit = pullQuoteDoubleReturnExit(active) {
                    switch exit {
                    case .after:  exitPullQuoteToBodyParagraph(active)
                    case .before: exitPullQuoteToBodyParagraphBefore(active)
                    case .unmake: unmakeEmptyPullQuote(active)
                    }
                } else {
                    insertPullQuoteNewline()
                }
            } else if selFrom == selTo, isInsideBlockQuote(head), blockQuoteEmptyTrailingChildExit() {
                // Double-return EXITS the block quote at the END: empty trailing child → body paragraph after
                // the quote; a wholly-empty quote (after \n\n) → one body paragraph in place. A SINGLE Return
                // in a wholly-empty quote just adds a line (the escape requires \n\n). Handled inside the
                // helper; execution falls through to the outer `return`.
                _ = ()
            } else if selFrom == selTo, isInsideBlockQuote(head), blockQuoteEmptyLeadingChildExit() {
                // Double-return at the BEGINNING → body paragraph BEFORE the quote (the leading blank line is
                // dropped). Checked after the trailing exit so a wholly-empty quote takes the un-quote path.
                _ = ()
            } else if selFrom == selTo, let active = activeStack(at: head),
                      headerCellDoubleReturnExitsAbove(active) {
                // Double-return on the START of a header cell's second block (empty first block) EXITS the
                // table to a body paragraph ABOVE it. Header rows only; body cells + trailing/non-leading
                // blanks fall through to the normal in-cell split.
                exitHeaderCellToBodyParagraphBefore(active)
            } else {
                insertParagraphBreak()
            }
            return
        }
        if selFrom != selTo {
            editing(coalescing: .typing) { applySelectionReplace(globalFrom: selFrom, globalTo: selTo, text: text) }
            return
        }
        // A collapsed caret in a quote AUTHOR line: the author is a SECOND leaf region on the box (outside the
        // box's primary textStart/textLength extent and off the child stack), so applyReplace/activeStack would
        // mis-route the insert to the following block. Route it through the region-aware applyLeafReplace, exactly
        // as an in-cell edit does below.
        if let (region, _) = leafRegion(containingGlobal: head), case .quoteAuthor = region.ref {
            editing(coalescing: .typing) { applyLeafReplace(globalFrom: selFrom, globalTo: selTo, text: text) }
            return
        }
        // A collapsed caret that resolves to a table or block-quote box (e.g. before a leading
        // container / after a trailing one) is a structural boundary — snap it into the nearest
        // in-container text start so the edit goes through that container's stack, never through
        // the container's degenerate textLayout (which would drop the keystroke).
        if !isInsideTable(head) && !isInsideBlockQuote(head),
           let r = resolveBox(at: head), r.box is TableBlockBox || r.box is BlockQuoteBox {
            let snapped = caretSnappedIntoContainer(head)
            anchor = snapped; head = snapped
        }
        if isInsideTable(head) {
            // collapsed caret in a cell: text is in-place.
            editing(coalescing: .typing) { applyLeafReplace(globalFrom: selFrom, globalTo: selTo, text: text) }
            return
        }
        editing(coalescing: .typing) { applyReplace(globalFrom: selFrom, globalTo: selTo, text: text) }
    }

    /// The number of UTF-16 units the composed character sequence (grapheme cluster) immediately
    /// before the caret at global position `head` occupies. Backspace deletes this many units so a
    /// multi-unit emoji — a surrogate-pair scalar, a ZWJ sequence, a skin-tone / flag / variation-
    /// selector combo — is removed as ONE unit instead of one code unit (which would orphan the rest
    /// and render "part" of the emoji). Within a leaf region the global axis is 1:1 with UTF-16, and a
    /// grapheme never spans regions, so `head - n` stays in the same region. Returns 1 when the region
    /// can't be resolved (the safe single-unit fallback); a custom-emoji `U+FFFC` and any plain BMP
    /// character are single-unit clusters, so this is a no-op for them. Caller guarantees `local > 0`.
    func graphemeClusterLengthBeforeCaret(global head: Int) -> Int {
        guard let (region, local) = leafRegion(containingGlobal: head), local > 0 else { return 1 }
        let s = region.layout.attributedString.string as NSString
        guard local <= s.length else { return 1 }
        let r = s.rangeOfComposedCharacterSequence(at: local - 1)
        return max(1, local - r.location)
    }

    /// Expands a global range so neither endpoint SPLITS A UTF-16 SURROGATE PAIR (a single astral Unicode
    /// scalar whose two code units must stay together): `from` snaps DOWN to the pair start, `to` snaps UP
    /// to the pair end. The OS can request a delete/replace of a partial scalar — notably a backspace
    /// arriving as a 1-UTF-16-unit range covering only one half of a surrogate-pair emoji (`selFrom≠selTo`)
    /// — and deleting it verbatim leaves a stray code unit (a "service character").
    ///
    /// It deliberately does NOT expand across whole GRAPHEME CLUSTERS. A base + combining-mark sequence — a
    /// Tamil consonant + virama ("க்" = U+0B95 U+0BCD), and other Indic / Thai scripts — is two INDEPENDENT
    /// scalars that a composing IME (e.g. Tamil **Anjal**) edits individually: it selects the lone combining
    /// mark and deletes/replaces it to recompose the syllable (verified against the real iOS keyboard driving
    /// this view). Snapping that to the whole cluster would erase the base consonant, so the syllable could
    /// never be formed — the "can't type Tamil" bug. Matching a stock `UITextView`, only surrogate pairs are
    /// kept atomic here; grapheme atomicity is enforced for CARET stepping by the tokenizer, not for IME
    /// edits. A scalar never spans leaf regions, so each endpoint is snapped within its own region.
    func rangeExpandedToScalarBoundaries(globalFrom: Int, globalTo: Int) -> (from: Int, to: Int) {
        func snap(_ g: Int, up: Bool) -> Int {
            guard let (region, local) = leafRegion(containingGlobal: g), local > 0 else { return g }
            let s = region.layout.attributedString.string as NSString
            guard local < s.length else { return g }
            // A split point sits INSIDE a surrogate pair iff the unit before is a high surrogate and the
            // unit at `local` is a low surrogate. Every other boundary (incl. base↔combining-mark) is kept.
            let unit = s.character(at: local), prev = s.character(at: local - 1)
            let splitsSurrogatePair = prev >= 0xD800 && prev <= 0xDBFF && unit >= 0xDC00 && unit <= 0xDFFF
            guard splitsSurrogatePair else { return g }
            return region.globalStart + (up ? local + 1 : local - 1)
        }
        let lo = min(globalFrom, globalTo), hi = max(globalFrom, globalTo)
        return (snap(lo, up: false), snap(hi, up: true))
    }

    /// True when `pos` is the START (local 0) of an empty CONTAINER whose Backspace un-makes it to a body
    /// paragraph: an empty code block, an empty pull quote, or the lone empty child of a block quote. Used to
    /// recognise the OS-delivered object-replacement Backspace RANGE at an empty container so it can be collapsed
    /// to a caret and routed through the same un-quote / un-code / un-make branches as a direct tap.
    func startsEmptyContainer(at pos: Int) -> Bool {
        guard let active = activeStack(at: pos), active.local == 0, active.box.textLength == 0 else { return false }
        if active.box is CodeBlockBox || active.box is PullQuoteBox { return true }
        if active.box is BlockBox, active.stack.boxes.count == 1, isInsideBlockQuote(pos) { return true }
        return false
    }

    func deleteBackward() {
        if markedRange != nil { commitMarkedText() }   // delete acts on committed text, not the composition
        guard !boxes.isEmpty else { return }
        // A tap-selected media block's Backspace: iOS represents the deletion by OVERRIDING the selection
        // (via the `selectedTextRange` setter, which clears `imageSelection`) to a RANGE whose head lands at
        // the media's leading gap but whose object geometry is offset from our position model (it anchors in
        // the preceding block), so the normal selection-replace below would delete the preceding text and
        // KEEP the media. The setter stashes the just-cleared image into `imageObjectDeletePending`; honor it
        // here by replacing that media with an empty body paragraph in place.
        if let pendingId = imageObjectDeletePending,
           let i = boxes.firstIndex(where: { $0.id == pendingId && $0 is MediaBlockBox }),
           head == boxes[i].nodeStart || selFrom == boxes[i].nodeStart || selTo == boxes[i].nodeStart {
            imageObjectDeletePending = nil
            editing { replaceMediaWithEmptyParagraph(at: i) }
            clearImageSelection()
            return
        }
        imageObjectDeletePending = nil
        if tableSelection != nil {
            // A structural row/column selection is active → Backspace deletes those rows/columns (or the
            // whole table when every row/column is selected). The caret is parked in a cell, so the normal
            // in-cell branch below would otherwise just delete a character.
            deleteTableStructuralSelection()
            return
        }
        // iOS delivers Backspace at the START (local 0) of a NON-FIRST block-quote CHILD as an object-replacement
        // RANGE anchored at the previous child's text end (the paragraph break INSIDE the quote), NOT a collapsed
        // caret — verified at runtime (Return at a quote line's end then Backspace arrives as e.g. `sel=3..5`, head
        // at the new empty 2nd child). This MUST run BEFORE the empty-container / empty-paragraph-after-atom handlers
        // below: `resolveBox(at: selTo)` mis-resolves this in-quote position to the FOLLOWING block, so the "empty
        // paragraph after a non-paragraph atom" handler (a BlockQuoteBox IS such an atom) would REMOVE that following
        // block (the device bug: "Backspace deletes the paragraph after the quote, not the quote's own line"). When
        // the range only spans the structural break before the child's start (`selFrom >= prevTextPosition(before:
        // selTo)`, excluding a genuine text selection), COLLAPSE it to a caret at the child start so the
        // collapsed-caret quote-child branch below merges it into its previous sibling.
        if selFrom != selTo, isInsideBlockQuote(selTo),
           let active = activeStack(at: selTo), active.box is BlockBox, active.local == 0, active.index > 0,
           selFrom >= prevTextPosition(before: selTo) {
            anchor = selTo; head = selTo
        }
        // iOS delivers Backspace at the START of an empty CONTAINER (block quote / code block / pull quote) as an
        // object-replacement RANGE anchored at the previous block's text end — the same offset geometry as a
        // media atom, NOT a collapsed caret. Left as a range it falls to the generic selection-replace below and
        // MERGES the container's (empty) content into the previous block, stranding the empty container — the
        // device bug ("Backspace jumps the caret to the previous line and the quote stays"). When the range only
        // spans the structural slots before the container's start (`selFrom >= prevTextPosition(before: selTo)`,
        // which excludes a genuine text selection), COLLAPSE it to a caret at the container start so the
        // collapsed-caret un-quote / un-code / un-make branches below un-make it — exactly like a direct tap.
        if selFrom != selTo, startsEmptyContainer(at: selTo),
           selFrom >= prevTextPosition(before: selTo) {
            anchor = selTo; head = selTo
        }
        // iOS delivers Backspace in an empty paragraph immediately AFTER a non-paragraph atom (image /
        // table / code / collapsed quote) as an object-replacement RANGE running from the atom's text end
        // to the empty paragraph's start (device-log: `setRange [8,10]` overriding the collapsed caret at
        // 10, then `deleteBackward selFrom=8 selTo=10`) — the same offset-geometry pattern for all atoms.
        // The generic selection-replace below would mangle the boundary and strand the empty paragraph.
        // Recognise it — selTo at the start of an EMPTY paragraph whose previous block is any non-paragraph
        // atom, with selFrom only covering the structural slots before (`selFrom >=
        // prevTextPosition(before: selTo)`, which excludes a genuine multi-char selection) — and remove the
        // empty paragraph, parking the caret at the atom's text end (matching the collapsed-caret path for
        // an empty paragraph after a non-text atom further below). `selTo` must be a genuine TOP-LEVEL position:
        // a position INSIDE a block quote OR a table cell has no degenerate-container-safe `resolveBox`, so
        // `resolveBox(selTo)` mis-resolves it to the FOLLOWING top-level block — and a mid-text Backspace inside
        // the container (delivered as the 1-char range [local0, local1]) satisfies `selFrom >=
        // prevTextPosition(before: selTo)`, so without the `!isInsideBlockQuote(selTo)` / `!isInsideTable(selTo)`
        // guards this would REMOVE the (empty) block after the container instead of deleting the char (the
        // "mid-quote / mid-cell delete misroutes into the following block" device bug).
        if selFrom != selTo, !isInsideBlockQuote(selTo), !isInsideTable(selTo), let posTo = resolveBox(at: selTo),
           posTo.local == 0, posTo.box.textLength == 0, posTo.index > 0,
           isNonParagraphAtom(boxes[posTo.index - 1]),
           selFrom >= prevTextPosition(before: selTo) {
            editing { removeBlock(at: posTo.index, parkingCaretAt: prevTextPosition(before: selTo)) }
            return
        }
        // iOS may deliver Backspace at the START (local 0) of a quote AUTHOR line as an object-replacement
        // RANGE anchored at the previous child's text end (the same offset geometry as an empty container /
        // atom), NOT a collapsed caret. When the range only spans the structural slots before the author's
        // start (`selFrom >= prevTextPosition(before: selTo)`, which excludes a genuine text selection),
        // COLLAPSE it to a caret at the author start so the collapsed-caret relocation branch below handles it.
        if selFrom != selTo, let (region, local) = leafRegion(containingGlobal: selTo),
           case .quoteAuthor = region.ref, local == 0,
           selFrom >= prevTextPosition(before: selTo) {
            anchor = selTo; head = selTo
        }
        // Backspace with a collapsed caret at the START of a quote author line: relocate the caret to the end
        // of the quote's last child (recursive via `prevTextPosition`) — the author is always present, so you
        // simply step OUT of it into the body. Never merge the author into the body, never delete the quote.
        if selFrom == selTo, let (region, local) = leafRegion(containingGlobal: head),
           case .quoteAuthor = region.ref, local == 0 {
            setCaret(global: prevTextPosition(before: region.globalStart))
            return
        }
        if selFrom != selTo {
            editing(coalescing: .deleting) { applySelectionReplace(globalFrom: selFrom, globalTo: selTo, text: "") }
            return
        }
        if isInsideTable(head) {
            guard let active = activeStack(at: head) else { return }
            if active.local > 0 {
                let n = graphemeClusterLengthBeforeCaret(global: head)
                editing(coalescing: .deleting) { applyLeafReplace(globalFrom: head - n, globalTo: head, text: "") }
            } else if active.index > 0 {
                editing { mergeParagraphs(in: active.stack, upperIndex: active.index - 1) }
            } else {
                // Caret at the cell's first-paragraph start: move WITHOUT deleting to the previous text
                // position — the previous cell's end (row-major), or, at the table's FIRST cell, the end
                // of the block before the table. No-op only when the table is the document's first block
                // (nothing before — like Backspace at the very start of a document).
                let prev = prevTextPosition(before: head)
                if prev != head { setCaret(global: prev) }
            }
            return
        }
        // Caret at a media block's leading gap → replace the media with an empty body paragraph in place.
        if let img = mediaBox(atGap: head), let i = boxIndex(of: img) {
            // The gap caret is where a tap / structural image selection lands. The OS clears `imageSelection`
            // via the `selectedTextRange` setter (which calls `clearStructuralSelections()`) BEFORE this runs,
            // so the deletion can't be gated on it — a collapsed gap caret IS the structural-selection signal.
            // Backspace replaces the media with an empty body paragraph in place (caret there), rather than
            // acting on the previous paragraph.
            editing { replaceMediaWithEmptyParagraph(at: i) }
            clearImageSelection()
            return
        }
        // Collapsed caret with text before it inside a block quote (a child's body OR the author line) →
        // delete the grapheme in that leaf region. `resolveBox(at:)` below cannot resolve a position inside
        // the container (its `textLength == 0`), so without this it mis-resolves to the container (lone quote
        // → silent no-op) or to the following sibling (wrong block). Mirrors the `isInsideTable` branch above.
        if selFrom == selTo, isInsideBlockQuote(head),
           let (_, local) = leafRegion(containingGlobal: head), local > 0 {
            let n = graphemeClusterLengthBeforeCaret(global: head)
            editing(coalescing: .deleting) { applyLeafReplace(globalFrom: head - n, globalTo: head, text: "") }
            return
        }
        // Collapsed caret at the START (local 0) of a block quote CHILD. resolveBox below mis-resolves any
        // local-0 position inside the degenerate container to the FOLLOWING sibling block, so resolve it here
        // via activeStack and peel one structural level:
        //   • a quoted LIST item → outdent (nested) or break the list to a plain paragraph (top-level), in place;
        //   • a non-first NON-list child (index > 0) → merge into its previous sibling within the quote;
        //   • an EMPTY first NON-list child (a stray leading blank line) → removed, caret to the next child;
        //   • a NON-empty first NON-list child → un-quoted: extracted as a plain paragraph before the quote.
        // A lone NON-list child (count == 1) keeps the whole-quote un-quote branch below (line ~593).
        if selFrom == selTo, isInsideBlockQuote(head),
           let active = activeStack(at: head), let child = active.box as? BlockBox, active.local == 0 {
            if let list = child.listMembership {
                editing {
                    if list.level > 0 {
                        child.listMembership = ListMembership(marker: list.marker, level: list.level - 1, checked: list.checked)
                    } else {
                        child.listMembership = nil
                        child.style = .body
                    }
                    restyle(child)
                    recomputeSpans()
                }
                return
            }
            if active.stack.boxes.count > 1 {
                if active.index > 0 {
                    editing { mergeParagraphs(in: active.stack, upperIndex: active.index - 1) }
                    return
                }
                if child.textLength == 0 {
                    editing {
                        active.stack.boxes.removeFirst()
                        recomputeSpans()
                        let caret = active.stack.boxes.first?.leafRegions().first?.globalStart ?? head
                        anchor = caret; head = caret
                    }
                    return
                }
                // non-empty first child → un-quote it (extract as a plain paragraph before the quote)
                if let (quoteBox, parentStack, qIndex) = enclosingQuote(at: head),
                   case .blockQuote(let model) = quoteBox.currentBlock(), model.children.count > 1 {
                    editing {
                        let firstBox = makeBox(for: model.children[0], mapper: mapper, quoteStyle: quoteStyle,
                                               pullQuoteStyle: pullQuoteStyle, expandImage: quoteCollapseIcons?.expand,
                                               collapseImage: quoteCollapseIcons?.collapse, horizontalBleed: 0, width: effectiveWidth)
                        let restBox = makeBox(for: .blockQuote(BlockQuote(id: model.id, children: Array(model.children.dropFirst()),
                                                                          collapsed: model.collapsed, author: model.author)),
                                              mapper: mapper, quoteStyle: quoteStyle, pullQuoteStyle: pullQuoteStyle,
                                              expandImage: quoteCollapseIcons?.expand, collapseImage: quoteCollapseIcons?.collapse,
                                              horizontalBleed: 0, width: effectiveWidth)
                        let replacement = [firstBox, restBox].compactMap { $0 }
                        parentStack.boxes.replaceSubrange(qIndex...qIndex, with: replacement)
                        recomputeSpans()
                        let caret = firstBox?.leafRegions().first?.globalStart ?? head
                        anchor = caret; head = caret
                    }
                    return
                }
            } else {
                // A LONE non-list child at local 0 → un-quote the whole quote HERE, before the resolveBox path
                // below (which mis-resolves this in-quote position to a FOLLOWING block and could mis-fire the
                // list-item / merge branches, e.g. when the block after the quote is a list item). Reached via
                // activeStack so a mis-resolved following block can't pre-empt it. (The later count==1
                // un-quote branch is now redundant but harmless.)
                unwrapBlockQuoteLevel()
                return
            }
        }
        guard let pos = resolveBox(at: head) else { return }
        // Backspace at the START of a list item: cancel one indent level, or (at the top level) break the
        // list here — the item becomes a body paragraph keeping its contents, so items before it stay a
        // list and items after start a fresh one. Applies to ANY list item (empty or not) and takes
        // priority over the merge-into-previous / empty-quote branches below. Mirrors empty-list-item Return
        // (`insertParagraphBreak`), but fires for a non-empty item too and always exits to a body paragraph
        // (a quoted list item un-quotes, matching the one-step empty-quote Backspace).
        if pos.local == 0, let p = pos.box as? BlockBox, let list = p.listMembership {
            if list.level > 0 {
                outdent()
            } else {
                editing { p.listMembership = nil; p.style = .body; restyle(p); recomputeSpans() }
            }
            return
        }
        // Backspace at the start of a LONE child of a block quote → un-quote one level (via unwrapBlockQuoteLevel).
        // "Lone" = the only child in its quote container (boxes.count == 1). Content is preserved; the quote
        // wrapper is removed and children are spliced to the parent. A non-lone child backspaces normally
        // (merges with the previous sibling). Mirrors the flat empty-quote branch above, adapted for the
        // `BlockQuoteBox` container structure.
        if selFrom == selTo, isInsideBlockQuote(head),
           let active = activeStack(at: head), let child = active.box as? BlockBox,
           active.local == 0,
           active.stack.boxes.count == 1 {
            unwrapBlockQuoteLevel()   // already wraps itself in editing { }
            return
        }
        if let codeBox = pos.box as? CodeBlockBox, codeBox.textLength == 0,
           let active = activeStack(at: head) {
            // Backspace in an EMPTY code block converts it to a body paragraph (a `CodeBlockBox` is a
            // distinct class, so it's REPLACED in its stack with a body `BlockBox`). Mirrors the empty-quote
            // branch above — without this an empty code block, especially the document's FIRST block, matches
            // no merge branch below and is undeletable.
            editing {
                let body = BlockBox(paragraph: ParagraphBlock(id: codeBox.id, style: .body, runs: []),
                                    mapper: mapper, width: effectiveWidth)
                var newBoxes = active.stack.boxes
                newBoxes.replaceSubrange(active.index...active.index, with: [body])
                active.stack.boxes = newBoxes
                recomputeSpans()
                anchor = body.textStart; head = body.textStart
            }
            return
        }
        if let pqBox = pos.box as? PullQuoteBox, pqBox.textLength == 0,
           let active = activeStack(at: head) {
            // Backspace in an EMPTY pull quote converts it to a body paragraph (`PullQuoteBox` is a distinct
            // class, so it's REPLACED in its stack with a body `BlockBox`). Mirrors the empty-code branch
            // above — without this an empty pull quote matches no merge branch below and is undeletable.
            editing {
                let body = BlockBox(paragraph: ParagraphBlock(id: pqBox.id, style: .body, runs: []),
                                    mapper: mapper, width: effectiveWidth)
                var newBoxes = active.stack.boxes
                newBoxes.replaceSubrange(active.index...active.index, with: [body])
                active.stack.boxes = newBoxes
                recomputeSpans()
                anchor = body.textStart; head = body.textStart
            }
            return
        }
        if pos.box is MediaBlockBox, pos.local == 0 {
            // Backspace at the start of a caption replaces the whole media block with an empty body paragraph
            // in place (caret there), discarding any caption text — consistent with the tap-selected and
            // object-replacement-selection paths (the gap branch above / applySelectionReplace).
            editing { replaceMediaWithEmptyParagraph(at: pos.index) }
        } else if pos.local > 0 {
            let n = graphemeClusterLengthBeforeCaret(global: head)
            editing(coalescing: .deleting) { applyReplace(globalFrom: head - n, globalTo: head, text: "") }
        } else if pos.index > 0, isNonParagraphAtom(boxes[pos.index - 1]) {
            // Start of a paragraph after a NON-TEXT block (image / table / code) that can't absorb a text
            // merge. Backspace must NOT delete that block. An EMPTY paragraph is removed — so "deleting the
            // last paragraph" is always possible; a non-empty one is kept. Either way the caret steps back
            // to that block's nearest text slot (an image's caption end, a table's last cell end, a code
            // block's end) via prevTextPosition — never the block's degenerate node-start boundary.
            let prev = prevTextPosition(before: head)
            if pos.box.textLength == 0 {
                editing { removeBlock(at: pos.index, parkingCaretAt: prev) }
            } else if prev != head {
                setCaret(global: prev)
            }
        } else if pos.index > 0 {
            let prev = boxes[pos.index - 1]
            let from = prev.textStart + prev.textLength
            // The cross-block merge runs through applyReplace → ParagraphBlock.merging, which drops the merged-
            // in runs' pinned font size on a style mismatch (body→heading renders heading-sized).
            editing { applyReplace(globalFrom: from, globalTo: head, text: "") }
        }
    }
}
#endif
