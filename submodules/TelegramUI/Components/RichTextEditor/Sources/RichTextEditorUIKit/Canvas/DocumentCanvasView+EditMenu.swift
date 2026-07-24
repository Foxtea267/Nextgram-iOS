#if canImport(UIKit)
import UIKit

/// A minimal pasteboard seam so copy/cut/paste are unit-testable with a fake — the simulator's
/// UIPasteboard.general can be unauthorized and hang on reads. Production uses UIPasteboard.general.
protocol TextPasteboard: AnyObject {
    var string: String? { get set }
    var hasStrings: Bool { get }
    func data(forPasteboardType type: String) -> Data?
    func setItems(_ items: [[String: Any]], options: [UIPasteboard.OptionsKey: Any])
    func contains(pasteboardTypes: [String]) -> Bool
}
extension UIPasteboard: TextPasteboard {}

/// The system edit menu + the responder actions that populate it. On iOS 16+ the menu is presented via
/// `UIEditMenuInteraction` (install + delegate live in the gated extension below); on iOS 13–15 it falls
/// back to the deprecated `UIMenuController`. The responder actions (Select/Copy/Cut/Paste + the custom
/// Bold/Italic/Underline/Look Up/Share) are SHARED — only the presentation differs. Presentation is
/// gesture-driven (see DocumentCanvasView+Interaction).
extension DocumentCanvasView {
    /// How far the edit-menu target rect grows above/below a text selection so the menu clears the round
    /// selection-handle knobs (the OS draws them a few points beyond the first/last line). Tuned visually.
    static let selectionHandleAllowance: CGFloat = 12

    /// The content the edit menu must not obscure, in canvas coordinates: a structurally-selected table
    /// row/column, else the selection union, else the image atom at a gap caret, else the collapsed caret.
    func editMenuContentRect() -> CGRect {
        if let outline = tableSelectionOutlineRect() { return outline }
        if selFrom != selTo {
            let union = selectionRects(globalFrom: selFrom, globalTo: selTo)
                .reduce(CGRect.null) { $0.union($1) }
            if !union.isNull { return union }
        }
        if let img = mediaBox(atGap: head) { return img.mediaRect() }
        return caretRect(for: DocumentTextPosition(head))
    }

    /// The rect the menu lays out AROUND — the content rect grown to clear the drag handles for a
    /// non-collapsed TEXT selection; a caret/image/structural-table pick has no text handles, so unpadded.
    func editMenuTargetRect() -> CGRect {
        let content = editMenuContentRect()
        if selFrom != selTo, tableSelection == nil {
            return content.insetBy(dx: 0, dy: -Self.selectionHandleAllowance)
        }
        return content
    }

    /// Present the system menu, anchored at the top-center of the content rect. iOS 16+ uses
    /// `UIEditMenuInteraction` (it lays out around `targetRectFor`); below 16, `UIMenuController`.
    func presentEditMenu() {
        guard isFirstResponder else { return }
        let rect = editMenuContentRect()
        if #available(iOS 16.0, *) {
            guard let interaction = editMenuInteraction else { return }
            let cfg = UIEditMenuConfiguration(identifier: nil, sourcePoint: CGPoint(x: rect.midX, y: rect.minY))
            interaction.presentEditMenu(with: cfg)
        } else {
            presentLegacyEditMenu(targetRect: editMenuTargetRect())
        }
    }

    func dismissEditMenu() {
        dismissEditMenuCountForTesting += 1
        if #available(iOS 16.0, *) {
            editMenuInteraction?.dismissMenu()
        } else {
            UIMenuController.shared.hideMenu()
            editMenuVisible = false
        }
    }

    /// Native UITextView dismisses the edit menu the moment the text or the caret/selection changes.
    /// Called from the selection setters, the `selectedTextRange` setter, and the `editing { }` wrapper.
    /// UNCONDITIONAL (not gated on `editMenuVisible`) — see the long note that previously lived here:
    /// a presented menu does not self-dismiss on a selection change, and the system clears `editMenuVisible`
    /// on touch-down before the gesture's setter runs. `dismissMenu()`/`hideMenu()` is a no-op when nothing
    /// is presented.
    func dismissEditMenuForSelectionOrTextChange() {
        pendingSpellingMenu = nil
        dismissEditMenu()
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(select(_:)):
            return hasText && selFrom == selTo && leafRegion(containingGlobal: head) != nil
        case #selector(selectAll(_:)):
            // Measured against RENDERABLE bounds (what `selectAllText` lands on), not raw 0/documentSize.
            let begin = (beginningOfDocument as? DocumentTextPosition)?.offset ?? 0
            let end = (endOfDocument as? DocumentTextPosition)?.offset ?? documentSize
            return hasText && !(selFrom <= begin && selTo >= end)
        case #selector(copy(_:)), #selector(cut(_:)), #selector(paste(_:)):
            return clipboardCanPerformAction(action)
        case #selector(legacyBold), #selector(legacyItalic), #selector(legacyUnderline),
             #selector(legacyLookUp), #selector(legacyShare):
            // The custom items of the UIMenuController (iOS 13–15) fallback — a non-collapsed selection only.
            return selFrom < selTo
        case #selector(spellGuess0), #selector(spellGuess1), #selector(spellGuess2),
             #selector(spellGuess3), #selector(spellNoop), #selector(spellRevert):
            return pendingSpellingMenu != nil
        default:
            return super.canPerformAction(action, withSender: sender)
        }
    }

    @objc override func select(_ sender: Any?) {
        selectWord(at: head)
        presentEditMenu()
    }

    @objc override func selectAll(_ sender: Any?) {
        selectAllText()
        presentEditMenu()
    }

    // MARK: - Legacy UIMenuController fallback (iOS 13–15)

    /// Presents the deprecated `UIMenuController`. Standard Cut/Copy/Paste/Select/Select All surface
    /// automatically from `canPerformAction`; the custom items (Format toggles + Look Up + Share) are added
    /// as flat `UIMenuItem`s (UIMenuController has no submenus, so the iOS-16+ "Format" submenu is flattened).
    /// `Translate` is iOS 17.4+, so it never appears on this path. Reuses the shared responder actions.
    private func presentLegacyEditMenu(targetRect: CGRect) {
        let mc = UIMenuController.shared
        mc.menuItems = pendingSpellingMenu != nil ? legacySpellingMenuItems() : legacyCustomMenuItems()
        mc.showMenu(from: self, rect: targetRect)
        editMenuVisible = true
    }

    private func legacyCustomMenuItems() -> [UIMenuItem] {
        guard selFrom < selTo else { return [] }
        return [
            UIMenuItem(title: "Bold", action: #selector(legacyBold)),
            UIMenuItem(title: "Italic", action: #selector(legacyItalic)),
            UIMenuItem(title: "Underline", action: #selector(legacyUnderline)),
            UIMenuItem(title: "Look Up", action: #selector(legacyLookUp)),
            UIMenuItem(title: "Share", action: #selector(legacyShare)),
        ]
    }

    @objc private func legacyBold() { toggleBold() }
    @objc private func legacyItalic() { toggleItalic() }
    @objc private func legacyUnderline() { toggleUnderline() }
    @objc private func legacyLookUp() { presentLookUp() }
    @objc private func legacyShare() { presentShare() }

    private func legacySpellingMenuItems() -> [UIMenuItem] {
        guard let pending = pendingSpellingMenu else {
            return [UIMenuItem(title: "No Replacements Found", action: #selector(spellNoop))]
        }
        var items: [UIMenuItem] = []
        // N5: a fixed selector (mirrors spellGuess0…3) — UIMenuItem needs an Obj-C #selector, so unlike the
        // iOS-16+ UIAction closure this can't just close over `revertTo`; `spellRevert` re-reads it from
        // `pendingSpellingMenu` at invocation time.
        if pending.revertTo != nil {
            items.append(UIMenuItem(title: "Revert to \u{201C}\(pending.revertTo!)\u{201D}", action: #selector(spellRevert)))
        }
        if pending.guesses.isEmpty {
            items.append(UIMenuItem(title: "No Replacements Found", action: #selector(spellNoop)))
            return items
        }
        let sels: [Selector] = [#selector(spellGuess0), #selector(spellGuess1),
                                #selector(spellGuess2), #selector(spellGuess3)]
        items.append(contentsOf: zip(pending.guesses.prefix(4), sels).map { UIMenuItem(title: $0.0, action: $0.1) })
        return items
    }
    @objc private func spellNoop() {}
    @objc private func spellRevert() {
        guard let revertTo = pendingSpellingMenu?.revertTo else { return }
        applySpellingReplacement(revertTo)
    }
    @objc private func spellGuess0() { applyLegacyGuess(0) }
    @objc private func spellGuess1() { applyLegacyGuess(1) }
    @objc private func spellGuess2() { applyLegacyGuess(2) }
    @objc private func spellGuess3() { applyLegacyGuess(3) }
    private func applyLegacyGuess(_ i: Int) {
        guard let g = pendingSpellingMenu?.guesses, i < g.count else { return }
        applySpellingReplacement(g[i])
    }
}

/// iOS 16+ system edit menu: the `UIEditMenuInteraction` install + its delegate. Below 16 this whole
/// extension is absent and `presentEditMenu`/`dismissEditMenu` use `UIMenuController` instead.
@available(iOS 16.0, *)
extension DocumentCanvasView {
    func installEditMenuInteraction() {
        guard editMenuInteraction == nil else { return }
        let interaction = UIEditMenuInteraction(delegate: self)
        addInteraction(interaction)
        editMenuInteraction = interaction
    }
}

@available(iOS 16.0, *)
extension DocumentCanvasView: UIEditMenuInteractionDelegate {
    /// Returning the content rect makes the menu present AROUND it (the default zero-size rect would let it
    /// overlap the selection + handles). Recomputed each call (the system re-invokes on layout changes).
    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        editMenuTargetRect()
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             willPresentMenuFor configuration: UIEditMenuConfiguration,
                             animator: UIEditMenuInteractionAnimating) {
        editMenuVisible = true
    }
    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             willDismissMenuFor configuration: UIEditMenuConfiguration,
                             animator: UIEditMenuInteractionAnimating) {
        editMenuVisible = false
        lastMenuDismissTime = Date().timeIntervalSinceReferenceDate
    }
}
#endif
