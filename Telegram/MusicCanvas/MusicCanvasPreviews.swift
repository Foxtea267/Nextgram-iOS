import NextgramMusicUI
import SwiftUI
import UIKit

struct MusicCanvasRoot: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let interlude = CommandLine.arguments.contains("lyrics-interlude") || CommandLine.arguments.contains("lyrics-interlude-pause")
        let translation = CommandLine.arguments.contains("--canvas-translated-lyrics")
        let fullEffects = interlude || translation || CommandLine.arguments.contains("lyrics-effects") || CommandLine.arguments.contains("lyrics-effects-paused") || CommandLine.arguments.contains("lyrics-motion-pause")
        let demo = fullEffects || CommandLine.arguments.contains("lyrics-original")
        let artworkMotion: Bool? = CommandLine.arguments.contains("artwork-motion") ? true :
            (CommandLine.arguments.contains("artwork-motion-off") || CommandLine.arguments.contains("artwork-metadata") ? false : nil)
        return MusicCanvasViewController(showingLyrics: demo,
            playing: !CommandLine.arguments.contains("lyrics-paused") && !CommandLine.arguments.contains("lyrics-effects-paused"),
            allLyricsEffects: fullEffects, animatedLyrics: true, interludePreview: interlude, artworkMotionPreview: artworkMotion,
            artworkMetadataPreview: CommandLine.arguments.contains("artwork-metadata") ? false : nil,
            usesConfiguredSettings: !translation && !CommandLine.arguments.contains("--canvas-motion"), translationPreview: translation)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    }
}

private final class MusicCanvasViewController: UIViewController {
    private let player: NextgramMusicPlayerView
    private var scheduledRecording = false
    private let artworkDetailPreview: Bool

    init(showingLyrics: Bool, playing: Bool = true, allLyricsEffects: Bool = false, animatedLyrics: Bool = false,
        interludePreview: Bool = false, artworkMotionPreview: Bool? = nil, artworkDetailPreview: Bool = false,
        artworkMetadataPreview: Bool? = nil, usesConfiguredSettings: Bool = false, translationPreview: Bool = false) {
        self.artworkDetailPreview = artworkDetailPreview
        var cover = Bundle.main.url(forResource: "MusicCanvasARU", withExtension: "jpg")
            .flatMap { UIImage(contentsOfFile: $0.path) }
            ?? UIImage(systemName: "music.note")!
        if CommandLine.arguments.contains("cover-regression") {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            let bounds = CGRect(x: 0.0, y: 0.0, width: 256.0, height: 256.0)
            cover = UIGraphicsImageRenderer(size: bounds.size, format: format).image { _ in cover.draw(in: bounds) }
        }
        self.player = NextgramMusicPlayerView.makeCanvasPreview(coverImage: cover, showingLyrics: showingLyrics, playing: playing,
            allLyricsEffects: allLyricsEffects, animatedLyrics: animatedLyrics, interludePreview: interludePreview,
            artworkMotionPreview: artworkMotionPreview, artworkMetadataPreview: artworkMetadataPreview, translationPreview: translationPreview)
        super.init(nibName: nil, bundle: nil)
        if usesConfiguredSettings { self.player.useCanvasSettings() }
        self.player.openSettings = { [weak self] in
            guard let self else { return }
            self.player.presentCanvasSettings(from: self)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    override func loadView() {
        self.view = UIView()
        self.view.addSubview(self.player)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.player.frame = self.view.bounds
        self.player.updateLayout(size: self.view.bounds.size, safeInsets: self.view.safeAreaInsets)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if self.artworkDetailPreview && !self.scheduledRecording {
            self.scheduledRecording = true
            self.player.performCanvasAction("artwork")
        }
        guard !self.scheduledRecording, let index = CommandLine.arguments.firstIndex(of: "--canvas-motion") else { return }
        guard index + 1 < CommandLine.arguments.count else { fatalError("--canvas-motion requires playback, lyrics-playing, or lyrics-paused") }
        let mode = CommandLine.arguments[index + 1]
        if mode == "cover-regression" {
            self.scheduledRecording = true
            for (delay, action) in [(0.1, "cover:card"), (0.1, "enhancement:off"), (0.1, "background:blur"),
                                    (1.0, "cover:disc"), (2.0, "cover:card"), (3.2, "cover:fullscreen"),
                                    (4.3, "enhancement:fullscreen"), (6.2, "cover:card"), (7.3, "enhancement:always")] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.player.performCanvasAction(action) }
            }
            return
        }
        if mode == "progress-stretch" {
            self.scheduledRecording = true
            for (delay, action) in [(0.3, "playback"), (1.2, "progress-start"), (1.9, "progress-release"),
                                    (2.6, "progress-end"), (3.3, "progress-release"), (4.1, "volume-toggle"),
                                    (4.8, "volume-toggle")] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.player.performCanvasAction(action) }
            }
            for (start, direction) in [(1.3, -1.0), (2.7, 1.0)] {
                for step in 1 ... 14 {
                    let distance = direction * Double(step) * 2.0
                    DispatchQueue.main.asyncAfter(deadline: .now() + start + Double(step) / 60.0) { [weak self] in
                        self?.player.performCanvasAction("progress-stretch:\(distance)")
                    }
                }
            }
            return
        }
        if mode == "cover-swipe" || mode == "fullscreen-swipe" {
            self.scheduledRecording = true
            let layout = mode == "fullscreen-swipe" ? "fullscreen" : "card"
            for (delay, action) in [(0.3, "cover:" + layout), (1.7, "cover-swipe-left"), (2.8, "cover-swipe-right")] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.player.performCanvasAction(action) }
            }
            return
        }
        if mode == "lyrics-seek" {
            self.scheduledRecording = true
            for (delay, action) in [(0.3, "effects-on"), (0.7, "lyrics"), (2.0, "lyrics-seek"), (3.5, "lyrics")] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.player.performCanvasAction(action) }
            }
            return
        }
        if mode == "disc-playback" {
            self.scheduledRecording = true
            for (delay, action) in [(0.3, "cover:disc"), (2.5, "playback"), (5.5, "playback"), (8.5, "playback")] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.player.performCanvasAction(action) }
            }
            return
        }
        if mode == "fullscreen-cover" || mode == "gradient-cover" {
            self.scheduledRecording = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                if mode == "fullscreen-cover" {
                    self.player.performCanvasAction("cover:fullscreen")
                } else {
                    self.player.performCanvasAction("cover:card")
                    self.player.performCanvasAction("background:gradient")
                }
            }
            return
        }
        if mode == "lyrics-online" {
            self.scheduledRecording = true
            for (delay, title, artist) in [(1.0, "Blue Dream", "ARU"),
                (5.0, "Nextgram Canvas Unmatched Fixture", "Nextgram"), (9.0, "Blue Dream", "ARU")] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.player.performCanvasLyricsLookup(title: title, artist: artist, duration: 194,
                        source: "netease", forceRefresh: false)
                }
            }
            return
        }
        if mode == "settings-panel" || mode == "settings-options" {
            self.scheduledRecording = true
            if mode == "settings-panel" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self else { return }
                    self.player.presentCanvasSettings(from: self)
                }
                for (delay, section) in [(4.0, 2), (7.0, 3), (10.0, 4)] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard let navigation = self?.presentedViewController as? UINavigationController,
                              let table = navigation.topViewController as? UITableViewController else { return }
                        table.tableView.scrollToRow(at: IndexPath(row: 0, section: section), at: .top, animated: true)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 14) { [weak self] in
                    self?.dismiss(animated: true)
                }
            } else {
                let actions = ["cover:card", "cover:fullscreen", "cover:disc", "background:gradient",
                    "background:artwork", "background:solid", "background:blur", "cover:card", "effects-on", "lyrics"]
                for (index, action) in actions.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(index) * 1.5) { [weak self] in
                        self?.player.performCanvasAction(action)
                    }
                }
            }
            return
        }
        if mode == "artwork-metadata" {
            self.scheduledRecording = true
            for (delay, action) in [(1.0, "artwork"), (2.0, "artwork-metadata-on"),
                                    (4.0, "artwork-metadata-off"), (5.0, "artwork-metadata-on"), (7.0, "artwork-close")] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.player.performCanvasAction(action) }
            }
            return
        }
        if mode == "artwork-motion" || mode == "artwork-motion-off" {
            self.scheduledRecording = true
            let events: [(Double, String)] = [
                (0.3, "artwork-main-press"), (1.0, "artwork"),
                (1.8, "artwork-top-left"), (2.6, "artwork-top-right"),
                (3.4, "artwork-bottom-right"), (4.2, "artwork-bottom-left"),
                (5.0, "artwork-release"), (6.0, "artwork-center"), (6.5, "artwork-release"),
                (9.2, "artwork-close"), (10.0, "artwork-main-press")
            ]
            for (delay, action) in events {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.player.performCanvasAction(action)
                }
            }
            for sample in 0 ... 96 {
                let angle = 0.30 * sin(2.0 * .pi * Double(sample) / 72.0) * min(1.0, Double(96 - sample) / 24.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 7.0 + Double(sample) / 60.0) { [weak self] in
                    self?.player.performCanvasAction("artwork-tilt:\(angle)")
                }
            }
            return
        }
        if mode == "lyrics-motion-pause" || mode == "lyrics-interlude-pause" {
            self.scheduledRecording = true
            for delay in [2.0, 3.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.player.performCanvasAction("playback")
                }
            }
            return
        }
        if ["lyrics-effects", "lyrics-original", "lyrics-effects-paused", "lyrics-interlude"].contains(mode) {
            self.scheduledRecording = true
            return
        }
        guard ["playback", "lyrics-playing", "lyrics-paused"].contains(mode) else { fatalError("Unsupported --canvas-motion mode: \(mode)") }
        self.scheduledRecording = true
        let action = mode == "playback" ? "playback" : "lyrics"
        for delay in [1.2, 2.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.player.performCanvasAction(action)
            }
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
@available(iOS 17.0, *)
#Preview("Music · Cover") {
    MusicCanvasViewController(showingLyrics: false)
}

@available(iOS 17.0, *)
#Preview("Music · Lyrics") {
    MusicCanvasViewController(showingLyrics: true)
}

@available(iOS 17.0, *)
#Preview("Music · Paused") {
    MusicCanvasViewController(showingLyrics: false, playing: false)
}

@available(iOS 17.0, *)
#Preview("Music · Lyrics Paused") {
    MusicCanvasViewController(showingLyrics: true, playing: false)
}

@available(iOS 17.0, *)
#Preview("Lyrics · All Effects") {
    MusicCanvasViewController(showingLyrics: true, allLyricsEffects: true)
}

@available(iOS 17.0, *)
#Preview("Lyrics · With Translation") {
    MusicCanvasViewController(showingLyrics: true, allLyricsEffects: true, translationPreview: true)
}

@available(iOS 17.0, *)
#Preview("Lyrics · Original") {
    MusicCanvasViewController(showingLyrics: true, animatedLyrics: true)
}

@available(iOS 17.0, *)
#Preview("Lyrics · Interlude") {
    MusicCanvasViewController(showingLyrics: true, allLyricsEffects: true, interludePreview: true)
}

@available(iOS 17.0, *)
#Preview("Music · Artwork 3D") {
    MusicCanvasViewController(showingLyrics: false, artworkMotionPreview: true, artworkDetailPreview: true)
}

@available(iOS 17.0, *)
#Preview("Music · Artwork Title / Artist") {
    MusicCanvasViewController(showingLyrics: false, artworkMotionPreview: false,
        artworkDetailPreview: true, artworkMetadataPreview: true)
}

#endif
