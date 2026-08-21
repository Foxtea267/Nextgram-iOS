import XCTest
@testable import RichTextEditorCore

final class CodeBlockTests: XCTestCase {
    func test_codeBlock_textAndCountJoinRuns() {
        let cb = CodeBlock(id: BlockID("c1"), language: "swift",
                           runs: [TextRun(text: "let x = 1\n"), TextRun(text: "let y = 2")])
        XCTAssertEqual(cb.text, "let x = 1\nlet y = 2")
        XCTAssertEqual(cb.utf16Count, 19)
    }

    func test_codeBlock_codableRoundTrip() throws {
        let cb = CodeBlock(id: BlockID("c1"), language: "python",
                           runs: [TextRun(text: "print(1)\nprint(2)")])
        let data = try JSONEncoder().encode(cb)
        let back = try JSONDecoder().decode(CodeBlock.self, from: data)
        XCTAssertEqual(cb, back)
    }

    func test_codeBlock_nilLanguageRoundTrips() throws {
        let cb = CodeBlock(id: BlockID("c1"), language: nil, runs: [TextRun(text: "x")])
        let back = try JSONDecoder().decode(CodeBlock.self, from: JSONEncoder().encode(cb))
        XCTAssertNil(back.language)
        XCTAssertEqual(cb, back)
    }

    func test_codeBlock_emptyRunsGiveZeroCount() {
        let cb = CodeBlock(id: BlockID("c1"))
        XCTAssertEqual(cb.text, "")
        XCTAssertEqual(cb.utf16Count, 0)
    }

    func test_blockCode_idAndCodableRoundTrip() throws {
        let block = Block.code(CodeBlock(id: BlockID("c1"), language: "swift",
                                         runs: [TextRun(text: "a\nb")]))
        XCTAssertEqual(block.id, BlockID("c1"))
        let back = try JSONDecoder().decode(Block.self, from: JSONEncoder().encode(block))
        XCTAssertEqual(block, back)
    }
}
