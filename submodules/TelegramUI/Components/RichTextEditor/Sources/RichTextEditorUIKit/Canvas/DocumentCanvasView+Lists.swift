#if canImport(UIKit)
import UIKit
import RichTextEditorCore

@available(iOS 13.0, *)
extension DocumentCanvasView {
    /// Per-block marker strings, computed by Core `ListNumbering` from each box's list membership
    /// (runs are irrelevant to numbering, so we pass lightweight paragraphs). Keyed by `BlockID`.
    func listMarkerLabels() -> [BlockID: String] {
        // Image blocks have no list membership → a nil-list ParagraphBlock, which ListNumbering treats
        // as a non-list paragraph (resets numbering). That is the intended behavior. The paragraph
        // `style` is forwarded so ListNumbering can treat a quote as its own numbering scope (a quoted
        // list and the surrounding list number independently); non-BlockBox blocks default to `.body`.
        ListNumbering.labels(for: boxes.map { box in
            let p = box as? BlockBox
            return ParagraphBlock(id: box.id, style: p?.style ?? .body, list: p?.listMembership)
        })
    }

    struct ListMarkerDraw { let label: String; let origin: CGPoint; let font: UIFont; let id: BlockID }

    /// Stamps each top-level list box with its Core-computed marker label and flags each as
    /// `isTopLevelBlock` (the top-level placeholder gate) and `isOnlyBlock` (the sole-block gate for the
    /// body placeholder — true only when the document has exactly one block). Called during layout so a box
    /// can draw its own marker. Table-cell boxes are intentionally NOT stamped (parity: markers in cells
    /// aren't drawn today, and cell paragraphs draw no placeholder).
    func stampListMarkers() {
        let labels = listMarkerLabels()
        let isSoleBlock = (boxes.count == 1)
        for case let p as BlockBox in boxes {
            p.isTopLevelBlock = true
            p.isOnlyBlock = isSoleBlock
            p.resolvedListMarker = labels[p.id]
            p.placeholders = self.placeholders
            p.hostsChecklistCheckbox = (self.checklistMarkerViewProvider != nil) && (p.listMembership?.marker == .checklist)
        }
        for case let pq as PullQuoteBox in boxes { pq.placeholders = self.placeholders }
        for case let cb as CodeBlockBox in boxes { cb.placeholders = self.placeholders }
        for case let bq as BlockQuoteBox in boxes { bq.placeholders = self.placeholders }
    }

    /// Test/geometry seam: the per-box marker draws keyed by `BlockID`. Production draws each marker in
    /// `BlockBox.draw`; this re-derives the same geometry (via `BlockBox.listMarkerDraw()`) for assertions.
    func listMarkerDraws() -> [ListMarkerDraw] {
        boxes.compactMap { box in
            guard let p = box as? BlockBox, let d = p.listMarkerDraw() else { return nil }
            return ListMarkerDraw(label: d.label, origin: d.origin, font: d.font, id: p.id)
        }
    }

    /// Sets (or clears, with `nil`) list membership on every box the current selection touches,
    /// re-styling each affected box. Undoable.
    func setList(_ marker: ListMarker?) {
        guard !boxes.isEmpty else { return }
        editing {
            for box in boxes {
                guard let p = box as? BlockBox else { continue }
                let boxLo = p.textStart, boxHi = p.textStart + p.textLength
                guard selFrom <= boxHi && selTo >= boxLo else { continue }
                if let marker = marker {
                    // Seed `checked` only when the box becomes a checklist FRESH; when it is already a
                    // `.checklist`, preserve its current checked state so re-applying the checklist marker
                    // (host re-tap, or a mixed multi-paragraph selection) never silently unticks an item.
                    let checked: Bool?
                    if marker == .checklist {
                        checked = (p.listMembership?.marker == .checklist) ? (p.listMembership?.checked ?? false) : false
                    } else {
                        checked = nil
                    }
                    p.listMembership = ListMembership(
                        marker: marker,
                        level: p.listMembership?.level ?? 0,
                        checked: checked)
                } else {
                    p.listMembership = nil
                }
                restyle(p)
            }
            recomputeSpans()
        }
    }

    /// The top-level `.checklist` box whose checkbox (marker rect, inflated to a ≥30pt touch target)
    /// contains `point` (canvas coords), or nil.
    func checklistBox(atCanvasPoint point: CGPoint) -> BlockBox? {
        let minTarget: CGFloat = 30
        for case let p as BlockBox in boxes {
            guard let rect = p.checklistMarkerCanvasRect() else { continue }
            let dx = max(0, (minTarget - rect.width) / 2), dy = max(0, (minTarget - rect.height) / 2)
            if rect.insetBy(dx: -dx, dy: -dy).contains(point) { return p }
        }
        return nil
    }

    /// Flips a checklist item's `checked` state as one undo step. Does not move the caret.
    func toggleChecklistItem(box: BlockBox) {
        guard box.listMembership?.marker == .checklist else { return }
        let newValue = !(box.listMembership?.checked ?? false)
        editing {
            box.listMembership?.checked = newValue
            restyle(box)
            recomputeSpans()
        }
        checklistMarkerViews[box.id]?.view.setChecked(newValue, animated: true)
    }

    /// Re-applies the paragraph style (reflecting the box's current style + list membership) across
    /// the box's text. No-op for an empty box (typing applies the style via `typingAttributeDict`).
    func restyle(_ box: BlockBox) {
        let ps = mapper.styleSheet.paragraphStyle(for: box.style, attributes: box.paragraphAttributes,
                                                  list: box.listMembership,
                                                  baseWritingDirection: box.writingDirectionOverride ?? mapper.baseWritingDirection)
        let storage = box.layout.attributedString
        guard storage.length > 0 else { return }
        let m = NSMutableAttributedString(attributedString: storage)
        m.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: m.length))
        box.layout.attributedString = m
    }
}
#endif
