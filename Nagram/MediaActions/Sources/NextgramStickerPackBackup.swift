// Adapted from Regram's RGStickerPackBackup, ff561aa7504d85caf2bfffbc981667d992a9f483; see Nagram/VoiceMessages/NOTICE.md.
import AccountContext
import Display
import Foundation
import LegacyMediaPickerUI
import NagramStrings
import OverlayStatusController
import SaveToCameraRoll
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import UIKit
import ZipArchive

public enum NextgramStickerPackBackupError: Error { case tooLarge, download, io }

/// Original files and emoji/order metadata only. No credentials or account information are exported.
public func nextgramBackupStickerPack(context: AccountContext, info: StickerPackCollectionInfo, items: [StickerPackItem], progress: @escaping (Int, Int) -> Void) -> Signal<URL, NextgramStickerPackBackupError> {
    guard !items.isEmpty, items.count <= 500 else { return .fail(.tooLarge) }
    return Signal { subscriber in
        let queue = Queue(name: "nextgram.sticker-pack-backup")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Nextgram-Stickers-" + UUID().uuidString)
        let contents = directory.appendingPathComponent("contents", isDirectory: true)
        let disposable = MetaDisposable()
        let cancelled = Atomic<Bool>(value: false)
        var completed = false
        var bytes: Int64 = 0
        var records: [[String: Any]] = []
        func fail(_ error: NextgramStickerPackBackupError) {
            subscriber.putError(error)
            try? FileManager.default.removeItem(at: directory)
        }
        queue.async {
            do { try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true) } catch { fail(.io); return }
            func next(_ index: Int) {
                guard !cancelled.with({ $0 }) else { return }
                if index == items.count {
                    do {
                        let manifest: [String: Any] = ["schema": 1, "format": "Regram.StickerPack", "exporter": "Nextgram", "title": info.title, "shortName": info.shortName, "kind": info.id.namespace == Namespaces.ItemCollection.CloudEmojiPacks ? "emoji" : "sticker", "items": records]
                        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted]).write(to: contents.appendingPathComponent("pack.json"), options: .atomic)
                        let archive = directory.appendingPathComponent("Nextgram-StickerPack.zip")
                        guard SSZipArchive.createZipFile(atPath: archive.path, withContentsOfDirectory: contents.path, keepParentDirectory: false), !cancelled.with({ $0 }) else { throw NextgramStickerPackBackupError.io }
                        try FileManager.default.removeItem(at: contents)
                        completed = true
                        subscriber.putNext(archive)
                        subscriber.putCompletion()
                    } catch { fail(.io) }
                    return
                }
                let item = items[index]
                let file = item.file._parse()
                let reference = FileMediaReference.stickerPack(stickerPack: .id(id: info.id.id, accessHash: info.accessHash), media: file)
                disposable.set((fetchMediaData(context: context, userLocation: .other, mediaReference: reference.abstract)
                |> map { value -> String? in
                    if case let .data(data) = value.0, data.isComplete { return data.path }
                    return nil
                }
                |> filter { $0 != nil } |> take(1) |> castError(NextgramStickerPackBackupError.self)
                |> timeout(120, queue: queue, alternate: .fail(.download)) |> deliverOn(queue)).start(next: { path in
                    guard let path, !cancelled.with({ $0 }) else { return }
                    do {
                        let size = (try FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
                        guard size > 0, size <= 32 * 1024 * 1024, bytes + size <= 256 * 1024 * 1024 else { throw NextgramStickerPackBackupError.tooLarge }
                        let ext = file.isAnimatedSticker ? "tgs" : file.isVideoSticker ? "webm" : file.mimeType == "image/png" ? "png" : "webp"
                        let name = String(format: "%04d", index + 1) + "." + ext
                        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: contents.appendingPathComponent(name))
                        bytes += size
                        records.append(["file": name, "id": String(file.fileId.id), "emoji": item.getStringRepresentationsOfIndexKeys(), "mimeType": file.mimeType])
                        progress(index + 1, items.count)
                        queue.async { next(index + 1) }
                    } catch let error as NextgramStickerPackBackupError { fail(error) }
                    catch { fail(.io) }
                }, error: { fail($0) }))
            }
            next(0)
        }
        return ActionDisposable {
            _ = cancelled.swap(true)
            disposable.dispose()
            queue.async { if !completed { try? FileManager.default.removeItem(at: directory) } }
        }
    }
}

public func nextgramPresentStickerPackBackup(context: AccountContext, info: StickerPackCollectionInfo, items: [StickerPackItem], presentationData: PresentationData, present: @escaping (ViewController) -> Void) -> Disposable {
    let operation = MetaDisposable()
    weak var loadingReference: ViewController?
    let loading = OverlayStatusController(style: presentationData.theme.overallDarkAppearance ? .dark : .light, type: .loading(cancelled: {
        operation.dispose()
        loadingReference?.dismiss()
    }))
    loadingReference = loading
    present(loading)
    operation.set((nextgramBackupStickerPack(context: context, info: info, items: items, progress: { _, _ in }) |> deliverOnMainQueue).start(next: { url in
        loading.dismiss()
        present(legacyICloudFilePicker(theme: presentationData.theme, mode: .export, url: url, completion: { _ in
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }))
    }, error: { error in
        loading.dismiss()
        let key: String
        if case .tooLarge = error { key = "Nagram.StickerBackup.TooLarge" } else { key = "Nagram.StickerBackup.Failed" }
        let alert = ActionSheetController(presentationData: presentationData)
        alert.setItemGroups([ActionSheetItemGroup(items: [
            ActionSheetTextItem(title: ngI18n(key, presentationData.strings.baseLanguageCode)),
            ActionSheetButtonItem(title: presentationData.strings.Common_OK, action: { [weak alert] in alert?.dismissAnimated() })
        ])])
        present(alert)
    }))
    return ActionDisposable { operation.dispose(); Queue.mainQueue().async { loading.dismiss() } }
}
