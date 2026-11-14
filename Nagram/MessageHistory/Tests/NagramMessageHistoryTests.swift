import Foundation
import NagramMessageHistory
import Postbox
import XCTest

private final class HistoryTestFormatting: MessageAttribute {
    let value: Int32

    init(_ value: Int32) {
        self.value = value
    }

    init(decoder: PostboxDecoder) {
        self.value = decoder.decodeInt32ForKey("v", orElse: 0)
    }

    func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.value, forKey: "v")
    }
}

private final class HistoryTestMedia: Media {
    let value: Int64
    var id: MediaId? { MediaId(namespace: 0, id: self.value) }
    var peerIds: [PeerId] { [] }

    init(_ value: Int64) {
        self.value = value
    }

    init(decoder: PostboxDecoder) {
        self.value = decoder.decodeInt64ForKey("v", orElse: 0)
    }

    func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt64(self.value, forKey: "v")
    }

    func isEqual(to other: Media) -> Bool {
        return (other as? HistoryTestMedia)?.value == self.value
    }

    func isSemanticallyEqual(to other: Media) -> Bool {
        return self.isEqual(to: other)
    }
}

final class NagramMessageHistoryTests: XCTestCase {
    func testLegacyTextHistoryDecodes() {
        let encoder = PostboxEncoder()
        encoder.encodeStringArray(["first", "second"], forKey: "t")
        encoder.encodeInt32Array([100, 200], forKey: "d")
        let decoded = NagramMessageHistoryAttribute(decoder: PostboxDecoder(buffer: MemoryBuffer(data: encoder.makeData())))
        XCTAssertEqual(decoded.versions, [
            NagramMessageEditVersion(text: "first", timestamp: 100),
            NagramMessageEditVersion(text: "second", timestamp: 200)
        ])
    }

    func testFormattingAndMediaRoundTrip() {
        declareEncodable(HistoryTestFormatting.self, f: { HistoryTestFormatting(decoder: $0) })
        declareEncodable(HistoryTestMedia.self, f: { HistoryTestMedia(decoder: $0) })
        let version = NagramMessageEditVersion(text: "same text", timestamp: 100,
            attributes: [HistoryTestFormatting(1)], media: [HistoryTestMedia(42)])
        let history = NagramMessageHistoryAttribute(versions: [version])
        let encoder = PostboxEncoder()
        history.encode(encoder)
        let decoded = NagramMessageHistoryAttribute(decoder: PostboxDecoder(buffer: MemoryBuffer(data: encoder.makeData())))
        XCTAssertEqual(decoded.versions, [version])
        XCTAssertEqual((decoded.versions.first?.media.first as? HistoryTestMedia)?.value, 42)
    }

    func testContentComparisonIgnoresTimestampButDetectsFormattingAndMedia() {
        let version = NagramMessageEditVersion(text: "same", timestamp: 100,
            attributes: [HistoryTestFormatting(1)], media: [HistoryTestMedia(42)])
        XCTAssertTrue(version.contentMatches(text: "same", attributes: [HistoryTestFormatting(1)], media: [HistoryTestMedia(42)]))
        XCTAssertFalse(version.contentMatches(text: "same", attributes: [HistoryTestFormatting(2)], media: [HistoryTestMedia(42)]))
        XCTAssertFalse(version.contentMatches(text: "same", attributes: [HistoryTestFormatting(1)], media: [HistoryTestMedia(43)]))
        XCTAssertFalse(version.contentMatches(text: "same", attributes: [HistoryTestFormatting(1)], media: []))
    }

    func testHistoryPreservesOriginalAndNewestVersionsWithoutRepeatingLastVersion() {
        let versions = (0 ..< 60).map { NagramMessageEditVersion(text: "\($0)", timestamp: Int32($0)) }
        let history = NagramMessageHistoryAttribute(versions: versions)
        XCTAssertEqual(history.versions.count, 50)
        XCTAssertEqual(history.versions.first?.text, "0")
        XCTAssertEqual(history.versions[1].text, "11")
        let appended = NagramMessageHistoryAttribute(appending: versions[59], to: history)
        XCTAssertEqual(appended.versions, history.versions)
    }

    func testHistoricalMediaIdIsRetained() {
        let history = NagramMessageHistoryAttribute(versions: [NagramMessageEditVersion(text: "", timestamp: 1, media: [HistoryTestMedia(42)])])
        XCTAssertTrue(history.associatedMediaIds.contains(MediaId(namespace: 0, id: 42)))
    }

    func testImageBudgetPreservesOriginalAndRecentPreviews() {
        let bytes = Data(repeating: 1, count: NagramMessageEditVersion.maximumImageBytes)
        let versions = (0 ..< 6).map { NagramMessageEditVersion(text: "\($0)", timestamp: Int32($0), imageData: bytes) }
        let history = NagramMessageHistoryAttribute(versions: versions)
        XCTAssertNotNil(history.versions[0].imageData)
        XCTAssertNil(history.versions[1].imageData)
        XCTAssertNil(history.versions[2].imageData)
        XCTAssertNotNil(history.versions[5].imageData)
        XCTAssertEqual(history.versions.reduce(0) { $0 + ($1.imageData?.count ?? 0) }, NagramMessageHistoryAttribute.maximumImageHistoryBytes)
        let encoder = PostboxEncoder()
        history.encode(encoder)
        let decoded = NagramMessageHistoryAttribute(decoder: PostboxDecoder(buffer: MemoryBuffer(data: encoder.makeData())))
        XCTAssertEqual(decoded.versions, history.versions)
    }

    func testServerRefreshPreservesLocalAttributesWithoutReplacingExplicitUpdates() {
        let old = NagramMessageHistoryAttribute(versions: [NagramMessageEditVersion(text: "before", timestamp: 100)])
        let deletion = NagramDeletedMessageAttribute(timestamp: 200, preservedBotMessage: false)
        let refreshed = nagramPreservingMessageHistory(previous: [old, deletion], updated: [HistoryTestFormatting(1)])
        XCTAssertEqual(refreshed.count, 3)
        XCTAssertTrue(refreshed.contains(where: { $0 === old }))
        XCTAssertTrue(refreshed.contains(where: { $0 === deletion }))

        let new = NagramMessageHistoryAttribute(appending: NagramMessageEditVersion(text: "after", timestamp: 300), to: old)
        let edited = nagramPreservingMessageHistory(previous: [old, deletion], updated: [new])
        XCTAssertEqual(edited.count, 2)
        XCTAssertTrue(edited.contains(where: { $0 === new }))
        XCTAssertFalse(edited.contains(where: { $0 === old }))
    }
}
