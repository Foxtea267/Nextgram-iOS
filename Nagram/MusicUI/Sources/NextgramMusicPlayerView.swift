import AccountContext
import AVKit
import Display
import EdgeEffect
import Foundation
import LegacyMediaPickerUI
import MediaPlayer
import NagramSettings
import NagramSettingsSignal
import NagramStrings
import NextgramImageSuperResolution
import NextgramLyrics
import PhotoResources
import PresentationDataUtils
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import UIKit
import UniversalMediaPlayer

private final class NextgramPlayerDisplayLinkTarget: NSObject {
    weak var player: NextgramMusicPlayerView?

    @objc func tick() {
        self.player?.updatePosition()
    }
}

/// A presentation of the existing Telegram music session, never a separate audio player.
public final class NextgramMusicPlayerView: UIView, UIGestureRecognizerDelegate {
    public var dismiss: (() -> Void)?
    public var showQueue: (() -> Void)?
    public var openSettings: (() -> Void)?
    public var presentController: ((ViewController) -> Void)?
    public var toggleSavedMusic: (() -> Void)?
    public var updateStatusBarStyle: ((StatusBarStyle) -> Void)? {
        didSet { self.updateStatusBarStyle?(self.playerStatusBarStyle) }
    }
    public var isSavedMusic: Bool? { didSet { self.updateFavorite() } }

    private let context: AccountContext?
    private var settings = NagramMusicPlayerSettings()
    private var presentationData: PresentationData
    private var settingsDisposable: Disposable?
    private var systemDisplayDisposable: Disposable?
    private var playbackDisposable: Disposable?
    private var presentationDisposable: Disposable?
    private var state: SharedMediaPlayerItemPlaybackState?
    private var file: FileMediaReference?
    private var trackId: AnyHashable?
    private var trackTitle = ""
    private var trackArtist = ""
    private var albumArt: SharedMediaPlaybackAlbumArt?
    private var safeInsets = UIEdgeInsets()
    private var active = false
    private var foreground = true
    private var showingLyrics = false
    private var scrubbing = false
    private var transitioningLyrics = false
    private var lyricsTransitionGeneration = 0
    private var lastPlaying: Bool?
    private final class CoverDrag {
        let overlay = UIView()
        let neighbor = UIImageView()
        let surface: UIView
        let trackId: AnyHashable?
        var direction: CGFloat = 0.0
        var neighborId: AnyHashable?
        var artworkDisposable: Disposable?
        var committed = false
        var settled = false

        init(surface: UIView, trackId: AnyHashable?) {
            self.surface = surface
            self.trackId = trackId
        }

        deinit {
            self.artworkDisposable?.dispose()
        }
    }
    private var coverDrag: CoverDrag?
#if DEBUG && targetEnvironment(simulator)
    private var previewPlaying: Bool?
    private var previewLyricsEffects: NagramLyricsEffects?
    private var previewSampleLyrics: NextgramLyrics?
    private var previewOnlineLyrics = false
    private var previewDuration = 200.0
    private var previewClockStart: Double?
    private var previewClockPosition = 70.0
    private var previewAnimatedLyrics = false
    private var previewArtworkMotion: Bool?
    private var previewArtworkMetadata: Bool?
#endif

    private let backgroundArtworkContainer = UIView()
    private let backgroundArtwork = UIImageView()
    private var artworkFocusImage: UIImage?
    private var artworkFocus: CGPoint?
    private var artworkFocusTask: DispatchWorkItem?
    private var originalArtwork: UIImage?
    private var telegramArtwork: UIImage?
    private var onlineArtwork: UIImage?
    private var onlineArtworkTask: Task<Void, Never>?
    private var enhancedArtwork: UIImage?
    private var artworkEnhancementTask: DispatchWorkItem?
    private let shade = UIView()
    private let gradientBackground = CAGradientLayer()
    private let fullscreenShade = CAGradientLayer()
    private let fullscreenBlurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
    private var blur: VariableBlurView?
    private var fullscreenBottomBlur: UIVisualEffectView?
    private var artworkDisposable: Disposable?
    private var artworkColor = NextgramPlayerPalette.fallback
    private var foregroundColor = UIColor.white
    private var playerStatusBarStyle: StatusBarStyle = .White
    private let artwork = NextgramInteractiveArtwork(frame: .zero)
    private let artworkShadow = UIView()
    private var artworkDetail: NextgramArtworkDetailView?
    private var detailArtworkDisposable: Disposable?
    private let discHole = UIView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let grabber = UIView()
    private let elapsedLabel = UILabel()
    private let remainingLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let menuButton = UIButton(type: .system)
    private let favoriteButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let lyricsButton = UIButton(type: .custom)
    private let queueButton = UIButton(type: .system)
    private let positionSlider = NextgramPlayerSlider()
    private let volumeView = NextgramPlayerVolumeView()
    private let volumeLow = UIImageView()
    private let volumeHigh = UIImageView()
    private let routePicker = NextgramPlayerRoutePickerView()
    private let routeLabel = UILabel()
    private let repeatIndicator = UIImageView()
    private let dismissalPan = UIPanGestureRecognizer()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let lyricsView = NextgramLyricsView()
    private var lyrics: NextgramLyrics?
    private var lyricsPlaceholder = ""
    private var lyricsRequest = UUID()
    private var onlineTask: Task<Void, Never>?
    private var lyricsSourceOverride: NextgramLyricsSource?
    private var activeLyricsSource: NextgramLyricsSource?
    private var localLyricsOrigin: String?
    private struct LyricsAttempt {
        let source: NextgramLyricsSource
        let elapsed: Double
        let result: NextgramLyricsLookupResult
        let events: [NextgramLyricsLookupEvent]
    }
    private var lyricsAttempts: [LyricsAttempt] = []
    private var reusedPlayerLyrics = false
    private weak var lyricsDiagnostics: NextgramLyricsDiagnosticsController?
    private struct CachedLyrics {
        let lyrics: NextgramLyrics
        let source: NextgramLyricsSource?
        let localOrigin: String?
        let attempts: [LyricsAttempt]
    }
    private var lyricsMemory: [AnyHashable: [String: CachedLyrics]] = [:]
    private var lyricsSelections: [AnyHashable: NextgramLyricsSource] = [:]
    private var lyricsChoiceKey: String {
        self.lyricsSourceOverride?.rawValue ?? self.settings.lyricsSources.map(\.rawValue).joined(separator: ",")
    }
    private func rememberLyrics() {
        guard let id = self.trackId, let lyrics = self.lyrics else { return }
        if self.lyricsMemory.count >= 48, self.lyricsMemory[id] == nil, let oldest = self.lyricsMemory.keys.first {
            self.lyricsMemory.removeValue(forKey: oldest)
            self.lyricsSelections.removeValue(forKey: oldest)
        }
        self.lyricsMemory[id, default: [:]][self.lyricsChoiceKey] = CachedLyrics(lyrics: lyrics, source: self.activeLyricsSource,
            localOrigin: self.localLyricsOrigin, attempts: self.lyricsAttempts)
    }
    private let embeddedLoader = NextgramEmbeddedLyricsLoader()
    private var embeddedLyricsFound = false
    private let displayLinkTarget = NextgramPlayerDisplayLinkTarget()
    private var displayLink: CADisplayLink?

    public convenience init(context: AccountContext) {
        self.init(context: context, presentationData: context.sharedContext.currentPresentationData.with { $0 })
    }

    private init(context: AccountContext?, presentationData: PresentationData) {
        self.context = context
        self.presentationData = presentationData
        super.init(frame: .zero)

        self.dismissalPan.addTarget(self, action: #selector(self.dismissalPanned(_:)))
        self.dismissalPan.delegate = self
        self.dismissalPan.maximumNumberOfTouches = 1
        self.addGestureRecognizer(self.dismissalPan)

        self.clipsToBounds = true
        self.backgroundColor = UIColor(white: 0.09, alpha: 1.0)
        self.overrideUserInterfaceStyle = .dark
        self.backgroundArtwork.contentMode = .scaleAspectFill
        self.backgroundArtwork.clipsToBounds = true
        self.backgroundArtworkContainer.clipsToBounds = true
        self.backgroundArtworkContainer.isUserInteractionEnabled = false
        self.backgroundArtworkContainer.addSubview(self.backgroundArtwork)
        self.addSubview(self.backgroundArtworkContainer)
        self.gradientBackground.startPoint = CGPoint(x: 0.5, y: 0.0)
        self.gradientBackground.endPoint = CGPoint(x: 0.5, y: 0.7)
        self.layer.addSublayer(self.gradientBackground)
        self.shade.layer.addSublayer(self.fullscreenShade)
        self.shade.isUserInteractionEnabled = false
        self.addSubview(self.shade)
        self.artwork.contentMode = .scaleAspectFill
        self.artwork.clipsToBounds = true
        self.artwork.layer.cornerCurve = .continuous
        self.artwork.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
        self.artworkShadow.backgroundColor = .black
        self.artworkShadow.isUserInteractionEnabled = false
        self.artworkShadow.layer.shadowColor = UIColor.black.cgColor
        self.artworkShadow.layer.shadowOpacity = 0.24
        self.artworkShadow.layer.shadowRadius = 26.0
        self.artworkShadow.layer.shadowOffset = CGSize(width: 0.0, height: 14.0)
        self.artworkShadow.layer.cornerCurve = .continuous
        self.addSubview(self.artworkShadow)
        self.addSubview(self.artwork)
        self.discHole.backgroundColor = UIColor(white: 0.08, alpha: 0.9)
        self.discHole.layer.borderWidth = 4.0
        self.discHole.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        self.artwork.addSubview(self.discHole)
        self.artwork.isUserInteractionEnabled = true
        self.artwork.open = { [weak self] in self?.openArtworkDetail() }
        self.backgroundArtworkContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.openArtworkDetail)))
        for surface in [self.artwork, self.backgroundArtworkContainer] {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(self.artworkPanned(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            surface.addGestureRecognizer(pan)
        }

        self.titleLabel.font = .systemFont(ofSize: 25.0, weight: .bold)
        self.titleLabel.adjustsFontSizeToFitWidth = true
        self.titleLabel.minimumScaleFactor = 0.7
        self.artistLabel.font = .systemFont(ofSize: 19.0, weight: .medium)
        self.artistLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        self.grabber.layer.cornerRadius = 2.5
        self.grabber.isUserInteractionEnabled = false
        self.addSubview(self.grabber)
        for label in [self.titleLabel, self.artistLabel, self.elapsedLabel, self.remainingLabel] {
            self.addSubview(label)
        }
        self.titleLabel.textColor = .white
        for label in [self.elapsedLabel, self.remainingLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 12.0, weight: .medium)
            label.textColor = UIColor.white.withAlphaComponent(0.6)
        }
        self.remainingLabel.textAlignment = .right
        self.insertSubview(self.lyricsView, aboveSubview: self.shade)
        self.lyricsView.seek = { [weak self] time in self?.seek(time) }

        self.configure(self.closeButton, symbol: "chevron.down", size: 17.0, action: #selector(self.closePressed))
        self.configure(self.menuButton, symbol: "ellipsis", size: 18.0, action: nil)
        self.configure(self.favoriteButton, symbol: "star", size: 16.0, action: #selector(self.favoritePressed))
        self.menuButton.showsMenuAsPrimaryAction = true
        self.configure(self.playButton, symbol: "play.fill", size: 37.0, action: #selector(self.playPressed))
        self.configure(self.previousButton, symbol: "backward.end.fill", size: 28.0, action: #selector(self.previousPressed))
        self.configure(self.nextButton, symbol: "forward.end.fill", size: 28.0, action: #selector(self.nextPressed))
        self.configure(self.lyricsButton, symbol: "quote.bubble.fill", size: 23.0, action: #selector(self.lyricsPressed))
        self.configure(self.queueButton, symbol: "list.bullet", size: 18.0, action: #selector(self.queuePressed))
        self.positionSlider.editingStarted = { [weak self] in self?.scrubbing = true }
        self.positionSlider.valueChanged = { [weak self] in self?.updatePosition() }
        self.positionSlider.editingFinished = { [weak self] commit in
            guard let self else { return }
            self.scrubbing = false
            if commit {
                self.seek(Double(self.positionSlider.value) * self.playbackDuration)
            } else {
                self.updatePosition()
            }
        }
        self.addSubview(self.positionSlider)
        self.addSubview(self.volumeView)
        let volumeConfig = UIImage.SymbolConfiguration(pointSize: 13.0, weight: .semibold)
        self.volumeLow.image = UIImage(systemName: "speaker.fill", withConfiguration: volumeConfig)
        self.volumeHigh.image = UIImage(systemName: "speaker.wave.3.fill", withConfiguration: volumeConfig)
        for icon in [self.volumeLow, self.volumeHigh] {
            icon.contentMode = .center
            icon.isAccessibilityElement = false
            self.addSubview(icon)
        }
        self.routePicker.tintColor = UIColor.white.withAlphaComponent(0.75)
        self.addSubview(self.routePicker)
        self.routeLabel.font = .systemFont(ofSize: 13.0, weight: .semibold)
        self.routeLabel.textAlignment = .center
        self.routeLabel.lineBreakMode = .byTruncatingMiddle
        self.addSubview(self.routeLabel)
        self.repeatIndicator.contentMode = .center
        self.repeatIndicator.layer.cornerRadius = 10.0
        self.repeatIndicator.isUserInteractionEnabled = false
        self.repeatIndicator.isAccessibilityElement = false
        self.queueButton.addSubview(self.repeatIndicator)
        NotificationCenter.default.addObserver(self, selector: #selector(self.audioRouteChanged), name: AVAudioSession.routeChangeNotification, object: nil)
        self.audioRouteChanged()
        self.spinner.color = .white
        self.spinner.hidesWhenStopped = true
        self.addSubview(self.spinner)

        self.displayLinkTarget.player = self
        self.foreground = UIApplication.shared.applicationState == .active
        NotificationCenter.default.addObserver(self, selector: #selector(self.didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.accessibilityChanged), name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.accessibilityChanged), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)

        self.settingsDisposable = (nagramMusicPlayerSettingsSignal() |> deliverOnMainQueue).startStrict(next: { [weak self] settings in
            guard let self else { return }
            let reloadLyrics = settings.lyricsEnabled != self.settings.lyricsEnabled ||
                settings.onlineLyricsEnabled != self.settings.onlineLyricsEnabled ||
                (self.lyricsSourceOverride == nil && settings.lyricsSources != self.settings.lyricsSources)
            let reloadOnlineArtwork = settings.onlineArtwork != self.settings.onlineArtwork
            if settings.coverLayout != self.settings.coverLayout || !settings.swipeToSkip {
                self.finishCoverDrag()
            }
            self.settings = settings
            self.artworkDetail?.updateMetadataVisibility(settings.artworkMetadata)
            if !settings.lyricsEnabled { self.showingLyrics = false }
            self.updateAppearance()
            if reloadOnlineArtwork {
                self.refreshOnlineArtwork()
            }
            if reloadLyrics { self.reloadLyrics() }
            self.updateDisplayLink()
        })
        guard let context else {
            self.updateAppearance()
            return
        }
        self.systemDisplayDisposable = (nagramStringSignal("nagram.musicSystemNowPlaying", defaultValue: "always")
        |> deliverOnMainQueue).startStrict(next: { [weak self] _ in self?.updateMenu() })
        self.playbackDisposable = (context.sharedContext.mediaManager.musicMediaPlayerState |> deliverOnMainQueue).startStrict(next: { [weak self] value in
            guard let self else { return }
            if let (account, state, type) = value, account.id == context.account.id, type == .music, case let .state(state) = state {
                self.updateState(state)
            } else {
                // A loading emission does not identify a different song. Keep its metadata and lyrics.
                if let (account, playbackState, type) = value, account.id == context.account.id,
                   type == .music, case .loading = playbackState {
                    self.spinner.startAnimating()
                    return
                }
                self.state = nil
                self.scrubbing = false
                self.positionSlider.value = 0.0
                self.positionSlider.accessibilityValue = nil
                self.elapsedLabel.text = Self.timeString(0.0)
                self.remainingLabel.text = Self.timeString(0.0)
                if let (account, playbackState, type) = value, account.id == context.account.id, type == .music, case .loading = playbackState {
                    // Preserve the current selection until the next concrete track is known.
                } else {
                    self.trackId = nil
                    self.lyricsSourceOverride = nil
                    self.file = nil
                }
                self.albumArt = nil
                self.finishCoverDrag()
                self.onlineArtworkTask?.cancel()
                self.onlineArtworkTask = nil
                self.onlineArtwork = nil
                self.telegramArtwork = nil
                self.trackTitle = ""
                self.trackArtist = ""
                self.titleLabel.text = self.presentationData.strings.MediaPlayer_UnknownTrack
                self.artistLabel.text = self.presentationData.strings.MediaPlayer_UnknownArtist
                self.setOriginalArtwork(nil)
                self.artworkDisposable?.dispose()
                self.artworkColor = NextgramPlayerPalette.fallback
                self.updateAppearance()
                self.cancelLyrics()
                self.lyrics = nil
                self.lyricsPlaceholder = self.string("NoLyrics")
                self.updateLyricsView()
                self.updateMenu()
                self.spinner.stopAnimating()
                self.updateTransport()
                self.updateDisplayLink()
            }
        })
        self.presentationDisposable = (context.sharedContext.presentationData |> deliverOnMainQueue).startStrict(next: { [weak self] data in
            self?.presentationData = data
            self?.updateAppearance()
        })
        self.updateAppearance()
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.settingsDisposable?.dispose()
        self.systemDisplayDisposable?.dispose()
        self.playbackDisposable?.dispose()
        self.presentationDisposable?.dispose()
        self.artworkDisposable?.dispose()
        self.onlineArtworkTask?.cancel()
        self.artworkFocusTask?.cancel()
        self.artworkEnhancementTask?.cancel()
        self.detailArtworkDisposable?.dispose()
        self.displayLink?.invalidate()
        self.onlineTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    public func setActive(_ active: Bool) {
        guard self.active != active else { return }
        self.active = active
        if active {
            self.transform = .identity
            self.isUserInteractionEnabled = true
        }
        self.updateArtworkMotion()
        if !active { self.closeArtworkDetail(animated: false) }
        self.updateDisplayLink()
        if active {
            self.reloadLyrics()
            self.refreshOnlineArtwork()
            self.updatePosition()
        } else {
            self.finishCoverDrag()
            self.onlineArtworkTask?.cancel()
            self.onlineArtworkTask = nil
            self.cancelLyrics()
        }
    }

    public func updateLayout(size: CGSize, safeInsets: UIEdgeInsets) {
        self.safeInsets = safeInsets
        self.artworkDetail?.updateInsets(safeInsets)
        self.bounds = CGRect(origin: .zero, size: size)
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }

    public override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        self.setNeedsLayout()
    }

#if DEBUG && targetEnvironment(simulator)
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if self.previewAnimatedLyrics && self.previewPlaying == true && self.previewClockStart == nil && self.window != nil {
            self.previewClockStart = CACurrentMediaTime()
            self.updateDisplayLink()
        }
    }
#endif

    public override func layoutSubviews() {
        super.layoutSubviews()
        let size = self.bounds.size
        guard size.width > 0.0, size.height > 0.0 else { return }
        self.backgroundArtworkContainer.frame = self.bounds
        self.shade.frame = self.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.gradientBackground.frame = self.bounds
        self.fullscreenShade.frame = self.bounds
        CATransaction.commit()

        let top = max(12.0, self.safeInsets.top, self.safeAreaInsets.top) + 4.0
        let bottom = max(12.0, self.safeInsets.bottom, self.safeAreaInsets.bottom)
        let landscape = size.width > size.height * 1.15
        let left = max(landscape ? 24.0 : 32.0, self.safeInsets.left + 16.0)
        let right = max(landscape ? 24.0 : 32.0, self.safeInsets.right + 16.0)
        self.closeButton.frame = CGRect(x: left - 8.0, y: top, width: 44.0, height: 44.0)
        self.closeButton.isHidden = !UIAccessibility.isVoiceOverRunning
        self.grabber.frame = CGRect(x: (size.width - 60.0) * 0.5, y: top + 1.0, width: 60.0, height: 4.0)

        let contentTop = top + (landscape ? 40.0 : 22.0)
        let columnLeft = landscape ? size.width * 0.5 + 18.0 : left
        let columnRight = right
        let columnWidth = max(1.0, size.width - columnLeft - columnRight)
        let compact = size.height - top - bottom < 610.0
        let spacingScale = landscape ? 1.0 : min(1.0, max(0.72, (size.height - top - bottom) / 750.0))
        let footerY = size.height - bottom - (landscape ? 48.0 : 72.0)
        let volumeHeight: CGFloat = self.settings.showVolume ? (landscape ? 34.0 : max(34.0, 39.0 * spacingScale)) : 8.0
        let controlsHeight: CGFloat = landscape ? 58.0 : (compact ? 60.0 : 70.0)
        let baseControlsY = footerY - volumeHeight - controlsHeight - (landscape ? 0.0 : 16.0 * spacingScale)
        let roomAboveVolume = footerY - volumeHeight - baseControlsY - controlsHeight - 8.0
        let fullscreenLift = !landscape && self.settings.coverLayout == .fullscreen ? min(26.0, max(0.0, roomAboveVolume)) : 0.0
        let controlsY = baseControlsY + (self.showingLyrics ? 0.0 : fullscreenLift)
        let sliderOffset = landscape ? 44.0 : max(44.0, 54.0 * spacingScale)
        let titleOffsetFromSlider = landscape ? 61.0 : max(55.0, 63.0 * spacingScale)
        let sliderY = controlsY - sliderOffset
        let normalTitleY = sliderY - titleOffsetFromSlider
        let titleY = self.showingLyrics && !landscape ? contentTop : max(top, normalTitleY)
        let availableCoverHeight = max(0.0, normalTitleY - contentTop - 22.0 * spacingScale)
        let coverWidth = landscape ? max(1.0, size.width * 0.5 - left - 28.0) : max(1.0, size.width - 48.0)
        let coverHeight = landscape ? max(0.0, size.height - contentTop - bottom - 20.0) : availableCoverHeight
        var coverFrame = CGRect.zero
        let ratio = CGFloat(self.settings.coverSize) / 100.0
        switch self.settings.coverLayout {
        case .fullscreen:
            let width = landscape ? coverWidth : size.width
            coverFrame = CGRect(x: landscape ? left : 0.0, y: contentTop,
                width: width, height: landscape ? coverHeight : min(width, coverHeight + 10.0))
        case .card, .disc:
            let side = min(coverWidth, coverHeight, 460.0) * ratio
            coverFrame = CGRect(x: landscape ? left + (coverWidth - side) * 0.5 : (size.width - side) * 0.5,
                y: contentTop + (coverHeight - side) * 0.5, width: side, height: side)
        }
        if self.showingLyrics {
            coverFrame = landscape
                ? CGRect(x: left, y: contentTop, width: 62.0, height: 62.0)
                : CGRect(x: columnLeft, y: titleY, width: 72.0, height: 72.0)
        } else if self.settings.coverLayout == .card && !self.playing {
            let pausedSide = coverFrame.width * CGFloat(self.settings.pausedCoverSize) / 100.0
            coverFrame = CGRect(x: coverFrame.midX - pausedSide * 0.5, y: coverFrame.midY - pausedSide * 0.5,
                width: pausedSide, height: pausedSide)
        }
        self.artwork.bounds = CGRect(origin: .zero, size: coverFrame.size)
        self.artwork.center = CGPoint(x: coverFrame.midX, y: coverFrame.midY)
        self.artworkDetail?.frame = self.bounds
        self.artwork.cornerRadius = self.showingLyrics ? 8.0 :
            (self.settings.coverLayout == .disc ? coverFrame.width * 0.5 : (self.settings.coverLayout == .fullscreen ? 0.0 : CGFloat(self.settings.coverCornerRadius)))
        let holeSide = coverFrame.width * 0.12
        self.discHole.frame = CGRect(x: (coverFrame.width - holeSide) * 0.5, y: (coverFrame.height - holeSide) * 0.5, width: holeSide, height: holeSide)
        self.discHole.layer.cornerRadius = holeSide * 0.5
        self.discHole.isHidden = self.settings.coverLayout != .disc || self.showingLyrics
        // Fullscreen uses the single background artwork layer; the card/disc
        // artwork view is reserved for the other cover layouts.
        self.artwork.isHidden = !self.showingLyrics && self.settings.coverLayout == .fullscreen
        self.artworkShadow.bounds = self.artwork.bounds
        self.artworkShadow.center = self.artwork.center
        self.artworkShadow.layer.cornerRadius = self.artwork.cornerRadius
        self.artworkShadow.isHidden = self.artwork.isHidden || self.settings.coverLayout == .fullscreen
        self.artworkShadow.alpha = self.showingLyrics ? 0.0 : 1.0
        self.artwork.contentMode = self.settings.coverLayout == .fullscreen && !self.showingLyrics ? .scaleAspectFit : .scaleAspectFill
        self.artwork.backgroundColor = self.settings.coverLayout == .fullscreen ? .clear : UIColor.white.withAlphaComponent(0.08)

        // Anchor the mask to the fullscreen controls even while the lyrics header moves.
        if let blurView = self.fullscreenBottomBlur, let mask = blurView.layer.mask as? CAGradientLayer {
            let height: CGFloat
            let fadeEnd: CGFloat
            switch self.settings.fullscreenBlurHeight {
            case .short:
                height = min(size.height, max(160.0, min(180.0, size.height * 0.20)))
                fadeEnd = 0.84
            case .controls:
                let fullscreenTitleY = max(top, baseControlsY + fullscreenLift - sliderOffset - titleOffsetFromSlider)
                let blurTop = max(0.0, fullscreenTitleY - 42.0)
                height = size.height - blurTop
                fadeEnd = min(1.0, 108.0 / height)
            case .custom:
                height = size.height * CGFloat(self.settings.fullscreenBlurPercent) / 100.0
                fadeEnd = 0.84
            }
            UIView.performWithoutAnimation {
                blurView.frame = CGRect(x: 0.0, y: size.height - height, width: size.width, height: height)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                mask.frame = blurView.bounds
                mask.locations = [0.0, NSNumber(value: Double(fadeEnd))]
                CATransaction.commit()
            }
        }
        if let blur = self.blur {
            // A newly inserted backdrop must start at full size, outside the lyrics spring.
            UIView.performWithoutAnimation {
                blur.frame = self.bounds
                let transitionHeight = size.height * 0.85
                blur.update(size: size, constantHeight: transitionHeight, isInverted: true,
                    gradient: EdgeEffectView.generateEdgeGradientData(baseHeight: transitionHeight), transition: .immediate)
            }
        }

        if self.settings.smartArtworkCrop && self.settings.coverLayout == .fullscreen && !self.showingLyrics,
           let image = self.backgroundArtwork.image, image === self.artworkFocusImage, let focus = self.artworkFocus,
           image.size.width > 0.0, image.size.height > 0.0 {
            let clearHeight = min(titleY, self.fullscreenBottomBlur?.frame.minY ?? size.height)
            let target = CGPoint(x: landscape ? columnLeft * 0.5 : size.width * 0.5, y: clearHeight * 0.52)
            self.backgroundArtwork.frame = NextgramArtworkFocus.frame(imageSize: image.size, in: size, focus: focus, target: target)
        } else {
            self.backgroundArtwork.frame = self.backgroundArtworkContainer.bounds
        }

        let lyricTop = contentTop + (landscape ? 72.0 : 98.0)
        self.lyricsView.frame = CGRect(x: landscape ? left : 0.0, y: lyricTop,
            width: landscape ? coverWidth : size.width,
            height: max(0.0, (landscape ? size.height - bottom : sliderY - 6.0) - lyricTop))
        self.lyricsView.isHidden = !self.showingLyrics && !self.transitioningLyrics
        let titleInset: CGFloat = self.showingLyrics && !landscape ? 84.0 : 0.0
        let titleOffset: CGFloat = self.showingLyrics && !landscape ? 11.0 : 0.0
        self.menuButton.frame = CGRect(x: size.width - columnRight - 38.0, y: titleY + titleOffset + 4.0, width: 44.0, height: 44.0)
        self.favoriteButton.frame = self.menuButton.frame.offsetBy(dx: -48.0, dy: 0.0)
        self.titleLabel.frame = CGRect(x: columnLeft + titleInset, y: titleY + titleOffset + 1.0, width: max(1.0, columnWidth - titleInset - 88.0), height: 29.0)
        self.artistLabel.frame = CGRect(x: columnLeft + titleInset, y: titleY + titleOffset + 29.0, width: max(1.0, columnWidth - titleInset - 88.0), height: 24.0)
        self.spinner.frame = CGRect(x: columnLeft + columnWidth - 107.0, y: titleY + titleOffset + 32.0, width: 16.0, height: 16.0)
        self.positionSlider.frame = CGRect(x: columnLeft, y: sliderY, width: columnWidth, height: 30.0)
        self.elapsedLabel.frame = CGRect(x: columnLeft + 2.0, y: sliderY + 27.0, width: columnWidth * 0.5, height: 16.0)
        self.remainingLabel.frame = CGRect(x: columnLeft + columnWidth * 0.5, y: sliderY + 27.0, width: columnWidth * 0.5 - 2.0, height: 16.0)

        let buttons = [self.previousButton, self.playButton, self.nextButton]
        let step = min(106.0, columnWidth / 3.0)
        let rowStart = columnLeft + (columnWidth - step * 3.0) * 0.5
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: rowStart + CGFloat(index) * step, y: controlsY, width: step, height: controlsHeight)
        }
        let volumeY = footerY - volumeHeight
        self.volumeView.frame = CGRect(x: columnLeft + 24.0, y: volumeY, width: max(1.0, columnWidth - 48.0), height: 34.0)
        self.volumeLow.frame = CGRect(x: columnLeft, y: volumeY, width: 22.0, height: 34.0)
        self.volumeHigh.frame = CGRect(x: columnLeft + columnWidth - 22.0, y: volumeY, width: 22.0, height: 34.0)
        for view in [self.volumeView, self.volumeLow, self.volumeHigh] as [UIView] { view.isHidden = !self.settings.showVolume }
        let footerViews: [UIView] = [self.lyricsButton, self.routePicker, self.queueButton]
        for (index, view) in footerViews.enumerated() {
            let center = columnLeft + columnWidth / 3.0 * (CGFloat(index) + 0.5)
            view.frame = CGRect(x: center - 22.0, y: footerY, width: 44.0, height: 44.0)
        }
        self.repeatIndicator.frame = CGRect(x: 30.0, y: -2.0, width: 20.0, height: 20.0)
        self.routeLabel.frame = CGRect(x: columnLeft, y: footerY + 47.0, width: columnWidth, height: 20.0)
        self.routeLabel.isHidden = landscape
    }

    private func configure(_ button: UIButton, symbol: String, size: CGFloat, action: Selector?) {
        button.tintColor = .white
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.imageView?.contentMode = .scaleAspectFit
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .semibold)), for: .normal)
        button.layer.cornerRadius = 12.0
        if let action { button.addTarget(self, action: action, for: .touchUpInside) }
        self.addSubview(button)
    }

    private func updateFavorite() {
        let saved = self.isSavedMusic == true
        self.favoriteButton.setImage(UIImage(systemName: saved ? "star.fill" : "star",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16.0, weight: .semibold)), for: .normal)
        self.favoriteButton.isEnabled = self.isSavedMusic != nil
        self.favoriteButton.accessibilityLabel = saved
            ? self.presentationData.strings.MediaPlayer_SavedMusic_RemoveFromProfileShort
            : self.presentationData.strings.MediaPlayer_SavedMusic_AddToProfile
        self.favoriteButton.accessibilityTraits = saved ? [.button, .selected] : .button
    }

    @objc private func favoritePressed() {
        self.toggleSavedMusic?()
    }

    @objc private func audioRouteChanged() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.audioRouteChanged() }
            return
        }
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        self.routeLabel.text = outputs.isEmpty ? UIDevice.current.localizedModel : outputs.map(\.portName).joined(separator: ", ")
        self.routePicker.updateRoute(bluetooth: outputs.contains { [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0.portType) })
    }

    private func string(_ key: String) -> String {
#if DEBUG && targetEnvironment(simulator)
        if self.previewPlaying != nil { return ngI18n("Nagram.MusicPlayer." + key, "zh-hans") }
#endif
        return ngI18n("Nagram.MusicPlayer." + key, self.presentationData.strings.baseLanguageCode)
    }

    private func updateAppearance() {
        self.updateArtworkEnhancement()
        self.updateBackdrop()
        self.updateDisplayLink()
        self.updateArtworkMotion()
        self.closeButton.accessibilityLabel = self.presentationData.strings.Common_Close
        self.menuButton.accessibilityLabel = self.presentationData.strings.Common_More
        self.lyricsButton.accessibilityLabel = self.string("Lyrics")
        self.queueButton.accessibilityLabel = self.string("Queue")
        self.positionSlider.accessibilityLabel = self.string("PlaybackPosition")
        self.positionSlider.elasticEdges = self.settings.elasticProgress
        self.positionSlider.jumpOnTap = self.settings.tapToSeek
        self.volumeView.slider.accessibilityLabel = self.string("Volume")
        self.volumeView.slider.elasticEdges = self.settings.elasticVolume
        self.previousButton.accessibilityLabel = self.string("Previous")
        self.nextButton.accessibilityLabel = self.string("Next")
        self.lyricsButton.isHidden = !self.settings.lyricsEnabled
        self.lyricsButton.isSelected = self.showingLyrics
        self.updateLyricsView()
        if !self.transitioningLyrics {
            self.lyricsView.alpha = self.showingLyrics ? 1.0 : 0.0
        }
        self.updateFavorite()
        self.updateMenu()
        self.updateTransport()
        self.updateDiscAnimation()
        self.setNeedsLayout()
    }

    private func updateBackdrop() {
        let fullscreen = self.settings.coverLayout == .fullscreen && !self.showingLyrics
        let reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        let radius = CGFloat(self.settings.blurIntensity)
        let gradient = !fullscreen && self.settings.background == .gradient
        let showsArt = self.backgroundArtwork.image != nil && (fullscreen || (!reduceTransparency && self.settings.background == .blur && radius > 0.0))
        let progressiveBlur = !fullscreen && showsArt
        let base: UIColor
        switch self.settings.colors {
        case .cover: base = self.artworkColor
        case .theme: base = self.presentationData.theme.list.modalBlocksBackgroundColor
        case .custom: base = NextgramPlayerPalette.customColor(self.settings.customColor) ?? self.artworkColor
        }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        base.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let surface = gradient ? UIColor(red: red * 0.24, green: green * 0.24, blue: blue * 0.24, alpha: 1.0) : base
        self.backgroundColor = surface
        // Exteraless' tonal gradient: primary-container tint fades into the surface at 70% height.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.gradientBackground.isHidden = !gradient
        self.gradientBackground.colors = [base.withAlphaComponent(0.85).cgColor, base.withAlphaComponent(0.0).cgColor]
        self.fullscreenShade.isHidden = !fullscreen
        self.fullscreenShade.colors = [UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.02).cgColor, UIColor.black.withAlphaComponent(reduceTransparency ? 0.90 : 0.54).cgColor]
        self.fullscreenShade.locations = [0.0, 0.54, 1.0]
        CATransaction.commit()
        if fullscreen && !reduceTransparency && showsArt {
            if self.fullscreenBottomBlur == nil {
                let blurView = UIVisualEffectView(effect: self.transitioningLyrics ? nil : self.fullscreenBlurEffect)
                blurView.isUserInteractionEnabled = false
                let mask = CAGradientLayer()
                mask.colors = [UIColor.clear.cgColor, UIColor.white.cgColor]
                blurView.layer.mask = mask
                self.insertSubview(blurView, aboveSubview: self.backgroundArtworkContainer)
                self.fullscreenBottomBlur = blurView
            }
        } else if !(self.transitioningLyrics && self.showingLyrics && self.settings.coverLayout == .fullscreen && !reduceTransparency && self.backgroundArtwork.image != nil) {
            self.fullscreenBottomBlur?.removeFromSuperview()
            self.fullscreenBottomBlur = nil
        }
        if progressiveBlur {
            if self.blur?.maxBlurRadius != radius {
                self.blur?.removeFromSuperview()
                let blur = VariableBlurView(maxBlurRadius: radius)
                blur.isUserInteractionEnabled = false
                self.insertSubview(blur, aboveSubview: self.backgroundArtworkContainer)
                self.blur = blur
            }
        } else {
            self.blur?.removeFromSuperview()
            self.blur = nil
        }
        self.backgroundArtworkContainer.isHidden = !showsArt
        self.backgroundArtworkContainer.isUserInteractionEnabled = fullscreen
        self.updateArtworkFocus(enabled: fullscreen && self.settings.smartArtworkCrop)
        self.shade.backgroundColor = !showsArt || fullscreen ? .clear : base.withAlphaComponent(self.showingLyrics ? 0.85 : 0.73)
        let ink: UIColor = gradient || (fullscreen && showsArt) ? .white : NextgramPlayerPalette.foreground(on: surface)
        self.foregroundColor = ink
        self.playerStatusBarStyle = ink == .white ? .White : .Black
        self.updateStatusBarStyle?(self.playerStatusBarStyle)
        self.titleLabel.textColor = ink
        self.artistLabel.textColor = ink.withAlphaComponent(0.72)
        self.grabber.backgroundColor = ink.withAlphaComponent(0.30)
        for label in [self.elapsedLabel, self.remainingLabel] { label.textColor = ink.withAlphaComponent(0.66) }
        for button in [self.closeButton, self.menuButton, self.previousButton, self.playButton, self.nextButton, self.lyricsButton, self.queueButton] {
            button.tintColor = ink
        }
        self.closeButton.backgroundColor = .clear
        self.menuButton.backgroundColor = .clear
        self.favoriteButton.tintColor = ink
        self.repeatIndicator.tintColor = ink.withAlphaComponent(0.85)
        self.repeatIndicator.backgroundColor = ink.withAlphaComponent(0.20)
        self.routeLabel.textColor = ink.withAlphaComponent(0.75)
        self.lyricsButton.backgroundColor = self.showingLyrics ? ink.withAlphaComponent(0.60) : .clear
        self.lyricsButton.tintColor = self.showingLyrics ? surface : ink.withAlphaComponent(0.65)
        self.queueButton.tintColor = ink.withAlphaComponent(0.65)
        self.routePicker.tintColor = ink
        self.spinner.color = ink
        self.volumeLow.tintColor = ink.withAlphaComponent(0.62)
        self.volumeHigh.tintColor = self.volumeLow.tintColor
        let filledRail = ink.withAlphaComponent(0.78)
        let emptyRail = ink.withAlphaComponent(0.21)
        self.positionSlider.setColors(filled: filledRail, empty: emptyRail)
        self.volumeView.slider.setColors(filled: filledRail, empty: emptyRail)
        self.titleLabel.font = .systemFont(ofSize: min(self.showingLyrics ? 18.0 : 32.0, CGFloat(self.settings.titleFontSize)), weight: .bold)
        self.artistLabel.font = .systemFont(ofSize: self.showingLyrics ? 16.0 : 20.0, weight: .regular)
        self.lyricsButton.layer.cornerRadius = 22.0
        self.titleLabel.textAlignment = self.settings.titleAlignment == "center" && !self.showingLyrics ? .center : .left
        self.artistLabel.textAlignment = self.titleLabel.textAlignment
        let scale = CGFloat(self.settings.controlScale) / 100.0
        for (button, symbol, size) in [(self.previousButton, "backward.fill", 22.0), (self.nextButton, "forward.fill", 22.0)] {
            button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: CGFloat(size) * scale, weight: .semibold)), for: .normal)
        }
    }


    private func updateState(_ state: SharedMediaPlayerItemPlaybackState) {
        let resumedFromLoading = self.state == nil
        let previousFileId = self.file?.media.fileId
        let previousSeekId = self.state?.status.seekId
        let previousDuration = self.state?.status.duration ?? 0.0
        let previousTitle = self.trackTitle
        let previousArtist = self.trackArtist
        let menuChanged = self.state?.order != state.order || self.state?.looping != state.looping
        let changedItem = self.trackId != state.item.stableId
        if changedItem, let drag = self.coverDrag, !drag.committed {
            self.finishCoverDrag()
        }
        self.state = state
        self.trackId = state.item.stableId
        if let source = state.item.playbackData?.source, case let .telegramFile(file, _, _) = source {
            self.file = file
        } else {
            self.file = nil
        }
        let changed = changedItem || previousFileId != self.file?.media.fileId
        if changed {
            self.lyricsSourceOverride = self.lyricsSelections[state.item.stableId]
            self.closeArtworkDetail(animated: false)
        }
        if let display = state.item.displayData, case let .music(title, artist, albumArt, _, _) = display {
            self.trackTitle = title ?? ""
            self.trackArtist = artist ?? ""
            self.titleLabel.text = title ?? self.presentationData.strings.MediaPlayer_UnknownTrack
            self.artistLabel.text = artist ?? self.presentationData.strings.MediaPlayer_UnknownArtist
            if changed || resumedFromLoading || self.albumArt != albumArt {
                self.albumArt = albumArt
                if changed {
                    self.onlineArtworkTask?.cancel()
                    self.onlineArtworkTask = nil
                    self.onlineArtwork = nil
                    self.telegramArtwork = self.coverDrag.flatMap { $0.neighborId == self.trackId ? $0.neighbor.image : nil }
                    self.applyAvailableArtwork()
                }
                self.updateArtwork()
            }
        }
        if changed || previousTitle != self.trackTitle || previousArtist != self.trackArtist || (previousDuration == 0.0 && state.status.duration > 0.0) {
            self.refreshOnlineArtwork()
        }
        if changedItem, self.coverDrag?.settled == true {
            self.finishCoverDrag()
        }
        if case .buffering = state.status.status { self.spinner.startAnimating() } else { self.spinner.stopAnimating() }
        self.updateTransport()
        if menuChanged { self.updateMenu() }
        self.updateDisplayLink()
        self.updatePosition()
        if previousSeekId != state.status.seekId { self.lyricsView.updatePosition(self.currentPosition, force: true) }
        if changed || resumedFromLoading || previousTitle != self.trackTitle || previousArtist != self.trackArtist || (previousDuration == 0.0 && state.status.duration > 0.0) {
            self.scrubbing = false
            self.updatePosition()
            self.updateMenu()
            self.reloadLyrics()
        }
    }

    private func updateArtwork() {
        guard let context = self.context else { return }
        self.artworkDisposable?.dispose()
        let expectedTrack = self.trackId
        self.artworkDisposable = (nextgramPlayerArtwork(engine: context.engine, fileReference: self.file, albumArt: self.albumArt)
        |> deliverOnMainQueue).startStrict(next: { [weak self] image in
            guard let self, self.trackId == expectedTrack else { return }
            if let image {
                self.telegramArtwork = image
                self.applyAvailableArtwork()
            }
        })
    }

    private func refreshOnlineArtwork() {
        self.onlineArtworkTask?.cancel()
        self.onlineArtworkTask = nil
        guard self.settings.onlineArtwork else {
            if self.onlineArtwork != nil {
                self.onlineArtwork = nil
                self.applyAvailableArtwork()
                self.reloadDetailArtwork()
            }
            return
        }
        guard self.trackId != nil || self.isCanvasPlayer, self.active, self.foreground,
              self.onlineArtwork == nil, !self.trackTitle.isEmpty, !self.trackArtist.isEmpty else { return }
        let expectedTrack = self.trackId
        let title = self.trackTitle
        let artist = self.trackArtist
        let duration = self.playbackDuration
        self.onlineArtworkTask = Task { @MainActor [weak self] in
            let image = await NextgramOnlineArtwork.shared.artwork(title: title, artist: artist, duration: duration)
            guard let self, !Task.isCancelled, self.trackId == expectedTrack,
                  self.trackTitle == title, self.trackArtist == artist, self.settings.onlineArtwork else { return }
            self.onlineArtworkTask = nil
            if let image {
                self.onlineArtwork = image
                self.applyAvailableArtwork()
                self.reloadDetailArtwork()
            }
        }
    }

    private func applyAvailableArtwork() {
        let image = self.preferredOnlineArtwork ?? self.telegramArtwork
        guard self.originalArtwork !== image else { return }
        self.setOriginalArtwork(image)
        self.artworkColor = NextgramPlayerPalette.artworkColor(image)
        self.updateBackdrop()
        self.updateLyricsView()
        self.setNeedsLayout()
    }

    private var preferredOnlineArtwork: UIImage? {
        guard let online = self.onlineArtwork else { return nil }
        guard let local = self.telegramArtwork else { return online }
        let onlineSide = min(online.size.width, online.size.height) * online.scale
        let localSide = min(local.size.width, local.size.height) * local.scale
        return onlineSide > localSide ? online : nil
    }

    private func setOriginalArtwork(_ image: UIImage?) {
        guard self.originalArtwork !== image else { return }
        self.artworkEnhancementTask?.cancel()
        self.artworkEnhancementTask = nil
        self.originalArtwork = image
        self.enhancedArtwork = nil
        self.updateArtworkEnhancement()
    }

    private func updateArtworkEnhancement() {
        let fullscreen = self.settings.coverLayout == .fullscreen && !self.showingLyrics
        let enabled = self.settings.artworkEnhancement == .always || (fullscreen && self.settings.artworkEnhancement == .fullscreen)
        self.artwork.image = (enabled ? self.enhancedArtwork : nil) ?? self.originalArtwork
        self.backgroundArtwork.image = (enabled && fullscreen ? self.enhancedArtwork : nil) ?? self.originalArtwork
        guard enabled else {
            self.artworkEnhancementTask?.cancel()
            self.artworkEnhancementTask = nil
            return
        }
        guard self.enhancedArtwork == nil, self.artworkEnhancementTask == nil, let source = self.originalArtwork else { return }
        self.artworkEnhancementTask = NextgramImageSuperResolution.enhance(source) { [weak self] image in
            guard let self, self.originalArtwork === source, self.artworkEnhancementTask != nil else { return }
            self.artworkEnhancementTask = nil
            guard let image else { return }
            self.enhancedArtwork = image
            self.updateArtworkEnhancement()
            self.updateBackdrop()
            self.setNeedsLayout()
        }
    }

    private func updateArtworkFocus(enabled: Bool) {
        let image = self.backgroundArtwork.image
        guard image !== self.artworkFocusImage else { return }
        self.artworkFocusTask?.cancel()
        self.artworkFocusTask = nil
        self.artworkFocusImage = nil
        self.artworkFocus = nil
        guard enabled, let image else { return }
        self.artworkFocusImage = image
        let task = DispatchWorkItem { [weak self] in
            let focus = NextgramArtworkFocus.detect(in: image)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.artworkFocusImage === image, self.backgroundArtwork.image === image else { return }
                self.artworkFocusTask = nil
                self.artworkFocus = focus
                self.setNeedsLayout()
            }
        }
        self.artworkFocusTask = task
        NextgramArtworkFocus.queue.async(execute: task)
    }

    private var currentPosition: Double {
#if DEBUG && targetEnvironment(simulator)
        if self.previewPlaying != nil {
            let elapsed = self.previewClockStart.map { max(0.0, CACurrentMediaTime() - $0) } ?? 0.0
            return min(self.previewDuration, self.previewClockPosition + elapsed)
        }
#endif
        guard let status = self.state?.status else { return 0.0 }
        var time = status.timestamp
        if case .playing = status.status, status.generationTimestamp > 0.0 {
            time += max(0.0, CACurrentMediaTime() - status.generationTimestamp) * status.baseRate
        }
        return min(max(0.0, status.duration), max(0.0, time))
    }

    fileprivate func updatePosition() {
#if DEBUG && targetEnvironment(simulator)
        if self.previewPlaying != nil {
            let time = self.scrubbing ? Double(self.positionSlider.value) * self.previewDuration : self.currentPosition
            if self.showingLyrics { self.lyricsView.updatePosition(time) }
            self.elapsedLabel.text = Self.timeString(time)
            self.remainingLabel.text = self.settings.showRemainingTime ? "−" + Self.timeString(self.previewDuration - time) : Self.timeString(self.previewDuration)
            if !self.scrubbing { self.positionSlider.value = Float(time / self.previewDuration) }
            self.positionSlider.accessibilityValue = Self.timeString(time) + " / " + Self.timeString(self.previewDuration)
            return
        }
#endif
        guard let status = self.state?.status else { return }
        let time = self.scrubbing ? Double(self.positionSlider.value) * status.duration : self.currentPosition
        if !self.scrubbing { self.positionSlider.value = status.duration > 0.0 ? Float(time / status.duration) : 0.0 }
        self.elapsedLabel.text = Self.timeString(time)
        self.remainingLabel.text = self.settings.showRemainingTime ? "−" + Self.timeString(max(0.0, status.duration - time)) : Self.timeString(status.duration)
        self.positionSlider.accessibilityValue = Self.timeString(time) + " / " + Self.timeString(status.duration)
        if self.active && self.showingLyrics { self.lyricsView.updatePosition(time) }
    }

    private static func timeString(_ time: Double) -> String {
        let seconds = time.isFinite ? Int(min(359999.0, max(0.0, time))) : 0
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var playing: Bool {
#if DEBUG && targetEnvironment(simulator)
        if let previewPlaying = self.previewPlaying { return previewPlaying }
#endif
        guard let state = self.state else { return false }
        switch state.status.status {
        case .playing: return true
        case .paused: return false
        case let .buffering(_, whilePlaying, _, _): return whilePlaying
        }
    }

    private func updateTransport() {
        let scale = CGFloat(self.settings.controlScale) / 100.0
        self.playButton.setImage(UIImage(systemName: self.playing ? "pause.fill" : "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 37.0 * scale, weight: .semibold)), for: .normal)
        self.playButton.accessibilityLabel = self.string(self.playing ? "Pause" : "Play")
        for button in [self.playButton, self.nextButton, self.previousButton] {
            button.isEnabled = self.state != nil
        }
        self.positionSlider.isEnabled = (self.state?.status.duration ?? 0.0) > 0.0
#if DEBUG && targetEnvironment(simulator)
        if self.previewPlaying != nil {
            for button in [self.playButton, self.nextButton, self.previousButton] { button.isEnabled = true }
            self.positionSlider.isEnabled = true
        }
#endif
        let changed = self.lastPlaying != nil && self.lastPlaying != self.playing
        self.lastPlaying = self.playing
        if changed {
            self.setNeedsLayout()
            UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.38,
                delay: 0.0, usingSpringWithDamping: 0.88, initialSpringVelocity: 0.0,
                options: [.beginFromCurrentState, .allowUserInteraction], animations: { self.layoutIfNeeded() })
        }
    }

    private func updateDisplayLink() {
        let running = self.active && self.foreground && self.playing
        self.lyricsView.followsPlayback = running && self.showingLyrics
        if running && self.displayLink == nil {
            let link = CADisplayLink(target: self.displayLinkTarget, selector: #selector(NextgramPlayerDisplayLinkTarget.tick))
            link.preferredFramesPerSecond = 10
            link.add(to: .main, forMode: .common)
            self.displayLink = link
        } else if !running {
            self.displayLink?.invalidate()
            self.displayLink = nil
        }
        self.displayLink?.preferredFramesPerSecond = self.showingLyrics ? (self.lyricEffects.wordHighlight || self.lyricEffects.wordFloat ? 60 : 30) : 10
        self.updateDiscAnimation()
        self.updateBackdropMotion()
    }

    private func updateBackdropMotion() {
        let layer = self.backgroundArtwork.layer
        guard self.active, self.foreground, self.settings.background == .blur,
              !(self.settings.coverLayout == .fullscreen && !self.showingLyrics),
              self.backgroundArtwork.image != nil, !UIAccessibility.isReduceMotionEnabled else {
            layer.removeAnimation(forKey: "nextgram.background")
            layer.speed = 1.0
            layer.timeOffset = 0.0
            layer.beginTime = 0.0
            layer.transform = CATransform3DIdentity
            return
        }
        guard self.playing else {
            if layer.animation(forKey: "nextgram.background") != nil && layer.speed != 0.0 {
                let time = layer.convertTime(CACurrentMediaTime(), from: nil)
                layer.speed = 0.0
                layer.timeOffset = time
            }
            return
        }
        if layer.speed == 0.0 {
            let time = layer.timeOffset
            layer.speed = 1.0
            layer.timeOffset = 0.0
            layer.beginTime = 0.0
            layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - time
        }
        guard layer.animation(forKey: "nextgram.background") == nil else { return }
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: CATransform3DScale(CATransform3DMakeTranslation(-12.0, 10.0, 0.0), 1.12, 1.12, 1.0))
        animation.toValue = NSValue(caTransform3D: CATransform3DScale(CATransform3DMakeTranslation(12.0, -10.0, 0.0), 1.16, 1.16, 1.0))
        animation.duration = 18.0
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "nextgram.background")
    }

    private func updateDiscAnimation() {
        self.updateArtworkMotion()
        let layer = self.artwork.layer
        let disc = self.settings.coverLayout == .disc && !self.showingLyrics
        let spinning = self.active && self.foreground && self.playing && disc && self.settings.discRotation && !UIAccessibility.isReduceMotionEnabled
        if spinning {
            if layer.animation(forKey: "nextgram.disc") == nil {
                let transform = layer.sublayerTransform
                let angle = atan2(transform.m12, transform.m11)
                let animation = CABasicAnimation(keyPath: "sublayerTransform.rotation.z")
                animation.fromValue = angle
                animation.toValue = angle + CGFloat.pi * 2.0
                animation.duration = 20.0
                animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name: .linear)
                layer.add(animation, forKey: "nextgram.disc")
            }
        } else {
            // Freeze at the presented angle, so pause/resume never snaps the album back to zero.
            let transform = disc ? (layer.presentation()?.sublayerTransform ?? layer.sublayerTransform) : CATransform3DIdentity
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.sublayerTransform = transform
            layer.removeAnimation(forKey: "nextgram.disc")
            CATransaction.commit()
        }
    }

    private func cancelLyrics() {
        self.lyricsRequest = UUID()
        self.onlineTask?.cancel()
        self.onlineTask = nil
        self.embeddedLoader.cancel()
    }

    private func reloadLyrics(forceRefresh: Bool = false) {
#if DEBUG && targetEnvironment(simulator)
        if self.previewPlaying != nil && !self.previewOnlineLyrics { return }
#endif
        self.cancelLyrics()
        let cached = self.trackId.flatMap { self.lyricsMemory[$0]?[self.lyricsChoiceKey] }.flatMap { cached in
            cached.source == nil || self.settings.onlineLyricsEnabled ? cached : nil
        }
        self.lyrics = cached?.lyrics
        self.activeLyricsSource = cached?.source
        self.localLyricsOrigin = cached?.localOrigin
        self.reusedPlayerLyrics = cached != nil && !forceRefresh
        self.lyricsAttempts = self.reusedPlayerLyrics ? (cached?.attempts ?? []) : []
        self.embeddedLyricsFound = false
        self.lyricsPlaceholder = self.string("NoLyrics")
        self.updateLyricsView()
        self.updateLyricsDiagnostics()
        self.updateMenu()
        guard self.active, self.foreground, self.settings.lyricsEnabled else {
            self.lyrics = nil
            self.updateLyricsView()
            return
        }
        if cached != nil && !forceRefresh { return }
        let request = self.lyricsRequest
        if let override = self.lyricsSourceOverride, self.settings.onlineLyricsEnabled {
            self.loadOnlineLyrics(request: request, sources: [override], forceRefresh: forceRefresh)
            return
        }
        guard let context = self.context, let file = self.file else {
            if self.settings.onlineLyricsEnabled { self.loadOnlineLyrics(request: request, sources: self.settings.lyricsSources, forceRefresh: forceRefresh) }
            return
        }
        let fileId = file.media.fileId.id
        self.lyricsPlaceholder = self.string("LoadingLyrics")
        self.updateLyricsView()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let imported = NextgramLyricsStore.load(fileId: fileId)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lyricsRequest == request else { return }
                if let imported {
                    self.lyrics = imported
                    self.activeLyricsSource = nil
                    self.localLyricsOrigin = "DiagnosticsImported"
                    self.rememberLyrics()
                    self.updateLyricsView()
                    self.updateLyricsDiagnostics()
                    return
                }
                self.lyricsPlaceholder = self.string("NoLyrics")
                self.updateLyricsView()
                self.embeddedLoader.load(context: context, file: file) { [weak self] text in
                    guard let self, self.lyricsRequest == request, let text, let lyrics = NextgramLyrics.parse(text) else { return }
                    self.embeddedLyricsFound = true
                    self.onlineTask?.cancel()
                    self.onlineTask = nil
                    self.lyrics = lyrics
                    self.activeLyricsSource = nil
                    self.localLyricsOrigin = "DiagnosticsEmbedded"
                    self.rememberLyrics()
                    self.updateLyricsView()
                    self.updateLyricsDiagnostics()
                }
                if self.settings.onlineLyricsEnabled {
                    self.loadOnlineLyrics(request: request, sources: self.settings.lyricsSources, forceRefresh: forceRefresh)
                }
            }
        }
    }

    private func loadOnlineLyrics(request: UUID, sources: [NextgramLyricsSource], forceRefresh: Bool) {
        let title = self.trackTitle, artist = self.trackArtist
        let duration = self.playbackDuration
        let manualSource = self.lyricsSourceOverride
        self.lyricsPlaceholder = self.string("LoadingLyrics")
        self.updateLyricsView()
        self.updateLyricsDiagnostics()
        self.onlineTask = Task { @MainActor [weak self] in
            var match: (source: NextgramLyricsSource, lyrics: NextgramLyrics, priority: Int)?
            var manualFailure: String?
            await withTaskGroup(of: (Int, LyricsAttempt).self) { group in
                for (priority, source) in sources.enumerated() {
                    guard let provider = NextgramOnlineLyricsProvider(rawValue: source.rawValue) else { continue }
                    group.addTask {
                        let started = ProcessInfo.processInfo.systemUptime
                        let (result, events) = await NextgramOnlineLyrics.lookupWithDiagnostics(provider: provider, title: title, artist: artist,
                            duration: duration, forceRefresh: forceRefresh)
                        return (priority, LyricsAttempt(source: source, elapsed: ProcessInfo.processInfo.systemUptime - started, result: result, events: events))
                    }
                }
                for await (priority, attempt) in group {
                    guard !Task.isCancelled, let self, self.lyricsRequest == request, !self.embeddedLyricsFound else {
                        group.cancelAll()
                        return
                    }
                    self.lyricsAttempts.append(attempt)
                    switch attempt.result {
                    case let .found(lyrics):
                        if match.map({ lyrics.lookupQuality > $0.lyrics.lookupQuality || (lyrics.lookupQuality == $0.lyrics.lookupQuality && priority < $0.priority) }) ?? true {
                            match = (attempt.source, lyrics, priority)
                        }
                    case .unavailable where attempt.source == manualSource:
                        if case .networkError? = attempt.events.last { manualFailure = "SourceUnavailable" }
                        else { manualFailure = "SourceServiceError" }
                    case .noMatch, .unavailable: break
                    }
                    self.updateLyricsDiagnostics()
                }
            }
            guard !Task.isCancelled, let self, self.lyricsRequest == request, !self.embeddedLyricsFound else { return }
            self.onlineTask = nil
            if let (source, lyrics, _) = match {
                self.activeLyricsSource = source
                self.localLyricsOrigin = nil
                self.lyrics = lyrics
                self.lyricsPlaceholder = self.string(lyrics.instrumental ? "Instrumental" : "NoLyrics")
                self.rememberLyrics()
            } else {
                self.lyricsPlaceholder = self.string(manualFailure ?? (manualSource == nil ? "NoLyrics" : "SourceNoMatch"))
            }
            self.updateLyricsView()
            self.updateMenu()
            self.updateLyricsDiagnostics()
        }
    }

    private func showLyricsDiagnostics() {
        let controller = NextgramLyricsDiagnosticsController(title: self.string("Diagnostics"),
            done: self.presentationData.strings.Common_Done, refresh: self.string("DiagnosticsRefresh"),
            viewLyrics: self.string("DiagnosticsViewLyrics"), hideLyrics: self.string("DiagnosticsHideLyrics"), onRefresh: { [weak self] in
                self?.reloadLyrics(forceRefresh: true)
            })
        self.lyricsDiagnostics = controller
        self.updateLyricsDiagnostics()
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .formSheet
        if let context = self.context {
            navigation.overrideUserInterfaceStyle = self.presentationData.theme.overallDarkAppearance ? .dark : .light
            context.sharedContext.applicationBindings.presentNativeController(navigation)
        } else {
            var responder: UIResponder? = self
            while let current = responder {
                if let host = current as? UIViewController {
                    host.present(navigation, animated: true)
                    break
                }
                responder = current.next
            }
        }
    }

    private func updateLyricsDiagnostics() {
        guard let controller = self.lyricsDiagnostics else { return }
        let requested = self.lyricsSourceOverride.map(self.lyricsSourceName) ?? self.string("SourceAutomatic")
        let order = self.lyricsSourceOverride.map { [$0] } ?? self.settings.lyricsSources
        let selected = self.activeLyricsSource.map(self.lyricsSourceName) ?? self.localLyricsOrigin.map(self.string) ?? "—"
        let mode = String(format: self.string("DiagnosticsMode"), requested)
        let source = String(format: self.string("DiagnosticsSelected"), selected)
        var lines = [self.trackTitle, self.trackArtist, String(format: "%.1fs", self.playbackDuration), "", mode, source]
        if self.settings.onlineLyricsEnabled {
            lines.append(String(format: self.string("DiagnosticsOrder"), order.map(self.lyricsSourceName).joined(separator: " → ")))
        } else {
            lines.append(self.string("DiagnosticsOffline"))
        }
        var lyricsSections: [Int: String] = [:]
        var nextLyricsSection = 0
        func appendLyricsDetails(_ lyrics: NextgramLyrics) {
            guard !lyrics.instrumental, !lyrics.lines.isEmpty else { return }
            let id = nextLyricsSection
            nextLyricsSection += 1
            let details = lyrics.lines.map { line -> String in
                let timestamp = line.time.map { String(format: "[%02d:%05.2f] ", Int($0) / 60, $0.truncatingRemainder(dividingBy: 60)) } ?? ""
                if let translation = line.translation, !translation.isEmpty {
                    return timestamp + line.text + "\n↳ " + translation
                }
                return timestamp + line.text
            }.joined(separator: "\n")
            lyricsSections[id] = details
            lines.append("__NEXTGRAM_LYRICS__:\(id)")
        }
        if let lyrics = self.lyrics {
            lines.append(self.lyricsDiagnosticResult(.found(lyrics)))
            appendLyricsDetails(lyrics)
            if self.reusedPlayerLyrics { lines.append(self.string("DiagnosticsMemoryCache")) }
        } else {
            lines.append(self.lyricsPlaceholder)
        }
        for attempt in self.lyricsAttempts {
            lines += ["", self.lyricsSourceName(attempt.source) + String(format: " · %.1fs", attempt.elapsed),
                      self.lyricsDiagnosticResult(attempt.result)]
            if case let .found(lyrics) = attempt.result {
                appendLyricsDetails(lyrics)
            }
            lines += attempt.events.map(self.lyricsDiagnosticEvent)
        }
        controller.lyricsSections = lyricsSections
        controller.report = lines.joined(separator: "\n")
    }

    private func lyricsDiagnosticResult(_ result: NextgramLyricsLookupResult) -> String {
        switch result {
        case .noMatch: return self.string("NoLyrics")
        case .unavailable: return self.string("DiagnosticsRequestFailed")
        case let .found(lyrics):
            if lyrics.instrumental { return self.string("Instrumental") }
            let timedWords = lyrics.lines.contains(where: { !$0.words.isEmpty })
            let format = self.string(timedWords ? "DiagnosticsWord" : (lyrics.isSynced ? "DiagnosticsLine" : "DiagnosticsPlain"))
            return String(format: self.string("DiagnosticsFound"), format, lyrics.lines.count)
        }
    }

    private func lyricsDiagnosticEvent(_ event: NextgramLyricsLookupEvent) -> String {
        switch event {
        case .invalidMetadata: return self.string("DiagnosticsMissingMetadata")
        case .memoryCache: return self.string("DiagnosticsMemoryCache")
        case .diskCache: return self.string("DiagnosticsDiskCache")
        case .noUsableLyrics: return self.string("DiagnosticsNoUsableLyrics")
        case .timingMismatch: return self.string("DiagnosticsTimingMismatch")
        case let .networkError(code): return String(format: self.string("DiagnosticsNetworkError"), code)
        case let .httpError(code): return "HTTP \(code)"
        case .invalidResponse: return self.string("SourceServiceError")
        case let .candidate(title, artist, duration, decision):
            let key: String
            switch decision {
            case .titleMismatch: key = "DiagnosticsTitleMismatch"
            case .artistMismatch: key = "DiagnosticsArtistMismatch"
            case .durationMismatch: key = "DiagnosticsDurationMismatch"
            case .match: key = "DiagnosticsCandidateMatch"
            }
            let seconds = duration.map { String(format: "%.1fs", $0) } ?? "—"
            return "• \(title.prefix(120)) / \(artist.prefix(120)) · \(seconds) · \(self.string(key))"
        }
    }

    private func lyricsSourceName(_ source: NextgramLyricsSource) -> String {
        self.string("Source." + source.rawValue)
    }

    private func makeLyricsSourceMenu() -> UIMenu {
        let automatic = UIAction(title: self.string("SourceAutomatic"), state: self.lyricsSourceOverride == nil ? .on : .off) { [weak self] _ in
            guard let self else { return }
            self.lyricsSourceOverride = nil
            if let id = self.trackId { self.lyricsSelections.removeValue(forKey: id) }
            self.reloadLyrics()
        }
        let options = self.settings.lyricsSources.map { source in
            let inUse = self.lyricsSourceOverride == nil && self.activeLyricsSource == source
            let title = self.lyricsSourceName(source) + (inUse ? " · " + self.string("SourceInUse") : "")
            return UIAction(title: title, state: self.lyricsSourceOverride == source ? .on : .off) { [weak self] _ in
                guard let self, self.settings.onlineLyricsEnabled else { return }
                self.lyricsSourceOverride = source
                if let id = self.trackId { self.lyricsSelections[id] = source }
                self.reloadLyrics()
            }
        }
        return UIMenu(title: self.string("SourceForTrack"), image: UIImage(systemName: "music.note.list"), options: .singleSelection, children: [automatic] + options)
    }

    private var lyricEffects: NagramLyricsEffects {
#if DEBUG && targetEnvironment(simulator)
        if let effects = self.previewLyricsEffects { return effects }
#endif
        return self.settings.lyricsEffects
    }

    private func updateLyricsView() {
        self.lyricsView.update(lyrics: self.lyrics, placeholder: self.lyricsPlaceholder.isEmpty ? self.string("NoLyrics") : self.lyricsPlaceholder,
            fontSize: CGFloat(self.settings.lyricsFontSize), color: self.foregroundColor, effects: self.lyricEffects, showsTranslation: self.settings.lyricsTranslation)
        self.lyricsView.updatePosition(self.currentPosition)
    }

    private var isCanvasPlayer: Bool {
#if DEBUG && targetEnvironment(simulator)
        return self.previewPlaying != nil
#else
        return false
#endif
    }

    private func updateMenu() {
        self.repeatIndicator.isHidden = self.state?.looping == nil || self.state?.looping == MusicPlaybackSettingsLooping.none
#if DEBUG && targetEnvironment(simulator)
        if self.previewPlaying != nil { self.repeatIndicator.isHidden = false }
#endif
        self.repeatIndicator.image = UIImage(systemName: self.state?.looping == .item ? "repeat.1" : "repeat",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.0, weight: .bold))
        let covers = NagramMusicPlayerCoverLayout.allCases.map { layout in
            UIAction(title: self.string("CoverLayout." + layout.rawValue), state: self.settings.coverLayout == layout ? .on : .off) { _ in
                NagramSettings.shared.musicPlayerCoverLayout = layout.rawValue
            }
        }
        let backgrounds = NagramMusicPlayerBackground.allCases.map { background in
            UIAction(title: self.string("Background." + background.rawValue), state: self.settings.background == background ? .on : .off) { _ in
                NagramSettings.shared.musicPlayerBackground = background.rawValue
            }
        }
        let colors = NagramMusicPlayerColors.allCases.map { color in
            UIAction(title: self.string("Colors." + color.rawValue), state: self.settings.colors == color ? .on : .off) { _ in
                NagramSettings.shared.musicPlayerColors = color.rawValue
            }
        }
        let enhancementModes = NagramMusicPlayerArtworkEnhancement.allCases.map { mode in
            UIAction(title: self.string("ArtworkEnhancement." + mode.rawValue), state: self.settings.artworkEnhancement == mode ? .on : .off) { _ in
                NagramSettings.shared.musicPlayerArtworkEnhancement = mode.rawValue
            }
        }
        let systemModes = [NextgramSystemMusicDisplay.always, .background, .never].map { mode in
            UIAction(title: self.string("SystemNowPlaying." + mode.rawValue),
                state: NagramSettings.shared.musicSystemNowPlaying == mode.rawValue ? .on : .off) { _ in
                NagramSettings.shared.musicSystemNowPlaying = mode.rawValue
            }
        }
        // Keep text-only options together so icon-bearing rows do not indent their titles.
        var actions: [UIMenuElement] = [UIMenu(options: .displayInline, children: [
            UIMenu(title: self.string("CoverLayout"), children: covers),
            UIAction(title: self.string("OnlineArtwork"), state: self.settings.onlineArtwork ? .on : .off) { _ in
                NagramSettings.shared.musicPlayerOnlineArtwork.toggle()
            },
            UIMenu(title: self.string("ArtworkEnhancement"), children: enhancementModes),
            UIMenu(title: self.string("Background"), children: backgrounds),
            UIMenu(title: self.string("Colors"), children: colors),
            UIMenu(title: self.string("SystemNowPlaying"), children: systemModes),
            UIAction(title: self.string(self.settings.showVolume ? "HideVolume" : "ShowVolume")) { _ in
                NagramSettings.shared.musicPlayerShowVolume.toggle()
            }
        ])]
        if let state = self.state {
            actions.append(UIMenu(options: .displayInline, children: [
                UIAction(title: self.string("Shuffle"), image: UIImage(systemName: "shuffle"), state: state.order == .random ? .on : .off) { [weak self] _ in self?.shufflePressed() },
                UIAction(title: self.string("Repeat"), image: UIImage(systemName: state.looping == .item ? "repeat.1" : "repeat"), state: state.looping == .none ? .off : .on) { [weak self] _ in self?.repeatPressed() }
            ]))
        }
        if self.settings.lyricsEnabled && (self.state != nil || self.isCanvasPlayer) {
            actions.append(UIAction(title: self.string("RetryLyrics"), image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
                guard let self, self.onlineTask == nil else { return }
                self.reloadLyrics(forceRefresh: true)
            })
        }
        if self.settings.lyricsEnabled && self.file != nil {
            actions.append(UIAction(title: self.string("ImportLyrics"), image: UIImage(systemName: "doc.badge.plus")) { [weak self] _ in self?.importLyrics() })
            actions.append(UIAction(title: self.string("RemoveLyrics"), image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                guard let self, let fileId = self.file?.media.fileId.id else { return }
                do {
                    try NextgramLyricsStore.remove(fileId: fileId)
                    if let id = self.trackId { self.lyricsMemory.removeValue(forKey: id) }
                    self.reloadLyrics(forceRefresh: true)
                } catch { self.showLyricsError() }
            })
        }
        if self.settings.lyricsEnabled && self.settings.onlineLyricsEnabled && (self.state != nil || self.isCanvasPlayer) {
            actions.append(self.makeLyricsSourceMenu())
        }
        if self.settings.lyricsEnabled && (self.state != nil || self.isCanvasPlayer) {
            actions.append(UIAction(title: self.string("Diagnostics"), image: UIImage(systemName: "waveform.path.ecg")) { [weak self] _ in
                self?.showLyricsDiagnostics()
            })
        }
        actions.append(UIAction(title: self.string("Settings"), image: UIImage(systemName: "slider.horizontal.3")) { [weak self] _ in self?.openSettings?() })
        self.menuButton.menu = UIMenu(children: actions)
    }

    private func importLyrics() {
        guard let fileId = self.file?.media.fileId.id else { return }
        let picker = legacyICloudFilePicker(theme: self.presentationData.theme, mode: .import, documentTypes: ["public.text", "public.data"], completion: { [weak self] urls in
            guard let url = urls.first else { return }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    let file = try FileHandle(forReadingFrom: url)
                    defer { try? file.close() }
                    let data = try file.read(upToCount: NextgramLyrics.maximumFileSize + 1) ?? Data()
                    guard data.count <= NextgramLyrics.maximumFileSize,
                          let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16),
                          NextgramLyrics.parse(text) != nil else {
                        DispatchQueue.main.async { self?.showLyricsError() }
                        return
                    }
                    try NextgramLyricsStore.save(text: text, fileId: fileId)
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.file?.media.fileId.id == fileId else { return }
                        self.lyricsSourceOverride = nil
                        if let id = self.trackId {
                            self.lyricsSelections.removeValue(forKey: id)
                            self.lyricsMemory.removeValue(forKey: id)
                        }
                        self.reloadLyrics(forceRefresh: true)
                    }
                } catch {
                    DispatchQueue.main.async { self?.showLyricsError() }
                }
            }
        })
        self.presentController?(picker)
    }

    private func showLyricsError() {
        guard let context = self.context else { return }
        self.presentController?(textAlertController(context: context, title: self.string("Lyrics"), text: self.string("LyricsFileInvalid"), actions: [
            TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_OK, action: {})
        ]))
    }

    private var playbackDuration: Double {
#if DEBUG && targetEnvironment(simulator)
        if self.previewPlaying != nil { return self.previewDuration }
#endif
        return self.state?.status.duration ?? 0
    }

    private func seek(_ time: Double) {
#if DEBUG && targetEnvironment(simulator)
        if self.previewPlaying != nil {
            self.previewClockPosition = min(self.previewDuration, max(0, time))
            self.previewClockStart = self.previewPlaying == true ? CACurrentMediaTime() : nil
            self.lyricsView.updatePosition(self.previewClockPosition, force: true)
            self.updatePosition()
            return
        }
#endif
        guard let duration = self.state?.status.duration, duration > 0.0 else { return }
        let position = min(duration, max(0.0, time))
        self.context?.sharedContext.mediaManager.playlistControl(.seek(position), type: .music)
        self.lyricsView.updatePosition(position, force: true)
    }

    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let pan = gestureRecognizer as? UIPanGestureRecognizer, gestureRecognizer !== self.dismissalPan,
           pan.view === self.artwork || pan.view === self.backgroundArtworkContainer {
            let velocity = pan.velocity(in: self)
            return self.active && self.artworkDetail == nil && !self.transitioningLyrics && self.coverDrag == nil && self.settings.swipeToSkip
                && !self.showingLyrics && abs(velocity.x) > abs(velocity.y)
        }
        guard gestureRecognizer === self.dismissalPan else { return true }
        guard self.active, self.artworkDetail == nil else { return false }
        let velocity = self.dismissalPan.velocity(in: self)
        return velocity.y > 0.0 && velocity.y > abs(velocity.x)
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === self.dismissalPan else { return true }
        if self.showingLyrics && self.lyricsView.frame.contains(touch.location(in: self)) {
            return false
        }
        var view = touch.view
        while let current = view, current !== self {
            if current is UIControl || current is MPVolumeView || current is UIScrollView {
                return false
            }
            view = current.superview
        }
        return true
    }

    @objc private func dismissalPanned(_ recognizer: UIPanGestureRecognizer) {
        let distance = max(0.0, recognizer.translation(in: self.superview).y)
        switch recognizer.state {
        case .began, .changed:
            self.transform = CGAffineTransform(translationX: 0.0, y: distance)
        case .ended:
            self.transform = CGAffineTransform(translationX: 0.0, y: distance)
            if (distance > 60.0 || recognizer.velocity(in: self.superview).y > 300.0), let dismiss = self.dismiss {
                self.isUserInteractionEnabled = false
                dismiss()
            } else {
                self.restoreDismissalPosition()
            }
        case .cancelled, .failed:
            self.restoreDismissalPosition()
        default:
            break
        }
    }

    private func restoreDismissalPosition() {
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.3,
            delay: 0.0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut], animations: {
                self.transform = .identity
            })
    }

    @objc private func closePressed() { self.dismiss?() }
    @objc private func queuePressed() { self.showQueue?() }
    @objc private func openArtworkDetail() {
        guard self.active, self.foreground, self.artworkDetail == nil else { return }
        if self.showingLyrics {
            self.lyricsPressed()
            return
        }
        guard let image = self.artwork.image ?? self.backgroundArtwork.image else { return }
        let detail = NextgramArtworkDetailView(image: image, title: self.trackTitle, artist: self.trackArtist,
            insets: self.safeInsets, motionEnabled: self.artworkMotionEnabled, showsMetadata: self.artworkMetadataVisible,
            closeLabel: self.presentationData.strings.Common_Close)
        detail.frame = self.bounds
        detail.close = { [weak self] in self?.closeArtworkDetail(animated: true) }
        self.artworkDetail = detail
        self.addSubview(detail)
        self.reloadDetailArtwork()
        detail.alpha = 0
        detail.transform = UIAccessibility.isReduceMotionEnabled ? .identity : CGAffineTransform(scaleX: 0.94, y: 0.94)
        self.updateArtworkMotion()
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.3,
            delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: {
                detail.alpha = 1
                detail.transform = .identity
            }, completion: { _ in UIAccessibility.post(notification: .screenChanged, argument: detail) })
    }

    private func reloadDetailArtwork() {
        self.detailArtworkDisposable?.dispose()
        self.detailArtworkDisposable = nil
        guard let detail = self.artworkDetail else { return }
        if let image = self.preferredOnlineArtwork ?? self.telegramArtwork {
            detail.updateImage(image)
        }
        if self.preferredOnlineArtwork == nil, let context = self.context {
            self.detailArtworkDisposable = (nextgramPlayerArtwork(engine: context.engine, fileReference: self.file,
                albumArt: self.albumArt, embeddedArtSize: 2048) |> deliverOnMainQueue).startStrict(next: { [weak detail] image in
                    if let image { detail?.updateImage(image) }
                })
        }
    }

    private func closeArtworkDetail(animated: Bool) {
        guard let detail = self.artworkDetail else { return }
        self.detailArtworkDisposable?.dispose()
        self.detailArtworkDisposable = nil
        self.artworkDetail = nil
        let completion: (Bool) -> Void = { [weak self, weak detail] _ in
            detail?.removeFromSuperview()
            self?.updateArtworkMotion()
            if let self, self.active { UIAccessibility.post(notification: .screenChanged, argument: self.artwork) }
        }
        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState, .curveEaseIn], animations: {
                detail.alpha = 0
                if !UIAccessibility.isReduceMotionEnabled { detail.transform = CGAffineTransform(scaleX: 0.94, y: 0.94) }
            }, completion: completion)
        } else { completion(true) }
    }

    private func updateArtworkMotion() {
        self.artwork.motionEnabled = false
        self.artwork.accessibilityLabel = self.showingLyrics ? self.string("CloseLyrics") : self.string("ArtworkDetails")
        self.artworkDetail?.updateMotionEnabled(self.artworkMotionEnabled)
    }

    private var artworkMotionEnabled: Bool {
#if DEBUG && targetEnvironment(simulator)
        if let enabled = self.previewArtworkMotion { return enabled }
#endif
        return self.settings.artworkMotion
    }

    private var artworkMetadataVisible: Bool {
#if DEBUG && targetEnvironment(simulator)
        if let visible = self.previewArtworkMetadata { return visible }
#endif
        return self.settings.artworkMetadata
    }
    @objc private func playPressed() {
#if DEBUG && targetEnvironment(simulator)
        if let previewPlaying = self.previewPlaying {
            self.previewClockPosition = self.currentPosition
            self.previewPlaying = !previewPlaying
            self.previewClockStart = !previewPlaying && self.previewAnimatedLyrics ? CACurrentMediaTime() : nil
            self.updateTransport()
            self.updateDisplayLink()
            return
        }
#endif
        self.context?.sharedContext.mediaManager.playlistControl(.playback(.togglePlayPause), type: .music)
    }
    @objc private func previousPressed() { self.context?.sharedContext.mediaManager.playlistControl(.previous, type: .music) }
    @objc private func nextPressed() { self.context?.sharedContext.mediaManager.playlistControl(.next, type: .music) }
    @objc private func lyricsPressed() {
        self.finishCoverDrag()
        self.layoutIfNeeded()
        self.transitioningLyrics = true
        self.showingLyrics.toggle()
        self.lyricsTransitionGeneration += 1
        let generation = self.lyricsTransitionGeneration
        let opening = self.showingLyrics
        if opening {
            self.lyricsView.isHidden = false
            UIView.performWithoutAnimation {
                self.lyricsView.layoutIfNeeded()
                self.lyricsView.updatePosition(self.currentPosition, force: true)
            }
        }
        self.updateDisplayLink()
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.42,
            delay: 0.0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.0,
            options: [.beginFromCurrentState, .allowUserInteraction], animations: {
                self.updateAppearance()
                self.layoutIfNeeded()
            }, completion: { _ in
                guard self.lyricsTransitionGeneration == generation else { return }
                self.transitioningLyrics = false
                if self.showingLyrics {
                    self.fullscreenBottomBlur?.removeFromSuperview()
                    self.fullscreenBottomBlur = nil
                }
                self.setNeedsLayout()
            })
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.12 : 0.22,
            delay: 0.0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut], animations: {
                self.fullscreenBottomBlur?.effect = opening ? nil : self.fullscreenBlurEffect
            })
        UIView.animate(withDuration: opening ? 0.2 : 0.08,
            delay: opening && !UIAccessibility.isReduceMotionEnabled ? 0.12 : 0.0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut], animations: {
                self.lyricsView.alpha = opening ? 1.0 : 0.0
            })
    }
    @objc private func shufflePressed() {
        guard let state = self.state, let context = self.context else { return }
        let order: MusicPlaybackSettingsOrder = state.order == .random ? .regular : .random
        let _ = updateMusicPlaybackSettingsInteractively(accountManager: context.sharedContext.accountManager, { $0.withUpdatedOrder(order) }).startStandalone()
        context.sharedContext.mediaManager.playlistControl(.setOrder(order), type: .music)
    }
    @objc private func repeatPressed() {
        guard let state = self.state, let context = self.context else { return }
        let looping: MusicPlaybackSettingsLooping
        switch state.looping {
        case .none: looping = .all
        case .all: looping = .item
        case .item: looping = .none
        }
        let _ = updateMusicPlaybackSettingsInteractively(accountManager: context.sharedContext.accountManager, { $0.withUpdatedLooping(looping) }).startStandalone()
        context.sharedContext.mediaManager.playlistControl(.setLooping(looping), type: .music)
    }
    @objc private func artworkPanned(_ pan: UIPanGestureRecognizer) {
        let offset = pan.translation(in: self).x
        switch pan.state {
        case .began:
            guard let surface = pan.view else { return }
            self.beginCoverDrag(surface: surface)
            self.updateCoverDrag(offset: offset)
        case .changed:
            self.updateCoverDrag(offset: offset)
        case .ended:
            guard let drag = self.coverDrag else { return }
            let velocity = pan.velocity(in: self).x
            let threshold = min(94.0, self.bounds.width * 0.23)
            let commits = abs(offset) > threshold || (abs(offset) > 16.0 && velocity * offset > 0.0 && abs(velocity) > 460.0)
            self.settleCoverDrag(drag, commit: commits && self.canSwitchCover(drag))
        case .cancelled, .failed:
            if let drag = self.coverDrag { self.settleCoverDrag(drag, commit: false) }
        default:
            break
        }
    }

    private func beginCoverDrag(surface: UIView) {
        guard self.coverDrag == nil, !surface.isHidden, let snapshot = surface.snapshotView(afterScreenUpdates: false) else { return }
        let drag = CoverDrag(surface: surface, trackId: self.trackId)
        drag.overlay.frame = surface.frame
        drag.overlay.isUserInteractionEnabled = false
        snapshot.frame = drag.overlay.bounds
        drag.overlay.addSubview(snapshot)
        drag.neighbor.contentMode = .scaleAspectFill
        drag.neighbor.backgroundColor = self.artworkColor
        drag.neighbor.clipsToBounds = true
        drag.neighbor.layer.cornerRadius = surface.layer.cornerRadius
        drag.neighbor.layer.cornerCurve = .continuous
        drag.neighbor.isHidden = true
        drag.overlay.addSubview(drag.neighbor)
        self.insertSubview(drag.overlay, aboveSubview: surface)
        surface.alpha = 0.0
        self.coverDrag = drag
    }

    private func updateCoverDrag(offset: CGFloat) {
        guard let drag = self.coverDrag, !drag.committed else { return }
        let direction: CGFloat = offset < 0.0 ? -1.0 : 1.0
        if drag.direction != direction {
            drag.direction = direction
            drag.artworkDisposable?.dispose()
            drag.neighborId = nil
            drag.neighbor.image = nil
            if let state = self.state, state.order != .random, let context = self.context {
                let earlier = (direction < 0.0) == (state.order == .regular)
                if let item = earlier ? state.previousItem : state.nextItem {
                    drag.neighborId = item.stableId
                    var file: FileMediaReference?
                    if case let .telegramFile(reference, _, _)? = item.playbackData?.source { file = reference }
                    var albumArt: SharedMediaPlaybackAlbumArt?
                    if case let .music(_, _, art, _, _)? = item.displayData { albumArt = art }
                    drag.artworkDisposable = (nextgramPlayerArtwork(engine: context.engine, fileReference: file, albumArt: albumArt)
                    |> deliverOnMainQueue).startStrict(next: { [weak drag] image in
                        if let image { drag?.neighbor.image = image }
                    })
                }
            }
#if DEBUG && targetEnvironment(simulator)
            if self.previewPlaying != nil { drag.neighbor.image = self.originalArtwork }
#endif
            let stride = self.bounds.width
            drag.neighbor.frame = drag.overlay.bounds.offsetBy(dx: -direction * stride, dy: 0.0)
            drag.neighbor.isHidden = !self.canSwitchCover(drag)
        }
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let distance = min(self.bounds.width, abs(offset))
        let translation = self.canSwitchCover(drag) ? distance : min(32.0, distance * 0.20)
        drag.overlay.transform = CGAffineTransform(translationX: direction * translation, y: 0.0)
        if drag.surface === self.artwork {
            self.artworkShadow.transform = drag.overlay.transform
        }
    }

    private func canSwitchCover(_ drag: CoverDrag) -> Bool {
#if DEBUG && targetEnvironment(simulator)
        if self.previewPlaying != nil { return true }
#endif
        guard let state = self.state, self.trackId == drag.trackId else { return false }
        return drag.neighborId != nil || state.order == .random || state.looping == .all
    }

    private func settleCoverDrag(_ drag: CoverDrag, commit: Bool) {
        drag.committed = commit
        let reduced = UIAccessibility.isReduceMotionEnabled
        let target = commit && !reduced ? drag.direction * self.bounds.width : 0.0
        UIView.animate(withDuration: reduced ? 0.0 : (commit ? 0.23 : 0.30),
            delay: 0.0, usingSpringWithDamping: commit ? 1.0 : 0.85, initialSpringVelocity: 0.0,
            options: [.beginFromCurrentState, .allowUserInteraction], animations: {
                drag.overlay.transform = CGAffineTransform(translationX: target, y: 0.0)
                if drag.surface === self.artwork {
                    self.artworkShadow.transform = drag.overlay.transform
                }
            }, completion: { [weak self, weak drag] _ in
                guard let self, let drag, self.coverDrag === drag else { return }
                drag.settled = true
                if !commit || self.trackId != drag.trackId || self.isCanvasPlayer {
                    self.finishCoverDrag()
                }
            })
        if commit && !self.isCanvasPlayer {
            self.context?.sharedContext.mediaManager.playlistControl(drag.direction < 0.0 ? .next : .previousTrack, type: .music)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self, weak drag] in
                guard let self, let drag, self.coverDrag === drag else { return }
                self.settleCoverDrag(drag, commit: false)
            }
        }
    }

    private func finishCoverDrag() {
        guard let drag = self.coverDrag else { return }
        self.coverDrag = nil
        drag.overlay.removeFromSuperview()
        drag.surface.alpha = 1.0
        self.artworkShadow.transform = .identity
    }

#if DEBUG && targetEnvironment(simulator)
    private func animateCoverSwipe(direction: CGFloat) {
        self.beginCoverDrag(surface: self.settings.coverLayout == .fullscreen && !self.showingLyrics ? self.backgroundArtworkContainer : self.artwork)
        guard let drag = self.coverDrag else { return }
        self.updateCoverDrag(offset: direction * self.bounds.width * 0.22)
        self.settleCoverDrag(drag, commit: true)
    }
#endif
    @objc private func didEnterBackground() {
        self.foreground = false
        self.finishCoverDrag()
        self.onlineArtworkTask?.cancel()
        self.onlineArtworkTask = nil
        self.closeArtworkDetail(animated: false)
        self.cancelLyrics()
        self.updateDisplayLink()
    }
    @objc private func didBecomeActive() {
        self.foreground = true
        self.refreshOnlineArtwork()
        self.updateDisplayLink()
        self.updatePosition()
        if self.active && self.lyrics == nil { self.reloadLyrics() }
    }
    @objc private func accessibilityChanged() { self.updateAppearance() }
}

#if DEBUG && targetEnvironment(simulator)
public extension NextgramMusicPlayerView {
    /// Local presentation controls for recording this account-free preview host.
    func performCanvasAction(_ action: String) {
        guard self.previewPlaying != nil else { return }
        if action.hasPrefix("cover:"), let layout = NagramMusicPlayerCoverLayout(rawValue: String(action.dropFirst(6))) {
            NagramSettings.shared.musicPlayerCoverLayout = layout.rawValue
            return
        }
        if action.hasPrefix("background:"), let background = NagramMusicPlayerBackground(rawValue: String(action.dropFirst(11))) {
            NagramSettings.shared.musicPlayerBackground = background.rawValue
            return
        }
        if action.hasPrefix("enhancement:"), let mode = NagramMusicPlayerArtworkEnhancement(rawValue: String(action.dropFirst("enhancement:".count))) {
            NagramSettings.shared.musicPlayerArtworkEnhancement = mode.rawValue
            return
        }
        if action.hasPrefix("progress-stretch:"), let distance = Double(action.dropFirst(17)) {
            self.positionSlider.previewEdgeStretch(CGFloat(distance))
            return
        }
        if action.hasPrefix("artwork-tilt:"), let angle = Double(action.dropFirst("artwork-tilt:".count)) {
            self.artworkDetail?.previewDeviceTilt(x: CGFloat(angle), y: CGFloat(angle) * 0.65)
            return
        }
        switch action {
        case "progress-start": self.seek(0.0)
        case "progress-end": self.seek(self.previewDuration)
        case "progress-release": self.positionSlider.previewEdgeStretch(nil)
        case "volume-toggle": NagramSettings.shared.musicPlayerShowVolume.toggle()
        case "cover-swipe-left": self.animateCoverSwipe(direction: -1.0)
        case "cover-swipe-right": self.animateCoverSwipe(direction: 1.0)
        case "lyrics-seek": self.lyricsView.previewSeekVisibleLine()
        case "effects-on": self.setCanvasLyricsEffects(enabled: true)
        case "effects-off": self.setCanvasLyricsEffects(enabled: false)
        case "playback": self.playPressed()
        case "lyrics": self.lyricsPressed()
        case "artwork": self.openArtworkDetail()
        case "artwork-close": self.closeArtworkDetail(animated: true)
        case "artwork-top-left": self.artworkDetail?.previewPressure(at: CGPoint(x: 0.1, y: 0.1))
        case "artwork-bottom-right": self.artworkDetail?.previewPressure(at: CGPoint(x: 0.9, y: 0.9))
        case "artwork-top-right": self.artworkDetail?.previewPressure(at: CGPoint(x: 0.9, y: 0.1))
        case "artwork-bottom-left": self.artworkDetail?.previewPressure(at: CGPoint(x: 0.1, y: 0.9))
        case "artwork-release": self.artworkDetail?.previewPressure(at: nil)
        case "artwork-center": self.artworkDetail?.previewPressure(at: CGPoint(x: 0.5, y: 0.5))
        case "artwork-main-press": self.artwork.setPressure(at: CGPoint(x: 0.1, y: 0.1), animated: true)
        case "artwork-metadata-on":
            self.previewArtworkMetadata = true
            self.artworkDetail?.updateMetadataVisibility(true)
        case "artwork-metadata-off":
            self.previewArtworkMetadata = false
            self.artworkDetail?.updateMetadataVisibility(false)
        default: break
        }
    }

    static func makeCanvasPreview(coverImage: UIImage, showingLyrics: Bool, playing: Bool = true,
        allLyricsEffects: Bool = false, animatedLyrics: Bool = false, interludePreview: Bool = false,
        artworkMotionPreview: Bool? = nil, artworkMetadataPreview: Bool? = nil) -> NextgramMusicPlayerView {
        let view = NextgramMusicPlayerView(context: nil, presentationData: defaultPresentationData())
        let cover = coverImage
        view.trackTitle = "Blue Dream"
        view.trackArtist = "ARU / 存流"
        view.titleLabel.text = view.trackTitle
        view.artistLabel.text = view.trackArtist
        view.telegramArtwork = cover
        view.setOriginalArtwork(cover)
        view.artworkColor = NextgramPlayerPalette.artworkColor(cover)
        view.showingLyrics = showingLyrics
        view.previewDuration = 194.493
        view.previewPlaying = playing
        view.previewArtworkMotion = artworkMotionPreview
        view.previewArtworkMetadata = artworkMetadataPreview
        view.previewLyricsEffects = allLyricsEffects ? NagramLyricsEffects.allEnabled : NagramLyricsEffects.none
        view.previewAnimatedLyrics = animatedLyrics || allLyricsEffects
        view.active = true
        view.isSavedMusic = true
        view.toggleSavedMusic = { [weak view] in
            guard let view else { return }
            view.isSavedMusic = !(view.isSavedMusic ?? false)
        }
        view.lyrics = NextgramLyrics(lines: [
            NextgramLyricLine(time: 0.0, text: "窗外的灯光渐渐远去"),
            NextgramLyricLine(time: 30.0, text: "让音乐陪着夜色前行"),
            NextgramLyricLine(time: 60.0, text: "这是本地 Canvas 歌词样例"),
            NextgramLyricLine(time: 90.0, text: "在这里检查播放器的布局")
        ], isSynced: true)
        if view.previewAnimatedLyrics {
            // Original sample text with real TTML word timings; never synthesise timings for user songs.
            let text = """
            <tt xmlns="http://www.w3.org/ns/ttml"><body><div>
            <p begin="66s" end="70s"><span begin="66s" end="67s">留住</span><span begin="67s" end="68s">这一刻</span><span begin="68s" end="70s">的光</span></p>
            <p begin="70s" end="74s"><span begin="70.000s" end="70.444s">让</span><span begin="70.444s" end="70.889s">音</span><span begin="70.889s" end="71.333s">乐</span><span begin="71.333s" end="71.778s">陪</span><span begin="71.778s" end="72.222s">着</span><span begin="72.222s" end="72.667s">夜</span><span begin="72.667s" end="73.111s">色</span><span begin="73.111s" end="73.556s">前</span><span begin="73.556s" end="74.000s">行</span></p>
            <p begin="74s" end="78s"><span begin="74s" end="74.6s">Every </span><span begin="74.6s" end="75.3s">light </span><span begin="75.3s" end="75.7s">is </span><span begin="75.7s" end="76.5s">taking </span><span begin="76.5s" end="77s">us </span><span begin="77s" end="78s">home</span></p>
            <p begin="80s" end="85s"><span begin="80.000s" end="80.417s">把</span><span begin="80.417s" end="80.833s">未</span><span begin="80.833s" end="81.250s">唱</span><span begin="81.250s" end="81.667s">完</span><span begin="81.667s" end="82.083s">的</span><span begin="82.083s" end="82.500s">梦</span><span begin="82.500s" end="82.917s">慢</span><span begin="82.917s" end="83.333s">慢</span><span begin="83.333s" end="83.750s">唱</span><span begin="83.750s" end="84.167s">给</span><span begin="84.167s" end="84.583s">你</span><span begin="84.583s" end="85.000s">听</span></p>
            <p begin="85s" end="89s"><span begin="85s" end="86.3s">等</span><span begin="86.3s" end="87.5s">下一次</span><span begin="87.5s" end="89s">黎明</span></p>
            <p begin="89s" end="93s"><span begin="89s" end="90s">把这首歌</span><span begin="90s" end="91.4s">留在</span><span begin="91.4s" end="93s">心里</span></p>
            </div></body></tt>
            """
            guard let sample = NextgramLyrics.parse(text) else { preconditionFailure("Invalid timed Canvas lyric fixture") }
            var lines = sample.lines
            lines.insert(NextgramLyricLine(time: 78.0, text: ""), at: 3)
            view.lyrics = NextgramLyrics(lines: lines, isSynced: true)
        }
        if interludePreview {
            view.lyrics = NextgramLyrics(lines: [
                NextgramLyricLine(time: 66.0, text: "留住这一刻的光"),
                NextgramLyricLine(time: 70.0, text: ""),
                NextgramLyricLine(time: 78.0, text: "让音乐陪着夜色前行"),
                NextgramLyricLine(time: 82.0, text: "把未唱完的梦慢慢唱给你听")
            ], isSynced: true)
        }
        if CommandLine.arguments.contains("--canvas-plain-lyrics") {
            let middle = (2 ... 16).map { "第\($0)行：夜里的灯光" }
            view.lyrics = NextgramLyrics.parse((["第一行：在这里开始"] + middle + ["最后一行：在这里结束"]).joined(separator: "\n"))
            view.showingLyrics = true
        }
        view.previewSampleLyrics = view.lyrics
        view.updateAppearance()
        view.lyricsButton.isHidden = false
        view.updateTransport()
        view.repeatIndicator.isHidden = false
        view.repeatIndicator.image = UIImage(systemName: "repeat", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.0, weight: .bold))
        view.volumeView.showPreviewSlider()
        for button in [view.previousButton, view.playButton, view.nextButton] { button.isEnabled = true }
        view.positionSlider.isEnabled = true
        view.positionSlider.value = 0.35
        view.elapsedLabel.text = "1:10"
        view.remainingLabel.text = "−2:04"
        view.lyricsView.updatePosition(70.0, force: true)
        view.updateDisplayLink()
        return view
    }
}
#endif

#if DEBUG && targetEnvironment(simulator)
public extension NextgramMusicPlayerView {
    /// The interactive host keeps saved choices; named comparison fixtures retain their explicit effects.
    func useCanvasSettings() {
        guard self.previewPlaying != nil else { return }
        self.previewLyricsEffects = nil
        self.previewArtworkMotion = nil
        self.previewArtworkMetadata = nil
        self.updateAppearance()
        self.refreshOnlineArtwork()
    }

    func presentCanvasSettings(from host: UIViewController) {
        guard self.previewPlaying != nil else { return }
        let settings = NagramSettings.shared
        func title(_ key: String) -> String { self.string(key) }
        let changed: () -> Void = { [weak self] in
            guard let self else { return }
            self.previewLyricsEffects = nil
            self.previewArtworkMotion = nil
            self.previewArtworkMetadata = nil
            // The regular settings signal drives the same layout/effect update as the real app.
        }
        var sections: [(String, [NextgramCanvasSettingsController.Row])] = []
        sections.append(("封面", [
            .choice(title("CoverLayout"), NagramMusicPlayerCoverLayout.allCases.map { ($0.rawValue, title("CoverLayout." + $0.rawValue)) },
                { settings.musicPlayerCoverLayout }, { settings.musicPlayerCoverLayout = $0 }),
            .toggle(title("SmartArtworkCrop"), { settings.musicPlayerSmartArtworkCrop }, { settings.musicPlayerSmartArtworkCrop = $0 }),
            .toggle(title("OnlineArtwork"), { settings.musicPlayerOnlineArtwork }, { settings.musicPlayerOnlineArtwork = $0 }),
            .choice(title("ArtworkEnhancement"), NagramMusicPlayerArtworkEnhancement.allCases.map { ($0.rawValue, title("ArtworkEnhancement." + $0.rawValue)) },
                { settings.musicPlayerArtworkEnhancementValue.rawValue }, { settings.musicPlayerArtworkEnhancement = $0 }),
            .number(title("CoverSize"), 60...100, { settings.musicPlayerCoverSize }, { settings.musicPlayerCoverSize = $0 }),
            .number(title("PausedCoverSize"), 60...100, { settings.musicPlayerPausedCoverSize }, { settings.musicPlayerPausedCoverSize = $0 }),
            .number(title("CoverCornerRadius"), 0...48, { settings.musicPlayerCoverCornerRadius }, { settings.musicPlayerCoverCornerRadius = $0 }),
            .toggle(title("DiscRotation"), { settings.musicPlayerDiscRotation }, { settings.musicPlayerDiscRotation = $0 }),
            .toggle(title("SwipeToSkip"), { settings.musicPlayerSwipeToSkip }, { settings.musicPlayerSwipeToSkip = $0 }),
            .toggle(title("ArtworkMotion"), { settings.musicPlayerArtworkMotion }, { settings.musicPlayerArtworkMotion = $0 }),
            .toggle(title("ArtworkMetadata"), { settings.musicPlayerArtworkMetadata }, { settings.musicPlayerArtworkMetadata = $0 })
        ]))
        sections.append(("背景与配色", [
            .choice(title("Background"), NagramMusicPlayerBackground.allCases.map { ($0.rawValue, title("Background." + $0.rawValue)) },
                { settings.musicPlayerBackgroundValue.rawValue }, { settings.musicPlayerBackground = $0 }),
            .choice(title("Colors"), NagramMusicPlayerColors.allCases.map { ($0.rawValue, title("Colors." + $0.rawValue)) },
                { settings.musicPlayerColors }, { settings.musicPlayerColors = $0 }),
            .text(title("CustomColor"), { settings.musicPlayerCustomColor }, { settings.musicPlayerCustomColor = $0 }),
            .number(title("BlurIntensity"), 0...60, { settings.musicPlayerBlurIntensity }, { settings.musicPlayerBlurIntensity = $0 }),
            .choice(title("FullscreenBlurHeight"), NagramMusicPlayerFullscreenBlurHeight.allCases.map { ($0.rawValue, title("FullscreenBlurHeight." + $0.rawValue)) },
                { settings.musicPlayerFullscreenBlurHeightValue.rawValue }, { settings.musicPlayerFullscreenBlurHeight = $0 }),
            .number(title("FullscreenBlurPercent"), 10...50, { settings.musicPlayerFullscreenBlurPercentValue }, {
                settings.musicPlayerFullscreenBlurPercent = $0
                settings.musicPlayerFullscreenBlurHeight = NagramMusicPlayerFullscreenBlurHeight.custom.rawValue
            })
        ]))
        sections.append(("播放界面", [
            .toggle(title("ShowVolume"), { settings.musicPlayerShowVolume }, { settings.musicPlayerShowVolume = $0 }),
            .toggle(title("ElasticProgress"), { settings.musicPlayerElasticProgress }, { settings.musicPlayerElasticProgress = $0 }),
            .toggle(title("ElasticVolume"), { settings.musicPlayerElasticVolume }, { settings.musicPlayerElasticVolume = $0 }),
            .toggle(title("TapToSeek"), { settings.musicPlayerTapToSeek }, { settings.musicPlayerTapToSeek = $0 }),
            .toggle(title("ShowRemainingTime"), { settings.musicPlayerShowRemainingTime }, { settings.musicPlayerShowRemainingTime = $0 }),
            .choice(title("TitleAlignment"), [("left", "左对齐"), ("center", "居中")],
                { settings.musicPlayerTitleAlignment }, { settings.musicPlayerTitleAlignment = $0 }),
            .number(title("TitleFontSize"), 20...32, { settings.musicPlayerTitleFontSize }, { settings.musicPlayerTitleFontSize = $0 }),
            .number(title("ControlScale"), 80...120, { settings.musicPlayerControlScale }, { settings.musicPlayerControlScale = $0 })
        ]))
        sections.append(("歌词来源", [
            .toggle(title("Lyrics"), { settings.musicPlayerLyricsEnabled }, { settings.musicPlayerLyricsEnabled = $0 }),
            .toggle(title("LyricsTranslation"), { settings.musicPlayerLyricsTranslation }, { settings.musicPlayerLyricsTranslation = $0 }),
            .toggle(title("OnlineLyrics"), { settings.musicPlayerOnlineLyricsEnabled }, { settings.musicPlayerOnlineLyricsEnabled = $0 }),
            .choice("优先来源", NextgramLyricsSource.allCases.map { ($0.rawValue, self.lyricsSourceName($0)) },
                { self.settings.lyricsSources.first?.rawValue ?? "qqMusic" }, { source in
                    settings.musicPlayerLyricsSourceOrder = ([source] + NextgramLyricsSource.allCases.map(\.rawValue).filter { $0 != source }).joined(separator: ",")
                }),
            .action("输入歌曲信息，测试在线来源…", { [weak self, weak host] in
                guard let self, let host else { return }
                host.dismiss(animated: true) { self.canvasLookupSong(from: host) }
            }),
            .action("恢复本地逐字歌词样例", { [weak self] in self?.restoreCanvasLyrics() }),
            .number(title("LyricsFontSize"), 20...40, { settings.musicPlayerLyricsFontSize }, { settings.musicPlayerLyricsFontSize = $0 })
        ]))
        sections.append(("Apple Music 歌词动效", [
            .action("开启全部动效（弹性滚动）", { [weak self] in self?.setCanvasLyricsEffects(enabled: true) }),
            .action("恢复原有歌词样式", { [weak self] in self?.setCanvasLyricsEffects(enabled: false) }),
            .toggle(title("LyricsWordHighlight"), { settings.musicPlayerLyricsWordHighlight }, { settings.musicPlayerLyricsWordHighlight = $0 }),
            .toggle(title("LyricsWordFloat"), { settings.musicPlayerLyricsWordFloat }, { settings.musicPlayerLyricsWordFloat = $0 }),
            .toggle(title("LyricsGlow"), { settings.musicPlayerLyricsGlow }, { settings.musicPlayerLyricsGlow = $0 }),
            .toggle(title("LyricsBlur"), { settings.musicPlayerLyricsBlur }, { settings.musicPlayerLyricsBlur = $0 }),
            .toggle(title("LyricsLayeredBlur"), { settings.musicPlayerLyricsLayeredBlur }, { settings.musicPlayerLyricsLayeredBlur = $0 }),
            .toggle(title("LyricsScale"), { settings.musicPlayerLyricsScale }, { settings.musicPlayerLyricsScale = $0 }),
            .toggle(title("LyricsSpringScroll"), { settings.musicPlayerLyricsSpringScroll }, {
                settings.musicPlayerLyricsSpringScroll = $0
                if $0 { settings.musicPlayerLyricsLinearScroll = false }
            }),
            .toggle(title("LyricsLinearScroll"), { settings.musicPlayerLyricsLinearScroll }, {
                settings.musicPlayerLyricsLinearScroll = $0
                if $0 { settings.musicPlayerLyricsSpringScroll = false }
            }),
            .toggle(title("LyricsStagger"), { settings.musicPlayerLyricsStagger }, { settings.musicPlayerLyricsStagger = $0 }),
            .toggle(title("LyricsInterlude"), { settings.musicPlayerLyricsInterlude }, { settings.musicPlayerLyricsInterlude = $0 }),
            .toggle(title("LyricsEdgeFade"), { settings.musicPlayerLyricsEdgeFade }, { settings.musicPlayerLyricsEdgeFade = $0 })
        ]))
        sections.append(("", [.action(title("Reset"), { settings.resetMusicPlayerSettings() })]))
        let panel = NextgramCanvasSettingsController(sections: sections, changed: changed)
        let navigation = UINavigationController(rootViewController: panel)
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        host.present(navigation, animated: true)
    }

    private func setCanvasLyricsEffects(enabled: Bool) {
        self.previewLyricsEffects = nil
        let settings = NagramSettings.shared
        settings.musicPlayerLyricsWordHighlight = enabled
        settings.musicPlayerLyricsWordFloat = enabled
        settings.musicPlayerLyricsGlow = enabled
        settings.musicPlayerLyricsBlur = enabled
        settings.musicPlayerLyricsLayeredBlur = enabled
        settings.musicPlayerLyricsScale = enabled
        settings.musicPlayerLyricsSpringScroll = enabled
        settings.musicPlayerLyricsLinearScroll = false
        settings.musicPlayerLyricsStagger = enabled
        settings.musicPlayerLyricsInterlude = enabled
        settings.musicPlayerLyricsEdgeFade = enabled
    }

    private func restoreCanvasLyrics() {
        self.cancelLyrics()
        self.previewOnlineLyrics = false
        self.trackId = nil
        self.trackTitle = "Blue Dream"
        self.trackArtist = "ARU / 存流"
        self.titleLabel.text = self.trackTitle
        self.artistLabel.text = self.trackArtist
        self.previewDuration = 194.493
        self.previewClockPosition = 70
        self.previewClockStart = self.previewPlaying == true ? CACurrentMediaTime() : nil
        self.previewAnimatedLyrics = true
        self.lyricsSourceOverride = nil
        self.activeLyricsSource = nil
        self.localLyricsOrigin = nil
        self.reusedPlayerLyrics = false
        self.lyricsAttempts = []
        self.lyrics = self.previewSampleLyrics
        self.onlineArtwork = nil
        self.applyAvailableArtwork()
        self.refreshOnlineArtwork()
        self.updateLyricsView()
        self.updateMenu()
        self.updateDisplayLink()
    }

    func performCanvasLyricsLookup(title: String, artist: String, duration: Double, source: String? = nil, forceRefresh: Bool = true) {
        guard self.previewPlaying != nil, !title.isEmpty, !artist.isEmpty, duration.isFinite, duration > 0, duration < 86400 else { return }
        self.cancelLyrics()
        self.previewOnlineLyrics = true
        self.previewAnimatedLyrics = true
        self.previewDuration = duration
        self.previewClockPosition = 0
        self.previewClockStart = self.previewPlaying == true ? CACurrentMediaTime() : nil
        self.trackTitle = title
        self.trackArtist = artist
        self.titleLabel.text = title
        self.artistLabel.text = artist
        self.trackId = AnyHashable("canvas:\(title):\(artist):\(duration)")
        self.lyricsSourceOverride = source.flatMap(NextgramLyricsSource.init(rawValue:))
        NagramSettings.shared.musicPlayerLyricsEnabled = true
        NagramSettings.shared.musicPlayerOnlineLyricsEnabled = true
        self.settings = NagramMusicPlayerSettings()
        self.showingLyrics = true
        self.onlineArtwork = nil
        self.applyAvailableArtwork()
        self.refreshOnlineArtwork()
        self.reloadLyrics(forceRefresh: forceRefresh)
        self.updateAppearance()
        self.updateDisplayLink()
    }

    private func canvasLookupSong(from host: UIViewController) {
        let alert = UIAlertController(title: "在线歌词测试", message: "填写真实歌曲标签及总时长（秒）。仅查询歌词，不播放该歌曲。来源可在播放器“…”中切换。", preferredStyle: .alert)
        for (placeholder, value) in [("歌曲名称", "Blue Dream"), ("艺术家", "ARU"), ("总时长（秒）", "194")] {
            alert.addTextField { field in field.placeholder = placeholder; field.text = value }
        }
        alert.textFields?.last?.keyboardType = .decimalPad
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "获取歌词", style: .default) { [weak self, weak host, weak alert] _ in
            guard let self, let fields = alert?.textFields else { return }
            let title = (fields[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = (fields[1].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !artist.isEmpty, let duration = Double(fields[2].text ?? ""),
                  duration.isFinite, duration > 0, duration < 86400 else {
                let error = UIAlertController(title: "请填写完整的歌曲信息", message: "名称与艺术家不能为空，时长应为有效秒数。", preferredStyle: .alert)
                error.addAction(UIAlertAction(title: "好", style: .default))
                host?.present(error, animated: true)
                return
            }
            self.performCanvasLyricsLookup(title: title, artist: artist, duration: duration)
        })
        host.present(alert, animated: true)
    }
}

private final class NextgramCanvasSettingsController: UITableViewController {
    enum Row {
        case toggle(String, () -> Bool, (Bool) -> Void)
        case choice(String, [(String, String)], () -> String, (String) -> Void)
        case number(String, ClosedRange<Int32>, () -> Int32, (Int32) -> Void)
        case text(String, () -> String, (String) -> Void)
        case action(String, () -> Void)

        var title: String {
            switch self {
            case let .toggle(title, _, _), let .choice(title, _, _, _), let .number(title, _, _, _),
                 let .text(title, _, _), let .action(title, _): return title
            }
        }
    }
    private let sections: [(String, [Row])]
    private let changed: () -> Void

    init(sections: [(String, [Row])], changed: @escaping () -> Void) {
        self.sections = sections
        self.changed = changed
        super.init(style: .insetGrouped)
        self.title = "播放器演示设置"
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(close))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func close() { self.dismiss(animated: true) }
    override func numberOfSections(in tableView: UITableView) -> Int { self.sections.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { self.sections[section].1.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { self.sections[section].0 }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 3 ? "本地样例无需网络。在线测试使用与主 App 相同的请求、匹配和缓存；设置只保存在独立演示环境。" : nil
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = self.sections[indexPath.section].1[indexPath.row]
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = row.title
        cell.textLabel?.numberOfLines = 0
        switch row {
        case let .toggle(_, get, set):
            let control = UISwitch()
            control.isOn = get()
            control.addAction(UIAction { [weak self, weak control] _ in
                guard let self, let control else { return }
                self.changed(); set(control.isOn); self.tableView.reloadData()
            }, for: .valueChanged)
            cell.accessoryView = control
            cell.selectionStyle = .none
        case let .choice(_, options, get, _):
            cell.detailTextLabel?.text = options.first { $0.0 == get() }?.1
            cell.accessoryType = .disclosureIndicator
        case let .number(_, _, get, _): cell.detailTextLabel?.text = String(get()); cell.accessoryType = .disclosureIndicator
        case let .text(_, get, _): cell.detailTextLabel?.text = get(); cell.accessoryType = .disclosureIndicator
        case .action: cell.textLabel?.textColor = .systemBlue
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = self.sections[indexPath.section].1[indexPath.row]
        switch row {
        case .toggle: break
        case let .action(_, action): action(); self.tableView.reloadData()
        case let .choice(title, options, get, set):
            let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
            for (value, label) in options {
                alert.addAction(UIAlertAction(title: (get() == value ? "✓ " : "") + label, style: .default) { [weak self] _ in
                    self?.changed(); set(value); self?.tableView.reloadData()
                })
            }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
            self.present(alert, animated: true)
        case let .number(title, range, get, set):
            self.input(title: title, value: String(get()), hint: "\(range.lowerBound)–\(range.upperBound)", numeric: true) { text in
                guard let value = Int32(text), range.contains(value) else { return false }
                set(value); return true
            }
        case let .text(title, get, set):
            self.input(title: title, value: get(), hint: "#RRGGBB", numeric: false) { text in
                guard text.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil else { return false }
                set(text); return true
            }
        }
    }
    private func input(title: String, value: String, hint: String, numeric: Bool, save: @escaping (String) -> Bool) {
        let alert = UIAlertController(title: title, message: hint, preferredStyle: .alert)
        alert.addTextField { field in field.text = value; field.keyboardType = numeric ? .numberPad : .asciiCapable }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            self.changed()
            if save(alert?.textFields?.first?.text ?? "") { self.tableView.reloadData() }
            else {
                let error = UIAlertController(title: "请输入有效值", message: hint, preferredStyle: .alert)
                error.addAction(UIAlertAction(title: "好", style: .default))
                self.present(error, animated: true)
            }
        })
        self.present(alert, animated: true)
    }
}
#endif
