import Foundation
import NagramSettings
import XCTest

final class NextgramMusicSettingsTests: XCTestCase {
    func testSystemDisplayModes() {
        XCTAssertTrue(NextgramSystemMusicDisplay.always.isVisible(inForeground: true))
        XCTAssertTrue(NextgramSystemMusicDisplay.always.isVisible(inForeground: false))
        XCTAssertFalse(NextgramSystemMusicDisplay.background.isVisible(inForeground: true))
        XCTAssertTrue(NextgramSystemMusicDisplay.background.isVisible(inForeground: false))
        XCTAssertFalse(NextgramSystemMusicDisplay.never.isVisible(inForeground: true))
        XCTAssertFalse(NextgramSystemMusicDisplay.never.isVisible(inForeground: false))
    }

    func testSummaryEndpointDoesNotDuplicateVersionPath() {
        var configuration = NextgramSummarySettings.Configuration()
        configuration.baseURL = "https://example.com"
        XCTAssertEqual(NextgramSummarySettings.requestURL(configuration)?.path, "/v1/chat/completions")
        configuration.baseURL = "https://example.com/v1/"
        XCTAssertEqual(NextgramSummarySettings.requestURL(configuration)?.path, "/v1/chat/completions")
        configuration.format = "anthropic"
        XCTAssertEqual(NextgramSummarySettings.requestURL(configuration)?.path, "/v1/messages")
    }

    func testSummaryEndpointRejectsCredentialsAndTraversal() {
        var configuration = NextgramSummarySettings.Configuration()
        for base in ["http://example.com", "https://key@example.com", "https://example.com?key=secret"] {
            configuration.baseURL = base
            XCTAssertNil(NextgramSummarySettings.requestURL(configuration))
        }
        configuration.baseURL = "https://example.com"
        for path in ["../messages", "%2e%2e/messages", "https://other.example", "chat?key=secret", "chat\\messages"] {
            configuration.endpoint = path
            XCTAssertNil(NextgramSummarySettings.requestURL(configuration))
        }
    }
}
