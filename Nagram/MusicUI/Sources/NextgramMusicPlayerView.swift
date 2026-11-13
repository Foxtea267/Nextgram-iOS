import AccountContext
import AsyncDisplayKit
import AVKit
import Display
import EdgeEffect
import Foundation
import LegacyMediaPickerUI
import MediaPlayer
import NagramSettings
import NagramSettingsSignal
import NagramStrings
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
public final class NextgramMusicPlayerView: UIView {
    public var dismiss: (() -> Void)?
    public var showQueue: (() -> Void)?
    public var openSettings: (() -> Void)?
    public var presentController: ((ViewController) -> Void)?

    private let context: AccountContext
    private var settings = NagramMusicPlayerSettings()
    private var presentationData: PresentationData
    private var settingsDisposable: Disposable?
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

    private let backgroundArtwork = UIImageView()
    private let shade = UIView()
    private var blur: VariableBlurView?
    private let artworkNode = TransformImageNode()
    private let artwork = UIImageView()
    private let discHole = UIView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let headerLabel = UILabel()
    private let elapsedLabel = UILabel()
    private let remainingLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let menuButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let shuffleButton = UIButton(type: .system)
    private let repeatButton = UIButton(type: .system)
    private let lyricsButton = UIButton(type: .system)
    private let queueButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let positionSlider = UISlider()
    private let volumeView = MPVolumeView()
    private let routePicker = AVRoutePickerView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let lyricsView = NextgramLyricsView()
    private let sourceLabel = UILabel()
    private var lyrics: NextgramLyrics?
    private var lyricsPlaceholder = ""
    private var lyricsRequest = UUID()
    private var onlineTask: URLSessionDataTask?
    private let embeddedLoader = NextgramEmbeddedLyricsLoader()
    private var embeddedLyricsFound = false
    private let displayLinkTarget = NextgramPlayerDisplayLinkTarget()
    private var displayLink: CADisplayLink?

    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(frame: .zero)

        self.clipsToBounds = true
        self.backgroundColor = UIColor(white: 0.09, alpha: 1.0)
        self.overrideUserInterfaceStyle = .dark
        self.backgroundArtwork.contentMode = .scaleAspectFill
        self.backgroundArtwork.clipsToBounds = true
        self.backgroundArtwork.isUserInteractionEnabled = false
        self.addSubview(self.backgroundArtwork)
        self.shade.isUserInteractionEnabled = false
        self.addSubview(self.shade)
        self.artwork.contentMode = .scaleAspectFill
        self.artwork.clipsToBounds = true
        self.artwork.layer.cornerCurve = .continuous
        self.artwork.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
        self.addSubview(self.artwork)
        self.discHole.backgroundColor = UIColor(white: 0.08, alpha: 0.9)
        self.discHole.layer.borderWidth = 4.0
        self.discHole.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        self.artwork.addSubview(self.discHole)
        self.artwork.isUserInteractionEnabled = true
        let nextGesture = UISwipeGestureRecognizer(target: self, action: #selector(self.artworkSwiped(_:)))
        nextGesture.direction = .left
        self.artwork.addGestureRecognizer(nextGesture)
        let previousGesture = UISwipeGestureRecognizer(target: self, action: #selector(self.artworkSwiped(_:)))
        previousGesture.direction = .right
        self.artwork.addGestureRecognizer(previousGesture)
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let gesture = UISwipeGestureRecognizer(target: self, action: #selector(self.artworkSwiped(_:)))
            gesture.direction = direction
            self.backgroundArtwork.addGestureRecognizer(gesture)
        }

        self.titleLabel.font = .systemFont(ofSize: 25.0, weight: .bold)
        self.titleLabel.adjustsFontSizeToFitWidth = true
        self.titleLabel.minimumScaleFactor = 0.7
        self.artistLabel.font = .systemFont(ofSize: 19.0, weight: .medium)
        self.artistLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        self.headerLabel.font = .systemFont(ofSize: 12.0, weight: .semibold)
        self.headerLabel.textAlignment = .center
        self.headerLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        for label in [self.titleLabel, self.artistLabel, self.headerLabel, self.elapsedLabel, self.remainingLabel, self.sourceLabel] {
            self.addSubview(label)
        }
        self.titleLabel.textColor = .white
        for label in [self.elapsedLabel, self.remainingLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 12.0, weight: .medium)
            label.textColor = UIColor.white.withAlphaComponent(0.6)
        }
        self.remainingLabel.textAlignment = .right
        self.sourceLabel.font = .systemFont(ofSize: 11.0, weight: .medium)
        self.sourceLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        self.sourceLabel.textAlignment = .center
        self.sourceLabel.accessibilityElementsHidden = true
        self.addSubview(self.lyricsView)
        self.lyricsView.seek = { [weak self] time in self?.seek(time) }

        self.configure(self.closeButton, symbol: "chevron.down", size: 20.0, action: #selector(self.closePressed))
        self.configure(self.menuButton, symbol: "ellipsis", size: 23.0, action: nil)
        self.menuButton.showsMenuAsPrimaryAction = true
        self.configure(self.playButton, symbol: "play.fill", size: 43.0, action: #selector(self.playPressed))
        self.configure(self.previousButton, symbol: "backward.end.fill", size: 28.0, action: #selector(self.previousPressed))
        self.configure(self.nextButton, symbol: "forward.end.fill", size: 28.0, action: #selector(self.nextPressed))
        self.configure(self.shuffleButton, symbol: "shuffle", size: 20.0, action: #selector(self.shufflePressed))
        self.configure(self.repeatButton, symbol: "repeat", size: 20.0, action: #selector(self.repeatPressed))
        self.configure(self.lyricsButton, symbol: "quote.bubble", size: 22.0, action: #selector(self.lyricsPressed))
        self.configure(self.queueButton, symbol: "list.bullet", size: 23.0, action: #selector(self.queuePressed))
        self.configure(self.settingsButton, symbol: "slider.horizontal.3", size: 22.0, action: #selector(self.settingsPressed))
        self.positionSlider.minimumTrackTintColor = UIColor.white.withAlphaComponent(0.9)
        self.positionSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.2)
        self.positionSlider.setThumbImage(Self.sliderThumb(), for: .normal)
        self.positionSlider.addTarget(self, action: #selector(self.scrubBegan), for: .touchDown)
        self.positionSlider.addTarget(self, action: #selector(self.scrubChanged), for: .valueChanged)
        self.positionSlider.addTarget(self, action: #selector(self.scrubEnded), for: [.touchUpInside, .touchUpOutside])
        self.positionSlider.addTarget(self, action: #selector(self.scrubCancelled), for: .touchCancel)
        self.addSubview(self.positionSlider)
        self.volumeView.tintColor = UIColor.white.withAlphaComponent(0.7)
        self.addSubview(self.volumeView)
        self.routePicker.tintColor = UIColor.white.withAlphaComponent(0.75)
        self.routePicker.activeTintColor = .white
        self.addSubview(self.routePicker)
        self.spinner.color = .white
        self.spinner.hidesWhenStopped = true
        self.addSubview(self.spinner)

        self.artworkNode.imageUpdated = { [weak self] image in
            self?.artwork.image = image
            self?.backgroundArtwork.image = image
        }
        let artworkSize = CGSize(width: 640.0, height: 640.0)
        self.artworkNode.asyncLayout()(TransformImageArguments(corners: ImageCorners(radius: 0.0), imageSize: artworkSize,
            boundingSize: artworkSize, intrinsicInsets: .zero))()
        self.displayLinkTarget.player = self
        self.foreground = UIApplication.shared.applicationState == .active
        NotificationCenter.default.addObserver(self, selector: #selector(self.didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.accessibilityChanged), name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.accessibilityChanged), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)

        self.settingsDisposable = (nagramMusicPlayerSettingsSignal() |> deliverOnMainQueue).startStrict(next: { [weak self] settings in
            guard let self else { return }
            let reloadLyrics = settings.lyricsEnabled != self.settings.lyricsEnabled || settings.onlineLyricsEnabled != self.settings.onlineLyricsEnabled
            let reloadArtwork = (settings.coverLayout == .fit) != (self.settings.coverLayout == .fit)
            self.settings = settings
            if !settings.lyricsEnabled { self.showingLyrics = false }
            self.updateAppearance()
            if reloadArtwork { self.updateArtwork() }
            if reloadLyrics { self.reloadLyrics() }
        })
        self.playbackDisposable = (context.sharedContext.mediaManager.musicMediaPlayerState |> deliverOnMainQueue).startStrict(next: { [weak self] value in
            guard let self else { return }
            if let (account, state, type) = value, account.id == context.account.id, type == .music, case let .state(state) = state {
                self.updateState(state)
            } else {
                self.state = nil
                self.scrubbing = false
                self.positionSlider.value = 0.0
                self.positionSlider.accessibilityValue = nil
                self.elapsedLabel.text = Self.timeString(0.0)
                self.remainingLabel.text = Self.timeString(0.0)
                self.trackId = nil
                self.file = nil
                self.albumArt = nil
                self.trackTitle = ""
                self.trackArtist = ""
                self.titleLabel.text = self.presentationData.strings.MediaPlayer_UnknownTrack
                self.artistLabel.text = self.presentationData.strings.MediaPlayer_UnknownArtist
                self.artwork.image = nil
                self.backgroundArtwork.image = nil
                self.artworkNode.reset()
                self.cancelLyrics()
                self.lyrics = nil
                self.sourceLabel.text = nil
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
        self.playbackDisposable?.dispose()
        self.presentationDisposable?.dispose()
        self.displayLink?.invalidate()
        self.onlineTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    public func setActive(_ active: Bool) {
        guard self.active != active else { return }
        self.active = active
        self.updateDisplayLink()
        if active {
            self.reloadLyrics()
            self.updatePosition()
        } else {
            self.cancelLyrics()
        }
    }

    public func updateLayout(size: CGSize, safeInsets: UIEdgeInsets) {
        self.safeInsets = safeInsets
        self.bounds = CGRect(origin: .zero, size: size)
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let size = self.bounds.size
        guard size.width > 0.0, size.height > 0.0 else { return }
        self.backgroundArtwork.frame = self.bounds
        self.shade.frame = self.bounds
        self.blur?.frame = self.bounds
        self.blur?.update(size: size, constantHeight: size.height * 0.75, isInverted: true,
            gradient: EdgeEffectView.generateEdgeGradientData(baseHeight: size.height * 0.75), transition: .immediate)

        let top = max(12.0, self.safeInsets.top) + 6.0
        let bottom = max(12.0, self.safeInsets.bottom)
        let left = max(24.0, self.safeInsets.left + 16.0)
        let right = max(24.0, self.safeInsets.right + 16.0)
        self.closeButton.frame = CGRect(x: left - 8.0, y: top, width: 44.0, height: 44.0)
        self.menuButton.frame = CGRect(x: size.width - right - 36.0, y: top, width: 44.0, height: 44.0)
        self.headerLabel.frame = CGRect(x: left + 44.0, y: top + 11.0, width: max(0.0, size.width - left - right - 88.0), height: 22.0)

        let landscape = size.width > size.height * 1.15
        let contentTop = top + 58.0
        let columnLeft = landscape ? size.width * 0.5 + 18.0 : left + 6.0
        let columnRight = right + 6.0
        let columnWidth = max(1.0, size.width - columnLeft - columnRight)
        let compact = size.height - top - bottom < 610.0
        let footerY = size.height - bottom - 44.0
        let volumeHeight: CGFloat = self.settings.showVolume ? (landscape ? 28.0 : 36.0) : 0.0
        let controlsHeight: CGFloat = landscape ? 56.0 : (compact ? 64.0 : 78.0)
        let controlsY = footerY - volumeHeight - controlsHeight - 10.0
        let sliderY = controlsY - 44.0
        let titleY = sliderY - (landscape ? 64.0 : 72.0)
        let availableCoverHeight = max(0.0, titleY - contentTop - 20.0)
        let coverWidth = landscape ? max(1.0, size.width * 0.5 - left - 28.0) : columnWidth
        let coverHeight = landscape ? size.height - contentTop - bottom - 20.0 : availableCoverHeight
        var coverFrame = CGRect.zero
        let ratio = CGFloat(self.settings.coverSize) / 100.0
        switch self.settings.coverLayout {
        case .fullscreen:
            coverFrame = self.bounds
        case .wide:
            let width = landscape ? coverWidth : size.width
            let height = min(coverHeight, width * 0.72) * ratio
            coverFrame = CGRect(x: landscape ? left : 0.0, y: contentTop, width: width, height: max(0.0, height))
        case .fit, .fill:
            let width = coverWidth * ratio
            let height = coverHeight * ratio
            coverFrame = CGRect(x: landscape ? left + (coverWidth - width) * 0.5 : (size.width - width) * 0.5,
                y: contentTop + (coverHeight - height) * 0.5, width: width, height: height)
        case .card, .disc:
            let side = min(coverWidth, coverHeight, 460.0) * ratio
            coverFrame = CGRect(x: landscape ? left + (coverWidth - side) * 0.5 : (size.width - side) * 0.5,
                y: contentTop + (coverHeight - side) * 0.5, width: side, height: side)
        }
        self.artwork.frame = coverFrame
        self.artwork.layer.cornerRadius = self.settings.coverLayout == .disc ? coverFrame.width * 0.5 : CGFloat(self.settings.coverCornerRadius)
        let holeSide = coverFrame.width * 0.12
        self.discHole.frame = CGRect(x: (coverFrame.width - holeSide) * 0.5, y: (coverFrame.height - holeSide) * 0.5, width: holeSide, height: holeSide)
        self.discHole.layer.cornerRadius = holeSide * 0.5
        self.discHole.isHidden = self.settings.coverLayout != .disc
        self.artwork.isHidden = self.settings.coverLayout == .fullscreen || self.showingLyrics
        self.artwork.contentMode = self.settings.coverLayout == .fit ? .scaleAspectFit : .scaleAspectFill

        let lyricTop = contentTop
        self.lyricsView.frame = CGRect(x: left, y: lyricTop,
            width: landscape ? coverWidth : size.width - left - right,
            height: max(0.0, landscape ? size.height - lyricTop - bottom - 18.0 : titleY - lyricTop - 12.0))
        self.lyricsView.isHidden = !self.showingLyrics
        self.sourceLabel.frame = CGRect(x: columnLeft, y: titleY - 16.0, width: columnWidth, height: 14.0)
        self.sourceLabel.isHidden = !self.showingLyrics
        if landscape {
            // Reserve the left column for artwork/lyrics and the right column for controls.
            self.headerLabel.frame = CGRect(x: left + 36.0, y: top + 11.0, width: max(0.0, coverWidth - 44.0), height: 22.0)
            self.menuButton.frame.origin.y = titleY - 1.0
            self.sourceLabel.frame = CGRect(x: left, y: size.height - bottom - 16.0, width: coverWidth, height: 14.0)
        }
        self.titleLabel.frame = CGRect(x: columnLeft, y: titleY, width: columnWidth, height: 40.0)
        if landscape { self.titleLabel.frame.size.width = max(1.0, columnWidth - 44.0) }
        self.artistLabel.frame = CGRect(x: columnLeft, y: titleY + 40.0, width: columnWidth - 30.0, height: 22.0)
        self.spinner.frame = CGRect(x: columnLeft + columnWidth - 22.0, y: titleY + 40.0, width: 20.0, height: 20.0)
        self.positionSlider.frame = CGRect(x: columnLeft, y: sliderY, width: columnWidth, height: 30.0)
        self.elapsedLabel.frame = CGRect(x: columnLeft + 2.0, y: sliderY + 27.0, width: columnWidth * 0.5, height: 16.0)
        self.remainingLabel.frame = CGRect(x: columnLeft + columnWidth * 0.5, y: sliderY + 27.0, width: columnWidth * 0.5 - 2.0, height: 16.0)

        let buttons = [self.shuffleButton, self.previousButton, self.playButton, self.nextButton, self.repeatButton]
        let step = columnWidth / 5.0
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: columnLeft + CGFloat(index) * step, y: controlsY, width: step, height: controlsHeight)
        }
        self.volumeView.frame = CGRect(x: columnLeft + 4.0, y: footerY - volumeHeight + 2.0, width: columnWidth - 8.0, height: 32.0)
        self.volumeView.isHidden = !self.settings.showVolume
        let footerViews: [UIView] = [self.lyricsButton, self.routePicker, self.settingsButton, self.queueButton]
        for (index, view) in footerViews.enumerated() {
            view.frame = CGRect(x: columnLeft + columnWidth * CGFloat(index) / 4.0, y: footerY, width: columnWidth / 4.0, height: 44.0)
        }
    }

    private func configure(_ button: UIButton, symbol: String, size: CGFloat, action: Selector?) {
        button.tintColor = .white
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .semibold)), for: .normal)
        button.layer.cornerRadius = 12.0
        if let action { button.addTarget(self, action: action, for: .touchUpInside) }
        self.addSubview(button)
    }

    private static func sliderThumb() -> UIImage {
        return UIGraphicsImageRenderer(size: CGSize(width: 10.0, height: 10.0)).image { context in
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 1.0, y: 1.0, width: 8.0, height: 8.0))
        }
    }

    private func string(_ key: String) -> String {
        return ngI18n("Nagram.MusicPlayer." + key, self.presentationData.strings.baseLanguageCode)
    }

    private func updateAppearance() {
        let reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        let radius = CGFloat(self.settings.blurIntensity)
        if !reduceTransparency && radius > 0.0 {
            if self.blur?.maxBlurRadius != radius {
                self.blur?.removeFromSuperview()
                let blur = VariableBlurView(maxBlurRadius: radius)
                blur.isUserInteractionEnabled = false
                self.insertSubview(blur, aboveSubview: self.backgroundArtwork)
                self.blur = blur
            }
        } else {
            self.blur?.removeFromSuperview()
            self.blur = nil
        }
        self.backgroundArtwork.isHidden = reduceTransparency
        self.backgroundArtwork.isUserInteractionEnabled = self.settings.coverLayout == .fullscreen && !self.showingLyrics
        self.backgroundArtwork.alpha = self.settings.coverLayout == .fullscreen && !self.showingLyrics ? 1.0 : 0.65
        self.shade.backgroundColor = UIColor(white: 0.0, alpha: reduceTransparency ? 0.0 : (self.showingLyrics ? 0.55 : 0.42))
        self.headerLabel.text = self.string("NowPlaying").uppercased()
        self.closeButton.accessibilityLabel = self.presentationData.strings.Common_Close
        self.menuButton.accessibilityLabel = self.presentationData.strings.Common_More
        self.lyricsButton.accessibilityLabel = self.string("Lyrics")
        self.queueButton.accessibilityLabel = self.string("Queue")
        self.settingsButton.accessibilityLabel = self.string("Settings")
        self.positionSlider.accessibilityLabel = self.string("PlaybackPosition")
        self.previousButton.accessibilityLabel = self.string("Previous")
        self.nextButton.accessibilityLabel = self.string("Next")
        self.shuffleButton.accessibilityLabel = self.string("Shuffle")
        self.repeatButton.accessibilityLabel = self.string("Repeat")
        self.titleLabel.font = .systemFont(ofSize: CGFloat(self.settings.titleFontSize), weight: .bold)
        self.titleLabel.textAlignment = self.settings.titleAlignment == "center" ? .center : .left
        self.artistLabel.textAlignment = self.titleLabel.textAlignment
        let scale = CGFloat(self.settings.controlScale) / 100.0
        for (button, symbol, size) in [(self.previousButton, "backward.end.fill", 28.0), (self.nextButton, "forward.end.fill", 28.0),
                                     (self.shuffleButton, "shuffle", 20.0)] {
            button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: CGFloat(size) * scale, weight: .semibold)), for: .normal)
        }
        self.lyricsButton.isHidden = !self.settings.lyricsEnabled
        self.lyricsButton.backgroundColor = self.showingLyrics ? UIColor.white.withAlphaComponent(0.18) : .clear
        self.updateLyricsView()
        self.updateMenu()
        self.updateTransport()
        self.updateDiscAnimation()
        self.setNeedsLayout()
    }

    private func updateState(_ state: SharedMediaPlayerItemPlaybackState) {
        let previousFileId = self.file?.media.fileId
        let previousSeekId = self.state?.status.seekId
        let previousDuration = self.state?.status.duration ?? 0.0
        let previousTitle = self.trackTitle
        let previousArtist = self.trackArtist
        let changedItem = self.trackId != state.item.stableId
        self.state = state
        self.trackId = state.item.stableId
        if let source = state.item.playbackData?.source, case let .telegramFile(file, _, _) = source {
            self.file = file
        } else {
            self.file = nil
        }
        let changed = changedItem || previousFileId != self.file?.media.fileId
        if let display = state.item.displayData, case let .music(title, artist, albumArt, _, _) = display {
            self.trackTitle = title ?? ""
            self.trackArtist = artist ?? ""
            self.titleLabel.text = title ?? self.presentationData.strings.MediaPlayer_UnknownTrack
            self.artistLabel.text = artist ?? self.presentationData.strings.MediaPlayer_UnknownArtist
            if changed || self.albumArt != albumArt {
                self.albumArt = albumArt
                self.artwork.image = nil
                self.backgroundArtwork.image = nil
                self.updateArtwork()
            }
        }
        if case .buffering = state.status.status { self.spinner.startAnimating() } else { self.spinner.stopAnimating() }
        self.updateTransport()
        self.updateDisplayLink()
        self.updatePosition()
        if previousSeekId != state.status.seekId { self.lyricsView.updatePosition(self.currentPosition, force: true) }
        if changed || previousTitle != self.trackTitle || previousArtist != self.trackArtist || (previousDuration == 0.0 && state.status.duration > 0.0) {
            self.scrubbing = false
            self.updatePosition()
            self.updateMenu()
            self.reloadLyrics()
        }
    }

    private func updateArtwork() {
        self.artworkNode.setSignal(playerAlbumArt(engine: self.context.engine, fileReference: self.file, albumArt: self.albumArt,
            thumbnail: false, aspectFit: self.settings.coverLayout == .fit))
    }

    private var currentPosition: Double {
        guard let status = self.state?.status else { return 0.0 }
        var time = status.timestamp
        if case .playing = status.status, status.generationTimestamp > 0.0 {
            time += max(0.0, CACurrentMediaTime() - status.generationTimestamp) * status.baseRate
        }
        return min(max(0.0, status.duration), max(0.0, time))
    }

    fileprivate func updatePosition() {
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
        guard let state = self.state else { return false }
        switch state.status.status {
        case .playing: return true
        case .paused: return false
        case let .buffering(_, whilePlaying, _, _): return whilePlaying
        }
    }

    private func updateTransport() {
        let scale = CGFloat(self.settings.controlScale) / 100.0
        self.playButton.setImage(UIImage(systemName: self.playing ? "pause.fill" : "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 43.0 * scale, weight: .semibold)), for: .normal)
        self.playButton.accessibilityLabel = self.string(self.playing ? "Pause" : "Play")
        for button in [self.playButton, self.nextButton, self.previousButton, self.shuffleButton, self.repeatButton] {
            button.isEnabled = self.state != nil
        }
        self.positionSlider.isEnabled = (self.state?.status.duration ?? 0.0) > 0.0
        self.shuffleButton.backgroundColor = self.state?.order == .random ? UIColor.white.withAlphaComponent(0.18) : .clear
        self.shuffleButton.isSelected = self.state?.order == .random
        self.repeatButton.backgroundColor = self.state.map { $0.looping != .none } == true ? UIColor.white.withAlphaComponent(0.18) : .clear
        self.repeatButton.isSelected = self.state?.looping == .item || self.state?.looping == .all
        self.repeatButton.setImage(UIImage(systemName: self.state?.looping == .item ? "repeat.1" : "repeat", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20.0 * scale, weight: .semibold)), for: .normal)
    }

    private func updateDisplayLink() {
        let running = self.active && self.foreground && self.playing
        if running && self.displayLink == nil {
            let link = CADisplayLink(target: self.displayLinkTarget, selector: #selector(NextgramPlayerDisplayLinkTarget.tick))
            link.preferredFramesPerSecond = 10
            link.add(to: .main, forMode: .common)
            self.displayLink = link
        } else if !running {
            self.displayLink?.invalidate()
            self.displayLink = nil
        }
        self.updateDiscAnimation()
    }

    private func updateDiscAnimation() {
        let spinning = self.active && self.foreground && self.playing && self.settings.coverLayout == .disc && self.settings.discRotation && !UIAccessibility.isReduceMotionEnabled
        if spinning {
            if self.artwork.layer.animation(forKey: "nextgram.disc") == nil {
                let animation = CABasicAnimation(keyPath: "transform.rotation.z")
                animation.fromValue = 0.0
                animation.toValue = Double.pi * 2.0
                animation.duration = 20.0
                animation.repeatCount = .infinity
                self.artwork.layer.add(animation, forKey: "nextgram.disc")
            }
        } else {
            self.artwork.layer.removeAnimation(forKey: "nextgram.disc")
        }
    }

    private func cancelLyrics() {
        self.lyricsRequest = UUID()
        self.onlineTask?.cancel()
        self.onlineTask = nil
        self.embeddedLoader.cancel()
    }

    private func reloadLyrics() {
        self.cancelLyrics()
        self.lyrics = nil
        self.sourceLabel.text = nil
        self.embeddedLyricsFound = false
        self.lyricsPlaceholder = self.string("NoLyrics")
        self.updateLyricsView()
        guard self.active, self.foreground, self.settings.lyricsEnabled, let file = self.file else { return }
        let request = self.lyricsRequest
        let fileId = file.media.fileId.id
        self.lyricsPlaceholder = self.string("LoadingLyrics")
        self.updateLyricsView()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let imported = NextgramLyricsStore.load(fileId: fileId)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lyricsRequest == request else { return }
                if let imported {
                    self.lyrics = imported
                    self.sourceLabel.text = self.string("ImportLyrics")
                    self.updateLyricsView()
                    return
                }
                self.lyricsPlaceholder = self.string("NoLyrics")
                self.updateLyricsView()
                self.embeddedLoader.load(context: self.context, file: file) { [weak self] text in
                    guard let self, self.lyricsRequest == request, let text, let lyrics = NextgramLyrics.parse(text) else { return }
                    self.embeddedLyricsFound = true
                    self.onlineTask?.cancel()
                    self.onlineTask = nil
                    self.lyrics = lyrics
                    self.sourceLabel.text = nil
                    self.updateLyricsView()
                }
                if self.settings.onlineLyricsEnabled {
                    self.lyricsPlaceholder = self.string("LoadingLyrics")
                    self.updateLyricsView()
                    self.onlineTask = NextgramLyricsService.shared.fetch(title: self.trackTitle, artist: self.trackArtist,
                        duration: self.state?.status.duration ?? 0.0) { [weak self] lyrics in
                        guard let self, self.lyricsRequest == request, !self.embeddedLyricsFound else { return }
                        self.onlineTask = nil
                        self.lyrics = lyrics
                        self.lyricsPlaceholder = self.string(lyrics?.instrumental == true ? "Instrumental" : "NoLyrics")
                        self.sourceLabel.text = lyrics == nil ? nil : "LRCLIB"
                        self.updateLyricsView()
                    }
                }
            }
        }
    }

    private func updateLyricsView() {
        self.lyricsView.update(lyrics: self.lyrics, placeholder: self.lyricsPlaceholder.isEmpty ? self.string("NoLyrics") : self.lyricsPlaceholder,
            fontSize: CGFloat(self.settings.lyricsFontSize))
        self.lyricsView.updatePosition(self.currentPosition)
    }

    private func updateMenu() {
        let covers = NagramMusicPlayerCoverLayout.allCases.map { layout in
            UIAction(title: self.string("CoverLayout." + layout.rawValue), state: self.settings.coverLayout == layout ? .on : .off) { _ in
                NagramSettings.shared.musicPlayerCoverLayout = layout.rawValue
            }
        }
        var actions: [UIMenuElement] = [UIMenu(title: self.string("CoverLayout"), children: covers)]
        if self.settings.lyricsEnabled && self.file != nil {
            actions.append(UIAction(title: self.string("ImportLyrics"), image: UIImage(systemName: "doc.badge.plus")) { [weak self] _ in self?.importLyrics() })
            actions.append(UIAction(title: self.string("RetryLyrics"), image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in self?.reloadLyrics() })
            actions.append(UIAction(title: self.string("RemoveLyrics"), image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                guard let self, let fileId = self.file?.media.fileId.id else { return }
                do {
                    try NextgramLyricsStore.remove(fileId: fileId)
                    self.reloadLyrics()
                } catch { self.showLyricsError() }
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
                        self.reloadLyrics()
                    }
                } catch {
                    DispatchQueue.main.async { self?.showLyricsError() }
                }
            }
        })
        self.presentController?(picker)
    }

    private func showLyricsError() {
        self.presentController?(textAlertController(context: self.context, title: self.string("Lyrics"), text: self.string("LyricsFileInvalid"), actions: [
            TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_OK, action: {})
        ]))
    }

    private func seek(_ time: Double) {
        guard let duration = self.state?.status.duration, duration > 0.0 else { return }
        let position = min(duration, max(0.0, time))
        self.context.sharedContext.mediaManager.playlistControl(.seek(position), type: .music)
        self.lyricsView.updatePosition(position, force: true)
    }

    @objc private func closePressed() { self.dismiss?() }
    @objc private func queuePressed() { self.showQueue?() }
    @objc private func settingsPressed() { self.openSettings?() }
    @objc private func playPressed() { self.context.sharedContext.mediaManager.playlistControl(.playback(.togglePlayPause), type: .music) }
    @objc private func previousPressed() { self.context.sharedContext.mediaManager.playlistControl(.previous, type: .music) }
    @objc private func nextPressed() { self.context.sharedContext.mediaManager.playlistControl(.next, type: .music) }
    @objc private func lyricsPressed() {
        self.showingLyrics.toggle()
        self.updateAppearance()
        self.lyricsView.updatePosition(self.currentPosition, force: true)
    }
    @objc private func shufflePressed() {
        guard let state = self.state else { return }
        let order: MusicPlaybackSettingsOrder = state.order == .random ? .regular : .random
        let _ = updateMusicPlaybackSettingsInteractively(accountManager: self.context.sharedContext.accountManager, { $0.withUpdatedOrder(order) }).startStandalone()
        self.context.sharedContext.mediaManager.playlistControl(.setOrder(order), type: .music)
    }
    @objc private func repeatPressed() {
        guard let state = self.state else { return }
        let looping: MusicPlaybackSettingsLooping
        switch state.looping {
        case .none: looping = .all
        case .all: looping = .item
        case .item: looping = .none
        }
        let _ = updateMusicPlaybackSettingsInteractively(accountManager: self.context.sharedContext.accountManager, { $0.withUpdatedLooping(looping) }).startStandalone()
        self.context.sharedContext.mediaManager.playlistControl(.setLooping(looping), type: .music)
    }
    @objc private func scrubBegan() { self.scrubbing = true }
    @objc private func scrubChanged() {
        if !self.positionSlider.isTracking { self.seek(Double(self.positionSlider.value) * (self.state?.status.duration ?? 0.0)) }
        self.updatePosition()
    }
    @objc private func scrubEnded() {
        self.seek(Double(self.positionSlider.value) * (self.state?.status.duration ?? 0.0))
        self.scrubbing = false
    }
    @objc private func scrubCancelled() { self.scrubbing = false; self.updatePosition() }
    @objc private func artworkSwiped(_ gesture: UISwipeGestureRecognizer) {
        guard self.settings.swipeToSkip, self.state != nil else { return }
        if gesture.direction == .left { self.nextPressed() } else { self.previousPressed() }
    }
    @objc private func didEnterBackground() {
        self.foreground = false
        self.cancelLyrics()
        self.updateDisplayLink()
    }
    @objc private func didBecomeActive() {
        self.foreground = true
        self.updateDisplayLink()
        self.updatePosition()
        if self.active && self.lyrics == nil { self.reloadLyrics() }
    }
    @objc private func accessibilityChanged() { self.updateAppearance() }
}
