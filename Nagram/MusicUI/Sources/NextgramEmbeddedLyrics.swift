import AccountContext
import AVFoundation
import Foundation
import SwiftSignalKit
import TelegramCore

final class NextgramEmbeddedLyricsLoader {
    private static let maximumTextBytes = 1024 * 1024

    private let resourceDisposable = MetaDisposable()
    private var metadataTask: Task<Void, Never>?
    private var asset: AVURLAsset?
    private var requestId = UUID()

    deinit {
        self.resourceDisposable.dispose()
        self.metadataTask?.cancel()
        self.asset?.cancelLoading()
    }

    func load(context: AccountContext, file: FileMediaReference, completion: @escaping (String?) -> Void) {
        precondition(Thread.isMainThread)
        self.cancel()
        let requestId = self.requestId
        let pathExtension = file.media.fileName.flatMap { name -> String? in
            let value = (name as NSString).pathExtension
            return value.isEmpty ? nil : value
        }

        self.resourceDisposable.set((context.engine.resources.data(
            resource: EngineMediaResource(file.media.resource),
            pathExtension: pathExtension
        )
        |> filter { $0.isComplete }
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] data in
            guard let self, self.requestId == requestId else {
                return
            }
            let asset = AVURLAsset(url: URL(fileURLWithPath: data.path))
            self.asset = asset
            self.metadataTask = Task.detached(priority: .utility) { [weak self] in
                let lyrics = await NextgramEmbeddedLyricsLoader.readLyrics(asset: asset)
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { [weak self] in
                    guard let self, self.requestId == requestId else {
                        return
                    }
                    self.metadataTask = nil
                    self.asset = nil
                    completion(lyrics)
                }
            }
        }))
    }

    func cancel() {
        precondition(Thread.isMainThread)
        self.requestId = UUID()
        self.resourceDisposable.set(nil)
        self.metadataTask?.cancel()
        self.metadataTask = nil
        self.asset?.cancelLoading()
        self.asset = nil
    }

    private static func readLyrics(asset: AVURLAsset) async -> String? {
        guard !Task.isCancelled else {
            return nil
        }
        if let value = try? await asset.load(.lyrics), let lyrics = self.boundedText(value) {
            return lyrics
        }
        guard !Task.isCancelled else {
            return nil
        }
        if let items = try? await asset.load(.commonMetadata), let lyrics = await self.readLyrics(items: items) {
            return lyrics
        }
        guard !Task.isCancelled, let formats = try? await asset.load(.availableMetadataFormats) else {
            return nil
        }
        for format in formats {
            guard !Task.isCancelled else {
                return nil
            }
            if let items = try? await asset.loadMetadata(for: format), let lyrics = await self.readLyrics(items: items) {
                return lyrics
            }
        }
        return nil
    }

    private static func readLyrics(items: [AVMetadataItem]) async -> String? {
        for item in items {
            guard !Task.isCancelled else {
                return nil
            }
            let key = [item.identifier?.rawValue, item.commonKey?.rawValue, item.key as? String]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
            guard key.contains("lyric") || key.contains("uslt") || key.contains("©lyr") else {
                continue
            }
            if let value = try? await item.load(.stringValue), let lyrics = self.boundedText(value) {
                return lyrics
            }
        }
        return nil
    }

    private static func boundedText(_ text: String) -> String? {
        guard text.utf8.prefix(self.maximumTextBytes + 1).count <= self.maximumTextBytes else {
            return nil
        }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return text.isEmpty ? nil : text
    }
}
