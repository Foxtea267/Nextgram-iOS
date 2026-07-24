import XCTest
@testable import RichTextEditorCore

final class CodeBlockPositionTests: XCTestCase {
    // A multi-line code block is ONE text region whose length includes interior "\n"s; the block
    // contributes content + 2 to the position axis, exactly like a wrap-heavy paragraph.
    func test_codeBlock_sizeIncludesInteriorNewlines() {
        let text = "a\nbb"                          // 4 UTF-16 units incl. the "\n"
        let doc = Document(blocks: [.code(CodeBlock(id: BlockID("c1"), runs: [TextRun(text: text)]))])
        XCTAssertEqual(DocumentTree.documentSize(doc), 4 + 2)
    }

    func test_codeBlock_textPositionMapsToCodeRef() {
        let doc = Document(blocks: [.code(CodeBlock(id: BlockID("c1"), runs: [TextRun(text: "ab")]))])
        let root = DocumentTree.build(from: doc)
        // Position 2 (after the open token, 1 char in) is inside the code text node.
        let tp = PositionResolver.textPosition(at: 2, in: root)
        XCTAssertEqual(tp?.ref, .code(BlockID("c1")))
        XCTAssertEqual(tp?.offset, 1)
    }
}
