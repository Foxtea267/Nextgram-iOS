import AccountContext
import Display
import ItemListUI
import NagramSettings
import NagramStrings
import SwiftSignalKit
import TelegramPresentationData

private final class NagramGroupProfileSettingsArguments {
    let update: (NagramGroupProfileSettingItem, Bool) -> Void

    init(update: @escaping (NagramGroupProfileSettingItem, Bool) -> Void) {
        self.update = update
    }
}

private enum NagramGroupProfileSettingsEntryStableId: Hashable {
    case item(NagramGroupProfileSettingItem)
    case footer
}

private enum NagramGroupProfileSettingsEntry: ItemListNodeEntry {
    case item(NagramGroupProfileSettingItem, String, Bool)
    case footer(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: NagramGroupProfileSettingsEntryStableId {
        switch self {
        case let .item(item, _, _):
            return .item(item)
        case .footer:
            return .footer
        }
    }

    static func ==(lhs: NagramGroupProfileSettingsEntry, rhs: NagramGroupProfileSettingsEntry) -> Bool {
        switch lhs {
        case let .item(lhsItem, lhsTitle, lhsValue):
            if case let .item(rhsItem, rhsTitle, rhsValue) = rhs {
                return lhsItem == rhsItem && lhsTitle == rhsTitle && lhsValue == rhsValue
            }
            return false
        case let .footer(lhsText):
            if case let .footer(rhsText) = rhs {
                return lhsText == rhsText
            }
            return false
        }
    }

    static func <(lhs: NagramGroupProfileSettingsEntry, rhs: NagramGroupProfileSettingsEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    private var sortIndex: Int {
        switch self {
        case let .item(item, _, _):
            return NagramGroupProfileSettingItem.allCases.firstIndex(of: item) ?? 0
        case .footer:
            return NagramGroupProfileSettingItem.allCases.count
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NagramGroupProfileSettingsArguments
        switch self {
        case let .item(item, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update(item, value)
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func nagramGroupProfileSettingsController(context: AccountContext) -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }

    let arguments = NagramGroupProfileSettingsArguments(update: { item, visible in
        NagramSettings.shared.setGroupProfileSettingItemVisible(item, visible: visible)
        bump()
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        updatePromise.get()
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        var entries = NagramGroupProfileSettingItem.allCases.map { item in
            NagramGroupProfileSettingsEntry.item(
                item,
                ngI18n("Nagram.GroupProfileSettings.Item.\(item.rawValue)", lang),
                NagramSettings.shared.isGroupProfileSettingItemVisible(item)
            )
        }
        entries.append(.footer(ngI18n("Nagram.GroupProfileSettings.Footer", lang)))

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(ngI18n("Nagram.GroupProfileSettings", lang)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            animateChanges: false
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    return controller
}
