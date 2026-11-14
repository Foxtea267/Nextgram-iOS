import NagramSettings
import XCTest

final class NextgramMemberNotificationTests: XCTestCase {
    func testOnlySelectedIncomingUnreadGroupMessagesQualify() {
        XCTAssertTrue(NextgramMemberNotifications.isEligible(selected: true, isGroup: true, incoming: true, imported: false, unread: true))
        XCTAssertFalse(NextgramMemberNotifications.isEligible(selected: false, isGroup: true, incoming: true, imported: false, unread: true))
        XCTAssertFalse(NextgramMemberNotifications.isEligible(selected: true, isGroup: false, incoming: true, imported: false, unread: true))
        XCTAssertFalse(NextgramMemberNotifications.isEligible(selected: true, isGroup: true, incoming: false, imported: false, unread: true))
        XCTAssertFalse(NextgramMemberNotifications.isEligible(selected: true, isGroup: true, incoming: true, imported: true, unread: true))
        XCTAssertFalse(NextgramMemberNotifications.isEligible(selected: true, isGroup: true, incoming: true, imported: false, unread: false))
        XCTAssertFalse(NextgramMemberNotifications.isEligible(selected: true, isGroup: true, incoming: true, imported: false, unread: true, serviceMessage: true))
    }

    func testKeysSeparateAccountsAndChats() {
        XCTAssertNotEqual(NextgramMemberNotifications.key(accountId: 1, chatId: 2), NextgramMemberNotifications.key(accountId: 2, chatId: 2))
        XCTAssertNotEqual(NextgramMemberNotifications.key(accountId: 1, chatId: 2), NextgramMemberNotifications.key(accountId: 1, chatId: 3))
    }
}
