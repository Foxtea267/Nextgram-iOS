import CoreImage
import Display
import NagramSettings
import NextgramLyrics
import UIKit

/// A media-time-driven interlude: separate dots fill in sequence while the group breathes.
private final class NextgramInterludeDotsView: UIView {
    var start = 0.0
    var end: Double?
    var position = 0.0
    var diameter: CGFloat = 8.4
    var color = UIColor.white

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isOpaque = false
        self.isUserInteractionEnabled = false
        self.isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let end = self.end, let context = UIGraphicsGetCurrentContext() else { return }
        let duration = end - self.start
        let elapsed = self.position - self.start
        // Leave time for the line transition, staggered entrance and final contraction.
        let body = duration - 1.5
        guard body >= 0.91, elapsed >= 0.5, elapsed < duration else { return }
        let time = elapsed - 0.5
        let exit = max(0.0, time - body)
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let short = body < 3.0
        var scale = 1.0
        var opacity = Self.ease(time / 0.18, 0.59, 0.02, 0.07, 1.0)
        if !reduceMotion {
            if time >= body {
                scale = exit < 0.75
                    ? 1.0 + 0.25 * Self.ease(exit / 0.75, 0.14, 0.06, 0.25, 1.0)
                    : 1.25 - 0.85 * Self.ease((exit - 0.75) / 0.25, 0.29, 0.03, 1.0, 0.38)
            } else if !short {
                let period = body / max(1.0, floor(body / 4.0))
                scale = 1.0 + 0.125 * (1.0 - cos(time / period * .pi * 2.0))
            }
        }
        opacity *= 1.0 - Self.ease((exit - 0.75) / 0.25, 0.43, 0.08, 0.83, 0.31)
        let segment = (body + 0.75) / 3.0
        let thirdDuration = body - segment * 2.0
        let thirdTarget = thirdDuration / segment
        let gap = self.diameter * 0.6
        let width = self.diameter * 3.0 + gap * 2.0
        context.translateBy(x: self.diameter * (2.0 / 3.0) + width * 0.5, y: self.bounds.midY)
        context.scaleBy(x: scale, y: scale)
        for index in 0 ..< 3 {
            let entrance = min(1.0, max(0.0, (time - Double(index) * 0.08) / 0.75))
            let lit: Double
            if short || reduceMotion {
                lit = 1.0
            } else if time >= body {
                lit = index < 2 ? 1.0 : thirdTarget + (1.0 - thirdTarget) * min(1.0, exit / 0.75)
            } else {
                let length = index == 2 ? thirdDuration : segment
                let target = index == 2 ? thirdTarget : 1.0
                lit = target * Self.ease((time - Double(index) * segment) / length, 0.56, 0.01, 0.45, 1.0)
            }
            context.setFillColor(self.color.withAlphaComponent(CGFloat(opacity * entrance * entrance * (0.2 + 0.7 * lit))).cgColor)
            context.fillEllipse(in: CGRect(x: -width * 0.5 + CGFloat(index) * (self.diameter + gap),
                y: -self.diameter * 0.5, width: self.diameter, height: self.diameter))
        }
    }

    private static func ease(_ progress: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        let progress = min(1.0, max(0.0, progress))
        func coordinate(_ t: Double, _ first: Double, _ second: Double) -> Double {
            let inverse = 1.0 - t
            return 3.0 * inverse * inverse * t * first + 3.0 * inverse * t * t * second + t * t * t
        }
        var lower = 0.0
        var upper = 1.0
        for _ in 0 ..< 14 {
            let middle = (lower + upper) * 0.5
            if coordinate(middle, x1, x2) < progress { lower = middle } else { upper = middle }
        }
        return coordinate((lower + upper) * 0.5, y1, y2)
    }
}

private final class NextgramLyricCell: UITableViewCell {
    private let lyricLabel = NextgramLyricTextLabel()
    private let interludeDots = NextgramInterludeDotsView(frame: .zero)
    private let stack = UIView()
    private let seekHighlight = UIView()
    private var seekFeedbackGeneration = 0
    private var showingSeekFeedback = false
    private let blurredText = UIImageView()
    private static let blurContext = CIContext(options: [.cacheIntermediates: false])
    private var effects = NagramLyricsEffects.none
    private var active = false
    private var distance = 0
    private var blurSize = CGSize.zero
    private var renderedBlurRadius: CGFloat = 0.0
    private let translationLabel = UILabel()
    private var timed = false
    private var line: NextgramLyricLine?
    private var color = UIColor.white
    private var font = UIFont.systemFont(ofSize: 28.0, weight: .bold)
    private var wordProgress: [Int] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        self.backgroundColor = .clear
        self.contentView.backgroundColor = .clear
        self.selectionStyle = .none
        self.isAccessibilityElement = true
        self.lyricLabel.numberOfLines = 0
        self.lyricLabel.lineBreakMode = .byWordWrapping
        self.lyricLabel.textColor = .white
        self.lyricLabel.isAccessibilityElement = false
        self.translationLabel.numberOfLines = 0
        self.translationLabel.isAccessibilityElement = false
        let stack = self.stack
        stack.addSubview(self.lyricLabel)
        stack.addSubview(self.interludeDots)
        stack.addSubview(self.translationLabel)
        self.blurredText.isUserInteractionEnabled = false
        self.blurredText.isAccessibilityElement = false
        self.seekHighlight.isUserInteractionEnabled = false
        self.seekHighlight.layer.cornerRadius = 16.0
        self.seekHighlight.layer.cornerCurve = .continuous
        self.seekHighlight.alpha = 0.0
        self.contentView.addSubview(self.seekHighlight)
        self.contentView.addSubview(stack)
        self.contentView.addSubview(self.blurredText)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.layer.removeAnimation(forKey: "nextgram.lyricScroll")
        self.seekFeedbackGeneration += 1
        self.showingSeekFeedback = false
        self.seekHighlight.layer.removeAllAnimations()
        self.seekHighlight.alpha = 0.0
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        guard !self.showingSeekFeedback else { return }
        self.seekHighlight.alpha = highlighted && self.timed && self.line?.text.isEmpty == false ? 1.0 : 0.0
    }

    func showSeekFeedback() {
        self.seekFeedbackGeneration += 1
        let generation = self.seekFeedbackGeneration
        self.showingSeekFeedback = true
        self.seekHighlight.layer.removeAllAnimations()
        UIView.performWithoutAnimation {
            self.seekHighlight.alpha = 1.0
        }
        UIView.animate(withDuration: 0.24, delay: 0.16, options: [.allowUserInteraction]) {
            self.seekHighlight.alpha = 0.0
        } completion: { [weak self] _ in
            guard let self, self.seekFeedbackGeneration == generation else { return }
            self.showingSeekFeedback = false
        }
    }

    func configure(line: NextgramLyricLine, nextTime: Double?, font: UIFont, color: UIColor, active: Bool, effects: NagramLyricsEffects, showsTranslation: Bool) {
        self.stack.layer.removeAllAnimations()
        self.blurredText.layer.removeAllAnimations()
        self.effects = effects
        self.blurSize = .zero
        self.blurredText.image = nil
        self.line = line
        self.interludeDots.start = line.time ?? 0.0
        self.interludeDots.end = nextTime
        self.interludeDots.diameter = font.pointSize * 0.3
        self.interludeDots.color = color
        self.lyricLabel.lyricLine = line
        self.lyricLabel.lyricColor = color
        self.color = color
        self.seekHighlight.backgroundColor = color.withAlphaComponent(0.20)
        self.font = font
        self.wordProgress = []
        self.timed = line.time != nil
        let text = line.text.isEmpty ? (self.timed ? "•••" : " ") : line.text
        self.lyricLabel.text = text
        self.lyricLabel.font = font
        self.lyricLabel.textColor = color
        let translation = showsTranslation ? line.translation : nil
        self.translationLabel.text = translation
        self.translationLabel.isHidden = translation == nil
        self.translationLabel.font = .systemFont(ofSize: max(13, font.pointSize * 0.56), weight: .semibold)
        self.translationLabel.textColor = color.withAlphaComponent(0.76)
        self.accessibilityLabel = translation.map { text + "\n" + $0 } ?? text
        if let timestamp = line.time, timestamp.isFinite {
            let seconds = Int(max(0.0, min(359999.0, timestamp)))
            self.accessibilityValue = String(format: "%d:%02d", seconds / 60, seconds % 60)
        } else {
            self.accessibilityValue = nil
        }
        self.setActive(active, animated: false)
    }

    func setActive(_ active: Bool, animated: Bool) {
        if self.active != active { self.blurSize = .zero }
        self.active = active
        let interlude = self.effects.interlude && self.timed && self.line?.text.isEmpty == true
        self.lyricLabel.isHidden = interlude
        self.interludeDots.isHidden = !interlude || !active
        self.lyricLabel.isActiveLine = active
        self.lyricLabel.wordFloatEnabled = !self.browsing && self.effects.wordFloat && self.timed && !UIAccessibility.isReduceMotionEnabled
        self.lyricLabel.sweepEnabled = !self.browsing && active && self.effects.wordHighlight && self.line?.words.isEmpty == false
        self.lyricLabel.glowEnabled = self.lyricLabel.sweepEnabled && self.effects.glow
        self.lyricLabel.layer.shadowColor = self.color.cgColor
        self.lyricLabel.layer.shadowRadius = 6.0
        self.lyricLabel.layer.shadowOffset = .zero
        self.lyricLabel.layer.shadowOpacity = !self.browsing && active && self.effects.glow && self.line?.words.isEmpty == false && !self.lyricLabel.sweepEnabled ? 0.65 : 0.0
        self.lyricLabel.setNeedsDisplay()
        let activeOpacity: CGFloat = self.line?.words.isEmpty == false ? 1.0 : 0.85
        let alpha: CGFloat = self.browsing ? 1.0 : (self.timed ? (active ? activeOpacity : 0.4) : 0.85)
        var traits: UIAccessibilityTraits = self.timed ? .button : .staticText
        if active {
            traits.insert(.selected)
        }
        self.accessibilityTraits = traits
        if (!active || self.browsing), !self.wordProgress.isEmpty {
            self.wordProgress = []
            self.lyricLabel.attributedText = nil
            self.lyricLabel.text = self.line?.text
        }
        if animated && !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.2, delay: 0.0, options: [.beginFromCurrentState, .allowUserInteraction], animations: {
                self.lyricLabel.alpha = alpha
                self.translationLabel.alpha = alpha
            })
        } else {
            self.lyricLabel.layer.removeAllAnimations()
            self.translationLabel.layer.removeAllAnimations()
            self.lyricLabel.alpha = alpha
            self.translationLabel.alpha = alpha
        }
    }

    func updateWords(at position: Double) {
        guard !self.browsing else { return }
        if !self.interludeDots.isHidden, self.interludeDots.position != position {
            self.interludeDots.position = position
            self.interludeDots.setNeedsDisplay()
        }
        guard let line = self.line, !line.words.isEmpty else { return }
        if self.effects.wordHighlight || self.effects.wordFloat {
            let bounded = max(line.words.first?.time ?? position, min((line.words.last?.end ?? position) + 1.0, position))
            if self.lyricLabel.position != bounded {
                self.lyricLabel.position = bounded
                self.lyricLabel.setNeedsDisplay()
            }
            return
        }
        let progress = line.words.map { word -> Int in
            guard position >= word.time else { return 0 }
            if position >= word.end { return 8 }
            return max(0, min(8, Int((position - word.time) / (word.end - word.time) * 8.0)))
        }
        guard progress != self.wordProgress else { return }
        self.wordProgress = progress
        let text = NSMutableAttributedString(string: line.text, attributes: [
            .foregroundColor: self.color.withAlphaComponent(0.46),
            .font: self.font
        ])
        for (word, step) in zip(line.words, progress) where step > 0 {
            text.addAttribute(.foregroundColor, value: self.color.withAlphaComponent(0.54 + CGFloat(step) * 0.0575), range: word.range)
        }
        self.lyricLabel.attributedText = text
    }

    static func textHeights(line: NextgramLyricLine, font: UIFont, showsTranslation: Bool, width: CGFloat, scale: CGFloat) -> (CGFloat, CGFloat) {
        func height(_ text: String, _ font: UIFont) -> CGFloat {
            let rect = (text as NSString).boundingRect(with: CGSize(width: max(1.0, width), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
            let scale = max(1.0, scale)
            return ceil(max(font.lineHeight, rect.height) * scale) / scale
        }
        let main = height(line.text.isEmpty ? "•••" : line.text, font)
        let translation = showsTranslation ? line.translation.map { height($0, .systemFont(ofSize: max(13.0, font.pointSize * 0.56), weight: .semibold)) } ?? 0.0 : 0.0
        return (main, translation)
    }

    func setDistance(_ distance: Int, animated: Bool) {
        self.distance = distance
        self.updateFocus(animated: animated)
    }

    private var browsing = false

    func setBrowsing(_ browsing: Bool, animated: Bool) {
        guard self.browsing != browsing else { return }
        self.browsing = browsing
        self.setActive(self.active, animated: animated)
        self.updateFocus(animated: animated)
    }

    private var blurRadius: CGFloat {
        guard !self.browsing, self.effects.blur, self.timed, !self.active, self.line?.text.isEmpty == false else { return 0.0 }
        guard self.effects.layeredBlur else { return 2.0 }
        switch self.distance {
        case 0, 1: return 0.75
        case 2: return 1.5
        case 3: return 2.25
        default: return 3.0
        }
    }

    private func updateFocus(animated: Bool) {
        let blur = self.blurRadius > 0.0
        let scale: CGFloat = !self.browsing && self.effects.scale && self.timed && !self.active ? 0.94 : 1.0
        let transform = CGAffineTransform(translationX: -self.stack.bounds.width * (1.0 - scale) * 0.5, y: 0.0)
            .scaledBy(x: scale, y: scale)
        let update = {
            self.stack.transform = transform
            self.blurredText.transform = transform
            self.stack.alpha = blur ? 0.0 : 1.0
            self.blurredText.alpha = blur ? 0.4 : 0.0
        }
        if animated && !UIAccessibility.isReduceMotionEnabled {
            if self.effects.springScroll {
                UIView.animate(withDuration: 0.65, delay: 0.0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.0,
                    options: [.beginFromCurrentState, .allowUserInteraction], animations: update)
            } else {
                UIView.animate(withDuration: 0.3, delay: 0.0,
                    options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut], animations: update)
            }
        } else {
            update()
        }
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.seekHighlight.frame = self.contentView.bounds.insetBy(dx: 12.0, dy: 3.0)
        if let line = self.line {
            let width = max(1.0, self.contentView.bounds.width - 48.0)
            let heights = Self.textHeights(line: line, font: self.font, showsTranslation: !self.translationLabel.isHidden, width: width, scale: self.traitCollection.displayScale)
            let height = heights.0 + (heights.1 > 0.0 ? 6.0 + heights.1 : 0.0)
            self.stack.bounds = CGRect(x: 0.0, y: 0.0, width: width, height: height)
            self.stack.center = CGPoint(x: self.contentView.bounds.midX, y: 14.0 + height * 0.5)
            let floatPadding: CGFloat = self.effects.wordFloat ? 4.0 : 0.0
            self.lyricLabel.frame = CGRect(x: 0.0, y: -floatPadding, width: width, height: heights.0 + floatPadding * 2.0)
            let dotPadding = self.font.pointSize * 0.2
            self.interludeDots.frame = CGRect(x: -dotPadding, y: 0.0, width: width + dotPadding * 2.0, height: heights.0)
            self.translationLabel.frame = CGRect(x: 0.0, y: heights.0 + 6.0, width: width, height: heights.1)
        }
        let scale: CGFloat = !self.browsing && self.effects.scale && self.timed && !self.active ? 0.94 : 1.0
        let transform = CGAffineTransform(translationX: -self.stack.bounds.width * (1.0 - scale) * 0.5, y: 0.0)
            .scaledBy(x: scale, y: scale)
        if self.stack.transform != transform { self.stack.transform = transform }
        if self.blurredText.transform != transform { self.blurredText.transform = transform }
        self.blurredText.bounds = self.stack.bounds.insetBy(dx: -6.0, dy: -6.0)
        self.blurredText.center = self.stack.center
        let radius = self.blurRadius
        guard radius > 0.0, self.stack.bounds.width > 0.0, self.stack.bounds.height > 0.0,
              self.blurSize != self.stack.bounds.size || self.renderedBlurRadius != radius else { return }
        self.blurSize = self.stack.bounds.size
        self.renderedBlurRadius = radius
        let alpha = self.stack.layer.opacity
        let textAlpha = self.lyricLabel.layer.opacity
        let translationAlpha = self.translationLabel.layer.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.stack.layer.opacity = 1.0
        self.lyricLabel.layer.opacity = 1.0
        self.translationLabel.layer.opacity = 1.0
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(2.0, self.traitCollection.displayScale)
        let size = CGSize(width: self.stack.bounds.width + 12.0, height: self.stack.bounds.height + 12.0)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: 6.0, y: 6.0)
            self.stack.layer.render(in: context.cgContext)
        }
        self.stack.layer.opacity = alpha
        self.lyricLabel.layer.opacity = textAlpha
        self.translationLabel.layer.opacity = translationAlpha
        CATransaction.commit()
        if let input = CIImage(image: image),
           let filter = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputImageKey: input, kCIInputRadiusKey: radius * format.scale]),
           let output = filter.outputImage,
           let bitmap = Self.blurContext.createCGImage(output, from: input.extent) {
            self.blurredText.image = UIImage(cgImage: bitmap, scale: format.scale, orientation: .up)
        }
    }

}

final class NextgramLyricsView: UIView, UITableViewDataSource, UITableViewDelegate {
    var seek: ((Double) -> Void)?

    private let edgeMask = CAGradientLayer()
    private var effects = NagramLyricsEffects.none
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let placeholderLabel = UILabel()
    private var lyrics: NextgramLyrics?
    private var showsTranslation = true
    private var lyricFont = NextgramLyricsView.font(size: 28.0)
    private var fontSize: CGFloat = 28.0
    private var color = UIColor.white
    private var position = 0.0
    private var activeIndex: Int?
    private var needsCentering = true
    private var manualScrollUntil = 0.0
    var followsPlayback = false
    private var browsing = false
    private var returningToPlayback = false
    private var scrollGeneration = 0
    private var smoothScrollAnimator: DisplayLinkAnimator?
    private var reduceMotion = UIAccessibility.isReduceMotionEnabled

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)

        self.backgroundColor = .clear
        self.clipsToBounds = true
        self.tableView.backgroundColor = .clear
        self.tableView.separatorStyle = .none
        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.estimatedRowHeight = 96.0
        self.tableView.showsVerticalScrollIndicator = false
        self.tableView.contentInsetAdjustmentBehavior = .never
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.register(NextgramLyricCell.self, forCellReuseIdentifier: "Lyric")
        self.addSubview(self.tableView)

        self.placeholderLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        self.placeholderLabel.font = Self.font(size: 20.0)
        self.placeholderLabel.numberOfLines = 0
        self.placeholderLabel.textAlignment = .center
        self.addSubview(self.placeholderLabel)
        self.tableView.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func font(size: CGFloat) -> UIFont {
        let font = UIFont.systemFont(ofSize: size, weight: .bold)
        return font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? font
    }

    func resetBrowsing() {
        self.manualScrollUntil = 0.0
        self.setBrowsing(false)
        self.cancelRowMotion()
    }

    func update(lyrics: NextgramLyrics?, placeholder: String, fontSize: CGFloat, color: UIColor, effects: NagramLyricsEffects = .none, showsTranslation: Bool = true) {
        let fontSize = fontSize.isFinite ? min(64.0, max(12.0, fontSize)) : 28.0
        let lyricsChanged = self.lyrics != lyrics
        let fontChanged = self.fontSize != fontSize
        let colorChanged = self.color != color
        let effects = lyrics?.isSynced == true ? effects : .none
        let effectsChanged = self.effects != effects || self.showsTranslation != showsTranslation
        let motionChanged = self.reduceMotion != UIAccessibility.isReduceMotionEnabled
        self.reduceMotion = UIAccessibility.isReduceMotionEnabled
        self.effects = effects
        self.showsTranslation = showsTranslation
        self.layer.mask = effects.edgeFade && !self.browsing ? self.edgeMask : nil
        self.placeholderLabel.text = placeholder
        let hasLines = lyrics?.lines.isEmpty == false
        self.tableView.isHidden = !hasLines
        self.placeholderLabel.isHidden = hasLines
        guard lyricsChanged || fontChanged || colorChanged || effectsChanged || motionChanged else {
            return
        }

        self.lyrics = lyrics
        self.fontSize = fontSize
        self.color = color
        self.placeholderLabel.textColor = color.withAlphaComponent(0.85)
        self.lyricFont = Self.font(size: fontSize)
        self.tableView.estimatedRowHeight = lyrics?.isSynced == true ? fontSize * 2.0 + 28.0 : 0.0
        self.tableView.allowsSelection = lyrics?.isSynced == true
        self.activeIndex = lyrics?.currentLineIndex(at: self.position)
        self.needsCentering = true
        if lyricsChanged && !self.browsing {
            self.manualScrollUntil = 0.0
        }
        self.cancelRowMotion()
        self.tableView.reloadData()
        self.setNeedsLayout()
        self.layoutIfNeeded()
        if self.activeIndex == nil && lyricsChanged && !self.browsing {
            self.tableView.setContentOffset(CGPoint(x: 0.0, y: -self.tableView.contentInset.top), animated: false)
        }
        self.centerActiveLineIfNeeded(animated: false)
    }

    func updatePosition(_ timestamp: Double, force: Bool = false) {
        guard timestamp.isFinite else {
            return
        }
        self.position = max(0.0, timestamp)
        if force {
            if !self.browsing {
                self.cancelRowMotion()
            }
            self.needsCentering = true
        }
        let index = self.lyrics?.currentLineIndex(at: self.position)
        if self.activeIndex != index {
            self.activeIndex = index
            self.needsCentering = true
            self.updateVisibleFocus(animated: true)
        }
        if self.effects.wordFloat {
            for case let cell as NextgramLyricCell in self.tableView.visibleCells { cell.updateWords(at: self.position) }
        } else if let index, let cell = self.tableView.cellForRow(at: IndexPath(row: index, section: 0)) as? NextgramLyricCell {
            cell.updateWords(at: self.position)
        }
        self.resumeFollowingPlaybackIfNeeded()
        self.centerActiveLineIfNeeded(animated: !force)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard self.bounds.width > 0.0, self.bounds.height > 0.0 else {
            self.tableView.frame = self.bounds
            return
        }
        self.edgeMask.frame = self.bounds
        self.edgeMask.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        self.edgeMask.locations = [0.0, 0.1, 0.88, 1.0]
        let overscan: CGFloat = self.effects.springScroll || self.effects.stagger ? max(160.0, self.bounds.height * 0.6) : 0.0
        let tableFrame = self.bounds.insetBy(dx: 0.0, dy: -overscan)
        let sizeChanged = self.tableView.frame.size != tableFrame.size
        let widthChanged = self.tableView.frame.width != tableFrame.width
        self.tableView.frame = tableFrame
        if widthChanged { self.tableView.reloadData() }
        self.placeholderLabel.frame = self.bounds.insetBy(dx: 24.0, dy: 24.0)
        let inset = self.lyrics?.isSynced == true
            ? max(24.0, self.tableView.bounds.height * 0.5 - self.fontSize * 0.75 - 14.0) : 24.0
        let contentInset = UIEdgeInsets(top: inset, left: 0.0, bottom: inset, right: 0.0)
        if self.tableView.contentInset != contentInset {
            self.tableView.contentInset = contentInset
        }
        if sizeChanged {
            self.needsCentering = true
        }
        self.centerActiveLineIfNeeded(animated: false)
    }

    private func centerActiveLineIfNeeded(animated: Bool, returningFromBrowse: Bool = false) {
        let targetIndex = self.activeIndex ?? (self.lyrics?.isSynced == true ? 0 : nil)
        guard self.needsCentering, !self.tableView.isHidden, self.bounds.height > 0.0,
              !self.tableView.isDragging, !self.tableView.isDecelerating,
              !self.browsing, !self.returningToPlayback,
              let targetIndex, self.lyrics?.lines.indices.contains(targetIndex) == true else {
            return
        }
        self.needsCentering = false
        let path = IndexPath(row: targetIndex, section: 0)
        let animate = animated && !UIAccessibility.isReduceMotionEnabled
        if animate && (returningFromBrowse || self.effects.linearScroll || self.effects.springScroll || self.effects.stagger) {
            self.tableView.layoutIfNeeded()
            let target = self.centeredOffset(for: path)
            if returningFromBrowse {
                self.animateContentOffset(to: target, focusedRow: targetIndex, returningFromBrowse: true)
            } else if self.effects.springScroll || self.effects.stagger {
                self.animateRows(to: target, focusedRow: targetIndex)
            } else {
                self.animateContentOffset(to: target, focusedRow: targetIndex)
            }
        } else {
            self.cancelRowMotion()
            self.tableView.scrollToRow(at: path, at: .middle, animated: animate)
        }
    }

    private func centeredOffset(for path: IndexPath) -> CGFloat {
        let row = self.tableView.rectForRow(at: path)
        let minY = -self.tableView.contentInset.top
        let maxY = max(minY, self.tableView.contentSize.height - self.tableView.bounds.height + self.tableView.contentInset.bottom)
        return min(maxY, max(minY, row.midY - self.tableView.bounds.height * 0.5))
    }

    private func smoothScrollDuration(focusedRow: Int) -> Double {
        let nextTime = self.lyrics?.lines.dropFirst(focusedRow + 1).first(where: { $0.time != nil })?.time
        return min(0.52, max(0.16, ((nextTime ?? .infinity) - self.position) * 0.82))
    }

    private func animateContentOffset(to target: CGFloat, focusedRow: Int, returningFromBrowse: Bool = false) {
        self.cancelRowMotion()
        let start = self.tableView.contentOffset.y
        let distance = target - start
        guard abs(distance) > 0.5, returningFromBrowse || abs(distance) < self.bounds.height * 0.9 else {
            self.tableView.scrollToRow(at: IndexPath(row: focusedRow, section: 0), at: .middle, animated: false)
            return
        }
        // Scroll through real table coordinates so entering rows are laid out when they appear.
        let duration = returningFromBrowse
            ? min(0.8, 0.36 + 0.16 * Double(abs(distance) / max(1.0, self.bounds.height)))
            : self.smoothScrollDuration(focusedRow: focusedRow)
        self.returningToPlayback = returningFromBrowse
        self.smoothScrollAnimator = DisplayLinkAnimator(duration: duration,
            from: 0.0, to: 1.0, update: { [weak self] progress in
                let eased = bezierPoint(0.26, 0.0, 0.24, 1.0, progress)
                self?.tableView.setContentOffset(CGPoint(x: 0.0, y: start + distance * eased), animated: false)
            }, completion: { [weak self] in
                guard let self else { return }
                self.smoothScrollAnimator = nil
                self.returningToPlayback = false
                if returningFromBrowse {
                    self.centerActiveLineIfNeeded(animated: true, returningFromBrowse: true)
                }
            })
    }

    private func animateRows(to target: CGFloat, focusedRow: Int) {
        let oldOffset = self.tableView.contentOffset.y
        let travel = target - oldOffset
        guard abs(travel) > 0.5, abs(travel) < self.bounds.height * 0.9 else {
            self.cancelRowMotion()
            self.tableView.setContentOffset(CGPoint(x: 0.0, y: target), animated: false)
            return
        }
        var oldPositions: [IndexPath: CGFloat] = [:]
        for path in self.tableView.indexPathsForVisibleRows ?? [] {
            guard let cell = self.tableView.cellForRow(at: path) else { continue }
            oldPositions[path] = cell.frame.minY - oldOffset + (cell.layer.presentation()?.transform.m42 ?? 0.0)
        }
        self.cancelRowMotion()
        let generation = self.scrollGeneration
        UIView.performWithoutAnimation {
            self.tableView.setContentOffset(CGPoint(x: 0.0, y: target), animated: false)
            self.tableView.layoutIfNeeded()
        }
        self.tableView.allowsSelection = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.scrollGeneration == generation else { return }
            self.tableView.allowsSelection = true
        }
        let smooth = self.effects.linearScroll && !self.effects.springScroll
        let smoothDuration = smooth ? self.smoothScrollDuration(focusedRow: focusedRow) : 0.0
        let staggerStep = smooth ? min(0.045, smoothDuration * 0.07) : 0.045
        for path in self.tableView.indexPathsForVisibleRows ?? [] {
            guard let cell = self.tableView.cellForRow(at: path) else { continue }
            let from = (oldPositions[path] ?? (cell.frame.minY - oldOffset)) - (cell.frame.minY - target)
            let delay = self.effects.stagger ? Double(min(4, max(0, path.row - focusedRow))) * staggerStep : 0.0
            let animation: CABasicAnimation
            if self.effects.springScroll {
                let spring = CASpringAnimation(keyPath: "transform.translation.y")
                spring.mass = 1.0
                spring.stiffness = 150.0
                spring.damping = 20.0
                spring.initialVelocity = 0.0
                spring.duration = spring.settlingDuration
                animation = spring
            } else {
                animation = CABasicAnimation(keyPath: "transform.translation.y")
                animation.duration = smooth ? smoothDuration * 0.86 : 0.48
                animation.timingFunction = smooth
                    ? CAMediaTimingFunction(controlPoints: 0.26, 0.0, 0.24, 1.0)
                    : CAMediaTimingFunction(name: .linear)
            }
            animation.fromValue = from
            animation.toValue = 0.0
            animation.beginTime = CACurrentMediaTime() + delay
            animation.fillMode = .backwards
            cell.layer.add(animation, forKey: "nextgram.lyricScroll")
        }
        CATransaction.commit()
    }

    private func cancelRowMotion(preservingPosition: Bool = false) {
        self.smoothScrollAnimator?.invalidate()
        self.smoothScrollAnimator = nil
        self.returningToPlayback = false
        self.scrollGeneration += 1
        if preservingPosition, let index = self.activeIndex,
           let cell = self.tableView.cellForRow(at: IndexPath(row: index, section: 0)),
           let presentation = cell.layer.presentation(), cell.layer.animation(forKey: "nextgram.lyricScroll") != nil {
            let minY = -self.tableView.contentInset.top
            let maxY = max(minY, self.tableView.contentSize.height - self.tableView.bounds.height + self.tableView.contentInset.bottom)
            let offset = min(maxY, max(minY, self.tableView.contentOffset.y - presentation.transform.m42))
            self.tableView.setContentOffset(CGPoint(x: 0.0, y: offset), animated: false)
        }
        self.tableView.layer.removeAllAnimations()
        for cell in self.tableView.visibleCells { cell.layer.removeAnimation(forKey: "nextgram.lyricScroll") }
        self.tableView.allowsSelection = self.lyrics?.isSynced == true
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let line = self.lyrics?.lines[indexPath.row] else { return self.tableView.estimatedRowHeight }
        let heights = NextgramLyricCell.textHeights(line: line, font: self.lyricFont, showsTranslation: self.showsTranslation,
            width: tableView.bounds.width - 48.0, scale: self.traitCollection.displayScale)
        return heights.0 + (heights.1 > 0.0 ? 6.0 + heights.1 : 0.0) + 28.0
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.lyrics?.lines.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Lyric", for: indexPath)
        if let cell = cell as? NextgramLyricCell, let lyrics = self.lyrics, lyrics.lines.indices.contains(indexPath.row) {
            let nextTime = lyrics.lines.dropFirst(indexPath.row + 1).compactMap { $0.time }.first
            cell.configure(line: lyrics.lines[indexPath.row], nextTime: nextTime, font: self.lyricFont, color: self.color, active: self.activeIndex == indexPath.row, effects: self.effects, showsTranslation: self.showsTranslation)
            cell.setBrowsing(self.browsing, animated: false)
            cell.setDistance(abs(indexPath.row - (self.activeIndex ?? indexPath.row)), animated: false)
            if self.activeIndex == indexPath.row || self.effects.wordFloat { cell.updateWords(at: self.position) }
        }
        return cell
    }

    private func updateVisibleFocus(animated: Bool) {
        for path in self.tableView.indexPathsForVisibleRows ?? [] {
            guard let cell = self.tableView.cellForRow(at: path) as? NextgramLyricCell else { continue }
            cell.setActive(self.activeIndex == path.row, animated: animated)
            cell.setDistance(abs(path.row - (self.activeIndex ?? path.row)), animated: animated)
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard let lyrics = self.lyrics, lyrics.isSynced, lyrics.lines.indices.contains(indexPath.row),
              !lyrics.lines[indexPath.row].text.isEmpty,
              let timestamp = lyrics.lines[indexPath.row].time, timestamp.isFinite else {
            return
        }
        self.manualScrollUntil = 0.0
        self.setBrowsing(false)
        self.updatePosition(timestamp, force: true)
        self.seek?(timestamp)
        tableView.layoutIfNeeded()
        (tableView.cellForRow(at: indexPath) as? NextgramLyricCell)?.showSeekFeedback()
    }

#if DEBUG && targetEnvironment(simulator)
    func previewSeekVisibleLine() {
        guard let lyrics = self.lyrics,
              let path = self.tableView.indexPathsForVisibleRows?.first(where: {
                  $0.row > (self.activeIndex ?? -1) && !lyrics.lines[$0.row].text.isEmpty
              }) else { return }
        self.tableView(self.tableView, didSelectRowAt: path)
    }
#endif

    private func setBrowsing(_ browsing: Bool) {
        guard self.browsing != browsing else { return }
        self.browsing = browsing
        self.layer.mask = self.effects.edgeFade && !browsing ? self.edgeMask : nil
        for path in self.tableView.indexPathsForVisibleRows ?? [] {
            (self.tableView.cellForRow(at: path) as? NextgramLyricCell)?.setBrowsing(browsing, animated: !browsing)
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        self.setBrowsing(true)
        self.cancelRowMotion(preservingPosition: true)
        self.needsCentering = true
        self.manualScrollUntil = ProcessInfo.processInfo.systemUptime + 5.0
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.isDragging || scrollView.isDecelerating {
            self.setBrowsing(true)
            self.manualScrollUntil = ProcessInfo.processInfo.systemUptime + 5.0
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            self.finishManualScrolling()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        self.finishManualScrolling()
    }

    private func finishManualScrolling() {
        self.manualScrollUntil = ProcessInfo.processInfo.systemUptime + 5.0
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.05) { [weak self] in
            self?.resumeFollowingPlaybackIfNeeded()
        }
    }

    private func resumeFollowingPlaybackIfNeeded() {
        guard self.lyrics?.isSynced == true, self.followsPlayback, self.browsing, !self.tableView.isDragging, !self.tableView.isDecelerating,
              ProcessInfo.processInfo.systemUptime >= self.manualScrollUntil else { return }
        self.setBrowsing(false)
        self.needsCentering = true
        self.centerActiveLineIfNeeded(animated: true, returningFromBrowse: true)
    }
}
