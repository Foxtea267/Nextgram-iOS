import AccountContext
import AsyncDisplayKit
import ComponentFlow
import Display
import EdgeEffect
import Foundation
import ItemListPeerItem
import ItemListUI
import NagramSettings
import NagramSettingsSignal
import NagramStrings
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import UIKit
import WallpaperBackgroundNode

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
        let searchQuery: String?
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
            guard !NagramDemoMode.isEnabled else { return false }
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
            if let index = self.histories[channel.peer.id]?.messages.last?.index {
                return index
            }
            return self.searchQuery == nil ? channel.latest.filter { $0.id.namespace == Namespaces.Message.Cloud }.map(\.index).min() : nil
        }
    }

    let context: AccountContext
    let updates: ValuePromise<State>
    private var state: State
    private let channelsDisposable = MetaDisposable()
    private let postsDisposable = MetaDisposable()
    private var initialized = false
    private var generation = UUID()
    var active = false
    private var lifecycleObservers: [NSObjectProtocol] = []

    func loadMoreIfNeeded() {
        guard self.active, self.state.searchQuery != nil || NagramSettings.shared.channelFeedAutoLoad, self.state.canLoadMore else { return }
        self.loadMore()
    }

    func suspend() {
        self.active = false
        self.generation = UUID()
        self.postsDisposable.set(nil)
        self.state.loadingPosts = false
        self.updates.set(self.state)
    }

    init(context: AccountContext, searchQuery: String?) {
        self.context = context
        let initial = State(preferences: NextgramChannelFeedPreferences.load(accountId: context.account.id.int64), searchQuery: searchQuery)
        self.state = initial
        self.updates = ValuePromise(initial)
        self.lifecycleObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.generation = UUID()
            self.postsDisposable.set(nil)
            self.state.loadingPosts = false
            self.updates.set(self.state)
        })
        self.lifecycleObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.updates.set(self.state)
        })
    }

    func start() {
        self.watchChannels(count: 128)
    }

    deinit {
        self.channelsDisposable.dispose()
        self.postsDisposable.dispose()
        self.lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
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
            // The isolated demo store does not finish the archive chat-list
            // stream because it has no network synchronization. The channel
            // rows are already complete in the seeded snapshot, so do not keep
            // the feed in its loading state in demo mode.
            self.state.loadingChannels = NagramDemoMode.isEnabled ? false : (root.isLoading || archive.isLoading)
            self.updates.set(self.state)
            if !self.initialized && !self.state.loadingChannels {
                self.initialized = true
                self.loadMore()
            }
        }))
    }

    func updatePreferences(_ update: (inout NextgramChannelFeedPreferences) -> Void) {
        self.state.preferences = NextgramChannelFeedPreferences.load(accountId: self.context.account.id.int64)
        update(&self.state.preferences)
        self.state.preferences.save(accountId: self.context.account.id.int64)
        self.updates.set(self.state)
    }

    func reloadPreferences() {
        let stored = NextgramChannelFeedPreferences.load(accountId: self.context.account.id.int64)
        guard stored != self.state.preferences else { return }
        self.state.preferences = stored
        self.updates.set(self.state)
    }

    func refresh() {
        self.generation = UUID()
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
        guard self.active, UIApplication.shared.applicationState != .background,
              !self.state.loadingChannels, !self.state.loadingPosts else { return }
        // Fetch channels whose next page can contain the newest posts first.
        let searchQuery = self.state.searchQuery
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
        let generation = self.generation
        self.updates.set(self.state)
        let requests = batch.map { channel -> Signal<(SearchMessagesResult, SearchMessagesState)?, NoError> in
            let id = channel.peer.id
            let cursor = self.state.histories[id]?.cursor
            return self.context.engine.messages.searchMessages(
                location: .peer(peerId: id, fromId: nil, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil),
                query: searchQuery ?? "", state: cursor, limit: 20
            )
            |> take(1)
            |> map(Optional.init)
            |> timeout(12.0, queue: .mainQueue(), alternate: .single(nil))
        }
        self.postsDisposable.set((combineLatest(requests) |> deliverOnMainQueue).start(next: { [weak self] results in
            guard let self, self.generation == generation else { return }
            for (channel, result) in zip(batch, results) {
                let id = channel.peer.id
                guard self.state.channels.contains(where: { $0.peer.id == id }) else { continue }
                guard let (page, cursor) = result, !page.nextgramRequestFailed, page.completed || self.state.histories[id]?.cursor != cursor,
                      searchQuery != nil || !page.messages.isEmpty || channel.latest.isEmpty else {
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
        case status, more, failure
        case post(EngineMessage.Id)
    }

    let stableId: Id
    let index: Int
    let text: String
    var post: NextgramFeedPost?
    let presentationData: PresentationData
    var displayOptions: NextgramChannelFeedPreferences.DisplayOptions?

    var section: ItemListSectionId { 0 }

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.index < rhs.index
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let actions = arguments as! FeedActions
        if let post = self.post {
            let options = self.displayOptions
            let canShare = options?.showShareButtons == true && !post.peer.isCopyProtectionEnabled && !post.message._asMessage().isCopyProtected()
            // MARK: NEXTGRAM — Use Telegram's native message item so feed bubbles,
            // media layout, spoilers and media taps match a conversation.
            let nativeActions = ChatMessageFeedItemActions(
                openUrl: { _ in actions.activate(.post(post.message.id)) },
                openMessage: { message in
                    if message.media.contains(where: { $0 is TelegramMediaImage || $0 is TelegramMediaFile || $0 is TelegramMediaWebpage }),
                       actions.openMedia(message) {
                        return true
                    }
                    actions.activate(.post(post.message.id))
                    return true
                },
                openPeer: { _ in actions.activate(.post(post.message.id)) },
                openInstantPage: { _ in actions.activate(.post(post.message.id)) },
                navigateToMessage: { _ in actions.activate(.post(post.message.id)) },
                nextgramShowsChannelAvatar: options?.showPostAvatars ?? false,
                nextgramShowsChannelName: options?.showChannelNames ?? false,
                nextgramShare: canShare ? { actions.share(post.messages) } : nil,
                nextgramHost: actions.host,
                nextgramHideChannel: { actions.hideChannel(post.peer.id) }
            )
            return actions.context.sharedContext.makeChatMessageFeedItem(
                context: actions.context,
                messages: post.messages,
                presentationData: actions.presentationData,
                accountPeer: nil,
                backgroundNode: actions.backgroundNode(),
                actions: nativeActions
            )
        }
        return NextgramFeedBubbleItem(context: actions.context, presentation: actions.presentation, text: self.text, post: self.post,
                                      action: self.stableId == .status ? nil : { actions.activate(self.stableId) })
    }
}

private struct FeedActions {
    let context: AccountContext
    let presentation: ChatPresentationData
    let presentationData: PresentationData
    let activate: (FeedEntry.Id) -> Void
    let openMedia: (EngineMessage) -> Bool
    let share: ([EngineMessage]) -> Void
    let hideChannel: (EnginePeer.Id) -> Void
    let host: () -> ViewController?
    let backgroundNode: () -> ASDisplayNode?
}

private func feedPreview(_ message: EngineMessage, peer: EnginePeer, strings: PresentationStrings) -> (text: String, showsMedia: Bool)? {
    let language = strings.baseLanguageCode
    if message.media.contains(where: { $0 is TelegramMediaAction }) || message.adAttribute != nil {
        return nil
    }
    if case let .channel(channel) = peer, channel.restrictionInfo?.rules.contains(where: { $0.platform == "ios" || $0.platform == "all" }) == true {
        return (ngI18n("Nagram.ChannelFeed.Post", language), false)
    }
    if message.attributes.contains(where: { $0 is RestrictedContentMessageAttribute }) {
        return (ngI18n("Nagram.ChannelFeed.Post", language), false)
    }
    let hasSpoiler = message.attributes.contains { attribute in
        (attribute as? TextEntitiesMessageAttribute)?.entities.contains { $0.type == .Spoiler } ?? false
    }
    if hasSpoiler && !NagramSettings.shared.autoRevealSpoilers {
        return (ngI18n("Nagram.ChannelFeed.Spoiler", language), false)
    }
    let rawMessage = message._asMessage()
    let channelProtected: Bool
    if case let .channel(channel) = peer {
        channelProtected = channel.flags.contains(.copyProtectionEnabled)
    } else {
        channelProtected = false
    }
    let showsMedia = !channelProtected && !rawMessage.isCopyProtected() && !rawMessage.containsSecretMedia
        && rawMessage.paidContent == nil && (NagramSettings.shared.autoRevealSpoilers || !message.attributes.contains { $0 is MediaSpoilerMessageAttribute })
    let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.isEmpty {
        return (text, showsMedia)
    }
    for media in message.media {
        if media is TelegramMediaImage {
            return (strings.Message_Photo, showsMedia)
        }
        if let file = media as? TelegramMediaFile {
            if file.isSticker { return (strings.Message_Sticker, false) }
            if file.isVideo { return (strings.Message_Video, showsMedia) }
            if file.isMusic || file.isVoice { return (strings.Message_Audio, false) }
            return (strings.Message_File, false)
        }
    }
    return (ngI18n("Nagram.ChannelFeed.Post", language), false)
}

private final class ChannelFeedTimelineController: ItemListController {
    private let wallpaperNode: WallpaperBackgroundNode
    private let wallpaperDisposable = MetaDisposable()
    private let headerEffectsDisposable = MetaDisposable()
    private let hiddenMediaDisposable = MetaDisposable()
    private var hiddenMedia: [EngineMessage.Id: [EngineRawMedia]] = [:]
    private let headerEffectsNode = ASDisplayNode()
    private let headerShadeView = EdgeEffectView()
    private var headerBlurNode: WallpaperEdgeEffectNode?
    private let context: AccountContext
    var feedWallpaper: ASDisplayNode { self.wallpaperNode }

    init(context: AccountContext, state: Signal<(ItemListControllerState, (ItemListNodeState, FeedActions)), NoError>) {
        self.context = context
        self.wallpaperNode = createWallpaperBackgroundNode(context: context, forChatDisplay: true, useSharedAnimationPhase: true)
        let presentation = context.sharedContext.currentPresentationData.with { $0 }
        super.init(presentationData: ItemListPresentationData(presentation),
                   updatedPresentationData: context.sharedContext.presentationData |> map { ItemListPresentationData($0) },
                   state: state, tabBarItem: nil)
        self.navigationEdgeEffectColorOverride = .clear
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.wallpaperDisposable.dispose()
        self.headerEffectsDisposable.dispose()
        self.hiddenMediaDisposable.dispose()
    }

    func transitionNode(messageId: EngineMessage.Id, media: EngineRawMedia, adjustRect: Bool) -> (ASDisplayNode, CGRect, () -> (UIView?, UIView?))? {
        var result: (ASDisplayNode, CGRect, () -> (UIView?, UIView?))?
        self.forEachItemNode { node in
            guard result == nil, let item = node as? ChatMessageItemNodeProtocol, item.view.window != nil else { return }
            result = item.transitionNode(id: messageId, media: media, adjustRect: adjustRect)
        }
        return result
    }

    func addToMediaTransitionSurface(_ view: UIView) {
        guard let listView = (self.displayNode as? ItemListControllerNode)?.listNode.view else { return }
        listView.superview?.insertSubview(view, aboveSubview: listView)
    }

    func updateHiddenMedia() {
        self.forEachItemNode { node in
            (node as? ChatMessageItemNodeProtocol)?.updateHiddenMedia(self.hiddenMedia)
        }
    }

    override func loadDisplayNode() {
        super.loadDisplayNode()
        self.hiddenMediaDisposable.set((self.context.sharedContext.mediaManager.galleryHiddenMediaManager.hiddenIds()
        |> deliverOnMainQueue).startStrict(next: { [weak self] ids in
            guard let self else { return }
            self.hiddenMedia = [:]
            for case let .chat(accountId, messageId, media) in ids where accountId == self.context.account.id {
                self.hiddenMedia[messageId, default: []].append(media)
            }
            self.updateHiddenMedia()
        }))
        (self.displayNode as? ItemListControllerNode)?.setListBackgroundNode(self.wallpaperNode)
        self.headerEffectsNode.isUserInteractionEnabled = false
        self.headerEffectsNode.view.accessibilityElementsHidden = true
        self.headerEffectsNode.view.addSubview(self.headerShadeView)
        let current = self.context.sharedContext.currentPresentationData.with { $0 }
        self.wallpaperNode.update(wallpaper: current.chatWallpaper, animated: false)
        self.wallpaperNode.updateBubbleTheme(bubbleTheme: current.theme, bubbleCorners: current.chatBubbleCorners)
        self.wallpaperDisposable.set((self.context.sharedContext.presentationData
        |> map { $0.chatWallpaper }
        |> distinctUntilChanged
        |> deliverOnMainQueue).start(next: { [weak self] wallpaper in
            self?.wallpaperNode.update(wallpaper: wallpaper, animated: false)
            self?.requestLayout(transition: .immediate)
        }))
        self.headerEffectsDisposable.set((combineLatest(
            nagramChatHeaderEffectsSignal(),
            nagramBoolSignal("nagram.hideChatTitleGlass", defaultValue: false),
            self.context.sharedContext.presentationData |> map { $0.theme.overallDarkAppearance } |> distinctUntilChanged
        )
        |> deliverOnMainQueue).start(next: { [weak self] _ in
            self?.requestLayout(transition: .immediate)
        }))
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.wallpaperNode.updateLayout(size: layout.size, displayMode: .aspectFill, transition: transition)
        transition.updateFrame(node: self.wallpaperNode, frame: CGRect(origin: .zero, size: layout.size))
        self.updateHeaderEffects(layout: layout, transition: transition)
    }

    private func updateHeaderEffects(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        let navigationHeight = self.cleanNavigationHeight
        guard let navigationBar = self.navigationBar, navigationBar.supernode === self.displayNode,
              navigationHeight > 0.0, layout.size.width > 0.0 else {
            self.headerEffectsNode.isHidden = true
            return
        }
        if self.headerEffectsNode.supernode == nil {
            self.displayNode.insertSubnode(self.headerEffectsNode, belowSubnode: navigationBar)
        }
        self.headerEffectsNode.isHidden = false
        let settings = NagramSettings.shared
        let presentation = self.context.sharedContext.currentPresentationData.with { $0 }
        let bottom = navigationHeight + layout.insets(options: [.input]).top + 34.0
        transition.updateFrame(node: self.headerEffectsNode, frame: CGRect(x: 0.0, y: 0.0, width: layout.size.width, height: bottom))
        let shadeHeight = navigationHeight + 28.0
        let shadeFrame = CGRect(x: 0.0, y: 0.0, width: layout.size.width, height: shadeHeight)
        let opacity = presentation.theme.overallDarkAppearance ? settings.chatHeaderDarkShadeOpacity : settings.chatHeaderLightShadeOpacity
        let shadeAlpha = settings.chatHeaderShadeEnabled ? CGFloat(min(100, max(0, opacity))) / 100.0 : 0.0
        self.headerShadeView.isHidden = shadeAlpha == 0.0
        if shadeAlpha > 0.0 {
            transition.updateFrame(view: self.headerShadeView, frame: shadeFrame)
            self.headerShadeView.update(content: .black, alpha: shadeAlpha, rect: shadeFrame, edge: .top, edgeSize: shadeHeight,
                transition: ComponentTransition(transition))
        }

        if settings.chatHeaderBlurEnabled {
            if self.headerBlurNode == nil, let blur = self.wallpaperNode.makeEdgeEffectNode() {
                blur.isUserInteractionEnabled = false
                self.headerEffectsNode.addSubnode(blur)
                self.headerEffectsNode.view.bringSubviewToFront(self.headerShadeView)
                self.headerBlurNode = blur
            }
            let height = max(100.0, bottom)
            let blurFrame = CGRect(x: 0.0, y: bottom - height, width: layout.size.width, height: height)
            let edgeSize = settings.hideChatTitleGlass ? max(80.0, navigationHeight + 12.0) : 80.0
            let alpha: CGFloat
            if case .image = presentation.chatWallpaper {
                alpha = 0.7
            } else {
                alpha = presentation.chatWallpaper.singleColor != nil ? 0.85 : 0.75
            }
            if let blur = self.headerBlurNode {
                transition.updateFrame(node: blur, frame: blurFrame)
                blur.update(rect: blurFrame, edge: WallpaperEdgeEffectEdge(edge: .top, size: edgeSize), alpha: alpha,
                    blur: true, containerSize: layout.size, transition: transition)
            }
        } else {
            self.headerBlurNode?.removeFromSupernode()
            self.headerBlurNode = nil
        }
    }
}

public func nextgramChannelFeedController(context: AccountContext) -> ViewController {
    return channelFeedTimelineController(context: context, searchQuery: nil)
}

private func channelFeedTimelineController(context: AccountContext, searchQuery: String?) -> ViewController {
    let feed = ChannelFeed(context: context, searchQuery: searchQuery)
    let dayFormatter = DateFormatter()
    dayFormatter.dateStyle = .medium
    let timeFormatter = DateFormatter()
    timeFormatter.timeStyle = .short
    var openSources: (() -> Void)?
    var openSettings: (() -> Void)?
    var openPost: ((EngineMessage.Id, EnginePeer) -> Void)?
    var openMedia: ((EngineMessage) -> Bool)?
    var openSearch: ((String) -> Void)?
    var share: (([EngineMessage]) -> Void)?
    var feedHost: (() -> ViewController?)?
    var feedWallpaperNode: (() -> ASDisplayNode?)?
    var nearBottom = false
    var moreRowVisible = false
    var autoLoadScheduled = false

    func scheduleAutoLoad() {
        guard !autoLoadScheduled, nearBottom || moreRowVisible else { return }
        autoLoadScheduled = true
        Queue.mainQueue().async {
            autoLoadScheduled = false
            // Recheck after list layout: the user may have scrolled away before this callback runs.
            if nearBottom || moreRowVisible { feed.loadMoreIfNeeded() }
        }
    }

    let state = combineLatest(context.sharedContext.presentationData, feed.updates.get(), nagramBoolSignal("nagram.channelFeedAutoLoad", defaultValue: true))
    |> deliverOnMainQueue
    |> map { presentationData, state, autoLoad -> (ItemListControllerState, (ItemListNodeState, FeedActions)) in
        // Queue after the current list update. A short result page should fill the viewport without requiring a tap.
        if (autoLoad || searchQuery != nil) && !state.loadingPosts && !state.loadingChannels && state.canLoadMore {
            scheduleAutoLoad()
        }
        let strings = presentationData.strings
        let language = strings.baseLanguageCode
        let data = ItemListPresentationData(presentationData)
        let title = ngI18n("Nagram.ChannelFeed", language)
        let categoryTitle = state.category?.name ?? ngI18n("Nagram.ChannelFeed.All", language)
        var entries: [FeedEntry] = []
        let channels = state.includedChannels
        // Stop where an unloaded channel page might still interleave with the visible posts.
        let visibleThrough = channels.filter { state.shouldLoad($0) }.compactMap { state.loadedThrough($0) }.max()
        var posts: [(FeedChannel, EngineMessage)] = []
        var seen = Set<EngineMessage.Id>()
        for channel in channels {
            let history = state.histories[channel.peer.id]?.messages ?? []
            let messages: [EngineMessage]
            if let searchQuery {
                messages = NagramDemoMode.isEnabled
                    ? channel.latest.filter { $0.text.localizedStandardContains(searchQuery) }
                    : history
            } else {
                messages = channel.latest + history
            }
            for message in messages {
                guard message.id.peerId == channel.peer.id, message.id.namespace == Namespaces.Message.Cloud,
                      visibleThrough.map({ message.index >= $0 }) ?? true,
                      seen.insert(message.id).inserted,
                      !state.preferences.unreadOnly || channel.isUnread(message) else { continue }
                posts.append((channel, message))
            }
        }
        posts.sort { $0.1.index > $1.1.index }
        let albums = Dictionary(grouping: posts.filter { $0.1.groupingKey != nil }, by: { $0.0.peer.id })
            .mapValues { Dictionary(grouping: $0.map(\.1), by: { $0.groupingKey }) }
        var displayedGroups: [EnginePeer.Id: Set<Int64>] = [:]
        var previousDay: Date?
        let calendar = Calendar.current
        for (channel, message) in posts {
            guard let preview = feedPreview(message, peer: channel.peer, strings: strings) else { continue }
            if let group = message.groupingKey, !displayedGroups[channel.peer.id, default: []].insert(group).inserted {
                continue
            }
            let date = Date(timeIntervalSince1970: TimeInterval(message.timestamp))
            let day = calendar.startOfDay(for: date)
            let album = message.groupingKey.flatMap { albums[channel.peer.id]?[$0] } ?? [message]
            let post = NextgramFeedPost(peer: channel.peer, message: message, messages: album.sorted { $0.index < $1.index }, showsMedia: preview.showsMedia,
                                        day: day == previousDay ? nil : dayFormatter.string(from: date),
                                        time: timeFormatter.string(from: date), unread: channel.isUnread(message))
            previousDay = day
            entries.append(FeedEntry(stableId: .post(message.id), index: entries.count, text: preview.text, post: post, presentationData: presentationData, displayOptions: state.preferences.displayOptions))
        }
        if state.loadingChannels || state.loadingPosts {
            entries.append(FeedEntry(stableId: .status, index: entries.count, text: ngI18n("Nagram.ChannelFeed.Loading", language), presentationData: presentationData))
        } else {
            let hasFailures = channels.contains { state.failedChannels.contains($0.peer.id) }
            if entries.isEmpty && (searchQuery == nil || (!state.canLoadMore && !hasFailures)) {
                entries.append(FeedEntry(stableId: .status, index: entries.count, text: ngI18n("Nagram.ChannelFeed.Empty", language), presentationData: presentationData))
            }
            if state.canLoadMore {
                entries.append(FeedEntry(stableId: .more, index: entries.count, text: ngI18n("Nagram.ChannelFeed.More", language), presentationData: presentationData))
            }
            if hasFailures {
                entries.append(FeedEntry(stableId: .failure, index: entries.count, text: ngI18n("Nagram.ChannelFeed.Retry", language), presentationData: presentationData))
            }
        }
        let actions = FeedActions(context: context, presentation: ChatPresentationData(presentationData: presentationData), presentationData: presentationData, activate: { id in
            switch id {
            case .more: feed.loadMore()
            case .failure: feed.retryFailedChannels()
            case let .post(id):
                if let channel = channels.first(where: { $0.peer.id == id.peerId }) {
                    openPost?(id, channel.peer)
                }
            case .status: break
            }
        }, openMedia: { message in openMedia?(message) ?? false }, share: { messages in share?(messages) }, hideChannel: { id in
            feed.updatePreferences { $0.setChannelIncluded(false, channelId: id.toInt64()) }
        },
            host: { feedHost?() }, backgroundNode: { feedWallpaperNode?() })
        let menu = ItemListNavigationButton(content: .text(ngI18n("Nagram.ChannelFeed.Actions", language)), style: .regular,
                                            enabled: !state.loadingChannels, action: {
            let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: strings.Common_Search, style: .default) { _ in
                let editor = UIAlertController(title: strings.Common_Search, message: categoryTitle, preferredStyle: .alert)
                editor.addTextField { field in
                    field.placeholder = strings.Common_Search
                    field.returnKeyType = .search
                }
                editor.addAction(UIAlertAction(title: strings.Common_Cancel, style: .cancel))
                editor.addAction(UIAlertAction(title: strings.Common_Search, style: .default) { [weak editor] _ in
                    let query = editor?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !query.isEmpty { openSearch?(query) }
                })
                context.sharedContext.applicationBindings.presentNativeController(editor)
            })
            alert.addAction(UIAlertAction(title: ngI18n("Nagram.ChannelFeed.Sources", language), style: .default) { _ in openSources?() })
            alert.addAction(UIAlertAction(title: ngI18n("Nagram.ChannelFeed.Unread", language) + (state.preferences.unreadOnly ? " ✓" : ""), style: .default) { _ in
                feed.updatePreferences { $0.unreadOnly.toggle() }
            })
            alert.addAction(UIAlertAction(title: ngI18n("Nagram.ChannelFeed.Refresh", language), style: .default) { _ in feed.refresh() })
            alert.addAction(UIAlertAction(title: ngI18n("Nagram.ChannelFeed.Settings", language), style: .default) { _ in openSettings?() })
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
        let navigationTitle = searchQuery.map { ItemListControllerTitle.textWithSubtitle($0, categoryTitle) } ?? .textWithSubtitle(title, categoryTitle)
        return (ItemListControllerState(presentationData: data, title: navigationTitle, leftNavigationButton: nil, rightNavigationButton: searchQuery == nil ? menu : nil,
                                        backNavigationButton: ItemListBackButton(title: strings.Common_Back)),
                (ItemListNodeState(presentationData: data, entries: entries, style: .plain, animateChanges: false), actions))
    }
    let controller = ChannelFeedTimelineController(context: context, state: state)
    controller.navigationPresentation = .default
    feedHost = { [weak controller] in controller }
    feedWallpaperNode = { [weak controller] in controller?.feedWallpaper }
    openMedia = { [weak controller] message in
        guard let controller, let navigationController = controller.navigationController as? NavigationController else { return false }
        let rawMessage = message._asMessage()
        let copyProtected = rawMessage.peers[message.id.peerId]?.isCopyProtectionEnabled == true
        return context.sharedContext.openChatMessage(OpenChatMessageParams(context: context, chatLocation: .peer(id: message.id.peerId), chatFilterTag: nil, chatLocationContextHolder: nil, message: rawMessage, standalone: false, copyProtected: copyProtected, reverseMessageGalleryOrder: false, navigationController: navigationController, dismissInput: {
        }, present: { [weak controller] c, a, _ in
            controller?.present(c, in: .window(.root), with: a, blockInteraction: true)
        }, transitionNode: { [weak controller] id, media, adjustRect in
            controller?.transitionNode(messageId: id, media: media, adjustRect: adjustRect)
        }, addToTransitionSurface: { [weak controller] view in
            controller?.addToMediaTransitionSurface(view)
        }, openUrl: { url in
            context.sharedContext.applicationBindings.openUrl(url)
        }, openPeer: { _, _ in
        }, callPeer: { _, _ in
        }, openConferenceCall: { _ in
        }, enqueueMessage: { _ in
        }, sendSticker: nil, sendEmoji: nil, setupTemporaryHiddenMedia: { _, _, _ in
        }, chatAvatarHiddenMedia: { _, _ in
        }))
    }
    controller.didAppear = { firstTime in
        feed.active = true
        feed.reloadPreferences()
        if firstTime { feed.start() }
        scheduleAutoLoad()
    }
    controller.willDisappear = { _ in feed.suspend() }
    controller.visibleBottomContentOffsetChanged = { offset in
        if case let .known(value) = offset { nearBottom = value < 180 }
        else { nearBottom = false }
        scheduleAutoLoad()
    }
    controller.visibleEntriesUpdated = { [weak controller] entries in
        controller?.updateHiddenMedia()
        moreRowVisible = entries.contains(where: { ($0 as? FeedEntry)?.stableId == .more })
        scheduleAutoLoad()
    }
    openSources = { [weak controller] in
        controller?.push(channelFeedSourcesController(feed: feed))
    }
    openSettings = { [weak controller] in
        controller?.push(channelFeedSettingsController(feed: feed))
    }
    openSearch = { [weak controller] query in
        controller?.push(channelFeedTimelineController(context: context, searchQuery: query))
    }
    share = { [weak controller] messages in
        guard let controller else { return }
        let params = ShareControllerParams(subject: .messages(messages.map { $0._asMessage() }), showInChat: nil, externalShare: true, immediateExternalShare: false)
        controller.present(context.sharedContext.makeShareScreen(context: context, params: params), in: .window(.root))
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
        case search, noMatches
        case category(UUID?)
        case add, rename, delete, autoInclude, autoLoad
        case displayHeader
        case display(DisplayOption)
        case channel(EnginePeer.Id, hasAvatar: Bool)
    }

    enum DisplayOption: String, CaseIterable {
        case postAvatars = "Nagram.ChannelFeed.PostAvatars"
        case channelNames = "Nagram.ChannelFeed.ChannelNames"
        case shareButtons = "Nagram.ChannelFeed.ShareButtons"
        case sourceAvatars = "Nagram.ChannelFeed.SourceAvatars"

        var keyPath: WritableKeyPath<NextgramChannelFeedPreferences.DisplayOptions, Bool> {
            switch self {
            case .postAvatars: return \.showPostAvatars
            case .channelNames: return \.showChannelNames
            case .shareButtons: return \.showShareButtons
            case .sourceAvatars: return \.showSourceAvatars
            }
        }
    }

    let stableId: Id
    let index: Int
    let title: String
    var selected = false
    var avatarPeer: EnginePeer?
    var query = ""

    var section: ItemListSectionId {
        switch self.stableId {
        case .search: return 0
        case .category: return 1
        case .add, .rename, .delete: return 2
        case .autoInclude, .autoLoad: return 3
        case .displayHeader, .display: return 4
        case .channel, .noMatches: return 5
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.index < rhs.index
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! FeedSourceActions
        let activate = arguments.activate
        if let peer = self.avatarPeer {
            return ItemListPeerItem(
                presentationData: presentationData, systemStyle: .glass,
                dateTimeFormat: arguments.presentationData.dateTimeFormat, nameDisplayOrder: arguments.presentationData.nameDisplayOrder,
                context: arguments.context, peer: peer, height: .generic, nameStyle: .plain,
                presence: nil, text: .none, label: .none,
                editing: ItemListPeerItemEditing(editable: false, editing: false, revealed: nil),
                switchValue: ItemListPeerItemSwitch(value: self.selected, style: .standard),
                enabled: true, selectable: false, sectionId: self.section, action: nil,
                setPeerIdWithRevealedOptions: { _, _ in }, removePeer: { _ in },
                toggleUpdated: { activate(self.stableId, $0) }
            )
        }
        switch self.stableId {
        case .search:
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass,
                title: NSAttributedString(string: ""), text: self.query, placeholder: self.title,
                type: .regular(capitalization: false, autocorrection: false), returnKeyType: .search,
                clearType: .always, tag: nil, preserveTextWhileEditing: true, sectionId: self.section,
                textUpdated: arguments.updateSearch, action: {
                    _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                })
        case .noMatches:
            return ItemListTextItem(presentationData: presentationData, text: .plain(self.title), sectionId: self.section)
        case .displayHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: self.title, sectionId: self.section)
        case .autoInclude, .autoLoad, .channel, .display:
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: self.title,
                                      value: self.selected, maximumNumberOfLines: 2, sectionId: self.section, style: .blocks,
                                      updated: { activate(self.stableId, $0) })
        case .category, .add, .rename, .delete:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: self.title,
                                          label: self.selected ? "✓" : "", sectionId: self.section, style: .blocks,
                                          action: { activate(self.stableId, true) })
        }
    }
}

private struct FeedSourceActions {
    let context: AccountContext
    let presentationData: PresentationData
    var updateSearch: (String) -> Void = { _ in }
    let activate: (FeedSourceEntry.Id, Bool) -> Void
}

func nextgramChannelFeedSettingsController(context: AccountContext) -> ViewController {
    return channelFeedSettingsController(feed: ChannelFeed(context: context, searchQuery: nil))
}

private func channelFeedSettingsController(feed: ChannelFeed) -> ViewController {
    let context = feed.context
    let state = combineLatest(context.sharedContext.presentationData, feed.updates.get(), nagramBoolSignal("nagram.channelFeedAutoLoad", defaultValue: true))
    |> deliverOnMainQueue
    |> map { presentationData, feedState, autoLoad -> (ItemListControllerState, (ItemListNodeState, FeedSourceActions)) in
        let strings = presentationData.strings
        let language = strings.baseLanguageCode
        let data = ItemListPresentationData(presentationData)
        var entries = [FeedSourceEntry(stableId: .autoLoad, index: 0, title: ngI18n("Nagram.ChannelFeed.AutoLoad", language), selected: autoLoad)]
        entries.append(FeedSourceEntry(stableId: .displayHeader, index: entries.count, title: ngI18n("Nagram.ChannelFeed.DisplayOptions", language)))
        for option in FeedSourceEntry.DisplayOption.allCases {
            entries.append(FeedSourceEntry(stableId: .display(option), index: entries.count,
                title: ngI18n(option.rawValue, language), selected: feedState.preferences.displayOptions[keyPath: option.keyPath]))
        }
        let actions = FeedSourceActions(context: context, presentationData: presentationData, activate: { id, enabled in
            switch id {
            case .autoLoad: NagramSettings.shared.channelFeedAutoLoad = enabled
            case let .display(option): feed.updatePreferences { $0.displayOptions[keyPath: option.keyPath] = enabled }
            default: break
            }
        })
        return (ItemListControllerState(presentationData: data, title: .text(ngI18n("Nagram.ChannelFeed.Settings", language)),
            leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: strings.Common_Back)),
            (ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false), actions))
    }
    let controller = ItemListController(context: context, state: state)
    controller.navigationPresentation = .default
    controller.didAppear = { _ in feed.reloadPreferences() }
    return controller
}

private func channelFeedSourcesController(feed: ChannelFeed) -> ViewController {
    let context = feed.context
    let search = ValuePromise<String>("", ignoreRepeated: true)
    let state = combineLatest(context.sharedContext.presentationData, feed.updates.get(), search.get())
    |> deliverOnMainQueue
    |> map { presentationData, state, query -> (ItemListControllerState, (ItemListNodeState, FeedSourceActions)) in
        let strings = presentationData.strings
        let language = strings.baseLanguageCode
        let data = ItemListPresentationData(presentationData)
        let category = state.category
        let terms = query.split(whereSeparator: \.isWhitespace).map { String($0.drop(while: { $0 == "@" })) }.filter { !$0.isEmpty }
        var entries = [FeedSourceEntry(stableId: .search, index: 0, title: ngI18n("Nagram.ChannelFeed.SearchChannels", language), query: query)]
        if terms.isEmpty {
            entries.append(FeedSourceEntry(stableId: .category(nil), index: entries.count, title: ngI18n("Nagram.ChannelFeed.All", language), selected: category == nil))
            for value in state.preferences.categories {
                entries.append(FeedSourceEntry(stableId: .category(value.id), index: entries.count, title: value.name, selected: value.id == category?.id))
            }
            entries.append(FeedSourceEntry(stableId: .add, index: entries.count, title: ngI18n("Nagram.ChannelFeed.AddCategory", language)))
            if category != nil {
                entries.append(FeedSourceEntry(stableId: .rename, index: entries.count, title: ngI18n("Nagram.ChannelFeed.RenameCategory", language)))
                entries.append(FeedSourceEntry(stableId: .delete, index: entries.count, title: ngI18n("Nagram.ChannelFeed.DeleteCategory", language)))
            } else {
                entries.append(FeedSourceEntry(stableId: .autoInclude, index: entries.count,
                    title: ngI18n("Nagram.ChannelFeed.AutoInclude", language), selected: state.preferences.manuallyIncludedChannelIds == nil))
            }
        }
        let options = state.preferences.displayOptions
        let includedIds = Set(state.includedChannels.map { $0.peer.id })
        let channels = state.channels.filter { channel in
            let names = [channel.peer.compactDisplayTitle, channel.peer.addressName ?? ""] + channel.peer.usernames.map(\.username)
            return terms.allSatisfy { term in names.contains { $0.localizedStandardContains(term) } }
        }.sorted { $0.peer.compactDisplayTitle.localizedStandardCompare($1.peer.compactDisplayTitle) == .orderedAscending }
        if !terms.isEmpty && channels.isEmpty && !state.loadingChannels {
            entries.append(FeedSourceEntry(stableId: .noMatches, index: entries.count, title: ngI18n("Nagram.ChannelFeed.NoMatchingChannels", language)))
        }
        for channel in channels {
            entries.append(FeedSourceEntry(stableId: .channel(channel.peer.id, hasAvatar: options.showSourceAvatars), index: entries.count,
                                           title: channel.peer.compactDisplayTitle, selected: includedIds.contains(channel.peer.id),
                                           avatarPeer: options.showSourceAvatars ? channel.peer : nil))
        }

        let activate: (FeedSourceEntry.Id, Bool) -> Void = { id, enabled in
            switch id {
            case .search, .noMatches, .autoLoad, .displayHeader, .display:
                break
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
            case let .channel(id, _):
                feed.updatePreferences { $0.setChannelIncluded(enabled, channelId: id.toInt64()) }
            }
        }
        return (ItemListControllerState(presentationData: data, title: .text(ngI18n("Nagram.ChannelFeed.Sources", language)),
                                        leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: strings.Common_Back)),
                (ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false),
                 FeedSourceActions(context: context, presentationData: presentationData, updateSearch: search.set, activate: activate)))
    }
    let controller = ItemListController(context: context, state: state)
    controller.navigationPresentation = .default
    return controller
}
