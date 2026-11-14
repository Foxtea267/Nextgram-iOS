// Adapted from Regram's RGVoiceFileConverter, ff561aa7504d85caf2bfffbc981667d992a9f483; see ../NOTICE.md.
import FFMpegBinding
import Foundation
import OpusBinding

public enum NextgramVoiceImportError: Error {
    case invalidAudio, tooLong, cancelled
}

public struct NextgramImportedVoice {
    public let data: Data
    public let duration: Double
    public let waveformSamples: Data
    public let resumeData: Data
}

public func nextgramIsVoiceImportFile(_ url: URL) -> Bool {
    return url.isFileURL && ["mp3", "m4a", "aac", "wav", "ogg", "opus", "flac", "aif", "aiff"].contains(url.pathExtension.lowercased())
}

/// Run off the main thread. PCM is streamed; only compressed output and a bounded waveform are retained.
public func nextgramConvertVoiceFile(_ url: URL, isCancelled: () -> Bool) throws -> NextgramImportedVoice {
    guard url.isFileURL else { throw NextgramVoiceImportError.invalidAudio }
    func checkCancellation() throws {
        if isCancelled() { throw NextgramVoiceImportError.cancelled }
    }
    try checkCancellation()
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let format = FFMpegAVFormatContext()
    guard format.openInput(withDirectFilePath: url.path) else { throw NextgramVoiceImportError.invalidAudio }
    format.discardStreams(notOf: FFMpegAVFormatStreamTypeAudio)
    guard format.findStreamInfo(), let index = format.streamIndices(for: FFMpegAVFormatStreamTypeAudio).first?.int32Value,
          let codec = FFMpegAVCodec.find(forId: format.codecId(atStreamIndex: index), preferHardwareAccelerationCapable: false) else {
        throw NextgramVoiceImportError.invalidAudio
    }
    let decoder = FFMpegAVCodecContext(codec: codec)
    guard format.codecParams(atStreamIndex: index, to: decoder), decoder.open(), decoder.channels() > 0, decoder.sampleRate() > 0 else {
        throw NextgramVoiceImportError.invalidAudio
    }
    format.seekFrame(forStreamIndex: index, pts: 0, positionOnKeyframe: true)
    let resampler = FFMpegSWResample(sourceChannelCount: Int(decoder.channels()), sourceSampleRate: Int(decoder.sampleRate()), sourceSampleFormat: decoder.sampleFormat(), destinationChannelCount: 1, destinationSampleRate: 48000, destinationSampleFormat: FFMPEG_AV_SAMPLE_FMT_S16)
    guard let item = TGDataItem(data: Data()) else { throw NextgramVoiceImportError.invalidAudio }
    let writer = TGOggOpusWriter()
    guard writer.begin(with: item) else { throw NextgramVoiceImportError.invalidAudio }
    var sampleCount: Int64 = 0
    var peaks: [Int16] = []
    var peak: Int16 = 0
    var peakCount = 0
    var peakWindow = 480
    func consume(_ pcm: Data) throws {
        try checkCancellation()
        sampleCount += Int64(pcm.count / 2)
        guard sampleCount <= 48000 * 60 * 60 else { throw NextgramVoiceImportError.tooLong }
        try pcm.withUnsafeBytes { bytes in
            for sample in bytes.bindMemory(to: Int16.self) {
                peak = max(peak, Int16(clamping: abs(Int32(sample))))
                peakCount += 1
                if peakCount == peakWindow {
                    peaks.append(peak)
                    peak = 0
                    peakCount = 0
                    if peaks.count == 200 {
                        peaks = stride(from: 0, to: 200, by: 2).map { max(peaks[$0], peaks[$0 + 1]) }
                        peakWindow *= 2
                    }
                }
            }
            var offset = 0
            while offset < bytes.count {
                let count = min(1920, bytes.count - offset)
                let pointer = UnsafeMutablePointer(mutating: bytes.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt8.self))
                guard writer.writeFrame(pointer, frameByteCount: UInt(count)) else { throw NextgramVoiceImportError.invalidAudio }
                offset += count
            }
        }
    }
    let frame = FFMpegAVFrame()
    func drain(finishing: Bool = false) throws {
        while true {
            try checkCancellation()
            switch decoder.receive(into: frame) {
            case .success:
                if let pcm = resampler.resample(frame) { try consume(pcm) }
            case .notEnoughData: return
            default:
                if !finishing { throw NextgramVoiceImportError.invalidAudio }
                return
            }
        }
    }
    let packet = FFMpegPacket()
    while format.readFrame(into: packet) {
        try checkCancellation()
        if packet.streamIndex == index {
            guard packet.send(toDecoder: decoder) == 0 else { throw NextgramVoiceImportError.invalidAudio }
            try drain()
        }
        packet.reuse()
    }
    if decoder.sendEnd() { try drain(finishing: true) }
    guard sampleCount > 0 else { throw NextgramVoiceImportError.invalidAudio }
    if peakCount > 0 { peaks.append(peak) }
    let resumeData = try JSONSerialization.data(withJSONObject: writer.pause())
    guard writer.writeFrame(nil, frameByteCount: 0), let data = item.data(), !data.isEmpty else { throw NextgramVoiceImportError.invalidAudio }
    try checkCancellation()
    var waveform = [Int16](repeating: 0, count: 100)
    for (i, peak) in peaks.enumerated() {
        let index = min(99, i * 100 / peaks.count)
        waveform[index] = max(waveform[index], peak)
    }
    let average = waveform.reduce(Int64(0)) { $0 + Int64($1) } / 100
    let ceiling = max(2500, average * 18 / 10)
    waveform = waveform.map { Int16(min(31, Int64($0) * 31 / ceiling)) }
    return NextgramImportedVoice(data: data, duration: Double(sampleCount) / 48000.0, waveformSamples: waveform.withUnsafeBytes { Data($0) }, resumeData: resumeData)
}
