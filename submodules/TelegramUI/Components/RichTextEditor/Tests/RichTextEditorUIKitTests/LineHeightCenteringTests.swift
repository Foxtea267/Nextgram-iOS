#if canImport(UIKit)
import XCTest
import UIKit
@testable import RichTextEditorUIKit
import RichTextEditorCore

/// The per-style line-height multiple (body = 1.10) makes the line-fragment box — the box the selection
/// wash + caret fill — taller than the glyphs. TextKit's default is to dump ALL of that extra leading
/// ABOVE the glyphs (the baseline drops), so the text reads as offset too low inside its rect. Baseline
/// centering must split the extra HALF above / HALF below so the glyphs sit centered in the box while the
/// box keeps its full (spacing-preserving) height. Verified on BOTH engines — TextKit 2 (`BlockLayout`)
/// and TextKit 1 (`BlockLayoutTK1`).
final class LineHeightCenteringTests: XCTestCase {
    private struct Gaps { var top: CGFloat; var bottom: CGFloat }

    /// A one-line body string carrying the default 1.10 line-height multiple, plus its font.
    private func bodyLine() -> (NSAttributedString, UIFont) {
        let sheet = StyleSheet.default
        let font = sheet.font(for: .body, attributes: .plain)
        let ps = sheet.paragraphStyle(for: .body, attributes: .default)
        return (NSAttributedString(string: "Qwefqwef", attributes: [.font: font, .paragraphStyle: ps]), font)
    }

    /// Empty leading ABOVE the glyphs (`top`) and BELOW them (`bottom`) inside the line-fragment box that
    /// `caretRect`/`selectionFillRects` fill. Centered ⇒ `top ≈ bottom`.
    private func gaps(_ engine: BlockLayoutEngine, font: UIFont) -> Gaps {
        let box = engine.caretRect(atOffset: 0)
        let baseline = engine.firstLineBaselineFromTop ?? 0
        let glyphTop = baseline - font.ascender              // ascender > 0
        let glyphBottom = baseline - font.descender          // descender < 0 → extends below the baseline
        return Gaps(top: glyphTop - box.minY, bottom: box.maxY - glyphBottom)
    }

    @available(iOS 16.0, *)
    func test_textKit2_centersGlyphsInLineBox() {
        let (attr, font) = bodyLine()
        let g = gaps(BlockLayout(attributedString: attr, width: 300), font: font)
        print("LH TK2 → topGap=\(g.top) bottomGap=\(g.bottom)")
        XCTAssertEqual(g.top, g.bottom, accuracy: 0.75,
            "TK2: body-1.10 glyphs must be centered in the line box (top \(g.top) vs bottom \(g.bottom))")
    }

    func test_textKit1_centersGlyphsInLineBox() {
        let (attr, font) = bodyLine()
        let g = gaps(BlockLayoutTK1(attributedString: attr, width: 300), font: font)
        print("LH TK1 → topGap=\(g.top) bottomGap=\(g.bottom)")
        XCTAssertEqual(g.top, g.bottom, accuracy: 0.75,
            "TK1: body-1.10 glyphs must be centered in the line box (top \(g.top) vs bottom \(g.bottom))")
    }
}
#endif
