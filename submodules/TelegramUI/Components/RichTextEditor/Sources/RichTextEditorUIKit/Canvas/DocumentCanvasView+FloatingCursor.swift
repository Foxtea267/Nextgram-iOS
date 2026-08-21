#if canImport(UIKit)
import UIKit
import RichTextEditorCore

/// The iOS hold-spacebar-to-move-cursor (keyboard-as-trackpad) gesture. The OS dispatches these optional
/// `UITextInput` methods to the first responder. The editor own-draws everything (no
/// `UITextSelectionDisplayInteraction`), so we render the floating cursor ourselves: a bright gliding
/// **shadow** (`transientCaretView`) follows the finger continuously, while the steady `CaretView` becomes a
/// dimmed **landing** indicator at the snapped position (see `updateCaretView`).
///
/// Two runtime-verified facts shape this implementation (both contradict the original spec's assumptions):
///  1. The `point` is an ABSOLUTE canvas (content) coordinate that already tracks the cursor across the whole
///     document — NOT a relative delta. So we feed it straight to `closestGlobalPosition`.
///  2. During the gesture iOS ALSO pushes selection RANGES (anchored at the gesture's start position) through
///     the `selectedTextRange` setter; applying them turns the cursor MOVE into a text SELECTION. The setter
///     ignores those writes while `floatingCursorActive` — the handlers here own the caret (see
///     `DocumentCanvasView+UITextInput`).
@available(iOS 13.0, *)
extension DocumentCanvasView {
    func beginFloatingCursor(at point: CGPoint) {
        guard !floatingCursorActive else { return }
        _ = finalizeMarkedText()
        clearStructuralSelections()
        dismissEditMenuForSelectionOrTextChange()
        // Collapse a ranged selection to its head (the caret we lift off from), bracketing the change.
        if anchor != head {
            textInputDelegate?.selectionWillChange(self)
            anchor = head
            textInputDelegate?.selectionDidChange(self)
        }
        floatingCursorActive = true
        floatingCursorPoint = point        // the begin point is in canvas coords, at the current caret
        updateCaretView()                  // floatingCursorActive == true → dimmed landing caret at `head`
        transientCaretView.accentColor = caretView.accentColor
        if let placement = caretHostPlacement(forGlobal: head) {
            hostOverlay(transientCaretView, at: placement)
        }
        transientCaretView.show(animated: true)
    }

    func updateFloatingCursor(at point: CGPoint) {
        guard floatingCursorActive else { return }
        // `point` is an absolute canvas (content) coordinate tracking the floating cursor. Use it DIRECTLY
        // (no relative-delta, no viewport clamp): the underlying caret snaps to the nearest grapheme
        // position; the shadow glides continuously under the finger.
        floatingCursorPoint = point
        resolveFloatingCaret()
        // Auto-scroll when the floating cursor nears the viewport's vertical edge.
        let offsetY = (superview as? UIScrollView)?.contentOffset.y ?? 0
        updateFloatingAutoScroll(viewportY: point.y - offsetY)
    }

    func endFloatingCursor() {
        guard floatingCursorActive else { return }
        stopFloatingAutoScroll()
        floatingCursorActive = false
        transientCaretView.hide(animated: true)
        updateCaretView()        // floatingCursorActive == false → steady caret reappears (full alpha + blink) at `head`
        onSelectionChange?()     // host resumes scroll-follow / onChange
    }

    /// Snaps the underlying caret to the grapheme position nearest the current floating point, and glides
    /// the shadow continuously under the finger.
    func resolveFloatingCaret() {
        let pos = closestGlobalPosition(to: floatingCursorPoint)
        moveFloatingCaret(toGlobal: pos, shadowX: floatingCursorPoint.x)
    }

    /// The lightweight per-update caret move: bracket the input delegate (mandatory invariant), update the
    /// selection, reposition the dimmed landing caret (`updateCaretView`), and position the bright shadow.
    /// Deliberately does NOT call `scrollCaretIntoViewIfNeeded` / `onSelectionChange` / `refreshSelectionUI`
    /// — the gesture owns scrolling (non-animated, via the auto-scroll driver). `setNeedsDisplay()` suffices:
    /// the selection is collapsed for the gesture's duration (begin collapses it), so there are no handles or
    /// selection wash to refresh — only the highlight repaint.
    ///
    /// `shadowX` (canvas coords) overrides the shadow's horizontal position so it glides continuously with
    /// the finger instead of snapping to the caret rect; the snapped caret rect still supplies the line's
    /// vertical extent + host (so the shadow stays on the right line / rides table-cell scroll). When
    /// `shadowX` is nil the shadow uses the snapped rect.
    func moveFloatingCaret(toGlobal pos: Int, shadowX: CGFloat? = nil) {
        let target = clampGlobal(pos)
        textInputDelegate?.selectionWillChange(self)
        anchor = target; head = target
        textInputDelegate?.selectionDidChange(self)
        setNeedsDisplay()
        updateCaretView()   // reposition the dimmed "landing" caret at the snapped position
        guard var placement = caretHostPlacement(forGlobal: target) else { return }
        if let sx = shadowX {
            // Map the finger x into the host container's coordinate space (identity for the canvas), and
            // clamp to the host bounds so an overshooting finger can't fling the shadow off-screen.
            let raw = (placement.container === self) ? sx : convert(CGPoint(x: sx, y: 0), to: placement.container).x
            placement.frame.origin.x = min(max(raw, 0), max(0, placement.container.bounds.width - placement.frame.width))
        }
        hostOverlay(transientCaretView, at: placement)
    }

    /// Per-update edge-band check: if the floating caret is in the top/bottom band, (re)start the
    /// `CADisplayLink` auto-scroller in that direction; otherwise stop it.
    func updateFloatingAutoScroll(viewportY: CGFloat) {
        let band: CGFloat = 60
        let v = floatingAutoScrollStep(forViewportY: viewportY, viewportHeight: viewportRect().size.height, band: band)
        floatingScrollVelocity = v
        if abs(v) < 0.001 { stopFloatingAutoScroll(); return }
        if floatingScrollLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(floatingAutoScrollTick))
            link.add(to: .main, forMode: .common)
            floatingScrollLink = link
        }
    }

    func stopFloatingAutoScroll() {
        floatingScrollLink?.invalidate(); floatingScrollLink = nil
        floatingScrollVelocity = 0
    }

    /// Tears down an in-flight floating-cursor gesture without firing host callbacks — for interruptions
    /// (resign first responder, removal from window) where the OS won't deliver `endFloatingCursor`.
    /// Invalidates the auto-scroll display link (which retains `self`), clears the active flag, and hides
    /// the transient caret. Safe to call when no gesture is active (no-op).
    func cancelFloatingCursor() {
        stopFloatingAutoScroll()
        guard floatingCursorActive else { return }
        floatingCursorActive = false
        transientCaretView.hide(animated: false)
    }

    /// Pure: the per-tick vertical scroll step (points) for a floating-caret viewport-Y. Zero outside the
    /// top/bottom `band`; signed toward the nearer edge; magnitude grows with penetration into the band.
    func floatingAutoScrollStep(forViewportY y: CGFloat, viewportHeight h: CGFloat, band: CGFloat) -> CGFloat {
        let maxStep: CGFloat = 14
        guard band > 0 else { return 0 }
        if y < band { return -maxStep * (1 - max(0, y) / band) }
        if y > h - band { return maxStep * (1 - max(0, h - y) / band) }
        return 0
    }

    @objc func floatingAutoScrollTick() {
        guard floatingCursorActive, let sv = superview as? UIScrollView else { return stopFloatingAutoScroll() }
        let maxY = max(sv.contentSize.height - sv.bounds.height, 0)
        let newY = min(max(sv.contentOffset.y + floatingScrollVelocity, 0), maxY)
        guard newY != sv.contentOffset.y else { return }   // already at the edge
        let delta = newY - sv.contentOffset.y
        sv.contentOffset.y = newY        // fires the façade's scrollViewDidScroll → viewportDidChange
        floatingCursorPoint.y += delta   // keep the floating point under the finger as content scrolls
        resolveFloatingCaret()           // re-snap (+ re-glide the shadow) against the new offset
    }
}
#endif
