import CoreMotion
import UIKit

/// Local device-motion parallax only; no motion data is stored or transmitted.
final class NextgramInteractiveArtwork: UIImageView {
    var open: (() -> Void)? { didSet { self.tap.isEnabled = self.open != nil } }
    var motionEnabled = false { didSet { self.updateMotion() } }
    private let motion = CMMotionManager()
    private var tilt = CGPoint.zero
    private var touchTilt = CGPoint.zero
    private var pressed = false
    private var reference: CMAttitude?
    private var settlingUntil: CFTimeInterval = 0
    private let tap = UITapGestureRecognizer()
    private let press = UILongPressGestureRecognizer()
    private let edgeHighlight = CAShapeLayer()
    private let reflection = CAShapeLayer()
    var pressureGestureRecognizer: UIGestureRecognizer { self.press }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = true
        self.tap.addTarget(self, action: #selector(self.tapped))
        self.press.addTarget(self, action: #selector(self.pressChanged(_:)))
        self.press.minimumPressDuration = 0.15
        self.press.allowableMovement = 1000
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
        self.layer.addSublayer(self.edgeHighlight)
        self.reflection.fillColor = UIColor.white.withAlphaComponent(0.045).cgColor
        self.reflection.shadowColor = UIColor.white.cgColor
        self.reflection.shadowOpacity = 0.18
        self.reflection.shadowRadius = 35
        self.reflection.opacity = 0
        self.layer.addSublayer(self.reflection)
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
            self.layer.transform = CATransform3DIdentity
            self.edgeHighlight.opacity = 0
            self.reflection.opacity = 0
            return
        }
        guard !self.motion.isDeviceMotionActive, self.motion.isDeviceMotionAvailable else { return }
        self.motion.deviceMotionUpdateInterval = 1.0 / 30.0
        self.motion.startDeviceMotionUpdates(to: .main) { [weak self] value, _ in
            guard let self, let value else { return }
            if self.reference == nil { self.reference = value.attitude.copy() as? CMAttitude }
            guard let reference = self.reference, let attitude = value.attitude.copy() as? CMAttitude else { return }
            attitude.multiply(byInverseOf: reference)
            // Roll/pitch relative to opening the view; rotate axes with the visible interface.
            var x = CGFloat(attitude.roll), y = CGFloat(attitude.pitch)
            switch self.window?.windowScene?.interfaceOrientation {
            case .landscapeLeft: (x, y) = (-y, x)
            case .landscapeRight: (x, y) = (y, -x)
            case .portraitUpsideDown: (x, y) = (-x, -y)
            default: break
            }
            self.tilt.x += (max(-0.07, min(0.07, x * 0.15)) - self.tilt.x) * 0.18
            self.tilt.y += (max(-0.07, min(0.07, y * 0.15)) - self.tilt.y) * 0.18
            if !self.pressed && CACurrentMediaTime() >= self.settlingUntil { self.applyTransform() }
        }
    }

    @objc private func tapped() { if self.image != nil { self.open?() } }
    override func accessibilityActivate() -> Bool {
        guard self.image != nil, let open = self.open else { return false }
        open()
        return true
    }

    @objc private func pressChanged(_ recognizer: UILongPressGestureRecognizer) {
        guard self.motionEnabled, !UIAccessibility.isReduceMotionEnabled else { return }
        switch recognizer.state {
        case .began, .changed:
            self.pressed = true
            let point = recognizer.location(in: self)
            self.touchTilt = CGPoint(x: max(-1, min(1, (point.x / max(1, self.bounds.width) - 0.5) * 2)) * 0.13,
                                     y: max(-1, min(1, (point.y / max(1, self.bounds.height) - 0.5) * 2)) * 0.13)
            if recognizer.state == .began {
                UIView.animate(withDuration: 0.16, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) { self.applyTransform() }
            } else { self.applyTransform() }
        default:
            self.pressed = false
            self.touchTilt = .zero
            self.settlingUntil = CACurrentMediaTime() + 0.42
            UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.72, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction]) { self.applyTransform() }
        }
    }

    private func applyTransform() {
        var transform = CATransform3DIdentity
        transform.m34 = -1.0 / 900.0
        transform = CATransform3DRotate(transform, -(self.tilt.y + self.touchTilt.y), 1, 0, 0)
        transform = CATransform3DRotate(transform, self.tilt.x + self.touchTilt.x, 0, 1, 0)
        let scale: CGFloat = self.pressed ? 0.965 : 1
        self.layer.transform = CATransform3DScale(transform, scale, scale, 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.edgeHighlight.opacity = Float(min(0.5, 0.12 + abs(self.tilt.x + self.touchTilt.x) * 1.5 + abs(self.tilt.y + self.touchTilt.y)))
        self.reflection.opacity = self.pressed ? 1 : 0.65
        self.reflection.position = CGPoint(x: self.bounds.midX + (self.tilt.x + self.touchTilt.x) * self.bounds.width * 3,
                                          y: self.bounds.midY + (self.tilt.y + self.touchTilt.y) * self.bounds.height * 3)
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.edgeHighlight.frame = self.bounds
        self.edgeHighlight.path = UIBezierPath(roundedRect: self.bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: self.layer.cornerRadius).cgPath
        let size = CGSize(width: self.bounds.width * 1.2, height: self.bounds.height * 0.4)
        self.reflection.bounds = CGRect(origin: .zero, size: size)
        self.reflection.path = UIBezierPath(ovalIn: self.reflection.bounds).cgPath
        self.reflection.position = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
    }
}

/// Kept inside the player so closing artwork cannot dismiss the music session.
final class NextgramArtworkDetailView: UIView, UIScrollViewDelegate {
    var close: (() -> Void)?
    private let scroll = UIScrollView()
    private let zoomContainer = UIView()
    private let artwork = NextgramInteractiveArtwork(frame: .zero)
    private let title = UILabel()
    private let artist = UILabel()
    private let done = UIButton(type: .system)
    private var insets: UIEdgeInsets
    private let motionAllowed: Bool
    private var lastLayoutSize = CGSize.zero

    init(image: UIImage, title: String, artist: String, insets: UIEdgeInsets, motionEnabled: Bool, closeLabel: String) {
        self.insets = insets
        self.motionAllowed = motionEnabled
        super.init(frame: .zero)
        self.backgroundColor = UIColor(white: 0.035, alpha: 1)
        self.accessibilityViewIsModal = true
        self.scroll.delegate = self
        self.scroll.minimumZoomScale = 1
        self.scroll.maximumZoomScale = 4
        self.scroll.clipsToBounds = false
        // At 1× there is nothing to pan: a held finger belongs to the cover's pressure interaction.
        // Zooming disables that gesture and restores normal image panning.
        self.scroll.panGestureRecognizer.require(toFail: self.artwork.pressureGestureRecognizer)
        self.artwork.image = image
        self.artwork.clipsToBounds = true
        self.artwork.layer.cornerRadius = 12
        self.artwork.contentMode = .scaleAspectFit
        self.artwork.motionEnabled = motionEnabled
        self.artwork.accessibilityLabel = title
        self.artwork.accessibilityTraits = .image
        self.zoomContainer.addSubview(self.artwork)
        self.scroll.addSubview(self.zoomContainer)
        self.addSubview(self.scroll)
        self.title.text = title
        self.artist.text = artist
        self.title.font = .preferredFont(forTextStyle: .title2)
        self.artist.font = .preferredFont(forTextStyle: .body)
        for label in [self.title, self.artist] {
            label.textColor = .white
            label.textAlignment = .center
            label.numberOfLines = 2
            label.adjustsFontForContentSizeCategory = true
            self.addSubview(label)
        }
        self.artist.textColor = UIColor.white.withAlphaComponent(0.65)
        self.done.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
        self.done.tintColor = .white
        self.done.accessibilityLabel = closeLabel
        self.done.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.addSubview(self.done)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(self.zoomTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        self.scroll.addGestureRecognizer(doubleTap)
        NotificationCenter.default.addObserver(self, selector: #selector(self.backgrounded), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }
    func updateImage(_ image: UIImage) { self.artwork.image = image; self.setNeedsLayout() }
    func updateInsets(_ insets: UIEdgeInsets) { self.insets = insets; self.setNeedsLayout() }
    override func layoutSubviews() {
        super.layoutSubviews()
        let top = max(self.insets.top, 16)
        self.done.frame = CGRect(x: self.bounds.width - max(self.insets.right, 16) - 44, y: top + 4, width: 44, height: 44)
        let available = CGRect(x: max(20, self.insets.left + 16), y: top + 64,
            width: max(1, self.bounds.width - max(20, self.insets.left + 16) - max(20, self.insets.right + 16)),
            height: max(1, self.bounds.height - top - max(self.insets.bottom, 16) - 190))
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
        self.title.frame = CGRect(x: available.minX, y: available.maxY + 24, width: available.width, height: 58)
        self.artist.frame = CGRect(x: available.minX, y: self.title.frame.maxY + 4, width: available.width, height: 48)
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
}
