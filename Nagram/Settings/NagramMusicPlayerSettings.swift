public enum NagramMusicPlayerCoverLayout: String, CaseIterable {
    case card
    case wide
    case fullscreen
    case disc
    case fit
    case fill
}

public struct NagramMusicPlayerSettings: Equatable {
    public let enabled: Bool
    public let coverLayout: NagramMusicPlayerCoverLayout
    public let coverSize: Int32
    public let coverCornerRadius: Int32
    public let lyricsEnabled: Bool
    public let onlineLyricsEnabled: Bool
    public let showVolume: Bool
    public let showRemainingTime: Bool
    public let lyricsFontSize: Int32
    public let blurIntensity: Int32
    public let titleAlignment: String
    public let titleFontSize: Int32
    public let controlScale: Int32
    public let discRotation: Bool
    public let swipeToSkip: Bool

    public init(settings: NagramSettings = .shared) {
        self.enabled = settings.musicPlayerModernUI
        self.coverLayout = settings.musicPlayerCoverLayoutValue
        self.coverSize = settings.musicPlayerCoverSizeValue
        self.coverCornerRadius = settings.musicPlayerCoverCornerRadiusValue
        self.lyricsEnabled = settings.musicPlayerLyricsEnabled
        self.onlineLyricsEnabled = settings.musicPlayerOnlineLyricsEnabled
        self.showVolume = settings.musicPlayerShowVolume
        self.showRemainingTime = settings.musicPlayerShowRemainingTime
        self.lyricsFontSize = settings.musicPlayerLyricsFontSizeValue
        self.blurIntensity = settings.musicPlayerBlurIntensityValue
        self.titleAlignment = settings.musicPlayerTitleAlignmentValue
        self.titleFontSize = settings.musicPlayerTitleFontSizeValue
        self.controlScale = settings.musicPlayerControlScaleValue
        self.discRotation = settings.musicPlayerDiscRotation
        self.swipeToSkip = settings.musicPlayerSwipeToSkip
    }
}

public extension NagramSettings {
    var musicPlayerCoverLayoutValue: NagramMusicPlayerCoverLayout {
        return NagramMusicPlayerCoverLayout(rawValue: self.musicPlayerCoverLayout) ?? .card
    }

    var musicPlayerCoverSizeValue: Int32 {
        return min(100, max(60, self.musicPlayerCoverSize))
    }

    var musicPlayerCoverCornerRadiusValue: Int32 {
        return min(48, max(0, self.musicPlayerCoverCornerRadius))
    }

    var musicPlayerLyricsFontSizeValue: Int32 {
        return min(40, max(20, self.musicPlayerLyricsFontSize))
    }

    var musicPlayerBlurIntensityValue: Int32 {
        return min(60, max(0, self.musicPlayerBlurIntensity))
    }

    var musicPlayerTitleAlignmentValue: String {
        return self.musicPlayerTitleAlignment == "center" ? "center" : "left"
    }

    var musicPlayerTitleFontSizeValue: Int32 {
        return min(32, max(20, self.musicPlayerTitleFontSize))
    }

    var musicPlayerControlScaleValue: Int32 {
        return min(120, max(80, self.musicPlayerControlScale))
    }
}
