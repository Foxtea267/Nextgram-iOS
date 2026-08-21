#if canImport(UIKit)
import UIKit
import RichTextEditorCore

// Prediction / correction traits. The canvas conforms to UITextInputTraits transitively
// (UITextInput: UIKeyInput: UITextInputTraits); these are @objc-optional members we override.
// Autocorrect/spell-check are ON because system inline predictions reportedly require them
// (and they're standard for a text editor). inlinePredictionType opts in to the iOS 17+ feature.
@available(iOS 13.0, *)
extension DocumentCanvasView {
    var autocorrectionType: UITextAutocorrectionType { get { .yes } set { } }
    var spellCheckingType: UITextSpellCheckingType { get { isSpellCheckingEnabled ? .yes : .no } set { } }
}

// `UITextInlinePredictionType` is iOS 17+; below it the trait simply isn't offered (no inline predictions).
@available(iOS 17.0, *)
extension DocumentCanvasView {
    var inlinePredictionType: UITextInlinePredictionType { get { .yes } set { } }
}

@available(iOS 13.0, *)
extension DocumentCanvasView {
    var markedTextRange: UITextRange? {
        guard let m = markedRange else { return nil }
        return DocumentTextRange(DocumentTextPosition(m.from), DocumentTextPosition(m.to))
    }
    // We draw our own underline decoration; no system styling.
    var markedTextStyle: [NSAttributedString.Key: Any]? { get { nil } set { } }

    /// True iff `pos` is inside a TOP-LEVEL body paragraph (a `BlockBox`) — not a table cell, image
    /// caption, or structural boundary. v1 composes only here (cells/captions are a follow-up).
    func isBodyParagraphPosition(_ pos: Int) -> Bool {
        // Exclude container interiors: a caret inside a table cell OR a block quote is not a TOP-LEVEL body
        // paragraph. `box(containingGlobal:)` has no degenerate-safe resolution there and would mis-resolve a
        // quote-interior position to the FOLLOWING top-level BlockBox and wrongly report `true` — letting IME
        // marked text compose in a quote (v1 composes only in top-level body paragraphs).
        guard !isInsideTable(clampGlobal(pos)), !isInsideBlockQuote(clampGlobal(pos)) else { return false }
        if let (box, _) = box(containingGlobal: clampGlobal(pos)), box is BlockBox { return true }
        return false
    }

    func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        let text = markedText ?? ""
        // The range being replaced: an existing composition, else the live selection.
        let lo = markedRange?.from ?? selFrom
        let hi = markedRange?.to ?? selTo

        // Body-paragraph guard: if we can't compose here, commit any pending composition and fall back
        // to a plain insert so we never strand provisional text in an unsupported region.
        guard isBodyParagraphPosition(lo) else {
            commitMarkedText()
            if !text.isEmpty { insertText(text) }
            return
        }

        // Capture the composition-start snapshot on the FIRST setMarkedText of a run.
        if markedRange == nil {
            compositionUndoSnapshot = currentBlocks()
            compositionAnchorHead = (anchor, head)
        }

        // Provisional text edit: in place, NO undo snapshot (applyReplace mutates + recomputes spans).
        textInputDelegate?.textWillChange(self)
        applyReplace(globalFrom: lo, globalTo: hi, text: text)
        textInputDelegate?.textDidChange(self)

        let newLen = (text as NSString).length
        if newLen == 0 {
            markedRange = nil
            markedTextIsPrediction = false
            compositionUndoSnapshot = nil; compositionAnchorHead = nil   // cancelled — discard snapshot
        } else {
            markedRange = (lo, lo + newLen)
            // A system inline PREDICTION arrives with the caret at the START (sel {0,0}) — the ghost
            // trails the caret; CJK/IME composition keeps the caret at the END. (See markedTextIsPrediction.)
            markedTextIsPrediction = (selectedRange.location == 0 && selectedRange.length == 0)
        }

        refreshPredictionStyling()   // grey ghost for a prediction; clears it otherwise

        // Place the selection within the marked text (selectedRange is marked-text-relative).
        textInputDelegate?.selectionWillChange(self)
        let selStart = clampGlobal(lo + selectedRange.location)
        anchor = selStart; head = clampGlobal(selStart + selectedRange.length)
        textInputDelegate?.selectionDidChange(self)

        notifyContentSizeChanged(); setNeedsDisplay(); refreshSelectionUI()
        onSelectionChange?()   // a growing composition advances the caret — scroll it into view (CJK/IME typing)
    }

    func unmarkText() {
        commitMarkedText()
    }

    /// Commits the active composition: registers ONE undo from the start snapshot and clears marked
    /// state. Does NOT mutate text (provisional chars stay committed). No-op when not composing.
    /// Keyboard-driven accept/confirm paths (unmarkText, the confirming-keystroke guard) call this; our
    /// own gesture/focus/structural interruptions call `finalizeMarkedText()` instead, which DISMISSES a
    /// prediction rather than committing it.
    func commitMarkedText() {
        guard markedRange != nil else { return }
        breakUndoCoalescing()   // a composition is its own undo step; end any surrounding Latin typing run
        let snap = compositionUndoSnapshot
        let (a, h) = compositionAnchorHead ?? (anchor, head)
        markedRange = nil
        markedTextIsPrediction = false
        compositionUndoSnapshot = nil; compositionAnchorHead = nil
        refreshPredictionStyling()   // clear any grey ghost colour
        if let snap { registerUndo(snapshot: snap, anchor: a, head: h) }
        setNeedsDisplay()
    }

    /// Removes an active PREDICTION's provisional ghost text. The ghost is keyboard-owned, never user
    /// content, so this registers NO undo. No-op unless a prediction is currently showing.
    func dismissPrediction() {
        guard let m = markedRange, markedTextIsPrediction else { return }
        textInputDelegate?.textWillChange(self)
        applyReplace(globalFrom: m.from, globalTo: m.to, text: "")   // remove ghost; caret → m.from
        textInputDelegate?.textDidChange(self)
        markedRange = nil
        markedTextIsPrediction = false
        compositionUndoSnapshot = nil; compositionAnchorHead = nil
        refreshPredictionStyling()   // clear any grey ghost colour
        setNeedsDisplay()
    }

    /// Finalizes any active marked text before a NON-keyboard-driven interruption (gesture caret-move,
    /// focus loss, structural edit, undo/redo, full reload): a COMPOSITION is committed (kept, one undo
    /// step); a PREDICTION ghost is DISMISSED (removed). Committing a prediction here would desync the
    /// keyboard's shadow document and duplicate the word on its accept-`replace` (the on-device bug).
    /// Returns the dismissed prediction's range (so a caller setting a caret from a pre-dismiss coordinate
    /// can adjust for the removed length); nil for a committed composition / no marked text.
    @discardableResult
    func finalizeMarkedText() -> (from: Int, to: Int)? {
        guard markedRange != nil else { return nil }
        if markedTextIsPrediction {
            let removed = markedRange
            dismissPrediction()
            return removed
        }
        commitMarkedText()
        return nil
    }

    /// Rects (canvas coords) to underline as composing/marked text — the marked range's selection
    /// rects. Empty when not composing. A PREDICTION is rendered as grey ghost text (no underline —
    /// see `refreshPredictionStyling`), so only CJK/IME composition gets the underline. Render-only.
    func markedTextDecorations() -> [CGRect] {
        guard let m = markedRange, m.to > m.from, !markedTextIsPrediction else { return [] }
        return selectionRects(globalFrom: m.from, globalTo: m.to)
    }

    /// Applies (or clears) the grey ghost colour for the active inline prediction as a DISPLAY-ONLY
    /// rendering attribute on the owning leaf's layout — so the predicted continuation looks like the
    /// native gray ghost text and nothing leaks into the model. Cleared automatically when the
    /// prediction moves, is dismissed, or commits. Call after any marked-range change.
    func refreshPredictionStyling() {
        ghostStyledLayout?.setGhostForeground(nil, start: 0, end: 0)   // clear the previously styled leaf
        ghostStyledLayout = nil
        guard let m = markedRange, markedTextIsPrediction,
              let (region, _) = leafRegion(containingGlobal: m.from) else { return }
        region.layout.setGhostForeground(self.mapper.theme.placeholder,
                                         start: m.from - region.globalStart,
                                         end: m.to - region.globalStart)
        ghostStyledLayout = region.layout
    }

    /// Draws a 1pt underline under the marked text (IME convention). Composed into the on-top
    /// `selectionHighlight` overlay's `draw(_:)`.
    func drawMarkedTextUnderline(in ctx: CGContext) {
        let rects = markedTextDecorations()
        guard !rects.isEmpty else { return }
        mapper.theme.markedTextUnderline.setFill()
        for r in rects { ctx.fill(CGRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1)) }
    }
}
#endif
