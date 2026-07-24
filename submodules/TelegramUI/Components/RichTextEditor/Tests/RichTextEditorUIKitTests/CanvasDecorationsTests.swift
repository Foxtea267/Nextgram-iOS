#if canImport(UIKit)
import XCTest
import UIKit
@testable import RichTextEditorUIKit
import RichTextEditorCore

final class CanvasDecorationsTests: XCTestCase {
    private func canvas(_ blocks: [Block], width: CGFloat = 390) -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.setBlocks(blocks, width: width)
        v.frame = CGRect(x: 0, y: 0, width: width, height: 600); v.layoutIfNeeded()
        return v
    }

    func test_codeBlock_contributesItsOwnBackgroundRun() {
        let v = canvas([
            .paragraph(ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Body")])),
            .code(CodeBlock(id: BlockID("c"), runs: [TextRun(text: "let x = 1")])),
        ])
        let decs = v.blockquoteDecorations()
        XCTAssertEqual(decs.count, 1, "only the code block makes a decoration run")
        let codeBox = v.boxes.first(where: { $0 is CodeBlockBox })!
        let codeDec = decs.first(where: { $0.fill == codeBox.frame })!
        XCTAssertEqual(codeDec.fill.minY, codeBox.frame.minY, accuracy: 0.5)   // fill spans the code block
        XCTAssertEqual(codeDec.fill.maxY, codeBox.frame.maxY, accuracy: 0.5)
        XCTAssertEqual(codeDec.bar.minX, codeBox.frame.minX, accuracy: 0.5)     // bar at the block's left edge
        XCTAssertEqual(codeDec.bar.width, v.quoteStyle.barWidth, accuracy: 0.5) // bar width tracks the quote bar
    }

    func test_typeSomethingPlaceholder_onlyWhenSoleBlock() {
        // A single empty body paragraph (an otherwise-empty document): the "Type something…" placeholder shows.
        let v = canvas([.paragraph(ParagraphBlock(id: BlockID("a"), style: .body, runs: []))])
        let draws = v.placeholderDraws()
        XCTAssertEqual(draws.map(\.text), ["Type something…"], "sole empty body block shows the placeholder")
        XCTAssertEqual(draws.first?.origin.y ?? -1, v.boxes[0].textOrigin.y, accuracy: 8.0)
    }

    func test_typeSomethingPlaceholder_notShown_whenOtherBlocksExist() {
        // As soon as a second block exists, no "Type something…" placeholder — regardless of where the empty
        // body sits or whether the other block has content.
        let twoEmptyBodies = canvas([
            .paragraph(ParagraphBlock(id: BlockID("a"), style: .body, runs: [])),
            .paragraph(ParagraphBlock(id: BlockID("b"), style: .body, runs: [])),
        ])
        XCTAssertTrue(twoEmptyBodies.placeholderDraws().isEmpty, "two blocks ⇒ no placeholder")

        let emptyBodyThenHeading = canvas([
            .paragraph(ParagraphBlock(id: BlockID("a"), style: .body, runs: [])),
            .paragraph(ParagraphBlock(id: BlockID("h"), style: .heading1, runs: [TextRun(text: "Hi")])),
        ])
        XCTAssertTrue(emptyBodyThenHeading.placeholderDraws().isEmpty,
                      "an empty body is not alone ⇒ no placeholder")
    }

    func test_typeSomethingPlaceholder_notShown_whenSoleBlockIsNotBody() {
        // The document's only block is an empty heading — the gate is sole-block + body, so no placeholder.
        let v = canvas([.paragraph(ParagraphBlock(id: BlockID("h"), style: .heading1, runs: []))])
        XCTAssertTrue(v.placeholderDraws().isEmpty, "a non-body sole block shows no body placeholder")
    }

    func test_placeholder_baselineMatchesRealFirstLineBaseline() {
        // The placeholder must sit on the paragraph's real first-line baseline (where the first typed glyph
        // lands), not float above OR below it. Real text's first baseline is pushed down by the multiple's
        // extra leading (body = 1.10) MINUS the render centering that raises the glyphs by HALF of it
        // (BlockLayout.centeringDelta) — i.e. HALF the extra leading. (Using the full leading, as before the
        // 2026-06-26 centering landed, left the ghost ~1pt below where typing actually appears.)
        let v = canvas([.paragraph(ParagraphBlock(id: BlockID("b"), style: .body, runs: []))])
        let box = v.boxes[0] as! BlockBox
        let draw = v.placeholderDraws().first!
        let font = StyleSheet.default.font(for: .body, attributes: .plain)
        let ps = StyleSheet.default.paragraphStyle(for: .body, attributes: ParagraphAttributes(), list: nil)
        let expectedShift = (ps.lineHeightMultiple - 1) * font.lineHeight / 2     // centered: half the extra leading
        XCTAssertGreaterThan(expectedShift, 0.5)                                  // body shift is ~1pt
        XCTAssertEqual(draw.origin.y, box.textOrigin.y + expectedShift, accuracy: 0.5)
        XCTAssertEqual(draw.origin.x, box.textOrigin.x, accuracy: 0.5)            // horizontal unchanged
    }

    func test_emptyParagraph_caretRectSpansTheLineHeight() {
        // An empty line's caret must span the real line height (font.lineHeight × lineHeightMultiple), not the
        // fixed 20pt fallback BlockLayout returns when there's no laid-out fragment — so it aligns with the
        // placeholder and with a typed line.
        let v = canvas([.paragraph(ParagraphBlock(id: BlockID("b"), style: .body, runs: []))])
        let box = v.boxes[0] as! BlockBox
        let caret = v.caretRect(for: DocumentTextPosition(box.textStart))
        let font = StyleSheet.default.font(for: .body, attributes: .plain)
        let ps = StyleSheet.default.paragraphStyle(for: .body, attributes: ParagraphAttributes(), list: nil)
        let mult = ps.lineHeightMultiple > 0 ? ps.lineHeightMultiple : 1
        XCTAssertEqual(caret.height, font.lineHeight * mult, accuracy: 0.5)
        XCTAssertGreaterThan(caret.height, 20.5)                                  // taller than the fixed-20 fallback
    }

    func test_placeholder_listItem_isInsetByHeadIndent() {
        // An empty list item shows a list-specific hint; it must be inset to the list's text column
        // (aligned with where typed text appears, past the marker), not drawn at the page margin.
        let v = canvas([.paragraph(ParagraphBlock(id: BlockID("li"), style: .body,
                                                  list: ListMembership(marker: .bullet), runs: []))])
        let box = v.boxes[0] as! BlockBox
        let draw = v.placeholderDraws().first { $0.text == "Press return to end the list" }
        XCTAssertNotNil(draw)
        XCTAssertEqual(draw!.origin.x, box.textOrigin.x + StyleSheet.listMarkerSpacing, accuracy: 0.5)
    }

    func test_placeholder_emptyListItem_level0_saysEndTheList() {
        let v = canvas([.paragraph(ParagraphBlock(id: BlockID("li"), style: .body,
                                                  list: ListMembership(marker: .bullet), runs: []))])
        XCTAssertEqual(v.placeholderDraws().first?.text, "Press return to end the list")
    }

    func test_placeholder_emptyNestedListItem_saysOutdent() {
        let v = canvas([.paragraph(ParagraphBlock(id: BlockID("li"), style: .body,
                                                  list: ListMembership(marker: .bullet, level: 1), runs: []))])
        XCTAssertEqual(v.placeholderDraws().first?.text, "Press return to outdent")
    }

    func test_placeholder_emptyOrderedListItem_alsoSaysEndTheList() {
        // The hint is about the list, not the marker style — ordered items get it too.
        let v = canvas([.paragraph(ParagraphBlock(id: BlockID("li"), style: .body,
                                                  list: ListMembership(marker: .ordered), runs: []))])
        XCTAssertEqual(v.placeholderDraws().first?.text, "Press return to end the list")
    }

    func test_placeholders_noneWhenNonEmpty() {
        let v = canvas([.paragraph(ParagraphBlock(id: BlockID("b"), style: .body, runs: [TextRun(text: "Hi")]))])
        XCTAssertTrue(v.placeholderDraws().isEmpty)
    }

    func test_placeholder_isDrawnByBox_onlyForTopLevelEmptyParagraph() {
        let v = DocumentCanvasView()
        v.setParagraphs([ParagraphBlock(id: BlockID("t"), style: .body, runs: [])], width: 300)
        v.frame = CGRect(x: 0, y: 0, width: 300, height: 200); v.layoutIfNeeded()
        let box = v.boxes[0] as! BlockBox
        XCTAssertTrue(box.isTopLevelBlock, "top-level boxes are flagged during layout")
        let d = box.placeholderDraw()!
        let seam = v.placeholderDraws().first!
        XCTAssertEqual(d.text, "Type something…")
        XCTAssertEqual(d.origin.x, seam.origin.x, accuracy: 0.01)
        XCTAssertEqual(d.origin.y, seam.origin.y, accuracy: 0.01)
    }

    func test_emptyCellParagraph_drawsNoPlaceholder() {
        // An empty BODY paragraph inside a table cell would show "Type something…" if it were top-level;
        // the isTopLevelBlock gate must keep cells placeholder-free (parity with pre-refactor behavior).
        let v = DocumentCanvasView()
        let cellPara = ParagraphBlock(id: BlockID("cp"), style: .body, runs: [])
        v.setBlocks([.table(TableBlock(id: BlockID("t"),
            columns: [ColumnSpec(width: 120)],
            rows: [Row(id: BlockID("r0"), cells: [Cell(id: BlockID("c0"), blocks: [.paragraph(cellPara)])])]))],
            width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 200); v.layoutIfNeeded()
        // Find the cell's BlockBox via the table's leaf regions / cell stacks.
        let table = v.boxes[0] as! TableBlockBox
        let cellBox = table.cellStack(containing: table.cellTextStart(row: 0, column: 0)!)!.box as! BlockBox
        XCTAssertFalse(cellBox.isTopLevelBlock, "cell paragraphs are never flagged top-level")
        XCTAssertNil(cellBox.placeholderDraw(), "cell empty paragraph draws no placeholder")
        XCTAssertTrue(v.placeholderDraws().isEmpty, "the canvas placeholder seam excludes cell paragraphs")
    }
}
#endif
