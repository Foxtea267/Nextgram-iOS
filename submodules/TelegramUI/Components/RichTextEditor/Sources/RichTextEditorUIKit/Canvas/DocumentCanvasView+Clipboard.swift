#if canImport(UIKit)
import UIKit
import RichTextEditorCore

extension DocumentCanvasView {
    /// Private pasteboard UTI carrying a JSON-encoded `Document` fragment (full within-app fidelity).
    /// Aliases the public `RichTextEditorClipboard.fragmentUTI` so the format has one source of truth.
    static let richTextFragmentUTI = RichTextEditorClipboard.fragmentUTI

    func clipboardCanPerformAction(_ action: Selector) -> Bool {
        switch action {
        case #selector(copy(_:)), #selector(cut(_:)):
            return selFrom < selTo
        case #selector(paste(_:)):
            return pasteboard.contains(pasteboardTypes: [Self.richTextFragmentUTI, "public.rtf"]) || pasteboard.hasStrings || (canPasteMedia?() ?? false)
        default:
            return false
        }
    }

    @objc override func copy(_ sender: Any?) {
        guard selFrom < selTo else { return }
        writeSelectionToPasteboard(globalFrom: selFrom, globalTo: selTo)
    }

    @objc override func cut(_ sender: Any?) {
        guard selFrom < selTo, let range = selectedTextRange else { return }
        writeSelectionToPasteboard(globalFrom: selFrom, globalTo: selTo)
        replace(range, withText: "")
    }

    /// Writes the three pasteboard representations for the selection atomically (via the public façade,
    /// the single source of truth for the format — see `RichTextEditorClipboard`).
    /// The plain rep is derived from the fragment via `externalChecklistPlainText` (so checklist items
    /// carry their emoji prefix); when the fragment is empty (e.g. a cross-cell table selection whose
    /// blocks `extractFragment` skips) we fall back to `text(in: selectedTextRange)` to preserve the
    /// pre-existing cross-cell concatenation behavior.
    private func writeSelectionToPasteboard(globalFrom: Int, globalTo: Int) {
        let fragment = Document(blocks: currentBlocks()).extractFragment(globalFrom: globalFrom, globalTo: globalTo)
        let plain: String? = fragment.blocks.isEmpty
            ? selectedTextRange.flatMap { text(in: $0) }
            : nil   // nil → pasteboardItem derives from fragment via externalChecklistPlainText
        pasteboard.setItems([RichTextEditorClipboard.pasteboardItem(for: fragment, plain: plain)], options: [:])
    }

    @objc override func paste(_ sender: Any?) {
        if let fragment = fragment(fromPasteboard: pasteboard) { pasteFragment(fragment); return }
        _ = onPasteMedia?()   // no text rep → let the host route media (image/gif/video/sticker) to send
    }

    /// The richest fragment available on the pasteboard: private UTI → RTF → plain text.
    func fragment(fromPasteboard pb: TextPasteboard) -> Document? {
        if let data = pb.data(forPasteboardType: Self.richTextFragmentUTI),
           let frag = try? DocumentCodec.decode(data) {
            return frag
        }
        if let data = pb.data(forPasteboardType: "public.rtf"),
           let frag = RTFConversion.fragment(fromRTF: data) {
            return frag
        }
        if let s = pb.string, !s.isEmpty {
            return plainTextFragment(s)
        }
        return nil
    }

    /// A multi-paragraph fragment from plain text — one paragraph per line (CRLF normalized first).
    /// Lines beginning with ⬜ or ✅ (per `ChecklistEmojiMarker.strippingMarker`) are decoded as
    /// checklist paragraphs; all other lines become plain body paragraphs.
    func plainTextFragment(_ s: String) -> Document {
        let lines = s.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        return Document(blocks: lines.map { line in
            if let det = ChecklistEmojiMarker.strippingMarker(line) {
                return .paragraph(ParagraphBlock(id: .generate(),
                    list: ListMembership(marker: .checklist, level: 0, checked: det.checked),
                    runs: det.remainder.isEmpty ? [] : [TextRun(text: det.remainder)]))
            }
            return .paragraph(ParagraphBlock(id: .generate(), runs: line.isEmpty ? [] : [TextRun(text: line)]))
        })
    }

    /// Splices a `Document` fragment at the current selection as ONE undo step. Reuses the existing
    /// edit engine to delete the selection, then the Core `insertingFragment` model splice.
    func pasteFragment(_ fragment: Document) {
        guard !fragment.blocks.isEmpty else { return }
        editing {
            // 1. delete the selection (grapheme-safe, cross-region) → collapsed caret at selFrom.
            if selFrom < selTo {
                applySelectionReplace(globalFrom: selFrom, globalTo: selTo, text: "")
            }
            let caret = head
            // 2. splice on the model.
            let doc = Document(blocks: currentBlocks())
            if let result = doc.insertingFragment(fragment, atGlobal: caret) {
                setBlocks(result.document.blocks, width: effectiveWidth)
                anchor = min(result.caret, documentSize)
                head = anchor
            } else {
                // Fallback: caret not in a top-level paragraph/code region (e.g. a table cell).
                // Flatten to plain text — newlines stripped, since applyReplace requires newline-free
                // text (paragraph breaks are structural; a code block's interior "\n"s must not leak into a run).
                let flat = fragment.blocks.map(blockPlainText).joined(separator: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                applySelectionReplace(globalFrom: caret, globalTo: caret, text: flat)
            }
        }
    }
}
#endif
