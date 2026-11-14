// Adapted from Regram's ChatControllerVoiceImport, ff561aa7504d85caf2bfffbc981667d992a9f483; see ../NOTICE.md.
import AudioWaveform
import AlertUI
import ChatInterfaceState
import ChatPresentationInterfaceState
import Display
import Foundation
import NagramStrings
import NextgramVoiceMessages
import OverlayStatusController
import PresentationDataUtils
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData

extension ChatControllerImpl {
    private var nextgramCanImportVoice: Bool {
        guard canSendMessagesToChat(self.presentationInterfaceState), self.presentationInterfaceState.voiceMessagesAvailable,
              self.audioRecorderValue == nil, self.videoRecorderValue == nil,
              self.presentationInterfaceState.interfaceState.mediaDraftState == nil,
              self.presentationInterfaceState.interfaceState.editMessage == nil else { return false }
        if let channel = self.presentationInterfaceState.renderedPeer?.peer as? TelegramChannel {
            return channel.hasBannedPermission(.banSendMedia) == nil && channel.hasBannedPermission(.banSendVoice) == nil
        } else if let group = self.presentationInterfaceState.renderedPeer?.peer as? TelegramGroup {
            return !group.hasBannedPermission(.banSendMedia) && !group.hasBannedPermission(.banSendVoice)
        }
        return true
    }

    func nextgramOfferVoiceImport(urls: [URL], fileName: String? = nil, sendAsFile: @escaping () -> Void) -> Bool {
        guard urls.count == 1, let url = urls.first,
              nextgramIsVoiceImportFile(fileName.map { URL(fileURLWithPath: $0) } ?? url), self.nextgramCanImportVoice else { return false }
        let lang = self.presentationData.strings.baseLanguageCode
        let sheet = ActionSheetController(presentationData: self.presentationData)
        sheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: fileName ?? url.lastPathComponent, parseMarkdown: false),
                ActionSheetButtonItem(title: ngI18n("Nagram.VoiceImport.SendAsVoice", lang), action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    self?.nextgramImportVoice(url)
                }),
                ActionSheetButtonItem(title: ngI18n("Nagram.VoiceImport.SendAsFile", lang), action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    sendAsFile()
                })
            ]),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: self.presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        self.present(sheet, in: .window(.root))
        return true
    }

    private func nextgramImportVoice(_ url: URL) {
        guard self.nextgramCanImportVoice else { return }
        let cancelled = Atomic<Bool>(value: false)
        let disposable = MetaDisposable()
        let progress = OverlayStatusController(theme: self.presentationData.theme, type: .loading(cancelled: { disposable.dispose() }))
        self.present(progress, in: .window(.root))
        let signal = Signal<NextgramImportedVoice, NextgramVoiceImportError> { subscriber in
            Queue.concurrentDefaultQueue().async {
                do {
                    let voice = try nextgramConvertVoiceFile(url, isCancelled: { cancelled.with { $0 } })
                    subscriber.putNext(voice)
                    subscriber.putCompletion()
                } catch let error as NextgramVoiceImportError { subscriber.putError(error) }
                catch { subscriber.putError(.invalidAudio) }
            }
            return ActionDisposable { _ = cancelled.swap(true) }
        }
        self.enqueueMediaMessageDisposable.set(disposable)
        disposable.set((signal |> afterDisposed { Queue.mainQueue().async { progress.dismiss() } } |> deliverOnMainQueue).startStrict(next: { [weak self] voice in
            guard let self, self.nextgramCanImportVoice, voice.data.count <= Int(Int32.max) else { return }
            let resource = LocalFileMediaResource(fileId: Int64.random(in: .min ... .max), size: Int64(voice.data.count))
            self.context.engine.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: voice.data)
            self.updateChatPresentationInterfaceState(animated: true, interactive: true, {
                $0.updatedInterfaceState {
                    $0.withUpdatedMediaDraftState(.audio(ChatInterfaceMediaDraftState.Audio(resource: resource, fileSize: Int32(voice.data.count), duration: voice.duration, waveform: AudioWaveform(samples: voice.waveformSamples, peak: 31), trimRange: nil, resumeData: voice.resumeData)))
                }
            })
            self.updateDownButtonVisibility()
        }, error: { [weak self] error in
            guard let self else { return }
            if case .cancelled = error { return }
            let key: String
            if case .tooLong = error { key = "Nagram.VoiceImport.TooLong" } else { key = "Nagram.VoiceImport.InvalidAudio" }
            self.present(textAlertController(context: self.context, title: nil, text: ngI18n(key, self.presentationData.strings.baseLanguageCode), actions: [TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_OK, action: {})]), in: .window(.root))
        }))
    }
}
