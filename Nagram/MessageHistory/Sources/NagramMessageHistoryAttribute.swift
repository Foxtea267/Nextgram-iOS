import Foundation
import Postbox

public struct NagramMessageEditVersion: Equatable {
    public let text: String
    public let timestamp: Int32

    public init(text: String, timestamp: Int32) {
        self.text = text
        self.timestamp = timestamp
    }
}

/// Message-local history so it follows Postbox lifecycle and account isolation.
public final class NagramMessageHistoryAttribute: MessageAttribute {
    public static let maximumVersionCount = 20

    public let versions: [NagramMessageEditVersion]

    public init(versions: [NagramMessageEditVersion]) {
        self.versions = Array(versions.suffix(Self.maximumVersionCount))
    }

    public convenience init(appending version: NagramMessageEditVersion, to attribute: NagramMessageHistoryAttribute?) {
        var versions = attribute?.versions ?? []
        if versions.last != version {
            versions.append(version)
        }
        self.init(versions: versions)
    }

    public required init(decoder: PostboxDecoder) {
        let texts = decoder.decodeStringArrayForKey("t")
        let timestamps = decoder.decodeInt32ArrayForKey("d")
        var versions: [NagramMessageEditVersion] = []
        for index in 0 ..< min(texts.count, timestamps.count) {
            versions.append(NagramMessageEditVersion(text: texts[index], timestamp: timestamps[index]))
        }
        self.versions = Array(versions.suffix(Self.maximumVersionCount))
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeStringArray(self.versions.map(\.text), forKey: "t")
        encoder.encodeInt32Array(self.versions.map(\.timestamp), forKey: "d")
    }
}

/// Marks a message retained after a remote deletion update.
public final class NagramDeletedMessageAttribute: MessageAttribute {
    public let timestamp: Int32
    public let preservedBotMessage: Bool

    public init(timestamp: Int32, preservedBotMessage: Bool) {
        self.timestamp = timestamp
        self.preservedBotMessage = preservedBotMessage
    }

    public required init(decoder: PostboxDecoder) {
        self.timestamp = decoder.decodeInt32ForKey("d", orElse: 0)
        self.preservedBotMessage = decoder.decodeInt32ForKey("b", orElse: 0) != 0
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.timestamp, forKey: "d")
        encoder.encodeInt32(self.preservedBotMessage ? 1 : 0, forKey: "b")
    }
}
