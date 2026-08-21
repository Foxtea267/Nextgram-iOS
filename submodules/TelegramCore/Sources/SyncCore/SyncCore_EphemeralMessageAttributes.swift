import Foundation
import Postbox

public final class EphemeralMessageAttribute: MessageAttribute {
    public let receiverId: Int64

    public var associatedPeerIds: [PeerId] {
        if self.receiverId == 0 {
            return []
        }
        return [PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(self.receiverId))]
    }

    public init(receiverId: Int64) {
        self.receiverId = receiverId
    }

    required public init(decoder: PostboxDecoder) {
        self.receiverId = decoder.decodeInt64ForKey("r", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt64(self.receiverId, forKey: "r")
    }
}

public final class EphemeralOutgoingMessageAttribute: MessageAttribute {
    public enum State: Int32 {
        case sending = 0
        case failed = 1
    }

    public let botPeerId: PeerId
    public let randomId: Int64
    public let state: State

    public var associatedPeerIds: [PeerId] {
        return [self.botPeerId]
    }

    public init(botPeerId: PeerId, randomId: Int64, state: State) {
        self.botPeerId = botPeerId
        self.randomId = randomId
        self.state = state
    }

    required public init(decoder: PostboxDecoder) {
        self.botPeerId = PeerId(decoder.decodeInt64ForKey("b", orElse: 0))
        self.randomId = decoder.decodeInt64ForKey("r", orElse: 0)
        self.state = State(rawValue: decoder.decodeInt32ForKey("s", orElse: State.sending.rawValue)) ?? .sending
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt64(self.botPeerId.toInt64(), forKey: "b")
        encoder.encodeInt64(self.randomId, forKey: "r")
        encoder.encodeInt32(self.state.rawValue, forKey: "s")
    }

    public func withUpdatedState(_ state: State) -> EphemeralOutgoingMessageAttribute {
        return EphemeralOutgoingMessageAttribute(botPeerId: self.botPeerId, randomId: self.randomId, state: state)
    }
}
