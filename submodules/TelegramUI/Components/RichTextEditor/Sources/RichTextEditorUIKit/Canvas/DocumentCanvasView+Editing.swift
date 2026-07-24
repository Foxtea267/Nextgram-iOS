#if canImport(UIKit)
import UIKit
import RichTextEditorCore

@available(iOS 13.0, *)
extension DocumentCanvasView {
    /// Wraps a mutation: snapshots the document + selection, brackets the input-delegate change,
    /// runs `body`, registers a self-re-registering undo, and refreshes layout/display. This is
    /// the single entry point for every editing operation (typing, structural, list).
    func editing(coalescing: UndoCoalescing = .none, _ body: () -> Void) {
        finalizeMarkedText()   // commit a composition (own undo step) / dismiss a prediction before this edit
        dismissEditMenuForSelectionOrTextChange()   // the text is about to change → close any open menu (native UITextView)
        let before = currentBlocks()
        let beforeAnchor = anchor, beforeHead = head
        // Does this edit CONTINUE the open coalescing run? Same kind, a collapsed caret (not a
        // selection-replace), landing exactly where the last keystroke left off. If so we skip
        // registerUndo entirely — the snapshot taken at the run's START already captures the pre-run
        // document, so one undo reverts the whole run. A caret move / kind switch / selection-replace
        // fails this test and starts a fresh step; see docs/superpowers/specs/2026-07-01-richtext-undo-coalescing-design.md.
        let continuesRun = coalescing != .none && beforeAnchor == beforeHead
            && (openUndoRun.map { $0.kind == coalescing && $0.caret == beforeHead } ?? false)
        // Every edit also moves the caret, so bracket the SELECTION change too — not just the text change.
        // Without this the OS keeps a stale `selectedTextRange` after a programmatic edit (custom emoji
        // keyboard insert / delete), so the caret appears not to advance and the next insert lands at the
        // wrong spot (leaving a stray U+FFFC "service character"). Mirrors `reload`. System-driven keystrokes
        // already let UIKit own the selection; the extra notification there is harmless (matches UITextView).
        textInputDelegate?.textWillChange(self)
        textInputDelegate?.selectionWillChange(self)
        body()
        textInputDelegate?.selectionDidChange(self)
        textInputDelegate?.textDidChange(self)
        if !continuesRun {
            // Undo caret (iOS-style): a CONTENT edit (typing/deleting/paste) collapses the caret
            // (post-body `anchor == head`) → restore a COLLAPSED caret at the end of the restored span,
            // so undoing a deletion/replacement doesn't re-select the restored text. A selection-
            // preserving edit (formatting: bold/italic/link/style) leaves a range post-body → restore the
            // pre-edit SELECTION so you still see what was un-formatted. See the systematic-debugging note.
            let restoreCaret = max(beforeAnchor, beforeHead)   // end of the pre-edit span
            let undoAnchor = (anchor == head) ? restoreCaret : beforeAnchor
            let undoHead   = (anchor == head) ? restoreCaret : beforeHead
            registerUndo(snapshot: before, anchor: undoAnchor, head: undoHead)   // start a fresh undo step
            undoRegistrationCount += 1
        }   // else: coalesce — the run-start snapshot still stands, so no new registration
        // Open / extend / close the coalescing run for the NEXT edit: a coalescable edit that left a
        // collapsed caret opens (or extends) a run at the new caret; anything else closes it.
        openUndoRun = (coalescing != .none && anchor == head) ? (coalescing, head) : nil
        recomputeDocumentHasSpoilers()   // an edit (toggleSpoiler/delete/paste/insert/structural) may add or remove the last spoiler — refresh the syncSpoilers gate before refreshSelectionUI runs it
        // A structural edit can create a fresh empty paragraph (Enter) or empty an existing one (delete its
        // last char), and an empty paragraph's caret side is driven by its per-box writing-direction hint
        // (render-only). Re-derive it from the typing direction now so a new RTL line opens its caret on the
        // RIGHT — otherwise it would keep the default (left) until the next reload/refocus. Empty-box-only work
        // (restyle no-ops on empty storage); the guard inside makes it a cheap no-op when nothing changed.
        refreshEmptyBoxWritingDirections()
        notifyContentSizeChanged(); setNeedsDisplay(); refreshSelectionUI()
        onSelectionChange?()   // an edit moves the caret too — ask the host to scroll it into view (like the arrow-key setter)
    }

    /// Restores a whole-document snapshot, then re-registers the inverse for redo (Phase 1 trick).
    func registerUndo(snapshot blocks: [Block], anchor: Int, head: Int) {
        effectiveUndoManager?.registerUndo(withTarget: self) { target in
            // A system Cmd-Z / shake-undo can fire while composing (the public undo()/redo() finalize first,
            // but the responder path doesn't). Drop any marked-text view state so the snapshot restore can't
            // leave a stale markedRange pointing into the replaced document.
            target.markedRange = nil; target.markedTextIsPrediction = false; target.ghostStyledLayout = nil
            let redo = target.currentBlocks()
            let redoAnchor = target.anchor, redoHead = target.head
            target.textInputDelegate?.textWillChange(target)
            target.textInputDelegate?.selectionWillChange(target)   // undo moves the caret too — keep the OS in sync (see editing)
            target.setBlocks(blocks, width: target.effectiveWidth)
            target.anchor = min(anchor, target.documentSize)
            target.head = min(head, target.documentSize)
            target.textInputDelegate?.selectionDidChange(target)
            target.textInputDelegate?.textDidChange(target)
            target.registerUndo(snapshot: redo, anchor: redoAnchor, head: redoHead)
            target.notifyContentSizeChanged()
            target.setNeedsDisplay(); target.refreshSelectionUI()
        }
    }

    /// The structural-edit engine, now operating on the `BlockStack` that owns the selection (the
    /// root stack, or a table cell's stack — resolved via `activeStack`). Replaces the global range
    /// `[from, to)` with `text` WITHIN that one stack. Same-block: in-place. Cross-block: split/merge
    /// (paragraph↔paragraph) or truncate (image endpoint), dropping covered middle boxes. The endpoints
    /// MUST live in the same stack — callers guarantee this (top-level OR same-cell); a cross-stack
    /// range goes to `applyMultiRegionClear` instead. NOT wrapped in undo — call inside `editing { … }`.
    /// Precondition: `text` must not contain a newline — callers split paragraphs first (see
    /// `insertParagraphBreak`); multi-line paste is deferred (Phase 2c).
    func applyReplace(globalFrom: Int, globalTo: Int, text: String) {
        guard !boxes.isEmpty else { return }
        let lo = clampGlobal(min(globalFrom, globalTo))
        let hi = clampGlobal(max(globalFrom, globalTo))
        guard let start = activeStack(at: lo), let end = activeStack(at: hi), start.stack === end.stack else { return }
        let stack = start.stack

        if start.index == end.index {
            let b = start.box
            let attrs = typingAttributesAtGlobal(b.textStart + start.local)
            b.textLayout.replace(start: start.local, end: end.local,
                                 with: NSAttributedString(string: text, attributes: attrs))
            recomputeSpans()
            let caret = b.textStart + start.local + (text as NSString).length
            anchor = caret; head = caret
            return
        }

        // Cross-block. A media (image/video) or code endpoint is REMOVED only when the selection covers
        // its whole node (the leading gap + the entire text); a selection that ends/starts PARTWAY through
        // the text keeps the block, truncated (the Phase 2c partial behavior — see the truncate branch).
        // Select-All over a document whose first/last block is an image/code fully covers it, so it is
        // dropped here exactly as a covered MIDDLE block already is.
        func endpointFullyCovered(_ box: CanvasBlock) -> Bool {
            (box is MediaBlockBox || box is CodeBlockBox || box is PullQuoteBox) && lo <= coverableContentStart(box) && hi >= coverableContentEnd(box)
        }
        let keepStartMedia = (start.box is MediaBlockBox || start.box is CodeBlockBox || start.box is PullQuoteBox) && !endpointFullyCovered(start.box)
        let keepEndMedia = (end.box is MediaBlockBox || end.box is CodeBlockBox || end.box is PullQuoteBox) && !endpointFullyCovered(end.box)

        // Merge path: each endpoint is a paragraph OR a fully-covered media/code block (which contributes
        // nothing and is dropped). The surviving paragraph is startPrefix + text + endSuffix; replaceSubrange
        // over [start.index ... end.index] drops every box between the endpoints — including a fully-covered
        // endpoint image or code block. (Paragraph↔paragraph is the original 2b split/merge, unchanged.)
        if !keepStartMedia && !keepEndMedia {
            let headPart = (start.box as? BlockBox)?.currentParagraph().split(at: start.local, newID: BlockID.generate()).0
            let tailPart = (end.box as? BlockBox)?.currentParagraph().split(at: end.local, newID: BlockID.generate()).1
            var headRuns = headPart?.runs ?? []
            if !text.isEmpty {
                let ca = mapper.characterAttributes(from: typingAttributesAtGlobal(start.box.textStart + start.local), style: (start.box as? BlockBox)?.style ?? .body)
                headRuns.append(TextRun(text: text, attributes: ca))
            }
            // Base paragraph carries the start paragraph's identity/style when present (preserving the
            // upper block's style across the merge), else the end paragraph's, else a fresh body paragraph
            // (both endpoints were fully-covered media — e.g. Select-All over [image, image]).
            var merged = headPart ?? tailPart ?? ParagraphBlock(id: BlockID.generate(), runs: [])
            merged.runs = headRuns
            if let tailPart { merged = merged.merging(tailPart) }
            // Inherit the endpoints' mapper (both share the stack) so a table cell keeps its smaller
            // base font across the merge — `mapper` is the canvas (document-body) mapper.
            let mergedBox = BlockBox(paragraph: merged, mapper: start.box.mapper, width: effectiveWidth)
            var newBoxes = stack.boxes
            newBoxes.replaceSubrange(start.index...end.index, with: [mergedBox])
            stack.boxes = newBoxes
            recomputeSpans()
            let caret = mergedBox.textStart + (headPart?.utf16Count ?? 0) + (text as NSString).length
            anchor = caret; head = caret
            return
        }
        // A media or code endpoint is only PARTIALLY covered (selection starts/ends partway through its
        // caption/body): TRUNCATE each endpoint's text region (start keeps [0, start.local) + inserted text;
        // end keeps [end.local, …)) and drop ONLY the strictly-covered middle boxes. Do NOT remove the
        // endpoint boxes — a selection ending inside an image/code block keeps that image/code block with
        // its surviving suffix.
        start.box.textLayout.replace(start: start.local, end: start.box.textLength,
                                     with: NSAttributedString(string: text,
                                         attributes: typingAttributesAtGlobal(start.box.textStart + start.local)))
        end.box.textLayout.replace(start: 0, end: end.local, with: NSAttributedString(string: ""))
        if end.index > start.index + 1 {
            var newBoxes = stack.boxes
            newBoxes.removeSubrange((start.index + 1)..<end.index)
            stack.boxes = newBoxes
        }
        recomputeSpans()
        let caret = start.box.textStart + start.local + (text as NSString).length
        anchor = caret; head = caret
    }

    /// Removes the image box at `index`, placing the caret at the end of the previous block's text
    /// (or the start of the new first block's text region). Caller wraps this in `editing { … }`.
    func deleteImageBox(at index: Int) {
        guard boxes.indices.contains(index) else { return }
        var newBoxes = boxes
        newBoxes.remove(at: index)
        if newBoxes.isEmpty {   // a document must never be zero blocks — leave an empty paragraph behind
            newBoxes.append(BlockBox(paragraph: ParagraphBlock(id: BlockID.generate()), mapper: mapper, width: effectiveWidth))
        }
        boxes = newBoxes
        recomputeSpans()
        let caret = index > 0 ? boxes[index - 1].textStart + boxes[index - 1].textLength
                              : (boxes.first?.textStart ?? 0)
        anchor = caret; head = caret
    }

    /// Removes the media block identified by its occurrence `BlockID` — NOT by `mediaID`, which may be shared
    /// by several blocks. Routes through the same path as the image edit-menu "Delete" (`deleteImageBox`):
    /// remove the block, merge the caret up, never leave a zero-block document. No-op when no block has `id`.
    /// Owns its own `editing { }` (one undo step).
    func deleteMediaBlock(id: BlockID) {
        guard let index = boxes.firstIndex(where: { $0.id == id }) else { return }
        editing { self.deleteImageBox(at: index) }
    }

    /// Replaces the media block at `index` with a fresh EMPTY body paragraph, placing the caret in it.
    /// Backspace on a (tap-selected, object-replacement-selected, or caption-start) media block turns the
    /// media into an empty paragraph IN PLACE — distinct from `deleteImageBox`, which removes the block and
    /// merges the caret up into the previous block. A fresh `BlockID` gives the replacement its own view
    /// (the repaint gate keys on box instance/id). Caller wraps this in `editing { … }`.
    func replaceMediaWithEmptyParagraph(at index: Int) {
        guard boxes.indices.contains(index) else { return }
        let empty = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), style: .body, runs: []),
                             mapper: mapper, width: effectiveWidth)
        var newBoxes = boxes
        newBoxes.replaceSubrange(index...index, with: [empty])
        boxes = newBoxes
        recomputeSpans()
        anchor = empty.textStart; head = empty.textStart
    }

    /// True for a block that is NOT an editable text paragraph — an image, a table, a block quote
    /// container, or a code block. A backspace at the start of the paragraph AFTER one of these can't
    /// merge text into it, so it removes an empty paragraph instead of the block (and never deletes
    /// the block). A `BlockBox` (body / heading / quote / list paragraph) is text and merges normally.
    func isNonParagraphAtom(_ box: CanvasBlock) -> Bool {
        box is MediaBlockBox || box is TableBlockBox || box is BlockQuoteBox || box is CodeBlockBox || box is PullQuoteBox
    }

    /// The position just past a media/code block's coverable content, for the Select-All / covered-range
    /// delete checks. Captioned media and code end at their caption/text end; a caption-less AUDIO block has
    /// no text region, so its coverable content ends just after the media atom (`nodeStart + 1`) — NOT at the
    /// collapsed `textStart + textLength` (which equals `nodeStart` for audio).
    /// NOTE: for a `PullQuoteBox` this deliberately only reaches the END OF THE PULL TEXT, not the trailing
    /// author region — `textStart`/`textLength` are the pull-text-only convenience members (see `PullQuoteBox`).
    /// That is fine for the CROSS-BLOCK drop (a fully-covered endpoint quote is removed wholesale, author and
    /// all). A LONE quote whose entire content (incl. author) is selected is dropped separately by the
    /// exact-content-span branch in `applySelectionReplace` (Task 5), which uses the box's full `leafRegions()`.
    func coverableContentEnd(_ box: CanvasBlock) -> Int {
        if let m = box as? MediaBlockBox, m.isAudio { return box.nodeStart + 1 }
        return box.textStart + box.textLength
    }

    /// The position at or before which a selection must start to cover a media/code/pull-quote block's
    /// LEADING edge, for the Select-All / covered-range delete checks (paired with `coverableContentEnd`).
    /// A media atom's leading gap (`nodeStart`) is itself a reachable/renderable caret stop (`isGapPosition`),
    /// so `lo <= nodeStart` is achievable via a real selection. A `PullQuoteBox`'s `nodeStart` is NOT reachable
    /// — it sits on the structural token that opens the `.blockQuote` container wrapping the pull/author
    /// paragraphs (added for the author region), one token before the pull text's own `textStart` — so the
    /// true leading edge a real selection can reach is `textStart`. Code blocks and non-audio/audio media have
    /// no such wrapper (`textStart == nodeStart` there already), so this is a no-op for them.
    func coverableContentStart(_ box: CanvasBlock) -> Int {
        if box is PullQuoteBox { return box.textStart }
        return box.nodeStart
    }

    /// Removes the block at `index`, parking the caret at an explicit global position the caller computed
    /// BEFORE the removal (positions before the removed block are unaffected by it). Used by backspace at
    /// the start of an empty trailing paragraph that follows a non-text block (image / table / code), which
    /// the caller parks at that block's nearest text slot. Caller wraps this in `editing { … }`.
    func removeBlock(at index: Int, parkingCaretAt caret: Int) {
        guard boxes.indices.contains(index) else { return }
        var newBoxes = boxes
        newBoxes.remove(at: index)
        boxes = newBoxes
        recomputeSpans()
        anchor = caret; head = caret
    }

    /// Resolves a global position to the innermost owning `BlockStack` — recursing through `BlockQuoteBox`
    /// children by token span, routing table cells through `cellStack`, and matching leaf boxes by their
    /// single leaf region. Handles top-level, in-cell, in-quote (incl. nested quotes), and
    /// quote-inside-table scenarios in one uniform recursive descent. Table selection is preserved:
    /// a table still resolves via `cellStack(containing:)`.
    ///
    /// For positions that fall outside all leaf regions (document start/end boundary, structural gap),
    /// falls back to `resolveBox`'s snapping behaviour — preserving the pre-Task-5 snapping that
    /// callers relied on. Container-structural boundary positions (at a `TableBlockBox` or
    /// `BlockQuoteBox` boundary) are filtered out of the fallback and return nil, so callers that
    /// handle them separately (`caretSnappedIntoContainer`, `selectionEndpointsEditableTopLevel`) still
    /// own that routing.
    func activeStack(at pos: Int) -> (stack: BlockStack, box: CanvasBlock, local: Int, index: Int)? {
        func descend(_ stack: BlockStack) -> (stack: BlockStack, box: CanvasBlock, local: Int, index: Int)? {
            for (i, b) in stack.boxes.enumerated() {
                // A block-quote child stack: descend by TOKEN SPAN (pos strictly inside the container).
                if let bq = b as? BlockQuoteBox, pos > b.nodeStart, pos < b.nodeStart + b.nodeSize {
                    return descend(bq.children)
                }
                // A table: keep the existing per-cell resolver (cells hold no nested containers in v1).
                if let t = b as? TableBlockBox, pos > b.nodeStart, pos < b.nodeStart + b.nodeSize {
                    return t.cellStack(containing: pos)
                }
                // A leaf text box (paragraph/code/pullQuote/media-caption): match by its single leaf region.
                if let first = b.leafRegions().first, pos >= first.globalStart, pos <= first.globalStart + first.length {
                    return (stack, b, pos - first.globalStart, i)
                }
            }
            return nil
        }
        if let hit = descend(root) { return hit }
        // Fallback: snap structural/document-boundary positions (before first leaf, past last leaf,
        // inter-block gaps) the same way the old resolveBox-based code did. A position INSIDE a container
        // (table cell or block quote) that `descend` couldn't reach — notably a quote/pull-quote AUTHOR
        // region, which is a second leaf region off the child stack — must return nil, NOT the following
        // top-level block that `resolveBox` mis-resolves it to. Genuine top-level boundaries pass through.
        guard !isInsideBlockQuote(pos), !isInsideTable(pos),
              let r = resolveBox(at: pos), !(r.box is TableBlockBox), !(r.box is BlockQuoteBox) else { return nil }
        return (root, r.box, r.local, r.index)
    }

    /// True when a range can be safely edited by the top-level cross-block engine: neither endpoint
    /// is inside a cell or block-quote child, and neither endpoint resolves to a table or block-quote box.
    /// (Spanning a table or block quote as a covered middle box is fine — the merge drops it.)
    func selectionEndpointsEditableTopLevel(_ a: Int, _ b: Int) -> Bool {
        if isInsideTable(a) || isInsideBlockQuote(a) || isInsideTable(b) || isInsideBlockQuote(b) { return false }
        if let ra = resolveBox(at: a), ra.box is TableBlockBox { return false }
        if let ra = resolveBox(at: a), ra.box is BlockQuoteBox { return false }
        if let rb = resolveBox(at: b), rb.box is TableBlockBox { return false }
        if let rb = resolveBox(at: b), rb.box is BlockQuoteBox { return false }
        return true
    }

    /// True when both positions resolve to the **same** owning `BlockStack` — either the same table
    /// cell's stack, or the same block-quote child stack — so the full (stack-scoped) `applyReplace`
    /// engine can edit within that container, exactly like top-level. Generalizes the former
    /// table-only `bothInSameCellStack`.
    func sameOwningStack(_ a: Int, _ b: Int) -> Bool {
        guard let sa = activeStack(at: a), let sb = activeStack(at: b) else { return false }
        return sa.stack === sb.stack
    }

    /// THE single routing point for replacing a (non-empty) selection `[from, to)` with `text`. A
    /// selection whose endpoints share a stack (both top-level, or both in one cell) goes to the
    /// stack-scoped `applyReplace`; a selection that crosses stack boundaries (cross-cell, cell↔body,
    /// cross-table, or an endpoint resting on a table box) goes to the structure-preserving
    /// `applyMultiRegionClear`. Every selection-replacing edit (typing, delete, paste, replace-witness,
    /// insert-image's pre-clear) MUST route through here so none drives a cross-stack range into
    /// `applyReplace`'s same-stack guard (which would silently no-op). Caller wraps in `editing { … }`.
    func applySelectionReplace(globalFrom: Int, globalTo: Int, text: String) {
        // Never delete/replace a PARTIAL surrogate pair (one half of an astral scalar, which the OS can
        // request on backspace as a 1-unit range) — expand to the whole scalar so no stray code unit is left.
        // (Combining-mark clusters like the Tamil consonant+virama are NOT expanded — a composing IME edits
        // the lone mark to recompose the syllable; see `rangeExpandedToScalarBoundaries`.)
        let (globalFrom, globalTo) = rangeExpandedToScalarBoundaries(globalFrom: globalFrom, globalTo: globalTo)
        // A delete covering the WHOLE document (Select-All → Backspace) resets to a single empty BODY paragraph,
        // dropping ALL block formatting/containers (heading style, quote, list, code, table, media) — not just
        // the text. Without this the cross-block merge/clear paths keep the FIRST block's style/container: an
        // empty heading stays a heading, a leading quote survives. Detected as the range spanning from the first
        // renderable text position to the last.
        // Skip the reset ONLY for a PARTIAL selection within a single table (a cross-cell delete keeps its
        // per-cell clear behavior — clear the covered cells, keep the table). A genuine whole-document Select-All
        // still resets: whether it covers a paragraph before/after the table, OR covers the ENTIRE content of a
        // lone/all-table document (which the old `!isInsideTable` guard — and its first cut — wrongly skipped
        // because a Select-All endpoint lands inside a cell).
        if text.isEmpty, !isPartialSelectionWithinOneTable(globalFrom, globalTo),
           min(globalFrom, globalTo) <= snapToRenderable(0, forward: true),
           max(globalFrom, globalTo) >= snapToRenderable(documentSizeValue, forward: false) {
            let body = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), style: .body, runs: []),
                                mapper: mapper, width: effectiveWidth)
            root.boxes = [body]
            recomputeSpans()
            anchor = body.textStart; head = body.textStart
            return
        }
        // A delete whose selection EXACTLY covers one media block's node span — UIKit expands a collapsed caret
        // at an image's empty caption / right after the image into [nodeStart, captionEnd], the "object
        // replacement" atom — resolves BOTH endpoints to that one media box, so the same-stack `applyReplace`
        // below would compute a zero-length edit and silently no-op (the "backspace on an empty caption does
        // nothing" bug). Replace the media with an empty body paragraph in place. A selection that also covers
        // adjacent text doesn't match (its endpoints differ from the node bounds) and falls through to the
        // normal cross-block drop path.
        if text.isEmpty, let i = boxes.firstIndex(where: {
            $0 is MediaBlockBox && globalFrom == $0.nodeStart && globalTo == coverableContentEnd($0)
        }) {
            replaceMediaWithEmptyParagraph(at: i)
            return
        }
        // A delete whose selection covers EXACTLY one (expanded) pull/block quote's entire content — every
        // leaf region including the trailing author line, and nothing outside it (e.g. Select-All over a lone
        // quote). Without this, `activeStack`/`resolveBox` collapse the author position back onto the
        // pull-text / last-child region, so the same-stack `applyReplace` clears only that region's text and
        // STRANDS the box together with its author (the author line survives). Drop the whole quote here,
        // replacing it with an empty body paragraph in place — the exact-span guard means a wider selection
        // (a quote plus a neighbour) still falls through to the normal cross-block path. (`replaceMedia…` is
        // reused generically: it just swaps boxes[i] for an empty body paragraph.)
        if text.isEmpty, let i = boxes.firstIndex(where: { box in
            guard box is PullQuoteBox || box is BlockQuoteBox else { return false }
            let regions = box.leafRegions()   // collapsed quote → [] (handled by the gap/atom paths, not here)
            guard let first = regions.first, let last = regions.last else { return false }
            return globalFrom == first.globalStart && globalTo == last.globalStart + last.length
        }) {
            replaceMediaWithEmptyParagraph(at: i)
            return
        }
        // A replace whose (expanded) range lies entirely within ONE quote AUTHOR region — a selection-replace
        // inside the author, or a system word-replace (autocorrect / dictation) via replace(_:withText:). The
        // author is a SECOND leaf region on the box (off activeStack's radar), so the same-stack applyReplace
        // below would mis-resolve BOTH endpoints to the following block. Route it region-aware, like a cell.
        if let (rf, _) = leafRegion(containingGlobal: clampGlobal(min(globalFrom, globalTo))),
           case .quoteAuthor = rf.ref,
           let (rt, _) = leafRegion(containingGlobal: clampGlobal(max(globalFrom, globalTo))),
           rt.globalStart == rf.globalStart {
            applyLeafReplace(globalFrom: globalFrom, globalTo: globalTo, text: text)
            return
        }
        if selectionEndpointsEditableTopLevel(globalFrom, globalTo) || sameOwningStack(globalFrom, globalTo) {
            applyReplace(globalFrom: globalFrom, globalTo: globalTo, text: text)
        } else {
            applyMultiRegionClear(globalFrom: globalFrom, globalTo: globalTo, text: text)
        }
    }

    /// If a collapsed caret resolves to a table or block-quote box — a structural boundary such as the
    /// position just before/after one of these containers — returns the nearest in-container text start
    /// so the edit routes through that container's stack. Returns `pos` unchanged when it is not at such
    /// a boundary (or the container has no reachable text). Prevents writing through a container's
    /// degenerate `textLayout` (which would silently drop the keystroke).
    func caretSnappedIntoContainer(_ pos: Int) -> Int {
        guard let r = resolveBox(at: pos) else { return pos }
        if !isInsideTable(pos), let table = r.box as? TableBlockBox {
            let snap = pos <= table.nodeStart
                ? table.cellTextStart(row: 0, column: 0)
                : table.cellTextStart(row: table.rowCount - 1, column: table.columnCount - 1)
            return snap ?? pos
        }
        if !isInsideBlockQuote(pos), let bq = r.box as? BlockQuoteBox,
           let first = bq.children.boxes.first?.leafRegions().first {
            return first.globalStart
        }
        return pos
    }

    /// Inserts a literal newline inside the caret's code block (no paragraph split), replacing any
    /// selection first. Caller checks the caret/selection `head` resolves to a `CodeBlockBox`.
    /// Wraps itself in `editing { }`.
    func insertCodeBlockNewline() {
        guard activeStack(at: head)?.box is CodeBlockBox else { return }
        let newline = "\n"
        editing {
            if selFrom != selTo {
                applySelectionReplace(globalFrom: selFrom, globalTo: selTo, text: "")
            }
            // Re-resolve after a possible delete (the caret moved); only insert if still in a code block.
            guard let active = activeStack(at: head), active.box is CodeBlockBox else { return }
            active.box.textLayout.replace(start: active.local, end: active.local,
                                          with: NSAttributedString(string: newline, attributes: CodeBlockBox.codeAttributes()))
            recomputeSpans()
            let caret = active.box.textStart + active.local + (newline as NSString).length
            anchor = caret; head = caret
        }
    }

    /// Removes a code block's trailing "\n" (if present) and inserts an empty body paragraph after it;
    /// caret lands in the new paragraph. Wraps itself in `editing { }`. Mirrors the quote escape hatch
    /// (`insertEmptyBodyParagraph`) — the only way to start a normal paragraph after a code block that
    /// ends the document.
    func exitCodeBlockToBodyParagraph(_ active: (stack: BlockStack, box: CanvasBlock, local: Int, index: Int)) {
        editing {
            let s = active.box.textLayout.attributedString.string as NSString
            if s.hasSuffix("\n") {
                active.box.textLayout.replace(start: s.length - 1, end: s.length, with: NSAttributedString(string: ""))
            }
            let body = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), style: .body, runs: []),
                                mapper: mapper, width: effectiveWidth)
            var newBoxes = active.stack.boxes
            newBoxes.insert(body, at: active.index + 1)
            active.stack.boxes = newBoxes
            recomputeSpans()
            anchor = body.textStart; head = body.textStart
        }
    }

    /// Where double-return (Enter on an empty line of a code block) exits: `.after` for the trailing blank
    /// line, `.before` for the first blank line, `.uncode` for a wholly-empty code block. `nil` for a
    /// non-empty line or a MIDDLE blank line — which just inserts another newline (no exit).
    enum CodeBlockDoubleReturnExit { case after, before, uncode }

    func codeBlockDoubleReturnExit(_ active: (stack: BlockStack, box: CanvasBlock, local: Int, index: Int)) -> CodeBlockDoubleReturnExit? {
        guard active.box is CodeBlockBox else { return nil }
        let s = active.box.textLayout.attributedString.string as NSString
        let nl = unichar(10)   // "\n"
        // A wholly-empty code block (a single blank line) must NOT un-code on a single Return — the escape
        // requires a double Return. The first Return inserts a newline (→ a wholly-BLANK two-line block); a
        // wholly-blank block then un-codes on the next Return.
        if s.length == 0 { return nil }
        var allBlank = true
        for i in 0..<s.length where s.character(at: i) != nl { allBlank = false; break }
        if allBlank { return .uncode }
        let local = active.local
        // Trailing blank line (caret at the end, last line empty) → after.
        if local == s.length, s.character(at: s.length - 1) == nl { return .after }
        // First blank line → before: the caret is ON it (local 0) OR at the start of the content right after
        // it (local 1) — so Enter at the very beginning, then Enter again, exits (the first Enter lands the
        // caret past the new "\n" on the content line, so the second is at local 1).
        if s.character(at: 0) == nl, local <= 1 { return .before }
        return nil                                    // a non-empty line or a MIDDLE blank line → normal newline
    }

    /// Removes a code block's leading "\n" and inserts an empty body paragraph BEFORE it (caret there) —
    /// the mirror of `exitCodeBlockToBodyParagraph` for double-return on the first line.
    func exitCodeBlockToBodyParagraphBefore(_ active: (stack: BlockStack, box: CanvasBlock, local: Int, index: Int)) {
        editing {
            let s = active.box.textLayout.attributedString.string as NSString
            if s.hasPrefix("\n") {
                active.box.textLayout.replace(start: 0, end: 1, with: NSAttributedString(string: ""))
            }
            let body = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), style: .body, runs: []),
                                mapper: mapper, width: effectiveWidth)
            var newBoxes = active.stack.boxes
            newBoxes.insert(body, at: active.index)
            active.stack.boxes = newBoxes
            recomputeSpans()
            anchor = body.textStart; head = body.textStart
        }
    }

    /// Replaces a wholly-empty code block with an empty body paragraph (caret there) — double-return on an
    /// empty code block exits it cleanly (mirrors the empty-quote exit and Backspace-in-empty-code).
    func uncodeEmptyCodeBlock(_ active: (stack: BlockStack, box: CanvasBlock, local: Int, index: Int)) {
        editing {
            let body = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), style: .body, runs: []),
                                mapper: mapper, width: effectiveWidth)
            var newBoxes = active.stack.boxes
            newBoxes.replaceSubrange(active.index...active.index, with: [body])
            active.stack.boxes = newBoxes
            recomputeSpans()
            anchor = body.textStart; head = body.textStart
        }
    }

    // MARK: - Pull-quote in-block editing (mirrors the code-block editing affordances)

    /// Where double-return (Enter on an empty line of a pull quote) exits: `.after` for the trailing blank
    /// line, `.before` for the first blank line, `.unmake` for a wholly-empty pull quote. `nil` for a
    /// non-empty line or a MIDDLE blank line — which just inserts another interior newline (no exit).
    enum PullQuoteDoubleReturnExit { case after, before, unmake }

    /// Inserts a literal newline inside the caret's pull quote (no paragraph split), replacing any selection
    /// first. The inserted newline carries pull-quote attributes (italic/centered). Caller checks the caret
    /// resolves to a `PullQuoteBox`. Wraps itself in `editing { }`.
    func insertPullQuoteNewline() {
        guard activeStack(at: head)?.box is PullQuoteBox else { return }
        editing {
            if selFrom != selTo { applySelectionReplace(globalFrom: selFrom, globalTo: selTo, text: "") }
            guard let active = activeStack(at: head), active.box is PullQuoteBox else { return }
            active.box.textLayout.replace(start: active.local, end: active.local,
                with: NSAttributedString(string: "\n", attributes: PullQuoteBox.pullQuoteTypingAttributes(mapper)))
            recomputeSpans()
            let caret = active.box.textStart + active.local + 1
            anchor = caret; head = caret
        }
    }

    func pullQuoteDoubleReturnExit(_ active: (stack: BlockStack, box: CanvasBlock, local: Int, index: Int)) -> PullQuoteDoubleReturnExit? {
        guard active.box is PullQuoteBox else { return nil }
        let s = active.box.textLayout.attributedString.string as NSString
        let nl = unichar(10)   // "\n"
        // A wholly-empty pull quote must NOT un-make on a single Return — the escape requires a double Return.
        // The first Return inserts a newline (→ a wholly-BLANK two-line quote); a wholly-blank quote then
        // un-makes on the next Return.
        if s.length == 0 { return nil }
        var allBlank = true
        for i in 0..<s.length where s.character(at: i) != nl { allBlank = false; break }
        if allBlank { return .unmake }
        let local = active.local
        if local == s.length, s.character(at: s.length - 1) == nl { return .after }
        if s.character(at: 0) == nl, local <= 1 { return .before }
        return nil
    }

    /// Removes a pull quote's trailing "\n" (if present) and inserts an empty body paragraph after it;
    /// caret lands in the new paragraph. Mirrors `exitCodeBlockToBodyParagraph`.
    func exitPullQuoteToBodyParagraph(_ active: (stack: BlockStack, box: CanvasBlock, local: Int, index: Int)) {
        editing {
            let s = active.box.textLayout.attributedString.string as NSString
            if s.hasSuffix("\n") {
                active.box.textLayout.replace(start: s.length - 1, end: s.length, with: NSAttributedString(string: ""))
            }
            let body = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), style: .body, runs: []),
                                mapper: mapper, width: effectiveWidth)
            var newBoxes = active.stack.boxes
            newBoxes.insert(body, at: active.index + 1)
            active.stack.boxes = newBoxes
            recomputeSpans()
            anchor = body.textStart; head = body.textStart
        }
    }

    /// Removes a pull quote's leading "\n" and inserts an empty body paragraph BEFORE it (caret there).
    /// Mirrors `exitCodeBlockToBodyParagraphBefore`.
    func exitPullQuoteToBodyParagraphBefore(_ active: (stack: BlockStack, box: CanvasBlock, local: Int, index: Int)) {
        editing {
            let s = active.box.textLayout.attributedString.string as NSString
            if s.hasPrefix("\n") {
                active.box.textLayout.replace(start: 0, end: 1, with: NSAttributedString(string: ""))
            }
            let body = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), style: .body, runs: []),
                                mapper: mapper, width: effectiveWidth)
            var newBoxes = active.stack.boxes
            newBoxes.insert(body, at: active.index)
            active.stack.boxes = newBoxes
            recomputeSpans()
            anchor = body.textStart; head = body.textStart
        }
    }

    /// Replaces a wholly-empty pull quote with an empty body paragraph (caret there). Mirrors
    /// `uncodeEmptyCodeBlock`.
    func unmakeEmptyPullQuote(_ active: (stack: BlockStack, box: CanvasBlock, local: Int, index: Int)) {
        editing {
            let body = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), style: .body, runs: []),
                                mapper: mapper, width: effectiveWidth)
            var newBoxes = active.stack.boxes
            newBoxes.replaceSubrange(active.index...active.index, with: [body])
            active.stack.boxes = newBoxes
            recomputeSpans()
            anchor = body.textStart; head = body.textStart
        }
    }

    // MARK: - Table header-cell double-return (exit ABOVE the table)

    /// True when Return should EXIT a header (first-row) table cell to a new body paragraph ABOVE the
    /// table: a collapsed caret at the START of the cell's SECOND block, whose FIRST block is an empty
    /// paragraph (the leading-blank case). The table analog of the code block's "two newlines at the
    /// beginning exits before". Header rows only; a trailing blank (previous block non-empty), a
    /// non-leading blank, or a body-row cell falls through to the normal in-cell split. The `activeTable()`
    /// guard also confirms the caret is in a table, so this can't misfire on a top-level paragraph.
    func headerCellDoubleReturnExitsAbove(_ active: (stack: BlockStack, box: CanvasBlock, local: Int, index: Int)) -> Bool {
        guard active.box is BlockBox, active.index == 1, active.local == 0,
              let first = active.stack.boxes.first as? BlockBox, first.textLength == 0 else { return false }
        guard let table = activeTable(), table.box.isHeaderRow(table.row) else { return false }
        return true
    }

    /// Exits a header cell's leading-blank double-return: drops the empty first block from the cell and
    /// inserts an empty body paragraph immediately BEFORE the table (caret there). Mirrors
    /// `exitCodeBlockToBodyParagraphBefore`. Wraps itself in `editing { }`.
    func exitHeaderCellToBodyParagraphBefore(_ active: (stack: BlockStack, box: CanvasBlock, local: Int, index: Int)) {
        guard let table = activeTable() else { return }
        editing {
            // Drop the empty leading block from the cell (active.index == 1 ⇒ index 0 is that empty block;
            // the cell keeps its remaining ≥1 block). The table box itself is unchanged, so its top-level
            // index in `boxes` — and the `active.stack` cell reference — stay valid.
            var cellBoxes = active.stack.boxes
            cellBoxes.remove(at: 0)
            active.stack.boxes = cellBoxes
            // Insert an empty body paragraph immediately before the table (17pt canvas mapper, not the
            // cell's 15pt variant).
            let body = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), style: .body, runs: []),
                                mapper: mapper, width: effectiveWidth)
            var nb = boxes
            nb.insert(body, at: table.index)
            boxes = nb
            recomputeSpans()
            anchor = body.textStart; head = body.textStart
        }
    }

    /// Splits the caret's paragraph at the caret, within whatever `BlockStack` owns the caret (root
    /// or a cell). Deletes any selection first (bounded if it touches a table). Caret → new block start.
    func insertParagraphBreak() {
        guard !boxes.isEmpty else { return }
        // Return on an EMPTY list item does NOT continue the list: a nested item outdents one level, a
        // top-level (level 0) one ends the list (becomes a body paragraph — or, inside a quote, an empty
        // quote line). The caret stays put. Matches the placeholder hint; a non-empty list item or plain
        // paragraph falls through to a normal split.
        if selFrom == selTo, let active = activeStack(at: head), let p = active.box as? BlockBox,
           let list = p.listMembership, p.textLength == 0 {
            if list.level > 0 {
                outdent()
            } else {
                editing {
                    p.listMembership = nil
                    p.style = .body
                    restyle(p)
                    recomputeSpans()
                }
            }
            return
        }
        // Enter in a media caption (image / video / location) splits it: the head stays as the caption,
        // the tail becomes a new body paragraph immediately after the media (caret there). A caret at the
        // end produces an empty new paragraph; a caret at the start moves the whole caption down. Audio is
        // caption-less and excluded — its Enter fires the gap-caret branch in insertText before we reach here.
        if selFrom == selTo, let active = activeStack(at: head),
           let mediaBox = active.box as? MediaBlockBox, !mediaBox.isAudio {
            editing {
                guard case .media(let mediaBlock) = mediaBox.currentBlock() else { return }
                let tmpCaption = ParagraphBlock(id: BlockID.generate(), style: .caption, runs: mediaBlock.caption)
                let parts = tmpCaption.split(at: active.local, newID: BlockID.generate())
                // Rebuild via the CONTAINER initializer (`items:`), not the legacy single-media one — the
                // legacy init wraps only `mediaBlock.mediaID`/`kind`/`naturalSize` (the FIRST item), which
                // silently drops items[1...] for a multi-item (mosaic) container. See docs/superpowers/sdd
                // task-7 notes.
                let newMedia = MediaBlock(id: mediaBlock.id, items: mediaBlock.items, displayWidth: mediaBlock.displayWidth,
                                          alignment: mediaBlock.alignment, caption: parts.0.runs)
                let newMediaBox = MediaBlockBox(media: newMedia, mapper: mediaBox.mapper, width: effectiveWidth,
                                                horizontalBleed: mediaBox.horizontalBleed)
                let bodyBox = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), style: .body, runs: parts.1.runs),
                                       mapper: mediaBox.mapper, width: effectiveWidth)
                var newBoxes = active.stack.boxes
                let replacement: [any CanvasBlock] = [newMediaBox, bodyBox]
                newBoxes.replaceSubrange(active.index...active.index, with: replacement)
                active.stack.boxes = newBoxes
                recomputeSpans()
                anchor = bodyBox.textStart; head = bodyBox.textStart
            }
            return
        }
        editing {
            if selFrom != selTo {
                applySelectionReplace(globalFrom: selFrom, globalTo: selTo, text: "")
            }
            guard let active = activeStack(at: head), let p = active.box as? BlockBox else { return }
            let split = p.currentParagraph().split(at: active.local, newID: BlockID.generate())
            let upper = split.0
            var lower = split.1
            // A heading is a single-line title: the paragraph AFTER a Return is a body paragraph, not another
            // heading (matches word processors' "next paragraph style"). Applies to the split-off lower half —
            // empty when Return is at the heading's end, or carrying the tail text when mid-heading.
            switch upper.style {
            case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
                lower.style = .body
                // `currentParagraph()` PINS the rendered font size into each run on read-back, so the tail
                // carries the heading's large size; drop it so the now-body tail inherits the body style size.
                lower.runs = lower.runs.map { var r = $0; r.attributes.fontSize = nil; return r }
            default: break
            }
            if lower.list?.marker == .checklist { lower.list?.checked = false }   // a new checklist item is never pre-checked
            // Both halves inherit `p`'s mapper so an in-cell split keeps the cell's smaller base font
            // (including the new EMPTY half, whose later first-typed character reads its box's mapper).
            let upperBox = BlockBox(paragraph: upper, mapper: p.mapper, width: effectiveWidth)
            let lowerBox = BlockBox(paragraph: lower, mapper: p.mapper, width: effectiveWidth)
            var newBoxes = active.stack.boxes
            newBoxes.replaceSubrange(active.index...active.index, with: [upperBox, lowerBox])
            active.stack.boxes = newBoxes
            recomputeSpans()
            anchor = lowerBox.textStart; head = lowerBox.textStart
        }
    }

    /// Merges `stack.boxes[upperIndex+1]` into `stack.boxes[upperIndex]` (both paragraphs), within the
    /// given stack. Caret lands at the join. Caller wraps in `editing { }`.
    func mergeParagraphs(in stack: BlockStack, upperIndex: Int) {
        guard stack.boxes.indices.contains(upperIndex), stack.boxes.indices.contains(upperIndex + 1),
              let upper = stack.boxes[upperIndex] as? BlockBox,
              let lower = stack.boxes[upperIndex + 1] as? BlockBox else { return }
        let joinLocal = upper.currentParagraph().utf16Count
        // `merging` drops the lower paragraph's pinned font size on a cross-style merge (body→heading etc.),
        // so the merged text inherits the surviving upper style's size. See ParagraphBlock.merging.
        let merged = upper.currentParagraph().merging(lower.currentParagraph())
        // Inherit `upper`'s mapper (same stack as `lower`) so an in-cell merge keeps the cell's base font.
        let mergedBox = BlockBox(paragraph: merged, mapper: upper.mapper, width: effectiveWidth)
        var newBoxes = stack.boxes
        newBoxes.replaceSubrange(upperIndex...(upperIndex + 1), with: [mergedBox])
        stack.boxes = newBoxes
        recomputeSpans()
        let caret = mergedBox.textStart + joinLocal
        anchor = caret; head = caret
    }

    /// Inserts a media block (`kind`, with the given `caption`, empty by default) at the caret, splitting the caret's paragraph
    /// if mid-text. The host resolves `mediaID` to a view via the canvas's `mediaViewProvider` (each
    /// occurrence gets its own view, keyed by the new block's `BlockID`). Caret lands in the new caption.
    /// Inserts `document`'s blocks at the caret. If the caret's top-level block is an empty paragraph (any
    /// empty `BlockBox`, regardless of style), that block is REPLACED by the inserted blocks; otherwise they
    /// are inserted AFTER the caret's top-level block (the current block is never split). One undo step; the
    /// caret lands at the end of the inserted content. A no-op for an empty document. Mirrors `insertMedia`'s
    /// splice, building boxes with the same `makeBox` factory `setBlocks` uses.
    func insertDocument(_ document: Document) {
        guard !document.blocks.isEmpty else { return }
        editing { insertDocumentBlocks(document.blocks) }
    }

    /// Box-level insert of `blocks` at the caret (NO `editing{}` — the caller owns the undo step): the caret's
    /// block is REPLACED if it's an empty paragraph, otherwise the blocks are inserted AFTER it (never
    /// splitting it). Caret lands at the end of the inserted content. Shared by `insertDocument` and by
    /// `replaceRange`'s non-text-gap fallback.
    func insertDocumentBlocks(_ blocks: [Block]) {
        let newBoxes = blocks.compactMap {
            makeBox(for: $0, mapper: mapper, quoteStyle: quoteStyle, pullQuoteStyle: pullQuoteStyle,
                    expandImage: quoteCollapseIcons?.expand, collapseImage: quoteCollapseIcons?.collapse,
                    horizontalBleed: mediaBlockStyle.horizontalBleed, width: effectiveWidth)
        }
        guard !newBoxes.isEmpty else { return }
        var updated = boxes
        let firstInserted: Int
        // Find the TOP-LEVEL block whose structural span contains the caret. This uses `nodeStart`/`nodeSize`
        // (which cover nested content) rather than `resolveBox`, whose text-span loop mis-resolves a caret
        // INSIDE a quote/table to the FOLLOWING top-level block — see the note in `insertMedia`.
        if let index = boxes.firstIndex(where: { head >= $0.nodeStart && head < $0.nodeStart + $0.nodeSize }) {
            if let p = boxes[index] as? BlockBox, p.textLength == 0 {
                updated.replaceSubrange(index...index, with: newBoxes)           // empty paragraph → replace it
                firstInserted = index
            } else {
                updated.insert(contentsOf: newBoxes, at: index + 1)              // else insert AFTER the block
                firstInserted = index + 1
            }
        } else {
            updated.append(contentsOf: newBoxes)                                 // caret past the last block → append
            firstInserted = updated.count - newBoxes.count
        }
        boxes = updated
        recomputeSpans()
        let last = boxes[firstInserted + newBoxes.count - 1]                      // caret at end of inserted content
        anchor = last.textStart + last.textLength; head = anchor
    }

    /// Replaces the global range `[globalFrom, globalTo)` with `document`'s blocks as ONE undo step, via the
    /// pure-Core `Document.replacingRange` (structural delete of the complement + the tested `insertingFragment`
    /// splice). Because the delete is computed structurally rather than through a caret-based cross-block walk,
    /// a fully-covered table/media is dropped at EITHER end of a mixed range — unlike `applySelectionReplace`,
    /// whose `resolveBox` routing mishandles a leading-edge container (the documented degenerate-container tech
    /// debt). An empty `document` deletes the range. The caret collapses to the end of the inserted content.
    func replaceRange(globalFrom: Int, globalTo: Int, with document: Document) {
        editing {
            let (newDoc, caret) = Document(blocks: currentBlocks())
                .replacingRange(globalFrom: globalFrom, globalTo: globalTo, with: document)
            setBlocks(newDoc.blocks, width: effectiveWidth)
            anchor = min(caret, documentSize); head = anchor
        }
    }

    func insertMedia(mediaID: String, naturalSize: CGSize, kind: MediaKind, caption: [TextRun] = []) {
        // `!isInsideBlockQuote(head)` is load-bearing: a caret inside a quote has no degenerate-container-safe
        // resolveBox, so `resolveBox(at: head)` below mis-resolves to the FOLLOWING top-level block and the media
        // would be inserted there. Media isn't supported inside quotes (v1) → no-op.
        guard !boxes.isEmpty, !isInsideBlockQuote(head) else { return }
        // Focus the editor BEFORE the edit so the caret placed at/after the new media is immediately
        // interactive — same first-responder-gated synchronous-layout reason as `insertTable` (the only
        // synchronous caret-move layout, the façade's `scrollCaretIntoView`, is FR-gated; without focus the
        // new block's frames stay stale until a later interaction).
        if !isFirstResponder { _ = becomeFirstResponder() }
        editing {
            if selFrom != selTo { applySelectionReplace(globalFrom: selFrom, globalTo: selTo, text: "") }
            guard let pos = resolveBox(at: head) else { return }
            let mediaBlock = MediaBlock(id: BlockID.generate(), mediaID: mediaID, kind: kind,
                                        naturalSize: Size2D(width: Double(naturalSize.width),
                                                            height: Double(naturalSize.height)),
                                        caption: caption)
            let mediaBox = MediaBlockBox(media: mediaBlock, mapper: mapper, width: effectiveWidth,
                                         horizontalBleed: mediaBlockStyle.horizontalBleed)
            var newBoxes = boxes
            if let p = pos.box as? BlockBox, p.textLength == 0 {
                newBoxes.replaceSubrange(pos.index...pos.index, with: [mediaBox])   // empty paragraph → replace it
            } else if let p = pos.box as? BlockBox, pos.local > 0, pos.local < p.textLength {
                // split the paragraph and insert the media between the halves
                let (upper, lower) = p.currentParagraph().split(at: pos.local, newID: BlockID.generate())
                let upperBox = BlockBox(paragraph: upper, mapper: mapper, width: effectiveWidth)
                let lowerBox = BlockBox(paragraph: lower, mapper: mapper, width: effectiveWidth)
                let replacement: [any CanvasBlock] = [upperBox, mediaBox, lowerBox]
                newBoxes.replaceSubrange(pos.index...pos.index, with: replacement)
            } else if pos.local == 0 {
                newBoxes.insert(mediaBox, at: pos.index)        // before the caret's block
            } else {
                newBoxes.insert(mediaBox, at: pos.index + 1)    // after the caret's block
            }
            boxes = newBoxes
            recomputeSpans()
            if kind == .audio {
                // Audio is caption-less: land the caret in the body paragraph AFTER the audio, appending an
                // empty one when the audio is the last block or is followed by a non-paragraph atom, so typing
                // continues. (Captioned media lands the caret in its caption.)
                let mediaIndex = boxes.firstIndex(where: { $0.id == mediaBox.id }) ?? boxes.count - 1
                let following = mediaIndex + 1 < boxes.count ? boxes[mediaIndex + 1] : nil
                if let nextParagraph = following as? BlockBox {
                    anchor = nextParagraph.textStart; head = nextParagraph.textStart
                } else {
                    let trailing = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), style: .body, runs: []),
                                            mapper: mapper, width: effectiveWidth)
                    var withTrailing = boxes
                    withTrailing.insert(trailing, at: mediaIndex + 1)
                    boxes = withTrailing
                    recomputeSpans()
                    anchor = trailing.textStart; head = trailing.textStart
                }
            } else {
                anchor = mediaBox.textStart; head = mediaBox.textStart
            }
        }
    }

    /// Inserts a new body paragraph immediately before the (top-level) ATOM box at `index` — currently a
    /// media block — containing `text` (empty for a bare newline). The caret lands at the end of the
    /// inserted text. Used when a keystroke arrives with the caret on an atom's leading gap, so it opens a
    /// normal paragraph there instead of falling into the atom's (display-only) layout. Mirrors `insertMedia`'s
    /// block-insert. Caller wraps this in `editing { … }`.
    func insertBodyParagraph(beforeBoxAt index: Int, text: String) {
        guard boxes.indices.contains(index) else { return }
        let runs = text.isEmpty ? [] : [TextRun(text: text)]
        let newBox = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), runs: runs),
                              mapper: mapper, width: effectiveWidth)
        var newBoxes = boxes
        newBoxes.insert(newBox, at: index)
        boxes = newBoxes
        recomputeSpans()
        let caret = newBox.textStart + (text as NSString).length
        anchor = caret; head = caret
    }

    /// Inserts an empty body paragraph at `insertIndex` (shifting later boxes down), placing the caret in
    /// it. The escape hatch for a quote (tap below it / Shift+Return) — there is otherwise no way to start
    /// a normal paragraph adjacent to a quote at the document's edge. Undoable.
    func insertEmptyBodyParagraph(at insertIndex: Int) {
        guard insertIndex >= 0, insertIndex <= boxes.count else { return }
        editing {
            let newBox = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), style: .body, runs: []),
                                  mapper: mapper, width: effectiveWidth)
            var newBoxes = boxes
            newBoxes.insert(newBox, at: insertIndex)
            boxes = newBoxes
            recomputeSpans()
            anchor = newBox.textStart; head = newBox.textStart
        }
    }

    /// In-place text replace within the leaf region's layout (used for typing inside cells, and as
    /// the same-leaf fast path generally). Recomputes spans. Caller wraps in `editing { }`.
    func applyLeafReplace(globalFrom: Int, globalTo: Int, text: String) {
        guard let (region, _) = leafRegion(containingGlobal: clampGlobal(min(globalFrom, globalTo))) else { return }
        let lo = clampGlobal(min(globalFrom, globalTo)) - region.globalStart
        let hi = min(clampGlobal(max(globalFrom, globalTo)) - region.globalStart, region.length)
        guard lo >= 0, hi >= lo else { return }
        let attrs = typingAttributeDict(region: region, atLocal: lo)
        region.layout.replace(start: lo, end: hi, with: NSAttributedString(string: text, attributes: attrs))
        recomputeSpans()
        let caret = region.globalStart + lo + (text as NSString).length
        anchor = caret; head = caret
    }

    /// Structure-preserving clear of a selection that crosses `BlockStack` boundaries (cross-cell,
    /// cell↔body, cross-table). Clears the covered text in EVERY touched leaf region (paragraph or
    /// image caption), and lands any replacement `text` in the region owning **selFrom** (its kept
    /// prefix + text), exactly as a single-region replace would. Never removes a box, cell, row, or the
    /// grid — a fully-covered cell keeps an empty paragraph; a covered image keeps its atom (only its
    /// caption clears). One `recomputeSpans()`; caret always collapses to selFrom (+ text length), even
    /// when the selection covered only empty regions (so a keystroke is never lost / the selection never
    /// sticks). Mirrors `selectionRects` so what clears == what was highlighted. Caller wraps in `editing { … }`.
    func applyMultiRegionClear(globalFrom: Int, globalTo: Int, text: String) {
        let lo = clampGlobal(min(globalFrom, globalTo))
        let hi = clampGlobal(max(globalFrom, globalTo))
        guard lo < hi else { return }
        // The region owning selFrom is where replacement text lands (it may be empty, hence not in
        // `touched`). Capture its attrs before any clearing mutates it.
        let anchorRegion = leafRegion(containingGlobal: lo)
        let insertAttrs = anchorRegion.map { typingAttributeDict(region: $0.region, atLocal: $0.local) } ?? [:]
        let touched: [(region: LeafTextRegion, rLo: Int, rHi: Int)] = allLeafRegions().compactMap { r in
            let a = max(lo, r.globalStart), b = min(hi, r.globalStart + r.length)
            guard a < b else { return nil }
            return (r, a - r.globalStart, b - r.globalStart)
        }
        var insertedIntoAnchor = false
        for t in touched {
            let isAnchor = (anchorRegion?.region.layout) === t.region.layout
            let s = isAnchor ? text : ""
            let attrs: [NSAttributedString.Key: Any] = isAnchor ? insertAttrs : [:]
            t.region.layout.replace(start: t.rLo, end: t.rHi, with: NSAttributedString(string: s, attributes: attrs))
            if isAnchor { insertedIntoAnchor = true }
        }
        // The selFrom region had no covered text (e.g. an empty start cell), so it wasn't cleared
        // above — insert `text` there directly so the keystroke isn't lost.
        if !insertedIntoAnchor, !text.isEmpty, let a = anchorRegion {
            a.region.layout.replace(start: a.local, end: a.local,
                                    with: NSAttributedString(string: text, attributes: insertAttrs))
        }
        recomputeSpans()
        // selFrom's region start is unaffected by the edit (nothing before lo changed), so this is
        // valid post-recompute. With no owning region (range in a structural gap), just collapse to lo.
        let caret = anchorRegion.map { $0.region.globalStart + $0.local + (text as NSString).length } ?? clampGlobal(lo)
        anchor = caret; head = caret
    }

    /// True if `pos` is inside a table (its owning top-level box is a `TableBlockBox`).
    func isInsideTable(_ pos: Int) -> Bool {
        return owningTable(pos) != nil
    }

    /// The `TableBlockBox` whose leaf regions contain `pos`, or nil if `pos` is not inside any table.
    func owningTable(_ pos: Int) -> TableBlockBox? {
        for box in boxes {
            guard let table = box as? TableBlockBox else { continue }
            for r in table.leafRegions() where pos >= r.globalStart && pos <= r.globalStart + r.length { return table }
        }
        return nil
    }

    /// True when `[a, b]` is a PARTIAL selection within a SINGLE table — both endpoints in the same table AND the
    /// range does NOT cover the table's entire content (first leaf region → last leaf region). The Select-All →
    /// empty-paragraph reset skips this case so a partial cross-cell delete keeps its per-cell clear behavior
    /// (clear the covered cells, keep the table). A selection that covers the table's WHOLE content — a genuine
    /// Select-All of a lone/all-table document — is NOT partial, so it resets to an empty paragraph like any other
    /// whole-document select; likewise a selection that also covers non-table content (owningTable == nil at an
    /// endpoint) is not "within one table" and resets.
    func isPartialSelectionWithinOneTable(_ a: Int, _ b: Int) -> Bool {
        let lo = clampGlobal(min(a, b)), hi = clampGlobal(max(a, b))
        guard let ta = owningTable(lo), let tb = owningTable(hi), ta === tb else { return false }
        let regions = ta.leafRegions()
        if let first = regions.first, let last = regions.last,
           lo <= first.globalStart, hi >= last.globalStart + last.length {
            return false   // covers the table's whole content → a full-table select, let it reset
        }
        return true
    }

    /// True if `pos` is inside a block-quote container (its owning top-level box is a `BlockQuoteBox`).
    /// Mirrors `isInsideTable` over `BlockQuoteBox` leaf regions. Because `BlockQuoteBox.leafRegions()`
    /// recurses into nested quotes, checking the top-level `BlockQuoteBox`es is sufficient.
    func isInsideBlockQuote(_ pos: Int) -> Bool {
        for box in boxes where box is BlockQuoteBox {
            for r in box.leafRegions() where pos >= r.globalStart && pos <= r.globalStart + r.length { return true }
        }
        return false
    }
}
#endif
