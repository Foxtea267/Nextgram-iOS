#if canImport(UIKit)
import UIKit
import RichTextEditorCore

@available(iOS 13.0, *)
extension DocumentCanvasView {
    private struct FormulaOccurrence {
        let ref: TextNodeRef
        let globalOffset: Int
        let localOffset: Int
        let latex: String
    }

    private func formulaFragment(latex: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        return mapper.attributedFormulaString(latex: latex, attributes: attributes)
    }

    /// Inserts a formula as one inline atom carrying semantic formula metadata. If no formula renderer is
    /// registered (or rendering fails), the fragment degrades to raw LaTeX text with the same metadata.
    func insertFormula(latex: String) {
        guard !latex.isEmpty else { return }
        guard !boxes.isEmpty else { return }

        if let active = activeStack(at: head), active.box is CodeBlockBox {
            insertText(latex)
            return
        }

        editing {
            if selFrom != selTo {
                applySelectionReplace(globalFrom: selFrom, globalTo: selTo, text: "")
            }
            if !isInsideTable(head) && !isInsideBlockQuote(head),
               let r = resolveBox(at: head), r.box is TableBlockBox || r.box is BlockQuoteBox {
                let snapped = caretSnappedIntoContainer(head)
                anchor = snapped
                head = snapped
            }
            if leafRegion(containingGlobal: head) == nil {
                let snapped = snapToRenderable(head, forward: true)
                anchor = snapped
                head = snapped
            }
            guard let (region, local) = leafRegion(containingGlobal: head) else {
                return
            }

            let attrs = typingAttributeDict(region: region, atLocal: local)
            let fragment = formulaFragment(latex: latex, attributes: attrs)
            region.layout.replace(start: local, end: local, with: fragment)
            recomputeSpans()

            let caret = region.globalStart + local + fragment.length
            anchor = caret
            head = caret
        }
    }

    private func formulaOccurrence(at point: CGPoint) -> FormulaOccurrence? {
        for region in allLeafRegions() {
            let attr = region.layout.attributedString
            let full = NSRange(location: 0, length: attr.length)
            var hit: FormulaOccurrence?
            attr.enumerateAttribute(.attachment, in: full, options: []) { value, range, stop in
                guard let att = value as? FormulaTextAttachment,
                      let box = region.layout.attachmentBox(at: range.location)
                else {
                    return
                }
                let offX = tableContentOffsetX(forGlobal: region.globalStart)
                let rect = box.offsetBy(dx: region.canvasOrigin.x - offX, dy: region.canvasOrigin.y)
                if rect.insetBy(dx: -6.0, dy: -6.0).contains(point) {
                    hit = FormulaOccurrence(
                        ref: region.ref,
                        globalOffset: region.globalStart + range.location,
                        localOffset: range.location,
                        latex: att.latex
                    )
                    stop.pointee = true
                }
            }
            if let hit {
                return hit
            }
        }
        return nil
    }

    func handleFormulaTapIfNeeded(at point: CGPoint) -> Bool {
        guard let formulaEditRequested, let occurrence = formulaOccurrence(at: point) else {
            return false
        }
        dismissEditMenu()
        setCaret(global: occurrence.globalOffset + 1)
        formulaEditRequested(occurrence.latex, { [weak self] updatedLatex in
            guard let self else {
                return
            }
            self.replaceFormula(occurrence: occurrence, latex: updatedLatex)
        })
        return true
    }

    private func replaceFormula(occurrence: FormulaOccurrence, latex: String) {
        guard !latex.isEmpty else {
            return
        }
        editing {
            guard let (region, _) = leafRegion(containingGlobal: occurrence.globalOffset),
                  region.ref == occurrence.ref,
                  occurrence.localOffset < region.layout.attributedString.length,
                  let current = region.layout.attributedString.attribute(.attachment, at: occurrence.localOffset, effectiveRange: nil) as? FormulaTextAttachment,
                  current.latex == occurrence.latex
            else {
                return
            }
            var attrs = region.layout.attributedString.attributes(at: occurrence.localOffset, effectiveRange: nil)
            attrs.removeValue(forKey: .attachment)
            let fragment = formulaFragment(latex: latex, attributes: attrs)
            region.layout.replace(start: occurrence.localOffset, end: occurrence.localOffset + 1, with: fragment)
            recomputeSpans()
            let caret = region.globalStart + occurrence.localOffset + fragment.length
            anchor = caret
            head = caret
        }
    }
}
#endif
