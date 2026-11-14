import Foundation
import Postbox

public struct NagramMessageEditVersion: Equatable {
    public let text: String
    public let timestamp: Int32
    public let attributes: [MessageAttribute]
    public let media: [Media]
    public let imageData: Data?
    public static let maximumImageBytes = 8 * 1024 * 1024

    public init(text: String, timestamp: Int32, attributes: [MessageAttribute] = [], media: [Media] = [], imageData: Data? = nil) {
        self.text = text
        self.timestamp = timestamp
        self.attributes = attributes
        self.media = media
        self.imageData = imageData.flatMap { $0.count <= Self.maximumImageBytes ? $0 : nil }
    }

    public func contentMatches(text: String, attributes: [MessageAttribute], media: [Media]) -> Bool {
        return self.text == text
            && self.attributes.map(Self.encodedAttribute) == attributes.map(Self.encodedAttribute)
            && self.media.count == media.count
            && zip(self.media, media).allSatisfy { $0.0.isSemanticallyEqual(to: $0.1) }
    }

    private static func encodedAttribute(_ attribute: MessageAttribute) -> Data {
        let encoder = PostboxEncoder()
        encoder.encodeRootObject(attribute)
        return encoder.makeData()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.timestamp == rhs.timestamp && lhs.imageData == rhs.imageData && lhs.contentMatches(text: rhs.text, attributes: rhs.attributes, media: rhs.media)
    }
}

/// Message-local history so it follows Postbox lifecycle and account isolation.
public final class NagramMessageHistoryAttribute: MessageAttribute {
    public static let maximumVersionCount = 50
    public static let maximumImageHistoryBytes = 32 * 1024 * 1024

    private static func boundedVersions(_ versions: [NagramMessageEditVersion]) -> [NagramMessageEditVersion] {
        var result = versions
        if versions.count > self.maximumVersionCount, let original = versions.first { result = [original] + versions.suffix(self.maximumVersionCount - 1) }
        var bytes = result.reduce(0) { $0 + ($1.imageData?.count ?? 0) }
        for index in result.indices.dropFirst() where bytes > self.maximumImageHistoryBytes {
            let old = result[index]
            bytes -= old.imageData?.count ?? 0
            result[index] = NagramMessageEditVersion(text: old.text, timestamp: old.timestamp, attributes: old.attributes, media: old.media)
        }
        return result
    }

    public let versions: [NagramMessageEditVersion]

    public var associatedPeerIds: [PeerId] {
        return Array(Set(self.versions.flatMap { $0.attributes.flatMap { $0.associatedPeerIds } + $0.media.flatMap { $0.peerIds } }))
    }

    public var associatedMediaIds: [MediaId] {
        return Array(Set(self.versions.flatMap {
            $0.attributes.flatMap { $0.associatedMediaIds } + $0.media.flatMap { media in
                media.mediaIds + (media.id.map { [$0] } ?? [])
            }
        }))
    }

    public init(versions: [NagramMessageEditVersion]) {
        self.versions = Self.boundedVersions(versions)
    }

    public convenience init(appending version: NagramMessageEditVersion, to attribute: NagramMessageHistoryAttribute?) {
        var versions = attribute?.versions ?? []
        if versions.last != version {
            versions.append(version)
        }
        self.init(versions: versions)
    }

    public required init(decoder: PostboxDecoder) {
        if decoder.decodeInt32ForKey("v", orElse: 0) == 2 {
            let versions = try? decoder.decodeObjectArrayWithCustomDecoderForKey("h", decoder: { decoder -> NagramMessageEditVersion in
                let attributes: [PostboxCoding] = decoder.decodeObjectArrayForKey("a")
                let media: [PostboxCoding] = decoder.decodeObjectArrayForKey("m")
                return NagramMessageEditVersion(
                    text: decoder.decodeStringForKey("t", orElse: ""),
                    timestamp: decoder.decodeInt32ForKey("d", orElse: 0),
                    attributes: attributes.compactMap { $0 as? MessageAttribute },
                    media: media.compactMap { $0 as? Media },
                    imageData: decoder.decodeDataForKey("ib")
                )
            })
            self.versions = Self.boundedVersions(versions ?? [])
            return
        }
        let texts = decoder.decodeStringArrayForKey("t")
        let timestamps = decoder.decodeInt32ArrayForKey("d")
        var versions: [NagramMessageEditVersion] = []
        for index in 0 ..< min(texts.count, timestamps.count) {
            versions.append(NagramMessageEditVersion(text: texts[index], timestamp: timestamps[index]))
        }
        self.versions = Self.boundedVersions(versions)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(2, forKey: "v")
        encoder.encodeObjectArrayWithEncoder(self.versions, forKey: "h", encoder: { version, encoder in
            encoder.encodeString(version.text, forKey: "t")
            encoder.encodeInt32(version.timestamp, forKey: "d")
            encoder.encodeGenericObjectArray(version.attributes.map { $0 as PostboxCoding }, forKey: "a")
            encoder.encodeGenericObjectArray(version.media.map { $0 as PostboxCoding }, forKey: "m")
            if let data = version.imageData { encoder.encodeData(data, forKey: "ib") }
        })
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

/// API refreshes omit local attributes. Explicit updates win over the stored copy.
public func nagramPreservingMessageHistory(previous: [MessageAttribute], updated: [MessageAttribute]) -> [MessageAttribute] {
    var result = updated
    if !result.contains(where: { $0 is NagramMessageHistoryAttribute }),
       let history = previous.first(where: { $0 is NagramMessageHistoryAttribute }) {
        result.append(history)
    }
    if !result.contains(where: { $0 is NagramDeletedMessageAttribute }),
       let deletion = previous.first(where: { $0 is NagramDeletedMessageAttribute }) {
        result.append(deletion)
    }
    return result
}
