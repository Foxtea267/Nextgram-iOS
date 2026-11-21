import NextgramMusicUI
import SwiftUI
import UIKit

struct MusicCanvasRoot: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let interlude = CommandLine.arguments.contains("lyrics-interlude") || CommandLine.arguments.contains("lyrics-interlude-pause")
        let fullEffects = interlude || CommandLine.arguments.contains("lyrics-effects") || CommandLine.arguments.contains("lyrics-effects-paused") || CommandLine.arguments.contains("lyrics-motion-pause")
        let demo = fullEffects || CommandLine.arguments.contains("lyrics-original")
        let artworkMotion: Bool? = CommandLine.arguments.contains("artwork-motion") || CommandLine.arguments.contains("artwork-gyro") ? true :
            (CommandLine.arguments.contains("artwork-motion-off") || CommandLine.arguments.contains("artwork-gyro-off") || CommandLine.arguments.contains("artwork-metadata") ? false : nil)
        return MusicCanvasViewController(showingLyrics: demo,
            playing: !CommandLine.arguments.contains("lyrics-paused") && !CommandLine.arguments.contains("lyrics-effects-paused"),
            allLyricsEffects: fullEffects, animatedLyrics: true, interludePreview: interlude, artworkMotionPreview: artworkMotion,
            artworkMetadataPreview: CommandLine.arguments.contains("artwork-metadata") ? false : nil,
            usesConfiguredSettings: !CommandLine.arguments.contains("--canvas-motion"))
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    }
}

private final class MusicCanvasViewController: UIViewController {
    private let player: NextgramMusicPlayerView
    private var scheduledRecording = false
    private let artworkDetailPreview: Bool
    private var motionTimer: Timer?

    init(showingLyrics: Bool, playing: Bool = true, allLyricsEffects: Bool = false, animatedLyrics: Bool = false,
        interludePreview: Bool = false, artworkMotionPreview: Bool? = nil, artworkDetailPreview: Bool = false,
        artworkMetadataPreview: Bool? = nil, usesConfiguredSettings: Bool = false) {
        self.artworkDetailPreview = artworkDetailPreview
        let cover = Bundle.main.url(forResource: "MusicCanvasARU", withExtension: "jpg")
            .flatMap { UIImage(contentsOfFile: $0.path) }
            ?? UIImage(systemName: "music.note")!
        self.player = NextgramMusicPlayerView.makeCanvasPreview(coverImage: cover, showingLyrics: showingLyrics, playing: playing,
            allLyricsEffects: allLyricsEffects, animatedLyrics: animatedLyrics, interludePreview: interludePreview,
            artworkMotionPreview: artworkMotionPreview, artworkMetadataPreview: artworkMetadataPreview)
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

    deinit { self.motionTimer?.invalidate() }

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
        if mode == "artwork-gyro" || mode == "artwork-gyro-off" {
            self.scheduledRecording = true
            let start = CACurrentMediaTime()
            // Relative sensor angles in radians; the real Core Motion filter handles these samples.
            let poses: [(Double, Double, Double)] = [
                (0, 0, 0), (0.3, 0, 0), (0.6, 0.34, -0.12), (1.0, 0.34, -0.12),
                (1.25, 0, 0), (1.5, 0.30, -0.10), (1.75, 0, 0),
                (2.05, -0.34, -0.12), (2.3, 0, 0), (2.6, 0.30, -0.10),
                (2.85, 0, 0), (3.15, -0.30, -0.10), (3.45, 0, 0),
                (3.8, 0.26, -0.10), (4.05, 0, 0), (4.4, -0.26, -0.10), (4.8, 0, 0)
            ]
            self.motionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                let elapsed = CACurrentMediaTime() - start
                let time = max(0, elapsed - 1.8)
                let upper = poses.firstIndex { $0.0 >= time } ?? (poses.count - 1)
                let lower = max(0, upper - 1)
                let fraction = min(1.0, max(0, (time - poses[lower].0) / max(0.001, poses[upper].0 - poses[lower].0)))
                let roll = poses[lower].1 + (poses[upper].1 - poses[lower].1) * fraction
                let pitch = poses[lower].2 + (poses[upper].2 - poses[lower].2) * fraction
                self.player.performCanvasDeviceMotion(roll: roll, pitch: pitch)
                if elapsed > 9 { timer.invalidate(); self.motionTimer = nil }
            }
            for (delay, action) in [(1.0, "artwork"), (4.0, "artwork-center"), (4.7, "artwork-release"), (7.3, "artwork-close")] {
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
                (7.5, "artwork-close"), (8.3, "artwork-main-press")
            ]
            for (delay, action) in events {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.player.performCanvasAction(action)
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
