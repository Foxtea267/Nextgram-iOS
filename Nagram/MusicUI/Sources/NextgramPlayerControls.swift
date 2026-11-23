import AVKit
import MediaPlayer
import UIKit

final class NextgramPlayerVolumeView: UIView {
    let slider = NextgramPlayerSlider()
    private let systemVolume = MPVolumeView()
    private var volumeObservation: NSKeyValueObservation?
#if DEBUG && targetEnvironment(simulator)
    private var preview = false

    func showPreviewSlider() {
        self.preview = true
        self.volumeObservation = nil
        self.slider.value = 0.32
    }
#endif

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.systemVolume.alpha = 0.0
        self.systemVolume.isUserInteractionEnabled = false
        self.systemVolume.accessibilityElementsHidden = true
        self.addSubview(self.systemVolume)
        self.addSubview(self.slider)
        self.slider.valueChanged = { [weak self] in
            guard let self else { return }
#if DEBUG && targetEnvironment(simulator)
            guard !self.preview else { return }
#endif
            // MPVolumeView owns the system volume slider, including its current route.
            if let systemSlider = self.systemVolume.subviews.first(where: { $0 is UISlider }) as? UISlider {
                systemSlider.setValue(self.slider.value, animated: false)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        self.volumeObservation = nil
        guard self.window != nil else { return }
#if DEBUG && targetEnvironment(simulator)
        guard !self.preview else { return }
#endif
        self.refreshVolume()
        self.volumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume) { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.slider.isTracking else { return }
                self.refreshVolume()
            }
        }
    }

    private func refreshVolume() {
#if DEBUG && targetEnvironment(simulator)
        guard !self.preview else { return }
#endif
        self.slider.value = AVAudioSession.sharedInstance().outputVolume
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.systemVolume.frame = self.bounds
        self.slider.frame = self.bounds
    }
}

final class NextgramPlayerRoutePickerView: UIView {
    private let picker = AVRoutePickerView()
    private let icon = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.picker.tintColor = .clear
        self.picker.activeTintColor = .clear
        self.picker.prioritizesVideoDevices = false
        self.addSubview(self.picker)
        self.updateRoute(bluetooth: false)
        self.icon.contentMode = .center
        self.icon.isUserInteractionEnabled = false
        self.icon.isAccessibilityElement = false
        self.addSubview(self.icon)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateRoute(bluetooth: Bool) {
        let configuration = UIImage.SymbolConfiguration(pointSize: 27.0, weight: .medium)
        if bluetooth {
            self.icon.image = UIGraphicsImageRenderer(size: CGSize(width: 38.0, height: 30.0)).image { _ in
                UIImage(systemName: "speaker.wave.2.fill", withConfiguration: configuration)?
                    .withTintColor(.black, renderingMode: .alwaysOriginal).draw(in: CGRect(x: 0.0, y: 3.0, width: 25.0, height: 24.0))
                UIColor.black.setStroke()
                let mark = UIBezierPath()
                mark.move(to: CGPoint(x: 29.0, y: 4.0))
                mark.addLine(to: CGPoint(x: 36.0, y: 10.0))
                mark.addLine(to: CGPoint(x: 26.0, y: 20.0))
                mark.move(to: CGPoint(x: 26.0, y: 10.0))
                mark.addLine(to: CGPoint(x: 36.0, y: 20.0))
                mark.addLine(to: CGPoint(x: 29.0, y: 26.0))
                mark.addLine(to: CGPoint(x: 29.0, y: 4.0))
                mark.lineWidth = 2.3
                mark.lineJoinStyle = .round
                mark.lineCapStyle = .round
                mark.stroke()
            }.withRenderingMode(.alwaysTemplate)
        } else {
            self.icon.image = UIImage(systemName: "airplay.audio", withConfiguration: configuration)
        }
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        self.icon.tintColor = self.tintColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.picker.frame = self.bounds
        self.icon.frame = self.bounds
    }
}

final class NextgramPlayerSlider: UIControl {
    var elasticEdges = false {
        didSet {
            if oldValue && !self.elasticEdges { self.resetEdgeStretch(animated: false) }
        }
    }
    var jumpOnTap = false
    var value: Float = 0.0 {
        didSet { if self.value != oldValue { self.updateRail() } }
    }
    var editingStarted: (() -> Void)?
    var valueChanged: (() -> Void)?
    var editingFinished: ((Bool) -> Void)?
    override var accessibilityValue: String? {
        get { super.accessibilityValue ?? NumberFormatter.localizedString(from: NSNumber(value: self.value), number: .percent) }
        set { super.accessibilityValue = newValue }
    }
    private let rail = CALayer()
    private let fill = CALayer()
    private var startPoint: CGPoint?
    private var touchOffset: CGFloat = 0.0
    private var dragging = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isAccessibilityElement = true
        self.accessibilityTraits = .adjustable
        self.rail.masksToBounds = true
        self.rail.addSublayer(self.fill)
        self.layer.addSublayer(self.rail)
        self.setColors(filled: UIColor.white.withAlphaComponent(0.9), empty: UIColor.white.withAlphaComponent(0.22))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setColors(filled: UIColor, empty: UIColor) {
        self.fill.backgroundColor = filled.cgColor
        self.rail.backgroundColor = empty.cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.updateRail()
    }

    private func updateRail() {
        let height: CGFloat = self.dragging ? 8.0 : 6.0
        let fraction = CGFloat(min(1, max(0, self.value)))
        let rtl = self.effectiveUserInterfaceLayoutDirection == .rightToLeft
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.rail.bounds = CGRect(x: 0, y: 0, width: self.bounds.width, height: height)
        self.rail.position = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        self.rail.cornerRadius = height * 0.5
        self.fill.frame = CGRect(x: rtl ? self.bounds.width * (1 - fraction) : 0, y: 0, width: self.bounds.width * fraction, height: height)
        CATransaction.commit()
    }

    private func updateValue(at position: CGFloat) {
        let fraction = min(1, max(0, position / max(1, self.bounds.width)))
        let value = Float(self.effectiveUserInterfaceLayoutDirection == .rightToLeft ? 1 - fraction : fraction)
        guard value != self.value else { return }
        self.value = value
        self.valueChanged?()
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard self.isEnabled else { return false }
        let point = touch.location(in: self)
        self.startPoint = point
        let fraction = CGFloat(self.value)
        let edge = self.bounds.width * (self.effectiveUserInterfaceLayoutDirection == .rightToLeft ? 1 - fraction : fraction)
        self.touchOffset = abs(point.x - edge) <= 12.0 ? point.x - edge : 0.0
        self.resetEdgeStretch(animated: false)
        self.editingStarted?()
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard let startPoint = self.startPoint else { return false }
        let position = touch.location(in: self).x
        if !self.dragging && abs(position - startPoint.x) >= 4.0 {
            self.dragging = true
            self.updateRail()
        }
        if self.dragging {
            let adjusted = position - self.touchOffset
            self.updateValue(at: adjusted)
            if self.elasticEdges {
                self.setEdgeStretch(adjusted - min(self.bounds.width, max(0.0, adjusted)))
            }
        }
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let touch, self.dragging || self.jumpOnTap {
            let point = touch.location(in: self)
            if self.dragging || self.bounds.contains(point) {
                self.updateValue(at: point.x - (self.dragging ? self.touchOffset : 0.0))
                self.finishTracking(commit: true)
                return
            }
        }
        self.finishTracking(commit: false)
    }

    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        self.finishTracking(commit: false)
    }

    private func finishTracking(commit: Bool) {
        guard self.startPoint != nil else { return }
        self.startPoint = nil
        self.dragging = false
        if self.elasticEdges { self.resetEdgeStretch(animated: true) }
        self.updateRail()
        self.editingFinished?(commit)
    }

    override func accessibilityIncrement() { self.adjustAccessibility(by: 0.05) }
    override func accessibilityDecrement() { self.adjustAccessibility(by: -0.05) }

    private func adjustAccessibility(by step: Float) {
        guard self.isEnabled else { return }
        self.editingStarted?()
        self.value = min(1, max(0, self.value + step))
        self.valueChanged?()
        self.editingFinished?(true)
    }

    private func setEdgeStretch(_ overshoot: CGFloat) {
        guard self.elasticEdges, !UIAccessibility.isReduceMotionEnabled, self.bounds.width > 0.0 else {
            self.resetEdgeStretch(animated: false)
            return
        }
        let stretch = 25.0 * overshoot / (25.0 + abs(overshoot))
        var transform = CATransform3DMakeScale(1.0 + abs(stretch) / self.bounds.width, 1.0 - abs(stretch) / 180.0, 1.0)
        transform.m41 = stretch * 0.5
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.rail.transform = transform
        CATransaction.commit()
    }

    private func resetEdgeStretch(animated: Bool) {
        let current = self.rail.presentation()?.transform ?? self.rail.transform
        self.rail.removeAnimation(forKey: "nextgram.edgeStretch")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.rail.transform = CATransform3DIdentity
        CATransaction.commit()
        guard animated, !UIAccessibility.isReduceMotionEnabled, !CATransform3DIsIdentity(current) else { return }
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = NSValue(caTransform3D: current)
        spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        spring.stiffness = 320.0
        spring.damping = 25.0
        spring.duration = spring.settlingDuration
        self.rail.add(spring, forKey: "nextgram.edgeStretch")
    }

#if DEBUG && targetEnvironment(simulator)
    func previewEdgeStretch(_ overshoot: CGFloat?) {
        if let overshoot {
            self.setEdgeStretch(overshoot)
        } else {
            self.resetEdgeStretch(animated: true)
        }
    }
#endif
}

enum NextgramPlayerPalette {
    static let fallback = UIColor(red: 0.14, green: 0.17, blue: 0.21, alpha: 1.0)

    static func artworkColor(_ image: UIImage?) -> UIColor {
        guard let cgImage = image?.cgImage else { return self.fallback }
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        return pixels.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            guard let context = CGContext(data: bytes.baseAddress, width: 16, height: 16,
                bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                return self.fallback
            }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0.0, y: 0.0, width: 16.0, height: 16.0))
            let colors = bytes.bindMemory(to: UInt8.self)
            var r = 0.0, g = 0.0, b = 0.0, total = 0.0
            for i in stride(from: 0, to: colors.count, by: 4) where colors[i + 3] > 230 {
                let red = Double(colors[i]) / 255.0
                let green = Double(colors[i + 1]) / 255.0
                let blue = Double(colors[i + 2]) / 255.0
                let saturation = max(red, green, blue) - min(red, green, blue)
                let weight = 0.25 + saturation * 3.0
                r += red * weight
                g += green * weight
                b += blue * weight
                total += weight
            }
            guard total > 0 else { return self.fallback }
            return UIColor(red: CGFloat(min(0.44, r / total * 0.55 + 0.14)),
                green: CGFloat(min(0.44, g / total * 0.55 + 0.12)),
                blue: CGFloat(min(0.44, b / total * 0.55 + 0.14)), alpha: 1.0)
        }
    }

    static func customColor(_ value: String) -> UIColor? {
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        return UIColor(red: CGFloat((rgb >> 16) & 255) / 255.0,
            green: CGFloat((rgb >> 8) & 255) / 255.0, blue: CGFloat(rgb & 255) / 255.0, alpha: 1.0)
    }

    static func foreground(on color: UIColor) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return .white }
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return linear(red) * 0.2126 + linear(green) * 0.7152 + linear(blue) * 0.0722 > 0.179 ? .black : .white
    }

}
