#if canImport(UIKit)
import XCTest
import UIKit
@testable import RichTextEditorUIKit
import RichTextEditorCore

final class BlockStackTests: XCTestCase {
    func test_recompute_assignsNodeStartsAndReturnsTokenSize() {
        let mapper = AttributedStringMapper()
        let stack = BlockStack(boxes: [
            BlockBox(paragraph: ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "One")]), mapper: mapper, width: 300),
            BlockBox(paragraph: ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Two")]), mapper: mapper, width: 300),
        ])
        let size = stack.recompute(baseOffset: 0)
        // "One"(3)+2 + "Two"(3)+2 = 10; globalStarts 1 and 6
        XCTAssertEqual(size, 10)
        XCTAssertEqual(stack.boxes[0].nodeStart, 1)
        XCTAssertEqual(stack.boxes[1].nodeStart, 6)
    }

    func test_recompute_withBaseOffset_shiftsGlobalStarts() {
        let mapper = AttributedStringMapper()
        let stack = BlockStack(boxes: [
            BlockBox(paragraph: ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "One")]), mapper: mapper, width: 300),
        ])
        _ = stack.recompute(baseOffset: 100)
        XCTAssertEqual(stack.boxes[0].nodeStart, 101)     // baseOffset + 1
        XCTAssertEqual(stack.boxes[0].leafRegions()[0].globalStart, 101)
    }

    func test_layout_stacksVerticallyAndReturnsHeight() {
        let mapper = AttributedStringMapper()
        let stack = BlockStack(boxes: [
            BlockBox(paragraph: ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "One")]), mapper: mapper, width: 300),
            BlockBox(paragraph: ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Two")]), mapper: mapper, width: 300),
        ])
        let h = stack.layout(origin: CGPoint(x: 10, y: 20), width: 300)
        XCTAssertEqual(stack.boxes[0].frame.minX, 10, accuracy: 0.5)
        XCTAssertEqual(stack.boxes[0].frame.minY, 20, accuracy: 0.5)
        XCTAssertEqual(stack.boxes[1].frame.minY, stack.boxes[0].frame.maxY, accuracy: 0.5)
        XCTAssertGreaterThan(h, 0)
    }

    /// The intra-paragraph advance between two adjacent lines of a single body paragraph — the target
    /// spacing for consecutive list items.
    private func intraParagraphLineAdvance() -> CGFloat {
        let ref = BlockBox(paragraph: ParagraphBlock(id: BlockID("ref"), runs: [TextRun(text: "AAAA\nBBBB")]),
                           mapper: AttributedStringMapper(), width: 300)
        ref.setWidth(300)
        return ref.layout.caretRect(atOffset: 5).minY - ref.layout.caretRect(atOffset: 0).minY
    }

    private func listBox(_ id: String) -> BlockBox {
        BlockBox(paragraph: ParagraphBlock(id: BlockID(id), list: ListMembership(marker: .bullet),
                                           runs: [TextRun(text: "Item")]),
                 mapper: AttributedStringMapper(), width: 300)
    }

    func test_consecutiveListItems_spacedLikeIntraParagraphLines() {
        let stack = BlockStack(boxes: [listBox("a"), listBox("b")])
        stack.layout(origin: .zero, width: 300)
        let advance = (stack.boxes[1] as! BlockBox).textOrigin.y - (stack.boxes[0] as! BlockBox).textOrigin.y
        // Engine-aware: TextKit 2 bakes the full lineHeightMultiple into a single line, so a single-line item
        // advances by exactly one intra-paragraph line. TextKit 1 applies the multiple BETWEEN lines (not
        // around a lone line), so a single-line item is its natural (shorter) height — the invariant that
        // still matters is that items pack TIGHT (no paragraph gap), i.e. no looser than one text line.
        if stack.boxes[0].textLayout is BlockLayoutTK1 {
            XCTAssertGreaterThan(advance, 0)
            XCTAssertLessThanOrEqual(advance, intraParagraphLineAdvance() + 1.0)
        } else {
            XCTAssertEqual(advance, intraParagraphLineAdvance(), accuracy: 1.0)
        }
        // Frames stay contiguous (no overlap) on both engines — the core stacking invariant.
        XCTAssertEqual(stack.boxes[1].frame.minY, stack.boxes[0].frame.maxY, accuracy: 0.5)
    }

    func test_consecutiveBodyBlocks_haveNoGap() {
        let mapper = AttributedStringMapper()
        let stack = BlockStack(boxes: [
            BlockBox(paragraph: ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "One")]), mapper: mapper, width: 300),
            BlockBox(paragraph: ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Two")]), mapper: mapper, width: 300),
        ])
        stack.layout(origin: .zero, width: 300)
        let a = stack.boxes[0] as! BlockBox, b = stack.boxes[1] as! BlockBox
        // The whitespace between the bottom of A's text and the top of B's text.
        let gap = b.textOrigin.y - (a.textOrigin.y + a.layout.boundingHeight)
        XCTAssertEqual(gap, 0, accuracy: 0.5)   // two adjacent body paragraphs now stack tight (was 8)
    }

    func test_codeBlockNeighbors_reserveExtraExternalMargin() {
        let mapper = AttributedStringMapper()
        func body(_ id: String) -> BlockBox {
            BlockBox(paragraph: ParagraphBlock(id: BlockID(id), runs: [TextRun(text: "x")]), mapper: mapper, width: 300)
        }
        let code = CodeBlockBox(code: CodeBlock(id: BlockID("c"), runs: [TextRun(text: "let x = 1")]), mapper: mapper, width: 300)
        let above = body("above"), below = body("below")
        BlockStack(boxes: [above, code, below]).layout(origin: .zero, width: 300)
        // A code block draws its own bounded (quote-style) fill, so neighbors reserve the extra external
        // margin on the code-facing side — exactly like quote / table / collapsed-quote neighbors, so a
        // code block sits the SAME distance from its neighbors as a quote does.
        XCTAssertGreaterThan(above.bottomInset, BlockBox.defaultVerticalInset)   // block above the code block
        XCTAssertGreaterThan(below.topInset, BlockBox.defaultVerticalInset)      // block below the code block
        XCTAssertEqual(above.topInset, BlockBox.defaultVerticalInset, accuracy: 0.5)  // far side unaffected
    }

    func test_tableNeighbors_reserveExtraExternalMargin() {
        let mapper = AttributedStringMapper()
        func body(_ id: String) -> BlockBox {
            BlockBox(paragraph: ParagraphBlock(id: BlockID(id), runs: [TextRun(text: "x")]), mapper: mapper, width: 300)
        }
        let table = TableBlockBox(table: TableBlock(id: BlockID("t"),
            columns: [ColumnSpec(width: 100), ColumnSpec(width: 100)],
            rows: [Row(id: BlockID("r0"), isHeader: true, cells: [
                Cell(id: BlockID("a"), blocks: [.paragraph(ParagraphBlock(id: BlockID("ap")))]),
                Cell(id: BlockID("b"), blocks: [.paragraph(ParagraphBlock(id: BlockID("bp")))])])]),
            mapper: mapper, width: 300)
        let above = body("above"), below = body("below")
        BlockStack(boxes: [above, table, below]).layout(origin: .zero, width: 300)
        // The blocks bordering the table reserve extra margin on the table-facing side (the table's
        // bounded grid needs breathing room), like quote neighbors.
        XCTAssertGreaterThan(above.bottomInset, BlockBox.defaultVerticalInset)   // block above the table
        XCTAssertGreaterThan(below.topInset, BlockBox.defaultVerticalInset)      // block below the table
        XCTAssertEqual(above.topInset, BlockBox.defaultVerticalInset, accuracy: 0.5)  // far side unaffected
    }

    func test_blockToMediaBoundary_usesDedicatedMediaInset_decoupledFromBase() {
        let mapper = AttributedStringMapper()
        func body(_ id: String) -> BlockBox {
            BlockBox(paragraph: ParagraphBlock(id: BlockID(id), runs: [TextRun(text: "x")]), mapper: mapper, width: 300)
        }
        let media = MediaBlockBox(media: MediaBlock(id: BlockID("m"), mediaID: "x",
                                                    naturalSize: Size2D(width: 100, height: 50), caption: []),
                                  mapper: mapper, width: 300)
        let heading = BlockBox(paragraph: ParagraphBlock(id: BlockID("h"), style: .heading1, runs: [TextRun(text: "H")]),
                               mapper: mapper, width: 300)
        let below = body("below")
        let stack = BlockStack(boxes: [heading, media, below])
        stack.verticalInsetBase = 30   // deliberately unrelated to the media inset — proves decoupling from base
        stack.layout(origin: .zero, width: 300)
        // Any block (heading here) facing the image reserves the dedicated media inset (6pt), not `base` (30).
        XCTAssertEqual(heading.bottomInset, 6, accuracy: 0.5, "block above the image uses the dedicated media inset")
        XCTAssertEqual(below.topInset, 6, accuracy: 0.5, "block below the image uses the dedicated media inset")
        // The far sides (facing the stack edge) still use `base`.
        XCTAssertEqual(heading.topInset, 30, accuracy: 0.5, "far side unaffected — still base")
        XCTAssertEqual(below.bottomInset, 30, accuracy: 0.5, "far side unaffected — still base")
    }

    func test_listItemToParagraphBoundary_stacksTight() {
        let mapper = AttributedStringMapper()
        let stack = BlockStack(boxes: [
            listBox("a"),
            BlockBox(paragraph: ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Plain")]), mapper: mapper, width: 300),
        ])
        stack.layout(origin: .zero, width: 300)
        let a = stack.boxes[0] as! BlockBox, b = stack.boxes[1] as! BlockBox
        // The list-item→body boundary now collapses to NO inter-block gap, exactly like a body↔body or
        // list↔list boundary — the body paragraph's text starts immediately after the list item's text.
        let gap = b.textOrigin.y - (a.textOrigin.y + a.layout.boundingHeight)
        XCTAssertEqual(gap, 0, accuracy: 0.5)
    }
}
#endif
