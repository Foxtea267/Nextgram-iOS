import UIKit
import XCTest
@testable import ItemListUI

// MARK: NEXTGRAM
final class NextgramDisclosureDetailLayoutTests: XCTestCase {
    func testDateFollowsMultilinePreview() {
        let title = CGRect(x: 74, y: 12, width: 220, height: 22)
        let preview = CGRect(x: 74, y: 35, width: 220, height: 66)
        let dateY = nextgramDisclosureAdditionalDetailY(titleFrame: title, labelFrame: preview, stackedLabel: true, spacing: 1)
        XCTAssertEqual(dateY, 102)
        XCTAssertGreaterThan(dateY, preview.maxY)
    }

    func testSingleLineAndSideLabelKeepTheirOwnLayout() {
        let title = CGRect(x: 74, y: 12, width: 220, height: 22)
        let side = CGRect(x: 300, y: 8, width: 80, height: 30)
        XCTAssertEqual(nextgramDisclosureAdditionalDetailY(titleFrame: title, labelFrame: side, stackedLabel: false, spacing: 1), 35)
        XCTAssertEqual(nextgramDisclosureAdditionalDetailY(titleFrame: title, labelFrame: .zero, stackedLabel: true, spacing: 1), 35)
    }

    func testDateFollowsPreviewAtLargerTextSizes() {
        let title = CGRect(x: 74, y: 12, width: 220, height: 38)
        for height in [CGFloat(28), 84, 168] {
            let preview = CGRect(x: 74, y: title.maxY + 2, width: 220, height: height)
            let dateY = nextgramDisclosureAdditionalDetailY(titleFrame: title, labelFrame: preview, stackedLabel: true, spacing: 2)
            XCTAssertEqual(dateY, preview.maxY + 2)
            XCTAssertGreaterThan(dateY, title.maxY)
        }
    }
}
