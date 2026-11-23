import CoreImage
import CoreML
import CoreVideo
import UIKit
import os

public enum NextgramImageSuperResolution {
    private static let queue = DispatchQueue(label: "app.nextgram.image-super-resolution", qos: .userInitiated)
    private static let logger = Logger(subsystem: "app.nextgram", category: "ImageSuperResolution")
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let model: MLModel? = {
        guard let url = Bundle.main.url(forResource: "NextgramFSRCNN", withExtension: "mlmodelc") else {
            logger.error("The bundled NextgramFSRCNN model is missing.")
            return nil
        }
        do {
            return try MLModel(contentsOf: url, configuration: MLModelConfiguration())
        } catch {
            logger.error("Failed to load NextgramFSRCNN: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    /// Enhances eligible low-resolution still images and reports the result on the main queue.
    @discardableResult
    public static func enhance(_ image: UIImage, completion: @escaping (UIImage?) -> Void) -> DispatchWorkItem? {
        guard image.images == nil, let source = image.cgImage,
              (16 ... 1024).contains(source.width), (16 ... 1024).contains(source.height) else { return nil }
        let task = DispatchWorkItem {
            let result = autoreleasepool { self.process(source, like: image) }
            DispatchQueue.main.async { completion(result) }
        }
        self.queue.async(execute: task)
        return task
    }

    private static func process(_ source: CGImage, like image: UIImage) -> UIImage? {
        guard let model = self.model else { return nil }
        let original = CIImage(cgImage: source)
        var input: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, source.width, source.height, kCVPixelFormatType_32BGRA, attributes, &input) == kCVReturnSuccess,
              let input else { return nil }
        self.context.render(original, to: input, bounds: original.extent, colorSpace: self.colorSpace)

        let prediction: CVPixelBuffer
        do {
            let features = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: input)])
            guard let buffer = try model.prediction(from: features).featureValue(for: "enhanced")?.imageBufferValue else { return nil }
            prediction = buffer
        } catch {
            self.logger.error("Image enhancement failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let enhanced = CIImage(cvPixelBuffer: prediction, options: [.colorSpace: self.colorSpace])
        guard enhanced.extent.width == CGFloat(source.width * 2), enhanced.extent.height == CGFloat(source.height * 2) else { return nil }
        let output: CIImage
        switch source.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            let mask = original.transformed(by: CGAffineTransform(scaleX: 2.0, y: 2.0))
            output = enhanced.applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: enhanced.extent),
                kCIInputMaskImageKey: mask
            ])
        default:
            output = enhanced
        }
        guard let result = self.context.createCGImage(output, from: enhanced.extent, format: .RGBA8, colorSpace: self.colorSpace) else { return nil }
        return UIImage(cgImage: result, scale: image.scale * 2.0, orientation: image.imageOrientation)
    }
}
