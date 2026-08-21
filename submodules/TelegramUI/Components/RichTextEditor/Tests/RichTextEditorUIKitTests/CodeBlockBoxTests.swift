#if canImport(UIKit)
import XCTest
@testable import RichTextEditorUIKit
@testable import RichTextEditorCore

@available(iOS 13.0, *)
final class CodeBlockBoxTests: XCTestCase {
    private func makeBox(_ text: String, language: String? = "swift") -> CodeBlockBox {
        CodeBlockBox(code: CodeBlock(id: BlockID("c1"), language: language, runs: [TextRun(text: text)]),
                     mapper: AttributedStringMapper(), width: 300)
    }

    func test_codeBox_nodeSizeIsLengthPlusTwo() {
        let box = makeBox("a\nbb")                 // 4 UTF-16 units
        XCTAssertEqual(box.nodeSize, 4 + 2)
        XCTAssertEqual(box.textLength, 4)
    }

    func test_codeBox_textRefIsCode() {
        XCTAssertEqual(makeBox("x").textRef, .code(BlockID("c1")))
    }

    func test_codeBox_usesFifteenPointFont_matchingQuote() {
        let font = CodeBlockBox.codeAttributes()[.font] as? UIFont
        XCTAssertEqual(font?.pointSize ?? 0, 15, accuracy: 0.5, "code block font is 15pt, matching the quote")
    }

    func test_codeBox_currentBlockRoundTripsTextAndLanguage() {
        guard case let .code(cb) = makeBox("a\nb", language: "ruby").currentBlock() else {
            return XCTFail("expected .code")
        }
        XCTAssertEqual(cb.text, "a\nb")
        XCTAssertEqual(cb.language, "ruby")
    }

    func test_codeBox_leafRegionsHasOneRegionSpanningText() {
        let box = makeBox("a\nb"); box.globalStart = 5
        let regions = box.leafRegions()
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].globalStart, 5)
        XCTAssertEqual(regions[0].length, 3)
        XCTAssertEqual(regions[0].ref, .code(BlockID("c1")))
    }

    func test_codeBox_textLeftInsetMatchesQuoteIndent() {
        // Code text must clear the shared accent bar exactly like quote text: its left inset is the
        // quote's leading indent, not the old 8pt code padding.
        let box = makeBox("x")
        box.frame = CGRect(x: 10, y: 0, width: 300, height: 40)
        XCTAssertEqual(box.textOrigin.x - box.frame.minX, StyleSheet.default.quoteIndent, accuracy: 0.5)
    }

    func test_codeBox_factoryProducesCodeBlockBox() {
        let canvas = DocumentCanvasView()
        canvas.setBlocks([.code(CodeBlock(id: BlockID("c1"), runs: [TextRun(text: "x")]))], width: 300)
        XCTAssertTrue(canvas.boxes.first is CodeBlockBox)
    }

    func test_theme_storesCodeBackground() {
        let theme = RichTextEditorTheme(
            primaryText: .black, secondaryText: .black, placeholder: .placeholderText,
            accent: .link, tableBorder: .gray, tableHeaderBackground: .gray, codeBackground: .red)
        XCTAssertEqual(theme.codeBackground, .red)
    }

    func test_emptyCodeBox_showsPlaceholder() {
        let box = makeBox("", language: nil)
        box.placeholders = .default
        XCTAssertEqual(box.placeholderText, "Type code here")
    }
    func test_nonEmptyCodeBox_noPlaceholder() {
        let box = makeBox("x")
        box.placeholders = .default
        XCTAssertNil(box.placeholderText)
    }
    func test_placeholders_containerDefaults() {
        XCTAssertEqual(RichTextEditorPlaceholders.default.codeBlock, "Type code here")
        XCTAssertEqual(RichTextEditorPlaceholders.default.blockQuote, "Type a quote here")
    }
    func test_theme_containerPlaceholder_settable() {
        var theme = RichTextEditorTheme.default
        theme.containerPlaceholder = .red
        XCTAssertEqual(theme.containerPlaceholder, .red)
    }

    // Regression: a TextKit-2 text edit that does NOT change the container width must still re-flow the
    // layout — otherwise the box height stays stale (the "code block doesn't grow on Enter; only rotation,
    // a width change, fixes it" bug). setWidth(200) after building at 200 is a genuine no-op, so the edit's
    // own invalidation is the only thing that can re-flow the height.
    func test_codeBox_editAtSameWidth_reflowsHeight() {
        let box = makeBox("a\nb", language: nil)   // built at width 300
        box.setWidth(300)                          // same width → genuine no-op (does not re-flow)
        let before = box.height
        box.textLayout.replace(start: 0, end: 0,
                               with: NSAttributedString(string: "\n", attributes: CodeBlockBox.codeAttributes()))
        XCTAssertGreaterThan(box.height, before, "height must grow after an insert even without a width change")
    }
}
#endif
