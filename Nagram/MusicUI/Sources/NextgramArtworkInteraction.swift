import CoreMotion
import UIKit

/// Local device-motion parallax only; no motion data is stored or transmitted.
final class NextgramInteractiveArtwork: UIView, UIGestureRecognizerDelegate {
    private let pressurePlane = UIView()
    private let imageView = UIImageView()
    var image: UIImage? {
        get { self.imageView.image }
        set { self.imageView.image = newValue }
    }
    override var contentMode: UIView.ContentMode { didSet { self.imageView.contentMode = self.contentMode } }
    var open: (() -> Void)? { didSet { self.tap.isEnabled = self.open != nil } }
    var motionEnabled = false { didSet { self.updateMotion() } }
    private let motion = CMMotionManager()
    private var tilt = CGPoint.zero
    private var touchTilt = CGPoint.zero
    private var pressed = false
    private var reference: CMAttitude?
    private var lastMotionTime: TimeInterval?
    private let tap = UITapGestureRecognizer()
    private let press = UILongPressGestureRecognizer()
    private let edgeHighlight = CAShapeLayer()
    private let reflection = CAGradientLayer()
    var pressureGestureRecognizer: UIGestureRecognizer { self.press }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Round the image inside the projected plane; never mask the 3D container itself.
        self.imageView.clipsToBounds = true
        self.imageView.isAccessibilityElement = false
        self.pressurePlane.addSubview(self.imageView)
        self.addSubview(self.pressurePlane)
        self.isAccessibilityElement = true
        self.isUserInteractionEnabled = true
        self.tap.addTarget(self, action: #selector(self.tapped))
        self.press.addTarget(self, action: #selector(self.pressChanged(_:)))
        self.press.minimumPressDuration = 0
        self.press.allowableMovement = 1000
        self.press.delegate = self
        self.tap.require(toFail: self.press)
        self.tap.isEnabled = false
        self.press.isEnabled = false
        self.addGestureRecognizer(self.tap)
        self.addGestureRecognizer(self.press)
        self.accessibilityTraits = .button
        self.edgeHighlight.fillColor = UIColor.clear.cgColor
        self.edgeHighlight.strokeColor = UIColor.white.cgColor
        self.edgeHighlight.lineWidth = 1
        self.edgeHighlight.opacity = 0
        self.imageView.layer.addSublayer(self.edgeHighlight)
        self.reflection.colors = [UIColor.clear.cgColor, UIColor.white.withAlphaComponent(0.10).cgColor,
            UIColor.white.withAlphaComponent(0.02).cgColor, UIColor.clear.cgColor]
        self.reflection.locations = [0, 0.46, 0.56, 1]
        self.reflection.startPoint = CGPoint(x: 0, y: 0)
        self.reflection.endPoint = CGPoint(x: 1, y: 1)
        self.reflection.opacity = 0
        self.imageView.layer.addSublayer(self.reflection)
        NotificationCenter.default.addObserver(self, selector: #selector(self.motionAccessibilityChanged), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { self.motion.stopDeviceMotionUpdates(); NotificationCenter.default.removeObserver(self) }
    @objc private func motionAccessibilityChanged() { self.updateMotion() }

    override func didMoveToWindow() { super.didMoveToWindow(); self.updateMotion() }

    private func updateMotion() {
        let enabled = self.motionEnabled && self.window != nil && !UIAccessibility.isReduceMotionEnabled
        self.press.isEnabled = enabled
        guard enabled else {
            self.motion.stopDeviceMotionUpdates()
            self.reference = nil
            self.tilt = .zero
            self.touchTilt = .zero
            self.pressed = false
            self.lastMotionTime = nil
            self.layer.removeAnimation(forKey: "transform")
            self.layer.transform = CATransform3DIdentity
            self.pressurePlane.layer.removeAnimation(forKey: "transform")
            self.pressurePlane.layer.transform = CATransform3DIdentity
            self.edgeHighlight.opacity = 0
            self.reflection.opacity = 0
            return
        }
        guard !self.motion.isDeviceMotionActive, self.motion.isDeviceMotionAvailable else { return }
        self.motion.deviceMotionUpdateInterval = 1.0 / 60.0
        self.motion.startDeviceMotionUpdates(to: .main) { [weak self] value, _ in
            guard let self, let value else { return }
            if self.reference == nil { self.reference = value.attitude.copy() as? CMAttitude }
            guard let reference = self.reference, let attitude = value.attitude.copy() as? CMAttitude else { return }
            attitude.multiply(byInverseOf: reference)
            self.updateDeviceMotion(roll: attitude.roll, pitch: attitude.pitch, timestamp: value.timestamp)
        }
    }

    private func updateDeviceMotion(roll: Double, pitch: Double, timestamp: TimeInterval) {
        guard self.motionEnabled, self.window != nil, !UIAccessibility.isReduceMotionEnabled,
              roll.isFinite, pitch.isFinite, timestamp.isFinite else { return }
        if let previous = self.lastMotionTime, timestamp <= previous { return }
        let interval = min(0.1, max(0.001, timestamp - (self.lastMotionTime ?? (timestamp - 1.0 / 60.0))))
        self.lastMotionTime = timestamp
        // Relative to the opening pose, expressed in the visible screen's axes.
        var x = CGFloat(roll), y = CGFloat(pitch)
        switch self.window?.windowScene?.interfaceOrientation {
        case .landscapeLeft: (x, y) = (-y, x)
        case .landscapeRight: (x, y) = (y, -x)
        case .portraitUpsideDown: (x, y) = (-x, -y)
        default: break
        }
        func target(_ angle: CGFloat, limit: CGFloat) -> CGFloat {
            let magnitude = max(0, abs(angle) - 0.003) * 0.85
            return min(limit, magnitude) * (angle < 0 ? -1 : 1)
        }
        let blend = CGFloat(1.0 - exp(-interval / 0.075))
        self.tilt.x += (target(x, limit: 0.32) - self.tilt.x) * blend
        self.tilt.y += (target(y, limit: 0.24) - self.tilt.y) * blend
        if abs(self.tilt.x) < 0.00001 { self.tilt.x = 0 }
        if abs(self.tilt.y) < 0.00001 { self.tilt.y = 0 }
        self.applyDeviceMotionTransform()
        self.updateReflection()
    }

    private func applyDeviceMotionTransform() {
        guard self.motionEnabled, self.bounds.width > 0, self.bounds.height > 0,
              self.tilt.x != 0 || self.tilt.y != 0 else {
            self.layer.transform = CATransform3DIdentity
            return
        }
        // Project around the lower edge: its baseline stays put while the upper corners recede.
        let pivot = self.bounds.height * 0.5
        var transform = CATransform3DMakeTranslation(0, -pivot, 0)
        transform = CATransform3DConcat(transform, CATransform3DMakeRotation(-self.tilt.y, 1, 0, 0))
        transform = CATransform3DConcat(transform, CATransform3DMakeRotation(self.tilt.x, 0, 1, 0))
        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / max(650.0, self.bounds.width * 2.2)
        transform = CATransform3DConcat(transform, perspective)
        self.layer.transform = CATransform3DConcat(transform, CATransform3DMakeTranslation(0, pivot, 0))
    }

    @objc private func tapped() { if self.image != nil { self.open?() } }
    override func accessibilityActivate() -> Bool {
        guard self.image != nil, let open = self.open else { return false }
        open()
        return true
    }

    @objc private func pressChanged(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            let point = recognizer.location(in: self.superview)
            let normalized = CGPoint(x: 0.5 + (point.x - self.center.x) / max(1, self.bounds.width),
                y: 0.5 + (point.y - self.center.y) / max(1, self.bounds.height))
            self.setPressure(at: normalized, animated: recognizer.state == .began)
        default:
            self.setPressure(at: nil, animated: true)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        return other is UITapGestureRecognizer || other is UIPinchGestureRecognizer
    }

    func setPressure(at point: CGPoint?, animated: Bool) {
        guard self.motionEnabled, !UIAccessibility.isReduceMotionEnabled else { return }
        if let point {
            self.pressed = true
            self.touchTilt = CGPoint(x: max(-1, min(1, (point.x - 0.5) * 2)) * 0.10,
                y: max(-1, min(1, (point.y - 0.5) * 2)) * 0.10)
        } else {
            self.pressed = false
            self.touchTilt = .zero
        }
        if !animated {
            self.pressurePlane.layer.removeAnimation(forKey: "transform")
            self.applyTransform()
        } else if point != nil {
            UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) { self.applyTransform() }
        } else {
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]) { self.applyTransform() }
        }
    }

    private func applyTransform() {
        var transform = CATransform3DIdentity
        let x = self.touchTilt.x
        let y = self.touchTilt.y
        transform.m34 = -1.0 / max(1200.0, self.bounds.width * 3.5)
        transform = CATransform3DRotate(transform, -y, 1, 0, 0)
        transform = CATransform3DRotate(transform, x, 0, 1, 0)
        let scale: CGFloat = self.pressed ? 0.985 : 1
        // Finger pressure animates independently, so live motion cannot cancel its spring.
        self.pressurePlane.layer.transform = CATransform3DScale(transform, scale, scale, 1)
        self.updateReflection()
    }

    private func updateReflection() {
        let x = self.tilt.x + self.touchTilt.x
        let y = self.tilt.y + self.touchTilt.y
        CATransaction.begin()
        let duration = UIView.inheritedAnimationDuration
        CATransaction.setDisableActions(duration == 0)
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        self.edgeHighlight.opacity = Float(min(0.22, 0.06 + abs(x) + abs(y)))
        self.reflection.opacity = self.pressed ? 0.8 : 0.35
        self.reflection.position = CGPoint(x: self.bounds.midX + x * self.bounds.width * 2,
            y: self.bounds.midY + y * self.bounds.height * 2)
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.pressurePlane.bounds = self.bounds
        self.pressurePlane.center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        self.imageView.frame = self.bounds
        self.imageView.layer.cornerRadius = self.layer.cornerRadius
        self.imageView.layer.cornerCurve = self.layer.cornerCurve
        self.edgeHighlight.frame = self.bounds
        self.edgeHighlight.path = UIBezierPath(roundedRect: self.bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: self.layer.cornerRadius).cgPath
        let size = CGSize(width: self.bounds.width * 2.0, height: self.bounds.height * 2.0)
        self.reflection.bounds = CGRect(origin: .zero, size: size)
        self.reflection.position = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        self.applyDeviceMotionTransform()
    }

#if DEBUG && targetEnvironment(simulator)
    func previewDeviceMotion(roll: Double, pitch: Double) {
        self.updateDeviceMotion(roll: roll, pitch: pitch, timestamp: CACurrentMediaTime())
    }
#endif
}

/// Kept inside the player so closing artwork cannot dismiss the music session.
final class NextgramArtworkDetailView: UIView, UIScrollViewDelegate {
    var close: (() -> Void)?
    private let scroll = UIScrollView()
    private let zoomContainer = UIView()
    private let artwork = NextgramInteractiveArtwork(frame: .zero)
    private let glow = CAGradientLayer()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private var showsMetadata: Bool
    private let done = UIButton(type: .system)
    private var insets: UIEdgeInsets
    private let motionAllowed: Bool
    private var lastLayoutSize = CGSize.zero

    init(image: UIImage, title: String, artist: String, insets: UIEdgeInsets, motionEnabled: Bool, showsMetadata: Bool, closeLabel: String) {
        self.insets = insets
        self.motionAllowed = motionEnabled
        self.showsMetadata = showsMetadata
        super.init(frame: .zero)
        self.backgroundColor = .black
        self.glow.type = .radial
        self.glow.colors = [UIColor(white: 0.12, alpha: 1).cgColor, UIColor(white: 0.035, alpha: 1).cgColor, UIColor.black.cgColor]
        self.glow.locations = [0, 0.65, 1]
        self.glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.glow.endPoint = CGPoint(x: 1, y: 1)
        self.layer.addSublayer(self.glow)
        self.accessibilityViewIsModal = true
        self.scroll.delegate = self
        self.scroll.minimumZoomScale = 1
        self.scroll.maximumZoomScale = 4
        self.scroll.clipsToBounds = false
        self.scroll.contentInsetAdjustmentBehavior = .never
        // At 1× there is nothing to pan: a held finger belongs to the cover's pressure interaction.
        // Zooming disables that gesture and restores normal image panning.
        self.scroll.panGestureRecognizer.require(toFail: self.artwork.pressureGestureRecognizer)
        self.artwork.image = image
        self.artwork.clipsToBounds = false
        self.artwork.layer.cornerRadius = 12
        self.artwork.contentMode = .scaleAspectFit
        self.artwork.motionEnabled = motionEnabled
        self.artwork.accessibilityLabel = [title, artist].filter { !$0.isEmpty }.joined(separator: ", ")
        self.artwork.accessibilityTraits = .image
        self.zoomContainer.addSubview(self.artwork)
        self.scroll.addSubview(self.zoomContainer)
        self.addSubview(self.scroll)
        self.titleLabel.text = title
        self.artistLabel.text = artist
        self.titleLabel.font = .preferredFont(forTextStyle: .title2)
        self.artistLabel.font = .preferredFont(forTextStyle: .body)
        self.titleLabel.textColor = .white
        self.artistLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        for label in [self.titleLabel, self.artistLabel] {
            label.numberOfLines = 2
            label.lineBreakMode = .byTruncatingTail
            label.textAlignment = .center
            label.adjustsFontForContentSizeCategory = true
            label.isHidden = !showsMetadata
            self.addSubview(label)
        }
        self.done.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
        self.done.tintColor = .white
        self.done.accessibilityLabel = closeLabel
        self.done.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.addSubview(self.done)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(self.zoomTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        self.scroll.addGestureRecognizer(doubleTap)
        NotificationCenter.default.addObserver(self, selector: #selector(self.backgrounded), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.metadataSizeChanged), name: UIContentSizeCategory.didChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }
    func updateImage(_ image: UIImage) { self.artwork.image = image; self.setNeedsLayout() }
    func updateInsets(_ insets: UIEdgeInsets) { self.insets = insets; self.setNeedsLayout() }
    func updateMetadataVisibility(_ visible: Bool) {
        guard self.showsMetadata != visible else { return }
        self.showsMetadata = visible
        self.titleLabel.isHidden = !visible
        self.artistLabel.isHidden = !visible
        self.setNeedsLayout()
    }
    @objc private func metadataSizeChanged() { self.setNeedsLayout() }
    override func layoutSubviews() {
        super.layoutSubviews()
        self.glow.frame = self.bounds
        let top = max(self.insets.top, 16)
        self.done.frame = CGRect(x: max(self.insets.left, 16), y: top + 16, width: 44, height: 44)
        let left = max(24, self.insets.left + 16)
        let width = max(1, self.bounds.width - left - max(24, self.insets.right + 16))
        let titleHeight = min(self.titleLabel.font.lineHeight * 2, self.titleLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        let artistHeight = min(self.artistLabel.font.lineHeight * 2, self.artistLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        let gap: CGFloat = titleHeight > 0 && artistHeight > 0 ? 6 : 0
        let metadataTop = self.bounds.height - max(self.insets.bottom, 16) - titleHeight - artistHeight - gap - 12
        self.titleLabel.frame = CGRect(x: left, y: metadataTop, width: width, height: titleHeight)
        self.artistLabel.frame = CGRect(x: left, y: metadataTop + titleHeight + gap, width: width, height: artistHeight)
        // Keep the centered cover when it fits; shorten its viewport only when captions would overlap.
        let coverWidth = max(1, self.bounds.width - max(20, self.insets.left + 16) - max(20, self.insets.right + 16))
        let imageSize = self.artwork.image?.size ?? CGSize(width: 1, height: 1)
        let naturalHeight = min(self.bounds.height, imageSize.height * coverWidth / max(1, imageSize.width))
        let captionsOverlap = self.showsMetadata && (self.bounds.height + naturalHeight) * 0.5 > metadataTop - 20
        let availableHeight = captionsOverlap ? max(1, metadataTop - 20) : self.bounds.height
        let available = CGRect(x: max(20, self.insets.left + 16), y: 0,
            width: max(1, self.bounds.width - max(20, self.insets.left + 16) - max(20, self.insets.right + 16)),
            height: max(1, availableHeight))
        self.scroll.frame = available
        if self.lastLayoutSize != available.size {
            self.scroll.setZoomScale(1, animated: false)
            self.lastLayoutSize = available.size
        }
        if self.scroll.zoomScale == 1 {
            self.zoomContainer.frame = CGRect(origin: .zero, size: available.size)
            let image = self.artwork.image?.size ?? CGSize(width: 1, height: 1)
            let ratio = min(available.width / max(1, image.width), available.height / max(1, image.height))
            self.artwork.bounds = CGRect(origin: .zero, size: CGSize(width: image.width * ratio, height: image.height * ratio))
            self.artwork.center = CGPoint(x: available.width / 2, y: available.height / 2)
            self.scroll.contentSize = available.size
        }
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { self.zoomContainer }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        self.artwork.motionEnabled = self.motionAllowed && scrollView.zoomScale <= 1
    }
    @objc private func closePressed() { self.close?() }
    @objc private func backgrounded() { self.close?() }
    override func accessibilityPerformEscape() -> Bool { self.close?(); return true }
    @objc private func zoomTapped(_ recognizer: UITapGestureRecognizer) {
        if self.scroll.zoomScale > 1 { self.scroll.setZoomScale(1, animated: true) }
        else {
            let point = recognizer.location(in: self.zoomContainer)
            let size = CGSize(width: self.scroll.bounds.width / 2, height: self.scroll.bounds.height / 2)
            self.scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }

#if DEBUG && targetEnvironment(simulator)
    func previewPressure(at point: CGPoint?) {
        self.artwork.setPressure(at: point, animated: true)
    }
    func previewDeviceMotion(roll: Double, pitch: Double) {
        self.artwork.previewDeviceMotion(roll: roll, pitch: pitch)
    }
#endif
}
