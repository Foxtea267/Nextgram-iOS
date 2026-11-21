import AVKit
import MediaPlayer
import UIKit

final class NextgramPlayerVolumeView: MPVolumeView {
#if DEBUG && targetEnvironment(simulator)
    private var previewSlider: UISlider?

    func showPreviewSlider() {
        guard self.previewSlider == nil else { return }
        self.showsVolumeSlider = false
        let slider = NextgramPlayerSlider()
        slider.value = 0.32
        slider.minimumTrackTintColor = UIColor.white.withAlphaComponent(0.75)
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.22)
        slider.setThumbImage(UIGraphicsImageRenderer(size: CGSize(width: 8.0, height: 8.0)).image { _ in }, for: .normal)
        self.previewSlider = slider
        self.addSubview(slider)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.previewSlider?.frame = self.bounds
    }
#endif
    override func volumeSliderRect(forBounds bounds: CGRect) -> CGRect {
        let slider = super.volumeSliderRect(forBounds: bounds)
        return CGRect(x: slider.minX, y: bounds.midY - slider.height * 0.5, width: slider.width, height: slider.height)
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

final class NextgramPlayerSlider: UISlider {
    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        let track = super.trackRect(forBounds: bounds)
        let height: CGFloat = self.isTracking ? 8.0 : 6.0
        return CGRect(x: track.minX, y: bounds.midY - height / 2.0, width: track.width, height: height)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let tracking = super.beginTracking(touch, with: event)
        self.setNeedsLayout()
        return tracking
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        self.setNeedsLayout()
    }

    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        self.setNeedsLayout()
    }
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

    static func rail(_ color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12.0, height: 6.0), format: format).image { _ in
            color.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0.0, y: 0.0, width: 12.0, height: 6.0), cornerRadius: 3.0).fill()
        }
        return image.resizableImage(withCapInsets: UIEdgeInsets(top: 0.0, left: 5.0, bottom: 0.0, right: 5.0))
    }
}
