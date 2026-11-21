public enum NagramMusicPlayerCoverLayout: String, CaseIterable {
    case card
    case fullscreen
    case disc
}

public enum NagramMusicPlayerBackground: String, CaseIterable {
    case blur, solid, artwork, gradient
}

public enum NagramMusicPlayerFullscreenBlurHeight: String, CaseIterable {
    case short, controls, custom
}

public enum NagramMusicPlayerColors: String, CaseIterable {
    case cover, theme, custom
}

public enum NextgramSystemMusicDisplay: String {
    case always, background, never

    public func isVisible(inForeground: Bool) -> Bool {
        return self != .never && (self != .background || !inForeground)
    }
}

public enum NextgramLyricsSource: String, CaseIterable {
    case qqMusic, netease, amll, lrclib

    public static let defaultOrder = NextgramLyricsSource.allCases.map(\.rawValue).joined(separator: ",")

    public static func ordered(_ value: String) -> [Self] {
        var seen = Set<Self>()
        let preferred = value.split(separator: ",").compactMap { Self(rawValue: String($0)) }
        return (preferred + Self.allCases).filter { seen.insert($0).inserted }
    }
}

/// Independent effects; leaving them off preserves the existing lyric presentation.
public struct NagramLyricsEffects: Equatable {
    public let wordHighlight: Bool
    public let wordFloat: Bool
    public let springScroll: Bool
    public let glow: Bool
    public let blur: Bool
    public let scale: Bool
    public let linearScroll: Bool
    public let stagger: Bool
    public let interlude: Bool
    public let edgeFade: Bool

    public static let none = NagramLyricsEffects(enabled: false)
    public static let allEnabled = NagramLyricsEffects(enabled: true)

    private init(enabled: Bool) {
        self.wordHighlight = enabled
        self.wordFloat = enabled
        self.springScroll = enabled
        self.glow = enabled
        self.blur = enabled
        self.scale = enabled
        self.linearScroll = false
        self.stagger = enabled
        self.interlude = enabled
        self.edgeFade = enabled
    }

    public init(settings: NagramSettings) {
        self.wordHighlight = settings.musicPlayerLyricsWordHighlight
        self.wordFloat = settings.musicPlayerLyricsWordFloat
        self.springScroll = settings.musicPlayerLyricsSpringScroll
        self.glow = settings.musicPlayerLyricsGlow
        self.blur = settings.musicPlayerLyricsBlur
        self.scale = settings.musicPlayerLyricsScale
        self.linearScroll = settings.musicPlayerLyricsLinearScroll
        self.stagger = settings.musicPlayerLyricsStagger
        self.interlude = settings.musicPlayerLyricsInterlude
        self.edgeFade = settings.musicPlayerLyricsEdgeFade
    }
}

public struct NagramMusicPlayerSettings: Equatable {
    public let enabled: Bool
    public let coverLayout: NagramMusicPlayerCoverLayout
    public let coverSize: Int32
    public let coverCornerRadius: Int32
    public let lyricsEnabled: Bool
    public let onlineLyricsEnabled: Bool
    public let lyricsSources: [NextgramLyricsSource]
    public let showVolume: Bool
    public let showRemainingTime: Bool
    public let lyricsEffects: NagramLyricsEffects
    public let lyricsFontSize: Int32
    public let blurIntensity: Int32
    public let fullscreenBlurHeight: NagramMusicPlayerFullscreenBlurHeight
    public let fullscreenBlurPercent: Int32
    public let smartArtworkCrop: Bool
    public let background: NagramMusicPlayerBackground
    public let colors: NagramMusicPlayerColors
    public let customColor: String
    public let titleAlignment: String
    public let titleFontSize: Int32
    public let controlScale: Int32
    public let discRotation: Bool
    public let swipeToSkip: Bool
    public let artworkMotion: Bool
    public let artworkMetadata: Bool

    public init(settings: NagramSettings = .shared) {
        self.enabled = settings.musicPlayerModernUI
        self.coverLayout = settings.musicPlayerCoverLayoutValue
        self.coverSize = settings.musicPlayerCoverSizeValue
        self.coverCornerRadius = settings.musicPlayerCoverCornerRadiusValue
        self.lyricsEnabled = settings.musicPlayerLyricsEnabled
        self.onlineLyricsEnabled = settings.musicPlayerOnlineLyricsEnabled
        self.lyricsSources = NextgramLyricsSource.ordered(settings.musicPlayerLyricsSourceOrder)
        self.showVolume = settings.musicPlayerShowVolume
        self.showRemainingTime = settings.musicPlayerShowRemainingTime
        self.lyricsEffects = NagramLyricsEffects(settings: settings)
        self.lyricsFontSize = settings.musicPlayerLyricsFontSizeValue
        self.blurIntensity = settings.musicPlayerBlurIntensityValue
        self.fullscreenBlurHeight = settings.musicPlayerFullscreenBlurHeightValue
        self.fullscreenBlurPercent = settings.musicPlayerFullscreenBlurPercentValue
        self.smartArtworkCrop = settings.musicPlayerSmartArtworkCrop
        self.background = settings.musicPlayerBackgroundValue
        self.colors = settings.musicPlayerColorsValue
        self.customColor = settings.musicPlayerCustomColor
        self.titleAlignment = settings.musicPlayerTitleAlignmentValue
        self.titleFontSize = settings.musicPlayerTitleFontSizeValue
        self.controlScale = settings.musicPlayerControlScaleValue
        self.discRotation = settings.musicPlayerDiscRotation
        self.swipeToSkip = settings.musicPlayerSwipeToSkip
        self.artworkMotion = settings.musicPlayerArtworkMotion
        self.artworkMetadata = settings.musicPlayerArtworkMetadata
    }
}

public extension NagramSettings {
    var musicPlayerBackgroundValue: NagramMusicPlayerBackground {
        NagramMusicPlayerBackground(rawValue: self.musicPlayerBackground) ?? .blur
    }

    var musicPlayerColorsValue: NagramMusicPlayerColors {
        NagramMusicPlayerColors(rawValue: self.musicPlayerColors) ?? .cover
    }
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

    var musicPlayerFullscreenBlurHeightValue: NagramMusicPlayerFullscreenBlurHeight {
        NagramMusicPlayerFullscreenBlurHeight(rawValue: self.musicPlayerFullscreenBlurHeight) ?? .short
    }

    var musicPlayerFullscreenBlurPercentValue: Int32 {
        min(50, max(10, self.musicPlayerFullscreenBlurPercent))
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
