#if canImport(UIKit)
import UIKit

/// The per-paragraph line-layout-and-draw engine seam. The editor is coordinate-free and talks to text
/// layout ONLY through this offset-based (`Int`) surface — never the underlying TextKit types — so the
/// concrete engine is swappable:
/// - `BlockLayout` (TextKit 2, `@available(iOS 13.0, *)`) is the production implementation;
/// - `BlockLayoutTK1` (TextKit 1, iOS 7+) is the iOS-15/16 back-port implementation.
///
/// Selected by `makeBlockLayout(...)`: an `RTE_TK1` build forces TextKit 1; otherwise TextKit 2 is used
/// where available, falling back to TextKit 1 below iOS 17. (This factory + protocol is also what the real
/// iOS-15 back-port needs — the seam was introduced as a feasibility spike, see the project CLAUDE.md.)
protocol BlockLayoutEngine: AnyObject {
    var attributedString: NSAttributedString { get set }
    var length: Int { get }
    var renderVersion: Int { get }
    var boundingHeight: CGFloat { get }
    var firstLineBaselineFromTop: CGFloat? { get }
    /// The underlying mutable text storage — abstracts TextKit 2's `contentStorage.textStorage`.
    var backingStorage: NSTextStorage? { get }
    /// The layout container's width — abstracts TextKit 2's `container.size.width`.
    var containerWidth: CGFloat { get }

    func bumpRenderVersion()
    func setWidth(_ width: CGFloat)
    func caretRect(atOffset offset: Int) -> CGRect
    func selectionRects(start: Int, end: Int) -> [CGRect]
    func selectionFillRects(start: Int, end: Int, fillTrailingLine: Bool, isRTL: Bool) -> [CGRect]
    /// The laid-out text height at container `width`, computed WITHOUT mutating the live
    /// container/storage/layout (a separate scratch layout of the same engine type). Used by the
    /// stateless `measuredHeight(forWidth:)` chain. Returns the live `boundingHeight` when `width`
    /// already equals the live container width.
    func boundingHeight(forWidth width: CGFloat) -> CGFloat
    func attachmentBox(at offset: Int) -> CGRect?
    func closestOffset(toPoint point: CGPoint) -> Int
    func drawText(in ctx: CGContext, at origin: CGPoint)
    func replace(start: Int, end: Int, with string: NSAttributedString)
    func setGhostForeground(_ color: UIColor?, start: Int, end: Int)
    @discardableResult func setSpoilerHidden(_ ranges: [NSRange]) -> Bool
    /// The base writing direction of the line containing `offset`, per CoreText's bidi resolution
    /// (`CTRunStatus.rightToLeft` of the line's first run) — the same first-run heuristic `TextNode` /
    /// `InstantPageV2Layout` use, so the editor agrees with how the sent message renders. nil when there
    /// is no laid-out content. A default implementation over `attributedString` covers both engines.
    func baseDirection(atOffset offset: Int) -> NSWritingDirection?

    /// When set, `caretRect(atOffset:)` returns the trailing-edge position for EMPTY text, so an empty
    /// RTL-keyboard paragraph shows its caret on the right before the first keystroke. nil = default (0).
    var emptyTextCaretDirection: NSWritingDirection? { get set }
}

/// Runtime control over which layout engine `makeBlockLayout` builds — for verifying the iOS-15 back-port
/// (TextKit 1) path inside the running app on a modern OS, without a special build.
public enum BlockLayoutBackend {
    /// Force the TextKit-1 engine. Set this manually (e.g. from a debug hook) to `true` before the editor
    /// builds its blocks — it's read at block-construction time, so reopen the composer to apply.
    public static var forceTextKit1: Bool = {
        #if DEBUG && false
        return true
        #else
        return false
        #endif
    }()
}

extension BlockLayoutEngine {
    func baseDirection(atOffset offset: Int) -> NSWritingDirection? {
        let attr = attributedString
        guard attr.length > 0 else { return nil }
        // Build a CTLine over the whole (single-paragraph) storage; its first run reflects the paragraph's
        // resolved base direction. Offset is accepted for API symmetry / future per-line use; our boxes are
        // one paragraph each, so the line is the storage.
        let line = CTLineCreateWithAttributedString(attr)
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun], let first = runs.first else { return nil }
        return CTRunGetStatus(first).contains(.rightToLeft) ? .rightToLeft : .leftToRight
    }
}

/// Constructs the active layout engine. `RTE_TK1` (the back-port build) forces TextKit 1; otherwise the
/// runtime `BlockLayoutBackend.forceTextKit1` override wins, else TextKit 2 on iOS 17+ / TextKit 1 below.
func makeBlockLayout(attributedString: NSAttributedString, width: CGFloat) -> BlockLayoutEngine {
    #if RTE_TK1
    return BlockLayoutTK1(attributedString: attributedString, width: width)
    #else
    if BlockLayoutBackend.forceTextKit1 {
        return BlockLayoutTK1(attributedString: attributedString, width: width)
    }
    if #available(iOS 16.0, *) {
        return BlockLayout(attributedString: attributedString, width: width)
    } else {
        return BlockLayoutTK1(attributedString: attributedString, width: width)
    }
    #endif
}
#endif
