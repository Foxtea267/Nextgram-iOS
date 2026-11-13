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

private struct FeedChannel: Equatable {
    let peer: EnginePeer
    let readCounters: EnginePeerReadCounters?
    let latest: [EngineMessage]

    func isUnread(_ message: EngineMessage) -> Bool {
        return message.flags.contains(.Incoming) && !(self.readCounters?.isIncomingMessageIndexRead(message.index) ?? true)
    }
}

private struct FeedHistory: Equatable {
    var cursor: SearchMessagesState?
    var messages: [EngineMessage] = []
    var complete = false
}

private final class ChannelFeed {
    struct State: Equatable {
        var channels: [FeedChannel] = []
        var histories: [EnginePeer.Id: FeedHistory] = [:]
        var failedChannels: Set<EnginePeer.Id> = []
        var preferences: NextgramChannelFeedPreferences
        var loadingChannels = true
        var loadingPosts = false

        var category: NextgramChannelFeedPreferences.Category? {
            return self.preferences.categories.first { $0.id == self.preferences.selectedCategoryId }
        }

        var includedChannels: [FeedChannel] {
            let category = self.category
            return self.channels.filter { channel in
                let id = channel.peer.id.toInt64()
                return category?.channelIds.contains(id) ?? self.preferences.includesInDefaultFeed(channelId: id)
            }
        }

        var canLoadMore: Bool {
            return self.includedChannels.contains { self.shouldLoad($0) }
        }

        func shouldLoad(_ channel: FeedChannel) -> Bool {
            let id = channel.peer.id
            guard !self.failedChannels.contains(id), self.histories[id]?.complete != true else { return false }
            if self.preferences.unreadOnly {
                guard let counters = channel.readCounters, counters.count > 0 else { return false }
                if let index = self.loadedThrough(channel), counters.isIncomingMessageIndexRead(index) {
                    return false
                }
            }
            return true
        }

        func loadedThrough(_ channel: FeedChannel) -> EngineMessage.Index? {
            return self.histories[channel.peer.id]?.messages.last?.index
                ?? channel.latest.filter { $0.id.namespace == Namespaces.Message.Cloud }.map(\.index).min()
        }
    }

    let context: AccountContext
    let updates: ValuePromise<State>
    private var state: State
    private let channelsDisposable = MetaDisposable()
    private let postsDisposable = MetaDisposable()
    private var initialized = false

    init(context: AccountContext) {
        self.context = context
        let initial = State(preferences: NextgramChannelFeedPreferences.load(accountId: context.account.id.int64))
        self.state = initial
        self.updates = ValuePromise(initial)
        self.watchChannels(count: 128)
    }

    deinit {
        self.channelsDisposable.dispose()
        self.postsDisposable.dispose()
    }

    private func watchChannels(count: Int) {
        let context = self.context
        let signal = combineLatest(context.engine.messages.chatList(group: .root, count: count),
                                   context.engine.messages.chatList(group: .archive, count: count))
        |> deliverOnMainQueue
        var expanding = false
        self.channelsDisposable.set(signal.start(next: { [weak self] root, archive in
            guard let self, !expanding else { return }
            var seen = Set<EnginePeer.Id>()
            let channels = (root.items + archive.items).compactMap { item -> FeedChannel? in
                guard let peer = item.renderedPeer.peer, case let .channel(channel) = peer,
                      case .broadcast = channel.info, channel.participationStatus == .member,
                      seen.insert(peer.id).inserted else {
                    return nil
                }
                return FeedChannel(peer: peer, readCounters: item.readCounters, latest: item.messages)
            }
            if root.hasEarlier || archive.hasEarlier {
                expanding = true
                Queue.mainQueue().async { [weak self] in
                    self?.watchChannels(count: count * 2)
                }
                return
            }
            self.state.channels = channels
            let ids = Set(channels.map { $0.peer.id })
            self.state.histories = self.state.histories.filter { ids.contains($0.key) }
            self.state.failedChannels.formIntersection(ids)
            self.state.loadingChannels = root.isLoading || archive.isLoading
            self.updates.set(self.state)
            if !self.initialized && !self.state.loadingChannels {
                self.initialized = true
                self.loadMore()
            }
        }))
    }

    func updatePreferences(_ update: (inout NextgramChannelFeedPreferences) -> Void) {
        update(&self.state.preferences)
        self.state.preferences.save(accountId: self.context.account.id.int64)
        self.updates.set(self.state)
    }

    func refresh() {
        self.postsDisposable.set(nil)
        self.state.histories.removeAll()
        self.state.failedChannels.removeAll()
        self.state.loadingPosts = false
        self.updates.set(self.state)
        self.loadMore()
    }

    func retryFailedChannels() {
        self.state.failedChannels.removeAll()
        self.updates.set(self.state)
        self.loadMore()
    }

    func loadMore() {
        guard !self.state.loadingChannels && !self.state.loadingPosts else { return }
        // Fetch channels whose next page can contain the newest posts first.
        let channels = self.state.includedChannels.filter { self.state.shouldLoad($0) }
        let boundaries = Dictionary(uniqueKeysWithValues: channels.compactMap { channel in
            self.state.loadedThrough(channel).map { (channel.peer.id, $0) }
        })
        let batch = channels.sorted { lhs, rhs in
            switch (boundaries[lhs.peer.id], boundaries[rhs.peer.id]) {
            case let (lhsIndex?, rhsIndex?) where lhsIndex != rhsIndex:
                return lhsIndex > rhsIndex
            case (nil, .some):
                return true
            case (.some, nil):
                return false
            default:
                return lhs.peer.id.toInt64() < rhs.peer.id.toInt64()
            }
        }.prefix(4)
        guard !batch.isEmpty else { return }

        self.state.loadingPosts = true
        self.updates.set(self.state)
        let requests = batch.map { channel -> Signal<(SearchMessagesResult, SearchMessagesState)?, NoError> in
            let id = channel.peer.id
            let cursor = self.state.histories[id]?.cursor
            return self.context.engine.messages.searchMessages(
                location: .peer(peerId: id, fromId: nil, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil),
                query: "", state: cursor, limit: 20
            )
            |> take(1)
            |> map(Optional.init)
            |> timeout(12.0, queue: .mainQueue(), alternate: .single(nil))
        }
        self.postsDisposable.set((combineLatest(requests) |> deliverOnMainQueue).start(next: { [weak self] results in
            guard let self else { return }
            for (channel, result) in zip(batch, results) {
                let id = channel.peer.id
                guard self.state.channels.contains(where: { $0.peer.id == id }) else { continue }
                guard let (page, cursor) = result, page.completed || self.state.histories[id]?.cursor != cursor,
                      !page.messages.isEmpty || channel.latest.isEmpty else {
                    self.state.failedChannels.insert(id)
                    continue
                }
                self.state.histories[id] = FeedHistory(
                    cursor: cursor,
                    messages: page.messages.map(EngineMessage.init),
                    complete: page.completed
                )
            }
            self.state.loadingPosts = false
            self.updates.set(self.state)
        }))
    }

    func markRead(channels: [FeedChannel]) {
        guard !NagramSettings.shared.suppressReadReceipts else { return }
        let unreadIds = channels.filter { $0.readCounters?.isUnread == true }.map { $0.peer.id }
        let _ = self.context.engine.messages.togglePeersUnreadMarkInteractively(peerIds: unreadIds, setToValue: false).startStandalone()
    }
}

private struct FeedEntry: ItemListNodeEntry {
    enum Id: Hashable {
        case sources, unread, status, more, failure
        case post(EngineMessage.Id)
    }

    let stableId: Id
    let index: Int
    let title: String
    var detail = ""
    var peer: EnginePeer?
    var date: String?
    var selected = false

    var section: ItemListSectionId {
        switch self.stableId {
        case .sources, .unread: return 0
        case .post, .status: return 1
        case .more, .failure: return 2
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.index < rhs.index
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let actions = arguments as! FeedActions
        switch self.stableId {
        case .status:
            return ItemListTextItem(presentationData: presentationData, text: .plain(self.title), sectionId: self.section)
        case .unread:
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: self.title,
                                      value: self.selected, sectionId: self.section, style: .blocks, updated: actions.unreadOnly)
        case .sources, .more, .post, .failure:
            return ItemListDisclosureItem(
                presentationData: presentationData, systemStyle: .glass, context: actions.context, iconPeer: self.peer,
                title: self.title, titleBadge: self.selected ? "●" : nil, label: self.detail,
                labelStyle: self.peer == nil ? .text : .multilineDetailText,
                additionalDetailLabel: self.date, sectionId: self.section, style: .blocks,
                action: { actions.activate(self.stableId) }
            )
        }
    }
}

private struct FeedActions {
    let context: AccountContext
    let activate: (FeedEntry.Id) -> Void
    let unreadOnly: (Bool) -> Void
}

private func feedPreview(_ message: EngineMessage, peer: EnginePeer, strings: PresentationStrings) -> String? {
    let language = strings.baseLanguageCode
    if message.media.contains(where: { $0 is TelegramMediaAction }) || message.adAttribute != nil {
        return nil
    }
    if case let .channel(channel) = peer, channel.restrictionInfo?.rules.contains(where: { $0.platform == "ios" || $0.platform == "all" }) == true {
        return ngI18n("Nagram.ChannelFeed.Post", language)
    }
    if message.attributes.contains(where: { $0 is RestrictedContentMessageAttribute }) {
        return ngI18n("Nagram.ChannelFeed.Post", language)
    }
    let hasSpoiler = message.attributes.contains { attribute in
        (attribute as? TextEntitiesMessageAttribute)?.entities.contains { $0.type == .Spoiler } ?? false
    }
    if hasSpoiler && !NagramSettings.shared.autoRevealSpoilers {
        return ngI18n("Nagram.ChannelFeed.Spoiler", language)
    }
    let text = message.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    if !text.isEmpty {
        return String(text.prefix(240))
    }
    for media in message.media {
        if media is TelegramMediaImage {
            return strings.Message_Photo
        }
        if let file = media as? TelegramMediaFile {
            if file.isSticker { return strings.Message_Sticker }
            if file.isVideo { return strings.Message_Video }
            if file.isMusic || file.isVoice { return strings.Message_Audio }
            return strings.Message_File
        }
    }
    return ngI18n("Nagram.ChannelFeed.Post", language)
}

public func nextgramChannelFeedController(context: AccountContext) -> ViewController {
    let feed = ChannelFeed(context: context)
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    var openSources: (() -> Void)?
    var openPost: ((EngineMessage.Id, EnginePeer) -> Void)?

    let state = combineLatest(context.sharedContext.presentationData, feed.updates.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, FeedActions)) in
        let strings = presentationData.strings
        let language = strings.baseLanguageCode
        let data = ItemListPresentationData(presentationData)
        let title = ngI18n("Nagram.ChannelFeed", language)
        var entries = [
            FeedEntry(stableId: .sources, index: 0, title: ngI18n("Nagram.ChannelFeed.Sources", language),
                      detail: state.category?.name ?? ngI18n("Nagram.ChannelFeed.All", language)),
            FeedEntry(stableId: .unread, index: 1, title: ngI18n("Nagram.ChannelFeed.Unread", language), selected: state.preferences.unreadOnly)
        ]
        let channels = state.includedChannels
        // Stop where an unloaded channel page might still interleave with the visible posts.
        let visibleThrough = channels.filter { state.shouldLoad($0) }.compactMap { state.loadedThrough($0) }.max()
        var posts: [(FeedChannel, EngineMessage)] = []
        var seen = Set<EngineMessage.Id>()
        for channel in channels {
            let history = state.histories[channel.peer.id]?.messages ?? []
            for message in channel.latest + history {
                guard message.id.peerId == channel.peer.id, message.id.namespace == Namespaces.Message.Cloud,
                      visibleThrough.map({ message.index >= $0 }) ?? true,
                      seen.insert(message.id).inserted,
                      !state.preferences.unreadOnly || channel.isUnread(message) else { continue }
                posts.append((channel, message))
            }
        }
        posts.sort { $0.1.index > $1.1.index }
        var displayedGroups: [EnginePeer.Id: Set<Int64>] = [:]
        for (channel, message) in posts {
            guard let preview = feedPreview(message, peer: channel.peer, strings: strings) else { continue }
            if let group = message.groupingKey, !displayedGroups[channel.peer.id, default: []].insert(group).inserted {
                continue
            }
            entries.append(FeedEntry(stableId: .post(message.id), index: entries.count,
                                     title: channel.peer.compactDisplayTitle, detail: preview, peer: channel.peer,
                                     date: formatter.string(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp))),
                                     selected: channel.isUnread(message)))
        }
        if state.loadingChannels || state.loadingPosts {
            entries.append(FeedEntry(stableId: .status, index: entries.count, title: ngI18n("Nagram.ChannelFeed.Loading", language)))
        } else {
            if entries.count == 2 {
                entries.append(FeedEntry(stableId: .status, index: entries.count, title: ngI18n("Nagram.ChannelFeed.Empty", language)))
            }
            if state.canLoadMore {
                entries.append(FeedEntry(stableId: .more, index: entries.count, title: ngI18n("Nagram.ChannelFeed.More", language)))
            }
            if channels.contains(where: { state.failedChannels.contains($0.peer.id) }) {
                entries.append(FeedEntry(stableId: .failure, index: entries.count, title: ngI18n("Nagram.ChannelFeed.Retry", language)))
            }
        }

        let actions = FeedActions(context: context, activate: { id in
            switch id {
            case .sources: openSources?()
            case .more: feed.loadMore()
            case .failure: feed.retryFailedChannels()
            case let .post(id):
                if let channel = channels.first(where: { $0.peer.id == id.peerId }) {
                    openPost?(id, channel.peer)
                }
            case .unread, .status: break
            }
        }, unreadOnly: { value in
            feed.updatePreferences { $0.unreadOnly = value }
        })
        let menu = ItemListNavigationButton(content: .text(ngI18n("Nagram.ChannelFeed.Actions", language)), style: .regular,
                                            enabled: !state.loadingChannels, action: {
            let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: ngI18n("Nagram.ChannelFeed.Refresh", language), style: .default) { _ in feed.refresh() })
            if channels.contains(where: { $0.readCounters?.isUnread == true }) && !NagramSettings.shared.suppressReadReceipts {
                alert.addAction(UIAlertAction(title: ngI18n("Nagram.ChannelFeed.MarkRead", language), style: .default) { _ in
                    let confirmation = UIAlertController(title: ngI18n("Nagram.ChannelFeed.MarkRead", language),
                                                         message: ngI18n("Nagram.ChannelFeed.MarkReadConfirm", language), preferredStyle: .alert)
                    confirmation.addAction(UIAlertAction(title: strings.Common_Cancel, style: .cancel))
                    confirmation.addAction(UIAlertAction(title: strings.Common_OK, style: .default) { _ in feed.markRead(channels: channels) })
                    context.sharedContext.applicationBindings.presentNativeController(confirmation)
                })
            }
            alert.addAction(UIAlertAction(title: strings.Common_Cancel, style: .cancel))
            context.sharedContext.applicationBindings.presentNativeController(alert)
        })
        return (ItemListControllerState(presentationData: data, title: .text(title), leftNavigationButton: nil, rightNavigationButton: menu,
                                        backNavigationButton: ItemListBackButton(title: strings.Common_Back)),
                (ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false), actions))
    }
    let controller = ItemListController(context: context, state: state)
    controller.navigationPresentation = .default
    openSources = { [weak controller] in
        controller?.push(channelFeedSourcesController(feed: feed))
    }
    openPost = { [weak controller] id, peer in
        guard let navigationController = controller?.navigationController as? NavigationController else { return }
        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(
            navigationController: navigationController, context: context, chatLocation: .peer(peer),
            subject: .message(id: .id(id), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false),
            keepStack: .always
        ))
    }
    return controller
}

private struct FeedSourceEntry: ItemListNodeEntry {
    enum Id: Hashable {
        case category(UUID?)
        case add, rename, delete, autoInclude
        case channel(EnginePeer.Id)
    }

    let stableId: Id
    let index: Int
    let title: String
    var selected = false

    var section: ItemListSectionId {
        switch self.stableId {
        case .category: return 0
        case .add, .rename, .delete: return 1
        case .autoInclude: return 2
        case .channel: return 3
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.index < rhs.index
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let activate = arguments as! (Id, Bool) -> Void
        switch self.stableId {
        case .autoInclude, .channel:
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: self.title,
                                      value: self.selected, sectionId: self.section, style: .blocks, updated: { activate(self.stableId, $0) })
        case .category, .add, .rename, .delete:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: self.title,
                                          label: self.selected ? "✓" : "", sectionId: self.section, style: .blocks,
                                          action: { activate(self.stableId, true) })
        }
    }
}

private func channelFeedSourcesController(feed: ChannelFeed) -> ViewController {
    let context = feed.context
    let state = combineLatest(context.sharedContext.presentationData, feed.updates.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, (FeedSourceEntry.Id, Bool) -> Void)) in
        let strings = presentationData.strings
        let language = strings.baseLanguageCode
        let data = ItemListPresentationData(presentationData)
        let category = state.category
        var entries = [
            FeedSourceEntry(stableId: .category(nil), index: 0, title: ngI18n("Nagram.ChannelFeed.All", language), selected: category == nil)
        ]
        for value in state.preferences.categories {
            entries.append(FeedSourceEntry(stableId: .category(value.id), index: entries.count, title: value.name, selected: value.id == category?.id))
        }
        entries.append(FeedSourceEntry(stableId: .add, index: entries.count, title: ngI18n("Nagram.ChannelFeed.AddCategory", language)))
        if category != nil {
            entries.append(FeedSourceEntry(stableId: .rename, index: entries.count, title: ngI18n("Nagram.ChannelFeed.RenameCategory", language)))
            entries.append(FeedSourceEntry(stableId: .delete, index: entries.count, title: ngI18n("Nagram.ChannelFeed.DeleteCategory", language)))
        } else {
            entries.append(FeedSourceEntry(stableId: .autoInclude, index: entries.count,
                                           title: ngI18n("Nagram.ChannelFeed.AutoInclude", language),
                                           selected: state.preferences.manuallyIncludedChannelIds == nil))
        }
        let includedIds = Set(state.includedChannels.map { $0.peer.id })
        let channels = state.channels.sorted { $0.peer.compactDisplayTitle.localizedStandardCompare($1.peer.compactDisplayTitle) == .orderedAscending }
        for channel in channels {
            entries.append(FeedSourceEntry(stableId: .channel(channel.peer.id), index: entries.count,
                                           title: channel.peer.compactDisplayTitle, selected: includedIds.contains(channel.peer.id)))
        }

        let activate: (FeedSourceEntry.Id, Bool) -> Void = { id, enabled in
            switch id {
            case let .category(id):
                feed.updatePreferences { $0.selectedCategoryId = id }
            case .autoInclude:
                let known = Set(state.channels.map { $0.peer.id.toInt64() })
                feed.updatePreferences { $0.setAutomaticallyIncludesNewChannels(enabled, knownChannelIds: known) }
            case .add, .rename:
                let editing = id == .rename ? category : nil
                let key = editing == nil ? "Nagram.ChannelFeed.AddCategory" : "Nagram.ChannelFeed.RenameCategory"
                let editor = UIAlertController(title: ngI18n(key, language), message: nil, preferredStyle: .alert)
                editor.addTextField { field in
                    field.placeholder = ngI18n("Nagram.ChannelFeed.CategoryName", language)
                    field.text = editing?.name
                }
                editor.addAction(UIAlertAction(title: strings.Common_Cancel, style: .cancel))
                editor.addAction(UIAlertAction(title: strings.Common_Done, style: .default) { [weak editor] _ in
                    let text = editor?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !text.isEmpty else { return }
                    let name = String(text.prefix(60))
                    feed.updatePreferences { preferences in
                        if let editing, let index = preferences.categories.firstIndex(where: { $0.id == editing.id }) {
                            preferences.categories[index].name = name
                        } else {
                            let value = NextgramChannelFeedPreferences.Category(name: name, channelIds: [])
                            preferences.categories.append(value)
                            preferences.selectedCategoryId = value.id
                        }
                    }
                })
                context.sharedContext.applicationBindings.presentNativeController(editor)
            case .delete:
                guard let category else { return }
                let alert = UIAlertController(title: ngI18n("Nagram.ChannelFeed.DeleteCategory", language),
                                              message: category.name, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: strings.Common_Cancel, style: .cancel))
                alert.addAction(UIAlertAction(title: strings.Common_Delete, style: .destructive) { _ in
                    feed.updatePreferences { preferences in
                        preferences.categories.removeAll { $0.id == category.id }
                        if preferences.selectedCategoryId == category.id {
                            preferences.selectedCategoryId = nil
                        }
                    }
                })
                context.sharedContext.applicationBindings.presentNativeController(alert)
            case let .channel(id):
                feed.updatePreferences { preferences in
                    let packedId = id.toInt64()
                    if let selectedId = preferences.selectedCategoryId,
                       let index = preferences.categories.firstIndex(where: { $0.id == selectedId }) {
                        if enabled {
                            preferences.categories[index].channelIds.insert(packedId)
                        } else {
                            preferences.categories[index].channelIds.remove(packedId)
                        }
                    } else if var manual = preferences.manuallyIncludedChannelIds {
                        if enabled {
                            manual.insert(packedId)
                        } else {
                            manual.remove(packedId)
                        }
                        preferences.manuallyIncludedChannelIds = manual
                    } else if enabled {
                        preferences.excludedChannelIds.remove(packedId)
                    } else {
                        preferences.excludedChannelIds.insert(packedId)
                    }
                }
            }
        }
        return (ItemListControllerState(presentationData: data, title: .text(ngI18n("Nagram.ChannelFeed.Sources", language)),
                                        leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: strings.Common_Back)),
                (ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false), activate))
    }
    let controller = ItemListController(context: context, state: state)
    controller.navigationPresentation = .default
    return controller
}
