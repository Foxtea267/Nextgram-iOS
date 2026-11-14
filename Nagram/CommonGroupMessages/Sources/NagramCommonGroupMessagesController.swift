import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import AccountContext
import ItemListUI
import ItemListPeerItem
import NagramStrings
import NagramSettings

// MARK: NAGRAM — 用户在共同群里的近期发言。
// 服务端没有跨群按发送者搜索的接口：先分页取完共同群，再逐群用 messages.search(from_id:) 取最近几条，合并后按时间倒序列出。

private let messagesPerGroup: Int32 = 20

private struct CommonGroupPage: Equatable {
    var cursor: SearchMessagesState?
    var messages: [CommonGroupMessage] = []
    var complete = false
}

private struct CommonGroupMessage: Equatable {
    let group: EnginePeer
    let message: EngineMessage

    static func ==(lhs: CommonGroupMessage, rhs: CommonGroupMessage) -> Bool {
        return lhs.group == rhs.group && lhs.message.id == rhs.message.id && lhs.message.stableVersion == rhs.message.stableVersion
    }
}

private struct CommonGroupMessagesState: Equatable {
    var totalGroups: Int?
    var searchedGroups: Int = 0
    var messages: [CommonGroupMessage] = []
    var isFinished: Bool = false
    var loading = false
    var paused = false
    var query = ""
    var selectedGroup: EnginePeer.Id?
    var groups: [EnginePeer] = []
    var failed: Set<EnginePeer.Id> = []
    var hasMore = false
}

private final class CommonGroupMessagesArguments {
    let context: AccountContext
    let openMessage: (EngineMessage) -> Void
    let action: (Int) -> Void

    init(context: AccountContext, openMessage: @escaping (EngineMessage) -> Void, action: @escaping (Int) -> Void) {
        self.context = context
        self.openMessage = openMessage
        self.action = action
    }
}

private enum CommonGroupMessagesEntry: ItemListNodeEntry {
    case progress(String)
    case message(Int, CommonGroupMessage, String, String)
    case action(Int, String, String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: AnyHashable {
        switch self {
        case .progress:
            return AnyHashable("progress")
        case let .action(id, _, _):
            return AnyHashable("action\(id)")
        case let .message(_, item, _, _):
            return AnyHashable(item.message.id)
        }
    }

    private var sortIndex: Int {
        switch self {
        case .progress:
            return -1
        case let .action(id, _, _):
            return id < 2 ? id - 4 : Int.max - 10 + id
        case let .message(index, _, _, _):
            return index
        }
    }

    static func ==(lhs: CommonGroupMessagesEntry, rhs: CommonGroupMessagesEntry) -> Bool {
        switch lhs {
        case let .progress(text):
            if case .progress(text) = rhs {
                return true
            }
            return false
        case let .message(index, item, text, date):
            if case .message(index, item, text, date) = rhs {
                return true
            }
            return false
        case let .action(id, title, detail):
            if case .action(id, title, detail) = rhs { return true }
            return false
        }
    }

    static func <(lhs: CommonGroupMessagesEntry, rhs: CommonGroupMessagesEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! CommonGroupMessagesArguments
        switch self {
        case let .progress(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .action(id, title, detail):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: detail, sectionId: self.section, style: .blocks, action: { arguments.action(id) })
        case let .message(_, item, text, date):
            let message = item.message
            return ItemListPeerItem(presentationData: presentationData, systemStyle: .glass, dateTimeFormat: PresentationDateTimeFormat(), nameDisplayOrder: .firstLast, context: arguments.context, peer: item.group, presence: nil, text: .text(text, .secondary), label: .text(date, .standard, nil, false), editing: ItemListPeerItemEditing(editable: false, editing: false, revealed: false), switchValue: nil, enabled: true, selectable: true, sectionId: self.section, action: {
                arguments.openMessage(message)
            }, setPeerIdWithRevealedOptions: { _, _ in }, removePeer: { _ in })
        }
    }
}

/// 逐批搜索共同群里该用户的消息；每批完成后更新一次状态。
private final class CommonGroupMessagesLoader {
    private let context: AccountContext
    private let userPeerId: EnginePeer.Id
    private let groupsContext: GroupsInCommonContext
    private var groupsDisposable: Disposable?
    private let searchDisposable = MetaDisposable()
    private var groups: [EnginePeer] = []
    private var didStartSearch = false
    private var resumeGroupLoading: (() -> Void)?
    private var pages: [EnginePeer.Id: CommonGroupPage] = [:]
    private var generation = UUID()
    private var observers: [NSObjectProtocol] = []

    private var stateValue = CommonGroupMessagesState() {
        didSet {
            self.statePromise.set(self.stateValue)
        }
    }
    private let statePromise = ValuePromise<CommonGroupMessagesState>(CommonGroupMessagesState())
    var state: Signal<CommonGroupMessagesState, NoError> {
        return self.statePromise.get()
    }

    init(context: AccountContext, userPeerId: EnginePeer.Id) {
        self.context = context
        self.userPeerId = userPeerId
        self.groupsContext = GroupsInCommonContext(account: context.account, peerId: userPeerId)

        self.groupsDisposable = (self.groupsContext.state
        |> deliverOnMainQueue).startStrict(next: { [weak self] state in
            guard let self, !self.didStartSearch else {
                return
            }
            guard case let .ready(canLoadMore) = state.dataState else {
                return
            }
            if self.stateValue.paused {
                self.resumeGroupLoading = { [weak self] in
                    guard let self else { return }
                    if canLoadMore {
                        self.groupsContext.loadMore()
                    } else {
                        self.finishGroupLoading(state.peers.compactMap { $0.peer.flatMap(EnginePeer.init) })
                    }
                }
                return
            }
            if canLoadMore {
                self.groupsContext.loadMore()
                return
            }
            self.finishGroupLoading(state.peers.compactMap { renderedPeer in
                return renderedPeer.peer.flatMap(EnginePeer.init)
            })
        })
        self.observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.pause() })
        self.observers.append(NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            if ProcessInfo.processInfo.thermalState == .critical { self?.pause() }
        })
    }

    deinit {
        self.groupsDisposable?.dispose()
        self.searchDisposable.dispose()
        self.observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func pause() {
        self.generation = UUID()
        self.searchDisposable.set(nil)
        self.stateValue.loading = false
        self.stateValue.paused = true
    }

    private func finishGroupLoading(_ groups: [EnginePeer]) {
        self.didStartSearch = true
        self.groups = groups
        self.stateValue.totalGroups = groups.count
        self.stateValue.groups = groups
        self.loadMore(initial: true)
    }

    func resume() {
        guard ProcessInfo.processInfo.thermalState != .critical else { return }
        self.stateValue.paused = false
        if self.didStartSearch {
            self.loadMore(initial: !self.stateValue.isFinished)
        } else if let resume = self.resumeGroupLoading {
            self.resumeGroupLoading = nil
            resume()
        }
    }

    func retry() {
        self.stateValue.failed.removeAll()
        self.loadMore(initial: !self.stateValue.isFinished)
    }

    func search(query: String, group: EnginePeer.Id?) {
        self.pause()
        self.pages.removeAll()
        self.stateValue.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.stateValue.selectedGroup = group
        self.stateValue.messages.removeAll()
        self.stateValue.failed.removeAll()
        self.stateValue.isFinished = false
        self.resume()
    }

    func loadMore(initial: Bool = false) {
        guard self.didStartSearch, !self.stateValue.paused, !self.stateValue.loading else { return }
        guard ProcessInfo.processInfo.thermalState != .critical else { self.pause(); return }
        let selected = self.stateValue.selectedGroup
        let candidates = self.groups.filter {
            (selected == nil || selected == $0.id) && !self.stateValue.failed.contains($0.id)
                && self.pages[$0.id]?.complete != true && (!initial || self.pages[$0.id] == nil)
        }.sorted {
            let lhs = self.pages[$0.id]?.messages.last?.message.timestamp ?? Int32.max
            let rhs = self.pages[$1.id]?.messages.last?.message.timestamp ?? Int32.max
            return lhs == rhs ? $0.id.toInt64() < $1.id.toInt64() : lhs > rhs
        }
        let count = ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState == .serious ? 1 : 3
        let batch = Array(candidates.prefix(count))
        guard !batch.isEmpty else {
            self.stateValue.isFinished = true
            self.updateResults()
            return
        }
        self.stateValue.loading = true
        let token = self.generation
        let userPeerId = self.userPeerId
        let signals: [Signal<(SearchMessagesResult, SearchMessagesState)?, NoError>] = batch.map { group in
            return self.context.engine.messages.searchMessages(location: .peer(peerId: group.id, fromId: userPeerId, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil), query: self.stateValue.query, state: self.pages[group.id]?.cursor, limit: messagesPerGroup)
            |> take(1)
            |> map(Optional.init)
            |> timeout(15.0, queue: .mainQueue(), alternate: .single(nil))
        }
        self.searchDisposable.set((combineLatest(signals)
        |> deliverOnMainQueue).startStrict(next: { [weak self] results in
            guard let self, self.generation == token else {
                return
            }
            for (group, result) in zip(batch, results) {
                guard let (result, cursor) = result, !result.nextgramRequestFailed, result.completed || cursor != self.pages[group.id]?.cursor else {
                    self.stateValue.failed.insert(group.id)
                    continue
                }
                self.pages[group.id] = CommonGroupPage(cursor: cursor, messages: result.messages.map { CommonGroupMessage(group: group, message: EngineMessage($0)) }, complete: result.completed)
            }
            self.stateValue.loading = false
            self.updateResults()
            if initial { Queue.mainQueue().async { [weak self] in
                guard let self, self.generation == token else { return }
                self.loadMore(initial: true)
            } }
        }))
    }

    private func updateResults() {
        var updated = self.stateValue
        updated.searchedGroups = self.pages.count + updated.failed.count
        updated.hasMore = self.groups.contains { (updated.selectedGroup == nil || updated.selectedGroup == $0.id) && self.pages[$0.id]?.complete != true && !updated.failed.contains($0.id) }
        updated.messages = self.pages.values.flatMap(\.messages).filter { item in
            let message = item.message
            if let author = message.author, NextgramGroupMemberFilter.hiddenMembers(accountId: self.context.account.peerId.toInt64(), chatId: item.group.id.toInt64()).contains(author.id.toInt64()) { return false }
            return !(NagramSettings.shared.regexFilterMatcher(peerId: item.group.id.toInt64(), isOutgoing: !message.flags.contains(.Incoming))?.isHidden(text: message.text, authorPeerId: message.author?.id.id._internalGetInt64Value()) ?? false)
        }.sorted(by: { lhs, rhs in
                if lhs.message.timestamp != rhs.message.timestamp {
                    return lhs.message.timestamp > rhs.message.timestamp
                }
                return lhs.message.index > rhs.message.index
            })
        self.stateValue = updated
    }
}

public func nagramCommonGroupMessagesController(context: AccountContext, userPeerId: EnginePeer.Id) -> ViewController {
    let loader = CommonGroupMessagesLoader(context: context, userPeerId: userPeerId)
    var openMessageImpl: ((EngineMessage) -> Void)?
    var actionImpl: ((Int) -> Void)?
    var latestState = CommonGroupMessagesState()
    let arguments = CommonGroupMessagesArguments(context: context, openMessage: { message in
        openMessageImpl?(message)
    }, action: { actionImpl?($0) })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        loader.state
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        latestState = state
        var entries: [CommonGroupMessagesEntry] = []
        let groupTitle = state.groups.first(where: { $0.id == state.selectedGroup })?.debugDisplayTitle ?? ngI18n("Nagram.CommonGroupMessages.AllGroups", lang)
        entries.append(.action(0, ngI18n("Nagram.CommonGroupMessages.Query", lang), state.query))
        entries.append(.action(1, ngI18n("Nagram.CommonGroupMessages.Groups", lang), groupTitle))
        if let totalGroups = state.totalGroups, totalGroups > 0 {
            let progressKey = state.isFinished ? "Nagram.CommonGroupMessages.Searched" : "Nagram.CommonGroupMessages.Searching"
            let progress = ngI18n(progressKey, lang)
                .replacingOccurrences(of: "{searched}", with: "\(state.searchedGroups)")
                .replacingOccurrences(of: "{total}", with: "\(totalGroups)")
            entries.append(.progress(progress))
        }
        let now = Int32(Date().timeIntervalSince1970)
        for (index, item) in state.messages.enumerated() {
            var text = descriptionStringForMessage(contentSettings: context.currentContentSettings.with { $0 }, message: item.message, strings: presentationData.strings, nameDisplayOrder: presentationData.nameDisplayOrder, dateTimeFormat: presentationData.dateTimeFormat, accountPeerId: context.account.peerId).0.string
            if let result = NagramSettings.shared.regexFilterMatcher(peerId: item.group.id.toInt64(), isOutgoing: !item.message.flags.contains(.Incoming))?.apply(to: item.message.text, authorPeerId: item.message.author?.id.id._internalGetInt64Value()) {
                switch result {
                case let .visible(value, ranges): if !ranges.isEmpty { text = "•••" } else if !value.isEmpty { text = value }
                case .contentHidden, .hidden: text = "•••"
                }
            }
            // Keep spoilers concealed after applying rules, including rules that leave the caption unchanged.
            if item.message.attributes.contains(where: { $0 is MediaSpoilerMessageAttribute }) { text = "•••" }
            let date = stringForRelativeTimestamp(strings: presentationData.strings, relativeTimestamp: item.message.timestamp, relativeTo: now, dateTimeFormat: presentationData.dateTimeFormat)
            entries.append(.message(index, item, text.replacingOccurrences(of: "\n", with: " "), date))
        }
        entries.append(.action(2, ngI18n("Nagram.CommonGroupMessages." + (state.paused ? "Resume" : "Pause"), lang), ""))
        if !state.loading && !state.paused && state.hasMore { entries.append(.action(3, ngI18n("Nagram.CommonGroupMessages.More", lang), "")) }
        if !state.failed.isEmpty { entries.append(.action(4, ngI18n("Nagram.CommonGroupMessages.Retry", lang), String(state.failed.count))) }

        let emptyStateItem: ItemListControllerEmptyStateItem?
        // Keep query, resume and retry controls accessible even with no results.
        emptyStateItem = nil
        if state.messages.isEmpty && state.isFinished {
            entries.removeAll { if case .progress = $0 { return true }; return false }
            entries.append(.progress(ngI18n("Nagram.CommonGroupMessages.Empty", lang)))
        }
        entries.sort()

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(ngI18n("Nagram.CommonGroupMessages", lang)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            emptyStateItem: emptyStateItem,
            animateChanges: false
        )
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        loader.pause()
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    controller.willDisappear = { _ in loader.pause() }
    controller.beganInteractiveDragging = { [weak controller] in controller?.view.endEditing(true) }
    actionImpl = { [weak controller] id in
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let lang = data.strings.baseLanguageCode
        switch id {
        case 0:
            let alert = UIAlertController(title: ngI18n("Nagram.CommonGroupMessages.Query", lang), message: nil, preferredStyle: .alert)
            alert.addTextField { $0.text = latestState.query; $0.returnKeyType = .search; $0.clearButtonMode = .whileEditing }
            alert.addAction(UIAlertAction(title: data.strings.Common_Cancel, style: .cancel))
            alert.addAction(UIAlertAction(title: data.strings.Common_OK, style: .default) { _ in
                alert.view.endEditing(true)
                loader.search(query: String((alert.textFields?.first?.text ?? "").prefix(256)), group: latestState.selectedGroup)
            })
            context.sharedContext.applicationBindings.presentNativeController(alert)
        case 1:
            let picker = NextgramCommonGroupPicker(groups: latestState.groups, selectedId: latestState.selectedGroup,
                title: ngI18n("Nagram.CommonGroupMessages.Groups", lang),
                allTitle: ngI18n("Nagram.CommonGroupMessages.AllGroups", lang), cancelTitle: data.strings.Common_Cancel,
                choose: { group in loader.search(query: latestState.query, group: group) })
            context.sharedContext.applicationBindings.presentNativeController(UINavigationController(rootViewController: picker))
        case 2: if latestState.paused { loader.resume() } else { loader.pause() }
        case 3: loader.loadMore()
        case 4: loader.retry()
        default: break
        }
    }
    openMessageImpl = { [weak controller] message in
        guard let controller, let navigationController = controller.navigationController as? NavigationController else {
            return
        }
        guard let peer = message.peers[message.id.peerId].flatMap(EnginePeer.init) else {
            return
        }
        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: .message(id: .id(message.id), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false), keepStack: .always, useExisting: false))
    }
    return controller
}
