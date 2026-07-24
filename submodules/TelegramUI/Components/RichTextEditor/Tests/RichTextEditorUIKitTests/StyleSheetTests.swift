#if canImport(UIKit)
import XCTest
import UIKit
@testable import RichTextEditorUIKit
import RichTextEditorCore

final class StyleSheetTests: XCTestCase {
    func test_color_roundTrips() {
        let c = RGBAColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        let back = c.uiColor.rgba
        XCTAssertEqual(back.red, 0.2, accuracy: 0.01)
        XCTAssertEqual(back.alpha, 0.8, accuracy: 0.01)
    }

    func test_font_appliesBoldItalicAndSize() {
        let f = FontResolver.font(family: nil, size: 20, bold: true, italic: true)
        XCTAssertEqual(f.pointSize, 20, accuracy: 0.5)
        XCTAssertTrue(f.fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertTrue(f.fontDescriptor.symbolicTraits.contains(.traitItalic))
    }

    func test_styleSheet_headingIsLargerThanBody() {
        let sheet = StyleSheet.default
        let h1 = sheet.font(for: .heading1, attributes: .plain)
        let body = sheet.font(for: .body, attributes: .plain)
        XCTAssertGreaterThan(h1.pointSize, body.pointSize)
    }

    func test_caption_is15ptSans_andBodyIsSans() {
        let sheet = StyleSheet.default
        let caption = sheet.font(for: .caption, attributes: .plain)
        XCTAssertEqual(caption.pointSize, 15, accuracy: 0.5)
        XCTAssertEqual(caption.familyName, UIFont.systemFont(ofSize: 15).familyName, "captions are sans")
        XCTAssertEqual(sheet.font(for: .body, attributes: .plain).familyName,
                       UIFont.systemFont(ofSize: 17).familyName, "body is sans")
    }

    func test_heading_isSerif_andNotBoldByDefault() {
        let f = StyleSheet.default.font(for: .heading1, attributes: .plain)
        XCTAssertTrue(f.fontName.contains("NewYork"), "headings stay serif")
        XCTAssertFalse(f.fontDescriptor.symbolicTraits.contains(.traitBold),
                       "headings are regular weight by default — bold is user emphasis only")
    }

    func test_heading_userBoldStillApplies() {
        var bold = CharacterAttributes(); bold.bold = true
        let f = StyleSheet.default.font(for: .heading1, attributes: bold)
        XCTAssertTrue(f.fontDescriptor.symbolicTraits.contains(.traitBold),
                      "a user can still bold a heading explicitly")
    }

    func test_body_is17pt() {
        XCTAssertEqual(StyleSheet.default.font(for: .body, attributes: .plain).pointSize, 17, accuracy: 0.5)
    }

    func test_tableCells_bodyIs15pt_headingsUnchanged() {
        let sheet = StyleSheet.tableCells
        XCTAssertEqual(sheet.font(for: .body, attributes: .plain).pointSize, 15, accuracy: 0.5,
                       "table-cell body base is 15pt")
        XCTAssertEqual(sheet.font(for: .heading1, attributes: .plain).pointSize, 24, accuracy: 0.5,
                       "headings keep their fixed size in cells")
        // The document body sheet is untouched.
        XCTAssertEqual(StyleSheet.default.font(for: .body, attributes: .plain).pointSize, 17, accuracy: 0.5)
    }

    func test_tableCells_explicitFontSizeStillWins() {
        var ca = CharacterAttributes(); ca.fontSize = 22
        XCTAssertEqual(StyleSheet.tableCells.font(for: .body, attributes: ca).pointSize, 22, accuracy: 0.5,
                       "an explicit run size overrides the cell base")
    }

    func test_headingSizes_matchTypeScale() {
        let sheet = StyleSheet.default
        XCTAssertEqual(sheet.font(for: .heading1, attributes: .plain).pointSize, 24, accuracy: 0.5)
        XCTAssertEqual(sheet.font(for: .heading2, attributes: .plain).pointSize, 21, accuracy: 0.5)
        XCTAssertEqual(sheet.font(for: .heading3, attributes: .plain).pointSize, 19, accuracy: 0.5)
    }

    func test_perStyleSpacing_applied() {
        let sheet = StyleSheet.default
        let body = sheet.paragraphStyle(for: .body, attributes: .default) as! NSParagraphStyle
        XCTAssertGreaterThan(body.lineHeightMultiple, 1.0)                 // body gets a line-height bump
        let h1 = sheet.paragraphStyle(for: .heading1, attributes: .default) as! NSParagraphStyle
        XCTAssertGreaterThan(h1.paragraphSpacingBefore, 0)                 // headings get space before
    }

    func test_textLayoutMetrics_defaultMetrics_matchDocumentLook() {
        let sheet = StyleSheet.default
        XCTAssertEqual(sheet.bodyLineHeightMultiple, 1.10, accuracy: 0.001, "document editors keep the built-in body metrics")
        let body = sheet.paragraphStyle(for: .body, attributes: .default) as! NSParagraphStyle
        XCTAssertEqual(body.lineHeightMultiple, 1.10, accuracy: 0.001)
        XCTAssertEqual(body.paragraphSpacing, 8, accuracy: 0.001)
    }

    func test_compactMetrics_zeroBodyLineHeightAndParagraphSpacing() {
        var sheet = StyleSheet()                                          // the chat-composer configuration
        let m = TextLayoutMetrics.compact
        sheet.bodyLineHeightMultiple = m.bodyLineHeightMultiple
        sheet.bodyParagraphSpacingBefore = m.bodyParagraphSpacingBefore
        sheet.bodyParagraphSpacingAfter = m.bodyParagraphSpacingAfter
        let body = sheet.paragraphStyle(for: .body, attributes: .default) as! NSParagraphStyle
        XCTAssertEqual(body.lineHeightMultiple, 1.0, accuracy: 0.001,
                       "compact body uses natural (1.0) line height — no extra inter-line gap")
        XCTAssertEqual(body.paragraphSpacing, 0, accuracy: 0.001,
                       "compact body has no inter-paragraph spacing")
        XCTAssertEqual(body.paragraphSpacingBefore, 0, accuracy: 0.001)
        let caption = sheet.paragraphStyle(for: .caption, attributes: .default) as! NSParagraphStyle
        XCTAssertEqual(caption.lineHeightMultiple, 1.0, accuracy: 0.001)
        XCTAssertEqual(caption.paragraphSpacing, 0, accuracy: 0.001)
    }

    func test_compactMetrics_respectExplicitModelLineHeight() {
        var sheet = StyleSheet()
        sheet.bodyLineHeightMultiple = TextLayoutMetrics.compact.bodyLineHeightMultiple
        var attrs = ParagraphAttributes.default
        attrs.lineHeightMultiple = 1.5                                    // an explicit model override still wins
        let body = sheet.paragraphStyle(for: .body, attributes: attrs) as! NSParagraphStyle
        XCTAssertEqual(body.lineHeightMultiple, 1.5, accuracy: 0.001)
    }

    func test_textLayoutMetrics_presets() {
        XCTAssertEqual(TextLayoutMetrics.compact.bodyLineHeightMultiple, 1.0, accuracy: 0.001)
        XCTAssertEqual(TextLayoutMetrics.compact.bodyParagraphSpacingAfter, 0, accuracy: 0.001)
        XCTAssertEqual(TextLayoutMetrics.default.bodyLineHeightMultiple, 1.10, accuracy: 0.001)
        XCTAssertEqual(TextLayoutMetrics.default.bodyParagraphSpacingAfter, 8, accuracy: 0.001)
    }
}
#endif
