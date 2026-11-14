import NagramSettings
import XCTest

final class NextgramTemporaryFilterRevealTests: XCTestCase {
    func testRevealIsScopedAndCanBeEndedWithoutChangingRules() {
        let reveal = NextgramTemporaryFilterReveal.shared
        let account: Int64 = -987654321
        let chat: Int64 = -123456789
        let rulesEnabled = NagramSettings.shared.regexFiltersEnabled
        let rules = NagramSettings.shared.regexFilterRules
        defer { reveal.setActive(false, accountId: account, chatId: chat) }
        reveal.setActive(true, accountId: account, chatId: chat)
        XCTAssertTrue(reveal.isActive(accountId: account, chatId: chat))
        XCTAssertFalse(reveal.isActive(accountId: account + 1, chatId: chat))
        XCTAssertFalse(reveal.isActive(accountId: account, chatId: chat + 1))
        XCTAssertEqual(NagramSettings.shared.regexFiltersEnabled, rulesEnabled)
        XCTAssertEqual(NagramSettings.shared.regexFilterRules, rules)
        reveal.setActive(false, accountId: account, chatId: chat)
        XCTAssertFalse(reveal.isActive(accountId: account, chatId: chat))
    }
}
