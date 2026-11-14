import XCTest
import NagramSearchLink

// MARK: NAGRAM — 聊天列表搜索框的链接识别。
final class NagramSearchLinkTests: XCTestCase {
    private func link(_ query: String) -> NagramSearchLink? {
        return nagramSearchLink(query: query, appSpecificScheme: "nagram")
    }

    private func assertLink(_ value: NagramSearchLink?, url: String, resolvableUrl: String?, kind: NagramSearchLink.Kind, isInferred: Bool, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(value?.url, url, file: file, line: line)
        XCTAssertEqual(value?.resolvableUrl, resolvableUrl, file: file, line: line)
        XCTAssertEqual(value?.kind, kind, file: file, line: line)
        XCTAssertEqual(value?.isInferred, isInferred, file: file, line: line)
    }

    func testFullTelegramLinks() {
        assertLink(link("https://t.me/durov/123"), url: "https://t.me/durov/123", resolvableUrl: "https://t.me/durov/123", kind: .message, isInferred: false)
        XCTAssertEqual(link("t.me/c/1234567/89")?.kind, .message)
        XCTAssertEqual(link("t.me/c/1234567/5/89")?.kind, .message)
        XCTAssertEqual(link("t.me/durov/5/89?single")?.kind, .message)
        XCTAssertEqual(link("t.me/s/durov/123")?.kind, .message)
        XCTAssertEqual(link("t.me/s/durov")?.kind, .generic)
        XCTAssertEqual(link("  telegram.me/+AbCdEf123456  ")?.kind, .invite)
        XCTAssertEqual(link("https://t.me/joinchat/AbCdEf123456")?.kind, .invite)
        XCTAssertEqual(link("HTTPS://T.ME/durov")?.url, "https://T.ME/durov")
        XCTAssertEqual(link("t.me/durov")?.kind, .generic)
        XCTAssertEqual(link("t.me/addstickers/Animals")?.kind, .generic)
        XCTAssertEqual(link("t.me/+8613800138000")?.kind, .generic)
        XCTAssertEqual(link("t.me/durov")?.displayUrl, "t.me/durov")
        XCTAssertEqual(link("durov.t.me/123")?.kind, .message)
        XCTAssertEqual(link("durov.t.me")?.kind, .generic)
    }

    func testNotTelegramLinks() {
        XCTAssertNil(link(""))
        XCTAssertNil(link("t.me"))
        XCTAssertNil(link("t.me/"))
        XCTAssertNil(link("hello world"))
        XCTAssertNil(link("https://example.com/durov/123"))
        XCTAssertNil(link("a.t.me/#123"))
        XCTAssertNil(link("t.me/durov/123 extra"))
    }

    func testDeeplinks() {
        assertLink(link("tg://join?invite=AbCdEf123456"), url: "tg://join?invite=AbCdEf123456", resolvableUrl: nil, kind: .invite, isInferred: false)
        XCTAssertEqual(link("tg://resolve?domain=durov&post=12")?.kind, .message)
        XCTAssertEqual(link("tg://privatepost?channel=123&post=4")?.kind, .message)
        XCTAssertEqual(link("tg://resolve?domain=durov")?.kind, .generic)
        XCTAssertEqual(link("nagram://nasettings")?.kind, .generic)
        XCTAssertNil(link("tg://"))
        XCTAssertNil(link("other://resolve?domain=durov"))
    }

    func testInferredLinks() {
        assertLink(link("durov/123"), url: "https://t.me/durov/123", resolvableUrl: "https://t.me/durov/123", kind: .message, isInferred: true)
        XCTAssertEqual(link("@durov/123")?.url, "https://t.me/durov/123")
        XCTAssertEqual(link("durov/5/89")?.kind, .message)
        XCTAssertEqual(link("c/1234567/89")?.kind, .message)
        XCTAssertEqual(link("c/1234567/89?thread=5")?.kind, .message)
        XCTAssertEqual(link("+AbCdEf123456")?.kind, .invite)
        XCTAssertEqual(link("joinchat/AbCdEf123456")?.kind, .invite)
    }

    func testInferenceStaysOffOrdinaryQueries() {
        // 普通搜索词、手机号、bot 命令、日期和分数都不能被当成链接。
        XCTAssertNil(link("durov"))
        XCTAssertNil(link("@durov"))
        XCTAssertNil(link("+8613800138000"))
        XCTAssertNil(link("+12345678"))
        XCTAssertNil(link("/start"))
        XCTAssertNil(link("/durov/123"))
        XCTAssertNil(link("1/2"))
        XCTAssertNil(link("2026/10/17"))
        XCTAssertNil(link("abc/123"))
        XCTAssertNil(link("durov/abc"))
        XCTAssertNil(link("durov/123/4/5"))
        XCTAssertNil(link("c/123"))
        XCTAssertNil(link("joinchat/123"))
        XCTAssertNil(link("share/123"))
        XCTAssertNil(link("+short"))
    }
}
