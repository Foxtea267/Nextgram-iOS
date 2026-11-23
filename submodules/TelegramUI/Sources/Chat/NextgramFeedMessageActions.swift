// MARK: NEXTGRAM
import AccountContext
import ChatMessageItem
import ChatMessageItemView
import ContextUI
import Display
import NagramSettingsUI
import NagramStrings
import Pasteboard
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import UIKit
import UndoUI

func nextgramOpenFeedReplies(context: AccountContext, host: ViewController, id: EngineMessage.Id, isChannelPost: Bool, displayModalProgress: Bool) {
    guard let navigation = host.navigationController as? NavigationController else { return }
    let _ = ChatControllerImpl.openMessageReplies(context: context, navigationController: navigation, present: { [weak host] controller, arguments in
        host?.present(controller, in: .window(.root), with: arguments)
    }, messageId: id, isChannelPost: isChannelPost, atMessage: nil, displayModalProgress: displayModalProgress).startStandalone()
}

func nextgramOpenFeedMessageMenu(context: AccountContext, host: ViewController, item: ChatMessageItemView, message: EngineMessage, messages: [EngineMessage], selectAll: Bool, recognizer: UIGestureRecognizer?, actions: ChatMessageFeedItemActions) {
    guard let chatItem = item.item, let node = item.getMessageContextSourceNode(stableId: selectAll ? nil : message.stableId), node.view.window != nil else { return }
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let strings = data.strings
    let raw = message._asMessage()
    let protected = chatItem.associatedData.isCopyProtectionEnabled || messages.contains { $0._asMessage().isCopyProtected() }
    let canExport = !protected && messages.allSatisfy { entry in
        !entry._asMessage().containsSecretMedia && !entry.attributes.contains { $0 is RestrictedContentMessageAttribute }
    }
    let ids = Set(messages.map(\.id))
    let peers = raw.peers[message.id.peerId].map { [message.id.peerId: EnginePeer($0)] } ?? [:]
    let permissions = context.sharedContext.chatAvailableMessageActions(engine: context.engine, accountPeerId: context.account.peerId,
        messageIds: ids, messages: Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) }), peers: peers)
    let menu = permissions |> map { [host] permissions -> ContextController.Items in
        func action(_ title: String, _ icon: String, _ perform: @escaping () -> Void) -> ContextMenuItem {
            .action(ContextMenuActionItem(text: title, icon: { theme in
                generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/" + icon), color: theme.contextMenu.primaryColor)
            }, action: { _, dismiss in
                dismiss(.default)
                Queue.mainQueue().after(0.25, perform)
            }))
        }
        var items: [ContextMenuItem] = []
        if hasCommentButton(item: chatItem) {
            let id = chatItem.content.firstMessage.id
            items.append(action(strings.Conversation_MessageLeaveComment, "Message", { [weak host] in
                guard let host else { return }
                nextgramOpenFeedReplies(context: context, host: host, id: id, isChannelPost: true, displayModalProgress: true)
            }))
        }
        if canExport && !permissions.isCopyProtected {
            if !message.text.isEmpty {
                let entities = raw.attributes.compactMap { $0 as? TextEntitiesMessageAttribute }.first?.entities
                items.append(action(strings.Conversation_ContextMenuCopy, "Copy", { storeMessageTextInPasteboard(message.text, entities: entities) }))
            }
            if permissions.options.contains(.forward) {
                items.append(action(ngI18n("Nagram.MessageMenu.Item.saveToSavedMessages", strings.baseLanguageCode), "Fave", { [weak host] in
                    let forwards = messages.map { EnqueueMessage.forward(source: $0.id, threadId: nil, grouping: .auto, attributes: [], correlationId: nil) }
                    let _ = (enqueueMessages(account: context.account, peerId: context.account.peerId, messages: forwards)
                    |> deliverOnMainQueue).startStandalone(next: { ids in
                        guard ids.contains(where: { $0 != nil }), let host else { return }
                        let text = forwards.count == 1 ? strings.Conversation_ForwardTooltip_SavedMessages_One : strings.Conversation_ForwardTooltip_SavedMessages_Many
                        host.present(UndoOverlayController(presentationData: data, content: .forward(savedMessages: true, text: text), elevatedLayout: false, position: .top, animateInAsReplacement: false, action: { _ in false }), in: .current)
                    })
                }))
                items.append(action(strings.Conversation_ContextMenuForward, "Forward", { [weak host] in
                    let params = ShareControllerParams(subject: .messages(messages.map { $0._asMessage() }), showInChat: nil, externalShare: false)
                    host?.present(context.sharedContext.makeShareScreen(context: context, params: params), in: .window(.root))
                }))
                if permissions.options.contains(.externalShare), let share = actions.nextgramShare {
                    items.append(action(strings.Conversation_ContextMenuShare, "Share", share))
                }
            }
            items.append(action(ngI18n("Nagram.Bookmarks.Action", strings.baseLanguageCode), "Fave", {
                nextgramPresentBookmarkEditor(context: context, messageId: message.id, forumThreadId: nil)
            }))
        }
        items.append(action(strings.MediaPlayer_ContextMenu_ShowInChat, "GoToMessage", { actions.navigateToMessage(message.id) }))
        if let hideChannel = actions.nextgramHideChannel {
            items.append(action(ngI18n("Nagram.ChannelFeed.HideChannel", strings.baseLanguageCode), "HideArchive", hideChannel))
        }
        return ContextController.Items(content: .list(items))
    }
    let source = NextgramFeedExtractedContentSource(node: node)
    let controller = makeContextController(presentationData: data, source: .extracted(source), items: menu,
        recognizer: recognizer as? TapLongTapOrDoubleTapGestureRecognizer, gesture: recognizer as? ContextGesture, disableScreenshots: protected)
    host.presentInGlobalOverlay(controller)
}

private final class NextgramFeedExtractedContentSource: ContextExtractedContentSource {
    let keepInPlace = false
    let ignoreContentTouches = false
    let blurBackground = true
    let node: ContextExtractedContentContainingNode

    init(node: ContextExtractedContentContainingNode) {
        self.node = node
    }

    func takeView() -> ContextControllerTakeViewInfo? {
        return ContextControllerTakeViewInfo(containingItem: .node(self.node), contentAreaInScreenSpace: mainWindowScreenBounds)
    }

    func putBack() -> ContextControllerPutBackViewInfo? {
        return ContextControllerPutBackViewInfo(contentAreaInScreenSpace: mainWindowScreenBounds)
    }
}
