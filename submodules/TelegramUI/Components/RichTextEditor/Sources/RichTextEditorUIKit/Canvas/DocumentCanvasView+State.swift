#if canImport(UIKit)
import UIKit
import RichTextEditorCore

@available(iOS 13.0, *)
extension DocumentCanvasView {
    /// The paragraph box containing the caret (`head`) — a top-level paragraph OR a block-quote child —
    /// used for the toolbar's paragraph style / list marker. Nil inside a table cell. Resolves via
    /// `activeStack` (container-aware), NOT `resolveBox`: a caret inside a quote has no degenerate-safe
    /// `resolveBox`, so `resolveBox(head)` would mis-resolve to the FOLLOWING block and report its style.
    private func headTopLevelBlock() -> BlockBox? {
        guard !isInsideTable(head) else { return nil }
        return activeStack(at: head)?.box as? BlockBox
    }

    private func currentInlineFormats() -> (bold: Bool, italic: Bool, underline: Bool, strikethrough: Bool, code: Bool, spoiler: Bool) {
        let targets = characterFormatTargets()
        if !targets.isEmpty {
            return (
                bold: targets.allSatisfy { rangeIsBold($0.storage, $0.range) },
                italic: targets.allSatisfy { rangeIsItalic($0.storage, $0.range) },
                underline: targets.allSatisfy { rangeIsUnderline($0.storage, $0.range) },
                strikethrough: targets.allSatisfy { rangeIsStrikethrough($0.storage, $0.range) },
                code: targets.allSatisfy { rangeIsInlineCode($0.storage, $0.range) },
                spoiler: targets.allSatisfy { rangeIsSpoiler($0.storage, $0.range) }
            )
        }
        // Collapsed caret: the format the next typed character would inherit.
        guard let (region, local) = leafRegion(containingGlobal: head) else { return (false, false, false, false, false, false) }
        let ca = mapper.characterAttributes(from: typingAttributeDict(region: region, atLocal: local))
        return (ca.bold, ca.italic, ca.underline, ca.strikethrough, ca.inlineCode, ca.spoiler)
    }

    /// Whether the current (non-empty) selection covers only paragraph text — no media or table block.
    /// `isInsideTable` handles a selection whose endpoint sits inside a cell; the box scan also rejects a
    /// top-level selection that spans a media/table block while both endpoints stay in paragraphs (where
    /// neither endpoint is "in table"). Code blocks and quotes are left in scope — `setList` no-ops on a
    /// code block and applies to quoted paragraphs, matching the caret-case List action.
    private func selectionIsTextOnly() -> Bool {
        guard selFrom < selTo else { return false }
        if isInsideTable(head) || isInsideTable(anchor) { return false }
        for box in boxes where box is MediaBlockBox || box is TableBlockBox {
            let lo = box.nodeStart, hi = box.nodeStart + box.nodeSize
            if selFrom < hi && selTo > lo { return false }
        }
        return true
    }

    func currentState() -> RichTextEditorView.EditorState {
        let topBlock = headTopLevelBlock()
        let fmt = currentInlineFormats()
        return RichTextEditorView.EditorState(
            bold: fmt.bold, italic: fmt.italic, underline: fmt.underline, strikethrough: fmt.strikethrough, code: fmt.code,
            spoiler: fmt.spoiler,
            paragraphStyle: topBlock?.style,
            isCodeBlock: activeStack(at: head)?.box is CodeBlockBox,
            isPullQuote: activeStack(at: head)?.box is PullQuoteBox,
            listMarker: topBlock?.listMembership?.marker,
            link: currentLink(),
            // Either endpoint in a table: a selection partially overlapping a table still counts as
            // "in table" for toolbar purposes (so table-structural commands can enable).
            hasSelection: selFrom < selTo,
            isInTable: isInsideTable(head) || isInsideTable(anchor),
            selectionIsTextOnly: selectionIsTextOnly(),
            canUndo: effectiveUndoManager?.canUndo ?? false,
            canRedo: effectiveUndoManager?.canRedo ?? false,
            blockQuoteDepth: blockQuoteDepth(at: head)
        )
    }
}
#endif
