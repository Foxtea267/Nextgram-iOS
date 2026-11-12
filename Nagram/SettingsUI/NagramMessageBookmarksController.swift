import AccountContext
import Display
import Foundation
import ItemListUI
import NagramSettings
import NagramStrings
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import UIKit

private func showBookmarkStorageError(context: AccountContext) {
    let strings = context.sharedContext.currentPresentationData.with { $0.strings }
    let alert = UIAlertController(title: ngI18n("Nagram.Bookmarks.StorageError", strings.baseLanguageCode), message: nil, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: strings.Common_OK, style: .default, handler: nil))
    context.sharedContext.applicationBindings.presentNativeController(alert)
}

public func nextgramPresentBookmarkEditor(
    context: AccountContext,
    messageId: EngineMessage.Id,
    forumThreadId: Int64?,
    changed: @escaping () -> Void = {}
) {
    let accountId = context.account.id.int64
    let location = NagramBookmarkLocation(peerId: messageId.peerId.toInt64(), namespace: messageId.namespace, messageId: messageId.id)
    let existing: NagramMessageBookmark?
    do {
        existing = try NagramMessageBookmarks.list(accountId: accountId).first { $0.location == location }
    } catch {
        showBookmarkStorageError(context: context)
        return
    }

    let strings = context.sharedContext.currentPresentationData.with { $0.strings }
    let language = strings.baseLanguageCode
    let title = ngI18n(existing == nil ? "Nagram.Bookmarks.Add" : "Nagram.Bookmarks.Edit", language)
    let editor = UIAlertController(title: title, message: nil, preferredStyle: .alert)
    editor.addTextField { field in
        field.placeholder = ngI18n("Nagram.Bookmarks.TagsPlaceholder", language)
        field.text = existing?.tags.joined(separator: ", ")
    }
    editor.addAction(UIAlertAction(title: strings.Common_Cancel, style: .cancel, handler: nil))
    if existing != nil {
        editor.addAction(UIAlertAction(title: ngI18n("Nagram.Bookmarks.Remove", language), style: .destructive) { _ in
            do {
                try NagramMessageBookmarks.remove(accountId: accountId, location: location)
                changed()
            } catch {
                showBookmarkStorageError(context: context)
            }
        })
    }
    editor.addAction(UIAlertAction(title: strings.Common_Done, style: .default) { [weak editor] _ in
        let text = editor?.textFields?.first?.text ?? ""
        let tags = text.components(separatedBy: CharacterSet(charactersIn: ",，"))
        do {
            try NagramMessageBookmarks.save(accountId: accountId, location: location, threadId: forumThreadId, tags: tags)
            changed()
        } catch {
            showBookmarkStorageError(context: context)
        }
    })
    context.sharedContext.applicationBindings.presentNativeController(editor)
}

private struct BookmarkEntry: ItemListNodeEntry {
    enum Id: Hashable {
        case filter
        case status
        case bookmark(NagramBookmarkLocation)
    }

    let stableId: Id
    let index: Int
    let title: String
    let label: String

    var section: ItemListSectionId {
        return self.stableId == .filter ? 0 : 1
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.index < rhs.index
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch stableId {
        case .status:
            return ItemListTextItem(presentationData: presentationData, text: .plain(title), sectionId: self.section)
        case .filter, .bookmark:
            let activate = arguments as! (Id) -> Void
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label,
                                          sectionId: self.section, style: .blocks, action: {
                activate(stableId)
            })
        }
    }
}

public func nextgramMessageBookmarksController(context: AccountContext) -> ViewController {
    let accountId = context.account.id.int64
    let bookmarks = Promise<[NagramMessageBookmark]?>()
    let selectedTag = ValuePromise<String?>(nil, ignoreRepeated: true)
    let refresh = {
        bookmarks.set(.single(try? NagramMessageBookmarks.list(accountId: accountId)))
    }
    refresh()

    let bookmarkPeers = bookmarks.get()
    |> mapToSignal { values -> Signal<([NagramMessageBookmark]?, [EnginePeer.Id: EnginePeer]), NoError> in
        let peerIds = Set((values ?? []).map { EnginePeer.Id($0.location.peerId) })
        guard !peerIds.isEmpty else {
            return .single((values, [:]))
        }
        return context.engine.data.get(EngineDataList(peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))))
        |> map { peers in
            return (values, Dictionary(uniqueKeysWithValues: peers.compactMap { peer in peer.map { ($0.id, $0) } }))
        }
    }
    var openBookmark: ((NagramMessageBookmark) -> Void)?
    let state = combineLatest(context.sharedContext.presentationData, bookmarkPeers, selectedTag.get())
    |> deliverOnMainQueue
    |> map { presentationData, result, selected -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let (saved, peers) = result
        let strings = presentationData.strings
        let language = strings.baseLanguageCode
        let allTagsTitle = ngI18n("Nagram.Bookmarks.AllTags", language)
        var uniqueTags: [String: String] = [:]
        for tag in (saved ?? []).flatMap(\.tags) {
            uniqueTags[tag.lowercased()] = tag
        }
        let tags = uniqueTags.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let selected = selected.flatMap { uniqueTags[$0.lowercased()] }
        let visible = (saved ?? []).filter { bookmark in
            guard let selected else { return true }
            return bookmark.tags.contains { $0.caseInsensitiveCompare(selected) == .orderedSame }
        }
        var entries: [BookmarkEntry] = []
        if !tags.isEmpty {
            entries.append(BookmarkEntry(stableId: .filter, index: 0, title: ngI18n("Nagram.Bookmarks.Filter", language), label: selected ?? allTagsTitle))
        }
        for (index, bookmark) in visible.enumerated() {
            let peer = peers[EnginePeer.Id(bookmark.location.peerId)]
            let title = (peer?.compactDisplayTitle ?? ngI18n("Nagram.Bookmarks.Message", language)) + " #\(bookmark.location.messageId)"
            entries.append(BookmarkEntry(stableId: .bookmark(bookmark.location), index: index + 1, title: title, label: bookmark.tags.joined(separator: " · ")))
        }
        if visible.isEmpty {
            let key = saved == nil ? "Nagram.Bookmarks.StorageError" : "Nagram.Bookmarks.Empty"
            entries.append(BookmarkEntry(stableId: .status, index: 1, title: ngI18n(key, language), label: ""))
        }

        let activate: (BookmarkEntry.Id) -> Void = { id in
            switch id {
            case .filter:
                let alert = UIAlertController(title: ngI18n("Nagram.Bookmarks.Filter", language), message: nil, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: allTagsTitle, style: .default) { _ in selectedTag.set(nil) })
                for tag in tags {
                    alert.addAction(UIAlertAction(title: tag, style: .default) { _ in selectedTag.set(tag) })
                }
                alert.addAction(UIAlertAction(title: strings.Common_Cancel, style: .cancel, handler: nil))
                context.sharedContext.applicationBindings.presentNativeController(alert)
            case let .bookmark(location):
                guard let bookmark = visible.first(where: { $0.location == location }) else { return }
                let messageId = EngineMessage.Id(peerId: EnginePeer.Id(location.peerId), namespace: location.namespace, id: location.messageId)
                let alert = UIAlertController(title: ngI18n("Nagram.Bookmarks.Message", language), message: nil, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: ngI18n("Nagram.Bookmarks.Open", language), style: .default) { _ in
                    openBookmark?(bookmark)
                })
                alert.addAction(UIAlertAction(title: ngI18n("Nagram.Bookmarks.Edit", language), style: .default) { _ in
                    nextgramPresentBookmarkEditor(context: context, messageId: messageId, forumThreadId: bookmark.threadId, changed: refresh)
                })
                alert.addAction(UIAlertAction(title: strings.Common_Cancel, style: .cancel, handler: nil))
                context.sharedContext.applicationBindings.presentNativeController(alert)
            case .status:
                break
            }
        }
        let data = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(presentationData: data, title: .text(ngI18n("Nagram.Bookmarks", language)),
            leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: strings.Common_Back))
        return (controllerState, (ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false), activate))
    }
    let controller = ItemListController(context: context, state: state)
    controller.navigationPresentation = .default
    openBookmark = { [weak controller] bookmark in
        guard let navigationController = controller?.navigationController as? NavigationController else { return }
        let peerId = EnginePeer.Id(bookmark.location.peerId)
        let messageId = EngineMessage.Id(peerId: peerId, namespace: bookmark.location.namespace, id: bookmark.location.messageId)
        if let threadId = bookmark.threadId {
            let _ = context.sharedContext.navigateToForumThread(context: context, peerId: peerId, threadId: threadId, messageId: messageId,
                navigationController: navigationController, activateInput: nil, scrollToEndIfExists: false, keepStack: .always, animated: true).startStandalone()
        } else {
            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context,
                chatLocation: .peer(peerId), subject: .message(id: .id(messageId), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false),
                keepStack: .always))
        }
    }
    return controller
}
