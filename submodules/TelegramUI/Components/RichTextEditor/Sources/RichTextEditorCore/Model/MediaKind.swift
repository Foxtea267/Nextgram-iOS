import Foundation

/// What an attached `MediaBlock` is — drives the converter's `.image` vs `.video` vs `.audio` InstantPage
/// block and lets a demo/host label its placeholder. The editor renders image/video identically (a hosted
/// view sized from `naturalSize`); `.audio` is a fixed-height row and `.location` a map snapshot — only
/// serialization, layout height, and the host's hosted view care about the distinction.
public enum MediaKind: String, Codable, Equatable, CaseIterable {
    case image
    case video
    case location
    case audio
}
