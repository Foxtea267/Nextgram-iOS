import Foundation

public enum NextgramPeerGhostMode {
    private static func key(accountPeerId: Int64, peerId: Int64) -> String {
        return "nextgram.peerGhostMode.\(accountPeerId).\(peerId)"
    }

    public static func isEnabled(accountPeerId: Int64, peerId: Int64) -> Bool {
        return NagramDemoMode.userDefaults.bool(forKey: self.key(accountPeerId: accountPeerId, peerId: peerId))
    }

    public static func setEnabled(_ enabled: Bool, accountPeerId: Int64, peerId: Int64) {
        let key = self.key(accountPeerId: accountPeerId, peerId: peerId)
        if enabled {
            NagramDemoMode.userDefaults.set(true, forKey: key)
        } else {
            NagramDemoMode.userDefaults.removeObject(forKey: key)
        }
    }
}
