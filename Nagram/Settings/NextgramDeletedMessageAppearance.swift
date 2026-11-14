import Foundation

public struct NextgramDeletedMessageAppearance: Equatable {
    public let opacity: Double
    public let overlayOpacity: Double
    public let overlayRGB: UInt32
    public let includesAvatar: Bool

    public init(settings: NagramSettings = .shared) {
        self.opacity = settings.deletedMessageSemiTransparent ? Double(min(100, max(20, settings.deletedMessageOpacity))) / 100.0 : 1.0
        self.overlayOpacity = settings.deletedMessageOverlayEnabled ? Double(min(65, max(0, settings.deletedMessageOverlayOpacity))) / 100.0 : 0.0
        self.overlayRGB = Self.parseColor(settings.deletedMessageOverlayColor) ?? 0x000000
        self.includesAvatar = settings.deletedMessageDimAvatar && (self.opacity < 1.0 || self.overlayOpacity > 0.0)
    }

    public static func parseColor(_ value: String) -> UInt32? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard hex.utf8.count == 6, hex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
        return UInt32(hex, radix: 16)
    }
}
