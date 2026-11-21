import CoreML
import CoreVideo
import ImageIO
import UIKit
import Vision

enum NextgramArtworkFocus {
    static let queue = DispatchQueue(label: "NextgramArtworkFocus", qos: .userInitiated)

    static func detect(in image: UIImage) -> CGPoint? {
        guard let source = image.cgImage else { return nil }
        let cgImage = analysisImage(source)
        let orientation = orientation(for: image.imageOrientation)

        let faces = VNDetectFaceRectanglesRequest()
        configureForSimulator(faces)
        let faceHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        if (try? faceHandler.perform([faces])) != nil,
           let face = faces.results?.max(by: {
               $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
           }) {
            return center(of: face.boundingBox)
        }

        let subjects = VNGenerateObjectnessBasedSaliencyImageRequest()
        configureForSimulator(subjects)
        let subjectHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        if (try? subjectHandler.perform([subjects])) != nil,
           let subject = subjects.results?.first?.salientObjects?.max(by: { $0.confidence < $1.confidence }) {
            return center(of: subject.boundingBox)
        }

        let attention = VNGenerateAttentionBasedSaliencyImageRequest()
        configureForSimulator(attention)
        let attentionHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        guard (try? attentionHandler.perform([attention])) != nil,
              let observation = attention.results?.first, observation.salientObjects?.isEmpty == false else { return nil }
        return strongestPoint(in: observation.pixelBuffer)
    }

    private static func analysisImage(_ source: CGImage) -> CGImage {
        let scale = min(1.0, 640.0 / CGFloat(max(source.width, source.height)))
        let width = max(1, Int(CGFloat(source.width) * scale))
        let height = max(1, Int(CGFloat(source.height) * scale))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return source }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? source
    }

    private static func strongestPoint(in buffer: CVPixelBuffer) -> CGPoint? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let address = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let pixels = address.assumingMemoryBound(to: Float.self)
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowStride = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<Float>.stride
        var peak: Float = 0
        var point: CGPoint?
        for y in 0 ..< height {
            for x in 0 ..< width {
                let score = pixels[y * rowStride + x]
                if score.isFinite && score > peak {
                    peak = score
                    point = CGPoint(x: (CGFloat(x) + 0.5) / CGFloat(width), y: (CGFloat(y) + 0.5) / CGFloat(height))
                }
            }
        }
        return point
    }

    private static func configureForSimulator(_ request: VNRequest) {
        #if targetEnvironment(simulator)
        // The simulator cannot create the default model's inference context.
        if #available(iOS 17.0, *), let stages = try? request.supportedComputeStageDevices {
            for (stage, devices) in stages {
                if let cpu = devices.first(where: {
                    if case .cpu = $0 { return true }
                    return false
                }) {
                    request.setComputeDevice(cpu, for: stage)
                }
            }
        }
        #endif
    }

    static func frame(imageSize: CGSize, in viewport: CGSize, focus: CGPoint, target: CGPoint) -> CGRect {
        let scale = max(viewport.width / imageSize.width, viewport.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: min(0, max(viewport.width - width, target.x - focus.x * width)),
            y: min(0, max(viewport.height - height, target.y - focus.y * height)),
            width: width,
            height: height
        )
    }

    private static func center(of rect: CGRect) -> CGPoint {
        return CGPoint(x: rect.midX, y: 1 - rect.midY)
    }

    private static func orientation(for orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
