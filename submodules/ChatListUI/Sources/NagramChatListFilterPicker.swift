// MARK: NEXTGRAM — Local chat filters use the same glass list controls as Telegram settings.
import AccountContext
import Display
import ItemListUI
import NagramChatListFilters
import NagramStrings
import SwiftSignalKit
import TelegramPresentationData

private final class NagramChatListFilterPickerArguments {
    let select: (Int32) -> Void

    init(select: @escaping (Int32) -> Void) {
        self.select = select
    }
}

private enum NagramChatListFilterPickerEntryKind {
    case header
    case checkbox
    case text
    case reset
}

enum NagramChatListSortMode {
    case newestFirst
    case unreadFirst
    case oldestFirst
}

private struct NagramChatListFilterPickerEntry: ItemListNodeEntry {
    let stableId: Int32
    let section: ItemListSectionId
    let title: String
    let kind: NagramChatListFilterPickerEntryKind
    let checked: Bool

    static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.stableId == rhs.stableId && lhs.section == rhs.section && lhs.title == rhs.title && lhs.kind == rhs.kind && lhs.checked == rhs.checked
    }

    static func <(lhs: Self, rhs: Self) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NagramChatListFilterPickerArguments
        switch self.kind {
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: self.title, sectionId: self.section)
        case .checkbox:
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: self.title, style: .left, checked: self.checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.select(self.stableId)
            })
        case .text:
            return ItemListTextItem(presentationData: presentationData, text: .plain(self.title), sectionId: self.section)
        case .reset:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: self.title, kind: .generic, alignment: .center, sectionId: self.section, style: .blocks, action: {
                arguments.select(self.stableId)
            })
        }
    }
}

func nagramChatListFilterPicker(
    context: AccountContext,
    readFilter: NagramChatListReadFilter,
    peerTypes: NagramChatListPeerTypes,
    sortMode: NagramChatListSortMode,
    apply: @escaping (NagramChatListReadFilter, NagramChatListPeerTypes, NagramChatListSortMode) -> Void
) -> ViewController {
    var selectedReadFilter = readFilter
    var selectedPeerTypes = peerTypes.intersection(.all)
    var selectedSortMode = sortMode
    if selectedPeerTypes.isEmpty {
        selectedPeerTypes = .all
    }

    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateVersion: Int32 = 0
    let refresh: () -> Void = {
        updateVersion += 1
        updatePromise.set(updateVersion)
    }
    var dismiss: (() -> Void)?
    var pendingSelection: (NagramChatListReadFilter, NagramChatListPeerTypes, NagramChatListSortMode)?

    let arguments = NagramChatListFilterPickerArguments(select: { id in
        switch id {
        case 10:
            selectedReadFilter = .all
        case 11:
            selectedReadFilter = .unread
        case 12:
            selectedReadFilter = .read
        case 20:
            selectedPeerTypes = .all
        case 21:
            selectedPeerTypes = .privateChats
        case 22:
            selectedPeerTypes = [.groups, .channels]
        case 30 ... 34:
            let option: NagramChatListPeerTypes
            switch id {
            case 30: option = .contacts
            case 31: option = .nonContacts
            case 32: option = .bots
            case 33: option = .groups
            default: option = .channels
            }
            if selectedPeerTypes == .all {
                // MARK: NEXTGRAM — From “all”, one tap narrows to the chosen type.
                selectedPeerTypes = option
            } else {
                let updated = selectedPeerTypes.symmetricDifference(option)
                if !updated.isEmpty {
                    selectedPeerTypes = updated
                }
            }
        case 40:
            selectedSortMode = .newestFirst
        case 41:
            selectedSortMode = .unreadFirst
        case 42:
            selectedSortMode = .oldestFirst
        case 50:
            selectedReadFilter = .all
            selectedPeerTypes = .all
            selectedSortMode = .newestFirst
        default:
            return
        }
        refresh()
    })

    let state = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, updatePromise.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let languageCode = presentationData.strings.baseLanguageCode
        let string: (String) -> String = { ngI18n($0, languageCode) }
        let entries: [NagramChatListFilterPickerEntry] = [
            .init(stableId: 0, section: 0, title: string("Nagram.ChatListFilter.Hint"), kind: .text, checked: false),
            .init(stableId: 1, section: 1, title: string("Nagram.ChatListFilter.ReadStatus"), kind: .header, checked: false),
            .init(stableId: 10, section: 1, title: string("Nagram.ChatListFilter.All"), kind: .checkbox, checked: selectedReadFilter == .all),
            .init(stableId: 11, section: 1, title: string("Nagram.ChatListQuickFilter.Unread"), kind: .checkbox, checked: selectedReadFilter == .unread),
            .init(stableId: 12, section: 1, title: string("Nagram.ChatListQuickFilter.Read"), kind: .checkbox, checked: selectedReadFilter == .read),
            .init(stableId: 19, section: 2, title: string("Nagram.ChatListFilter.Presets"), kind: .header, checked: false),
            .init(stableId: 20, section: 2, title: string("Nagram.ChatListFilter.AllTypes"), kind: .checkbox, checked: selectedPeerTypes == .all),
            .init(stableId: 21, section: 2, title: string("Nagram.ChatListQuickFilter.Private"), kind: .checkbox, checked: selectedPeerTypes == .privateChats),
            .init(stableId: 22, section: 2, title: string("Nagram.ChatListQuickFilter.GroupsAndChannels"), kind: .checkbox, checked: selectedPeerTypes == [.groups, .channels]),
            .init(stableId: 29, section: 3, title: string("Nagram.ChatListFilter.ChatTypes"), kind: .header, checked: false),
            .init(stableId: 30, section: 3, title: string("Nagram.ChatListQuickFilter.Contacts"), kind: .checkbox, checked: selectedPeerTypes.contains(.contacts)),
            .init(stableId: 31, section: 3, title: string("Nagram.ChatListQuickFilter.NonContacts"), kind: .checkbox, checked: selectedPeerTypes.contains(.nonContacts)),
            .init(stableId: 32, section: 3, title: string("Nagram.ChatListQuickFilter.Bots"), kind: .checkbox, checked: selectedPeerTypes.contains(.bots)),
            .init(stableId: 33, section: 3, title: string("Nagram.ChatListQuickFilter.Groups"), kind: .checkbox, checked: selectedPeerTypes.contains(.groups)),
            .init(stableId: 34, section: 3, title: string("Nagram.ChatListQuickFilter.Channels"), kind: .checkbox, checked: selectedPeerTypes.contains(.channels)),
            .init(stableId: 39, section: 4, title: string("Nagram.ChatListFilter.Sort"), kind: .header, checked: false),
            .init(stableId: 40, section: 4, title: string("Nagram.ChatListFilter.NewestFirst"), kind: .checkbox, checked: selectedSortMode == .newestFirst),
            .init(stableId: 41, section: 4, title: string("Nagram.ChatListUnreadFirst"), kind: .checkbox, checked: selectedSortMode == .unreadFirst),
            .init(stableId: 42, section: 4, title: string("Nagram.ChatListOldestFirst"), kind: .checkbox, checked: selectedSortMode == .oldestFirst),
            .init(stableId: 50, section: 5, title: string("Nagram.ChatListFilter.Reset"), kind: .reset, checked: false)
        ]
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData.withUpdated(theme: presentationData.theme.withModalBlocksBackground())),
            title: .text(string("Nagram.ChatListFilter.Title")),
            leftNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Cancel), style: .regular, enabled: true, action: { dismiss?() }),
            rightNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: true, action: {
                pendingSelection = (selectedReadFilter, selectedPeerTypes, selectedSortMode)
                dismiss?()
            }),
            backNavigationButton: nil
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData.withUpdated(theme: presentationData.theme.withModalBlocksBackground())),
            entries: entries,
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: state)
    controller.navigationPresentation = .modal
    controller.didDisappear = { _ in
        if let selection = pendingSelection {
            pendingSelection = nil
            apply(selection.0, selection.1, selection.2)
        }
    }
    dismiss = { [weak controller] in
        controller?.dismiss()
    }
    return controller
}
