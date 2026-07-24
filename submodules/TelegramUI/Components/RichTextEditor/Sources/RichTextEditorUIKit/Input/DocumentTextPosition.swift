#if canImport(UIKit)
import UIKit

/// A position = a UTF-16 offset within the active block (Phase 1 is single-block).
@available(iOS 13.0, *)
final class DocumentTextPosition: UITextPosition {
    let offset: Int
    init(_ offset: Int) { self.offset = offset }
}

@available(iOS 13.0, *)
final class DocumentTextRange: UITextRange {
    let from: DocumentTextPosition
    let to: DocumentTextPosition
    init(_ from: DocumentTextPosition, _ to: DocumentTextPosition) { self.from = from; self.to = to }
    override var start: UITextPosition { from }
    override var end: UITextPosition { to }
    override var isEmpty: Bool { from.offset == to.offset }
}

@available(iOS 13.0, *)
final class DocumentSelectionRect: UITextSelectionRect {
    private let _rect: CGRect
    private let _containsStart: Bool
    private let _containsEnd: Bool
    init(rect: CGRect, containsStart: Bool, containsEnd: Bool) {
        _rect = rect; _containsStart = containsStart; _containsEnd = containsEnd
    }
    override var rect: CGRect { _rect }
    override var writingDirection: NSWritingDirection { .leftToRight }
    override var containsStart: Bool { _containsStart }
    override var containsEnd: Bool { _containsEnd }
    override var isVertical: Bool { false }
}
#endif
