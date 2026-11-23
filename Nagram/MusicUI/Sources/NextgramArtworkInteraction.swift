import CoreMotion
import UIKit

final class NextgramInteractiveArtwork: UIView, UIGestureRecognizerDelegate {
    private let motionPlane = UIView()
    private let pressurePlane = UIView()
    private let imageView = UIImageView()
    var image: UIImage? {
        get { self.imageView.image }
        set { self.imageView.image = newValue }
    }
    override var contentMode: UIView.ContentMode { didSet { self.imageView.contentMode = self.contentMode } }
    var cornerRadius: CGFloat = 0.0 {
        didSet {
            guard oldValue != self.cornerRadius else { return }
            self.layer.cornerRadius = self.cornerRadius
            self.setNeedsLayout()
        }
    }
    var open: (() -> Void)? { didSet { self.tap.isEnabled = self.open != nil } }
    var motionEnabled = false { didSet { if oldValue != self.motionEnabled { self.updateMotion() } } }
    private var motionManager: CMMotionManager?
    private var referenceAttitude: CMAttitude?
    private var deviceTilt = CGPoint.zero
    private var touchTilt = CGPoint.zero
    private var pressed = false
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
        self.motionPlane.addSubview(self.pressurePlane)
        self.addSubview(self.motionPlane)
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
    deinit {
        self.motionManager?.stopDeviceMotionUpdates()
        NotificationCenter.default.removeObserver(self)
    }
    @objc private func motionAccessibilityChanged() { self.updateMotion() }

    override func didMoveToWindow() { super.didMoveToWindow(); self.updateMotion() }

    private func updateMotion() {
        let enabled = self.motionEnabled && self.window != nil && !UIAccessibility.isReduceMotionEnabled
        self.press.isEnabled = enabled
        if enabled {
            let manager = self.motionManager ?? CMMotionManager()
            self.motionManager = manager
            if manager.isDeviceMotionAvailable && !manager.isDeviceMotionActive {
                manager.deviceMotionUpdateInterval = 1.0 / 60.0
                manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                    guard let self, self.press.isEnabled, let motion else { return }
                    self.updateAttitude(motion.attitude)
                }
            }
        }
        if !enabled {
            self.motionManager?.stopDeviceMotionUpdates()
            self.referenceAttitude = nil
            self.deviceTilt = .zero
            self.motionPlane.layer.transform = CATransform3DIdentity
            self.touchTilt = .zero
            self.pressed = false
            self.pressurePlane.layer.removeAnimation(forKey: "transform")
            self.pressurePlane.layer.transform = CATransform3DIdentity
            self.edgeHighlight.opacity = 0
            self.reflection.opacity = 0
        }
    }

    private func updateAttitude(_ sample: CMAttitude) {
        guard let attitude = sample.copy() as? CMAttitude else { return }
        guard let referenceAttitude = self.referenceAttitude else {
            self.referenceAttitude = attitude
            return
        }
        attitude.multiply(byInverseOf: referenceAttitude)
        self.updateDeviceTilt(x: CGFloat(attitude.roll), y: CGFloat(attitude.pitch))
    }

    private func updateDeviceTilt(x: CGFloat, y: CGFloat) {
        guard x.isFinite, y.isFinite, self.press.isEnabled else { return }
        let target: CGPoint
        let orientation: UIInterfaceOrientation?
        if #available(iOS 16.0, *) {
            orientation = self.window?.windowScene?.effectiveGeometry.interfaceOrientation
        } else {
            orientation = self.window?.windowScene?.interfaceOrientation
        }
        switch orientation {
        case .landscapeLeft: target = CGPoint(x: -y, y: x)
        case .landscapeRight: target = CGPoint(x: y, y: -x)
        case .portraitUpsideDown: target = CGPoint(x: -x, y: -y)
        default: target = CGPoint(x: x, y: y)
        }
        let limit: CGFloat = 0.115
        let gain: CGFloat = 0.42
        let smoothing: CGFloat = 0.16
        let tilt = self.pressed ? CGPoint.zero : target
        self.deviceTilt.x += (max(-limit, min(limit, tilt.x * gain)) - self.deviceTilt.x) * smoothing
        self.deviceTilt.y += (max(-limit, min(limit, tilt.y * gain)) - self.deviceTilt.y) * smoothing
        let intensity = max(abs(self.deviceTilt.x), abs(self.deviceTilt.y)) / limit
        let scale = 1.0 - 0.018 * intensity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.motionPlane.layer.transform = self.coverTransform(tilt: self.deviceTilt, scale: scale)
        CATransaction.commit()
    }

#if DEBUG && targetEnvironment(simulator)
    func previewDeviceTilt(x: CGFloat, y: CGFloat) {
        self.updateDeviceTilt(x: x, y: y)
    }
#endif

    @objc private func tapped() { self.open?() }
    override func accessibilityActivate() -> Bool {
        guard let open = self.open else { return false }
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
        let scale: CGFloat = self.pressed ? 0.985 : 1
        self.pressurePlane.layer.transform = self.coverTransform(tilt: self.touchTilt, scale: scale)
        self.updateReflection()
    }

    private func coverTransform(tilt: CGPoint, scale: CGFloat) -> CATransform3D {
        var transform = CATransform3DIdentity
        transform.m34 = -1.0 / max(1200.0, self.bounds.width * 3.5)
        transform = CATransform3DRotate(transform, -tilt.y, 1, 0, 0)
        transform = CATransform3DRotate(transform, tilt.x, 0, 1, 0)
        return CATransform3DScale(transform, scale, scale, 1)
    }

    private func updateReflection() {
        let x = self.touchTilt.x
        let y = self.touchTilt.y
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
        self.motionPlane.bounds = self.bounds
        self.motionPlane.center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
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
    }
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
    private var motionAllowed: Bool
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
        self.artwork.cornerRadius = 12
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
    func updateMotionEnabled(_ enabled: Bool) {
        self.motionAllowed = enabled
        self.artwork.motionEnabled = enabled && self.scroll.zoomScale <= 1
    }
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

    func previewDeviceTilt(x: CGFloat, y: CGFloat) {
        self.artwork.previewDeviceTilt(x: x, y: y)
    }
#endif
}
