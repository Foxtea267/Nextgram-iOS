import AccountContext
import AsyncDisplayKit
import ComponentFlow
import Display
import Foundation
import ItemListUI
import NagramSettings
import NagramStrings
import PresentationDataUtils
import SwiftSignalKit
import TabBarComponent
import TelegramCore
import TelegramUIPreferences
import TelegramPresentationData
import UIKit

private final class NagramBottomBarArguments {
    let update: ((inout NagramBottomBarSettings) -> Void) -> Void
    let option: (NagramBottomBarOption) -> Void
    let reset: () -> Void

    init(update: @escaping ((inout NagramBottomBarSettings) -> Void) -> Void, option: @escaping (NagramBottomBarOption) -> Void, reset: @escaping () -> Void) {
        self.update = update
        self.option = option
        self.reset = reset
    }
}

private enum NagramBottomBarSwitchOption: Int32 {
    case topSearch
    case labels
    case settingsAvatar
}

private enum NagramBottomBarOption: Equatable {
    case alignment
    case searchMode
    case add
    case remove(NagramBottomBarItemId)
}

private enum NagramBottomBarEntry: ItemListNodeEntry {
    case preview(section: Int32, settings: NagramBottomBarSettings, strings: PresentationStrings, itemTitles: [NagramBottomBarItemId: String], topSearchTitle: String, topSearchVisibleHint: String, topSearchHiddenHint: String, bottomBarTitle: String, emptyBottomTitle: String)
    case header(stableId: Int32, section: Int32, text: String)
    case toggle(stableId: Int32, section: Int32, title: String, value: Bool, option: NagramBottomBarSwitchOption)
    case page(index: Int32, id: NagramBottomBarItemId, title: String, canRemove: Bool, canDrag: Bool)
    case add(title: String, enabled: Bool)
    case slider(stableId: Int32, section: Int32, title: String, value: Int32)
    case disclosure(stableId: Int32, section: Int32, title: String, label: String, option: NagramBottomBarOption)
    case reset(stableId: Int32, section: Int32, title: String)
    case footer(stableId: Int32, section: Int32, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .preview(section, _, _, _, _, _, _, _, _):
            return section
        case let .header(_, section, _):
            return section
        case let .toggle(_, section, _, _, _):
            return section
        case .page, .add:
            return 2
        case let .slider(_, section, _, _):
            return section
        case let .disclosure(_, section, _, _, _):
            return section
        case let .reset(_, section, _):
            return section
        case let .footer(_, section, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case .preview:
            return 0
        case let .header(stableId, _, _):
            return stableId
        case let .toggle(stableId, _, _, _, _):
            return stableId
        case let .page(_, id, _, _, _):
            return 100 + Int32(NagramBottomBarItemId.allCases.firstIndex(of: id) ?? 0)
        case .add:
            return 38
        case let .slider(stableId, _, _, _):
            return stableId
        case let .disclosure(stableId, _, _, _, _):
            return stableId
        case let .reset(stableId, _, _):
            return stableId
        case let .footer(stableId, _, _):
            return stableId
        }
    }

    static func ==(lhs: NagramBottomBarEntry, rhs: NagramBottomBarEntry) -> Bool {
        switch lhs {
        case let .preview(lSection, lSettings, lStrings, lItemTitles, lTopSearchTitle, lTopSearchVisibleHint, lTopSearchHiddenHint, lBottomBarTitle, lEmptyBottomTitle):
            if case let .preview(rSection, rSettings, rStrings, rItemTitles, rTopSearchTitle, rTopSearchVisibleHint, rTopSearchHiddenHint, rBottomBarTitle, rEmptyBottomTitle) = rhs {
                return lSection == rSection && lSettings == rSettings && lStrings.baseLanguageCode == rStrings.baseLanguageCode && lItemTitles == rItemTitles && lTopSearchTitle == rTopSearchTitle && lTopSearchVisibleHint == rTopSearchVisibleHint && lTopSearchHiddenHint == rTopSearchHiddenHint && lBottomBarTitle == rBottomBarTitle && lEmptyBottomTitle == rEmptyBottomTitle
            }
            return false
        case let .header(lId, lSection, lText):
            if case let .header(rId, rSection, rText) = rhs {
                return lId == rId && lSection == rSection && lText == rText
            }
            return false
        case let .toggle(lId, lSection, lTitle, lValue, lOption):
            if case let .toggle(rId, rSection, rTitle, rValue, rOption) = rhs {
                return lId == rId && lSection == rSection && lTitle == rTitle && lValue == rValue && lOption == rOption
            }
            return false
        case let .page(lIndex, lId, lTitle, lCanRemove, lCanDrag):
            if case let .page(rIndex, rId, rTitle, rCanRemove, rCanDrag) = rhs {
                return lIndex == rIndex && lId == rId && lTitle == rTitle && lCanRemove == rCanRemove && lCanDrag == rCanDrag
            }
            return false
        case let .add(lTitle, lEnabled):
            if case let .add(rTitle, rEnabled) = rhs { return lTitle == rTitle && lEnabled == rEnabled }
            return false
        case let .slider(lId, lSection, lTitle, lValue):
            if case let .slider(rId, rSection, rTitle, rValue) = rhs {
                return lId == rId && lSection == rSection && lTitle == rTitle && lValue == rValue
            }
            return false
        case let .disclosure(lId, lSection, lTitle, lLabel, lOption):
            if case let .disclosure(rId, rSection, rTitle, rLabel, rOption) = rhs {
                return lId == rId && lSection == rSection && lTitle == rTitle && lLabel == rLabel && lOption == rOption
            }
            return false
        case let .reset(lId, lSection, lTitle):
            if case let .reset(rId, rSection, rTitle) = rhs {
                return lId == rId && lSection == rSection && lTitle == rTitle
            }
            return false
        case let .footer(lId, lSection, lText):
            if case let .footer(rId, rSection, rText) = rhs {
                return lId == rId && lSection == rSection && lText == rText
            }
            return false
        }
    }

    static func <(lhs: NagramBottomBarEntry, rhs: NagramBottomBarEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    private var sortIndex: Int32 {
        if case let .page(index, _, _, _, _) = self { return 31 + index }
        return self.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NagramBottomBarArguments
        switch self {
        case let .preview(_, settings, strings, itemTitles, topSearchTitle, topSearchVisibleHint, topSearchHiddenHint, bottomBarTitle, emptyBottomTitle):
            return NagramBottomBarPreviewItem(
                theme: presentationData.theme,
                settings: settings,
                strings: strings,
                itemTitles: itemTitles,
                topSearchTitle: topSearchTitle,
                topSearchVisibleHint: topSearchVisibleHint,
                topSearchHiddenHint: topSearchHiddenHint,
                bottomBarTitle: bottomBarTitle,
                emptyBottomTitle: emptyBottomTitle,
                sectionId: self.section
            )
        case let .header(_, section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .toggle(_, section, title, value, option):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: section, style: .blocks, updated: { value in
                arguments.update { settings in
                    switch option {
                    case .topSearch:
                        settings.topSearchVisible = value
                    case .labels:
                        settings.showLabels = value
                    case .settingsAvatar:
                        settings.settingsUseAvatar = value
                    }
                }
            })
        case let .page(_, id, title, canRemove, canDrag):
            let handle = canDrag ? PresentationResourcesItemList.itemListReorderIndicatorIcon(presentationData.theme) : nil
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass,
                icon: nextgramBottomBarPageIcon(id, color: presentationData.theme.list.itemPrimaryTextColor),
                title: title, label: "", labelStyle: handle.map { .image(image: $0, size: CGSize(width: 18.0, height: 16.0)) } ?? .text,
                sectionId: self.section, style: .blocks, disclosureStyle: .none,
                action: canRemove ? { arguments.option(.remove(id)) } : nil, nextgramReorderable: canDrag)
        case let .add(title, enabled):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass,
                icon: nextgramBottomBarRasterIcon("plus.circle.fill", color: enabled ? presentationData.theme.list.itemAccentColor : presentationData.theme.list.itemSecondaryTextColor),
                title: title, enabled: enabled, titleColor: .accent, label: "", sectionId: self.section, style: .blocks,
                action: enabled ? { arguments.option(.add) } : nil)
        case let .slider(_, section, title, value):
            return NagramSliderItem(theme: presentationData.theme, minValue: 0, maxValue: 100, value: value, title: title, sectionId: section, updated: { value in
                arguments.update { settings in
                    settings.buttonWidthFillRatio = value
                    settings.widthMode = value >= 100 ? .full : .adaptive
                    settings.slotMode = value <= 0 ? .preserveHidden : .visibleOnly
                }
            })
        case let .disclosure(_, section, title, label, option):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, action: {
                arguments.option(option)
            })
        case let .reset(_, section, title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: section, style: .blocks, action: {
                arguments.reset()
            })
        case let .footer(_, section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

private func nextgramBottomBarPageTitle(_ id: NagramBottomBarItemId, language: String) -> String {
    return ngI18n("Nagram.BottomBarLayout.Item.\(id.rawValue)", language)
}

private func nextgramBottomBarPageIcon(_ id: NagramBottomBarItemId, color: UIColor) -> UIImage? {
    let symbol: String
    switch id {
    case .contacts: symbol = "person.2"
    case .calls: symbol = "phone"
    case .chats: symbol = "bubble.left.and.bubble.right"
    case .feed: symbol = "newspaper"
    case .savedMessages: symbol = "bookmark"
    case .settings: symbol = "gearshape"
    case .profile: symbol = "person.crop.circle"
    case .search: symbol = "magnifyingglass"
    }
    return nextgramBottomBarRasterIcon(symbol, color: color)
}

private func nextgramBottomBarRasterIcon(_ name: String, color: UIColor) -> UIImage? {
    guard let symbol = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.0, weight: .medium)) else {
        return nil
    }
    return UIGraphicsImageRenderer(size: symbol.size).image { _ in
        symbol.withTintColor(color, renderingMode: .alwaysOriginal).draw(at: .zero)
    }.withRenderingMode(.alwaysOriginal)
}

private func nextgramBottomBarPages(_ settings: NagramBottomBarSettings) -> [NagramBottomBarItemId] {
    var items = settings.bottomItems.filter { settings.isVisible($0) }
    if let external = settings.externalItem, external != .search, settings.isVisible(external) {
        items.append(external)
    }
    return items
}

private final class NextgramBottomBarSettingsController: ItemListController {
    override func loadDisplayNode() {
        super.loadDisplayNode()
        (self.displayNode as? ItemListControllerNode)?.listNode.reorderingRequiresLongPress = true
    }
}

private func nagramBottomBarSettingsCanUseSearchBar(_ settings: NagramBottomBarSettings) -> Bool {
    return settings.isVisible(.search) && settings.visibleBottomItems.isEmpty
}

private func nagramBottomBarSettingsNormalizedForLayout(_ settings: NagramBottomBarSettings) -> NagramBottomBarSettings {
    var result = settings
    if result.searchMode == .bar && !nagramBottomBarSettingsCanUseSearchBar(result) {
        result.setSearchMode(.button)
    }
    return result
}

private func nagramBottomBarSettings(_ settings: NagramBottomBarSettings, applyingShowCallsTab showCallsTab: Bool) -> NagramBottomBarSettings {
    var result = settings
    result.setVisible(.calls, visible: showCallsTab)
    return nagramBottomBarSettingsNormalizedForLayout(result)
}

public func nagramBottomBarSettingsController(context: AccountContext) -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }

    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var currentShowCallsTab = CallListSettings.defaultSettings.showTab
    var pendingShowCallsTab: Bool?

    let saveSettings: (NagramBottomBarSettings) -> Void = { settings in
        let normalizedSettings = nagramBottomBarSettingsNormalizedForLayout(settings)
        let nextShowCallsTab = normalizedSettings.isVisible(.calls)
        NagramSettings.shared.bottomBarSettings = normalizedSettings
        if nextShowCallsTab != currentShowCallsTab {
            currentShowCallsTab = nextShowCallsTab
            pendingShowCallsTab = nextShowCallsTab
            let _ = updateCallListSettingsInteractively(accountManager: context.sharedContext.accountManager, {
                $0.withUpdatedShowTab(nextShowCallsTab)
            }).startStandalone()
        }
    }

    let arguments = NagramBottomBarArguments(update: { update in
        var settings = nagramBottomBarSettings(NagramSettings.shared.bottomBarSettings, applyingShowCallsTab: currentShowCallsTab)
        update(&settings)
        saveSettings(settings)
        bump()
    }, option: { option in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        let actionSheet = ActionSheetController(presentationData: presentationData)
        let dismissAction: () -> Void = { [weak actionSheet] in
            actionSheet?.dismissAnimated()
        }

        let titleKey: String
        let items: [(String, (inout NagramBottomBarSettings) -> Void)]
        switch option {
        case .alignment:
            titleKey = "Nagram.BottomBarLayout.Alignment"
            items = [
                ("Nagram.BottomBarLayout.Alignment.spaceBetween", { $0.alignment = .spaceBetween }),
                ("Nagram.BottomBarLayout.Alignment.leftCenter", { $0.alignment = .leftCenter }),
                ("Nagram.BottomBarLayout.Alignment.center", { $0.alignment = .center }),
            ]
        case .searchMode:
            titleKey = "Nagram.BottomBarLayout.SearchStyle"
            let settings = nagramBottomBarSettings(NagramSettings.shared.bottomBarSettings, applyingShowCallsTab: currentShowCallsTab)
            items = [
                ("Nagram.BottomBarLayout.SearchStyle.button", { $0.setSearchMode(.button) })
            ] + (nagramBottomBarSettingsCanUseSearchBar(settings) ? [
                ("Nagram.BottomBarLayout.SearchStyle.bar", { $0.setSearchMode(.bar) })
            ] : [])
        case .add:
            titleKey = "Nagram.BottomBarLayout.AddPage"
            let settings = nagramBottomBarSettings(NagramSettings.shared.bottomBarSettings, applyingShowCallsTab: currentShowCallsTab)
            items = NagramBottomBarItemId.allCases.filter { !settings.isVisible($0) }.map { id in
                ("Nagram.BottomBarLayout.Item.\(id.rawValue)", { $0.show(id) })
            }
        case let .remove(id):
            titleKey = "Nagram.BottomBarLayout.Item.\(id.rawValue)"
            items = [("Nagram.BottomBarLayout.RemovePage", { $0.hide(id) })]
        }

        var actionItems: [ActionSheetItem] = [ActionSheetTextItem(title: ngI18n(titleKey, lang))]
        for (key, apply) in items {
            let isRemove = key == "Nagram.BottomBarLayout.RemovePage"
            actionItems.append(ActionSheetButtonItem(title: ngI18n(key, lang), color: isRemove ? .destructive : .accent, action: {
                dismissAction()
                var settings = nagramBottomBarSettings(NagramSettings.shared.bottomBarSettings, applyingShowCallsTab: currentShowCallsTab)
                apply(&settings)
                saveSettings(settings)
                bump()
            }))
        }
        if option == .searchMode && items.count == 1 {
            actionItems.append(ActionSheetTextItem(title: ngI18n("Nagram.BottomBarLayout.SearchStyle.BarDisabled", lang)))
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: actionItems),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { dismissAction() })])
        ])
        presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }, reset: {
        saveSettings(NagramBottomBarSettings())
        bump()
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        updatePromise.get(),
        context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.callListSettings])
        |> map { sharedData -> Bool in
            return sharedData.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self)?.showTab ?? CallListSettings.defaultSettings.showTab
        },
        context.sharedContext.activeAccountContexts
        |> map { accounts in
            return accounts.accounts.contains { $0.0 != context.account.id }
        }
        |> distinctUntilChanged
    )
    |> map { presentationData, _, showCallsTab, hasOtherAccounts -> (ItemListControllerState, (ItemListNodeState, Any)) in
        if let pendingShowCallsTabValue = pendingShowCallsTab {
            if showCallsTab == pendingShowCallsTabValue {
                pendingShowCallsTab = nil
            }
            currentShowCallsTab = pendingShowCallsTabValue
        } else {
            currentShowCallsTab = showCallsTab
        }
        let lang = presentationData.strings.baseLanguageCode
        let settings = nagramBottomBarSettings(NagramSettings.shared.bottomBarSettings, applyingShowCallsTab: currentShowCallsTab)
        let itemTitles = Dictionary(uniqueKeysWithValues: NagramBottomBarItemId.allCases.map { ($0, nextgramBottomBarPageTitle($0, language: lang)) })

        let alignmentLabel: String
        switch settings.alignment {
        case .spaceBetween:
            alignmentLabel = ngI18n("Nagram.BottomBarLayout.Alignment.spaceBetween", lang)
        case .leftCenter:
            alignmentLabel = ngI18n("Nagram.BottomBarLayout.Alignment.leftCenter", lang)
        case .center:
            alignmentLabel = ngI18n("Nagram.BottomBarLayout.Alignment.center", lang)
        }

        var entries: [NagramBottomBarEntry] = [
            .preview(
                section: 0,
                settings: settings,
                strings: presentationData.strings,
                itemTitles: itemTitles,
                topSearchTitle: ngI18n("Nagram.BottomBarLayout.TopBar", lang),
                topSearchVisibleHint: ngI18n("Nagram.BottomBarLayout.TopSearchHint.visible", lang),
                topSearchHiddenHint: ngI18n("Nagram.BottomBarLayout.TopSearchHint.hidden", lang),
                bottomBarTitle: ngI18n("Nagram.BottomBarLayout.BottomBar", lang),
                emptyBottomTitle: ngI18n("Nagram.BottomBarLayout.EmptyBottom", lang)
            ),
            .header(stableId: 1, section: 1, text: ngI18n("Nagram.BottomBarLayout.State", lang)),
            .toggle(stableId: 2, section: 1, title: ngI18n("Nagram.BottomBarLayout.TopSearch", lang), value: settings.topSearchVisible, option: .topSearch),
            .header(stableId: 40, section: 3, text: ngI18n("Nagram.BottomBarLayout.Options", lang)),
            .toggle(stableId: 42, section: 3, title: ngI18n("Nagram.BottomBarLayout.ShowLabels", lang), value: settings.showLabels, option: .labels),
            .slider(stableId: 43, section: 3, title: ngI18n("Nagram.BottomBarLayout.ButtonWidth", lang), value: settings.buttonWidthFillRatio),
            .disclosure(stableId: 44, section: 3, title: ngI18n("Nagram.BottomBarLayout.Alignment", lang), label: alignmentLabel, option: .alignment),
            .toggle(stableId: 45, section: 3, title: ngI18n("Nagram.BottomBarLayout.SettingsAvatar", lang), value: settings.settingsUseAvatar ?? hasOtherAccounts, option: .settingsAvatar),
            .reset(stableId: 46, section: 4, title: ngI18n("Nagram.BottomBarLayout.Reset", lang)),
            .footer(stableId: 47, section: 4, text: ngI18n("Nagram.BottomBarLayout.Footer", lang))
        ]
        let pages = nextgramBottomBarPages(settings)
        var pageEntries: [NagramBottomBarEntry] = [
            .header(stableId: 30, section: 2, text: ngI18n("Nagram.BottomBarLayout.Order", lang))
        ]
        for (index, id) in pages.enumerated() {
            pageEntries.append(.page(index: Int32(index), id: id, title: itemTitles[id] ?? id.rawValue,
                canRemove: settings.canHide(id), canDrag: pages.count > 1))
        }
        if settings.isVisible(.search) {
            pageEntries.append(.page(index: Int32(pages.count), id: .search, title: itemTitles[.search] ?? "", canRemove: settings.canHide(.search), canDrag: false))
        }
        pageEntries.append(.add(title: ngI18n("Nagram.BottomBarLayout.AddPage", lang),
            enabled: NagramBottomBarItemId.allCases.contains { !settings.isVisible($0) }))
        pageEntries.append(.footer(stableId: 39, section: 2, text: ngI18n("Nagram.BottomBarLayout.ReorderHint", lang)))
        entries += pageEntries
        if settings.isVisible(.search) {
            let searchStyleKey = "Nagram.BottomBarLayout.SearchStyle"
            entries.append(.disclosure(stableId: 41, section: 3, title: ngI18n(searchStyleKey, lang),
                label: ngI18n(searchStyleKey + "." + settings.searchMode.rawValue, lang), option: .searchMode))
        }
        entries.sort()

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ngI18n("Nagram.BottomBarLayout", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let presentationData = ItemListPresentationData(context.sharedContext.currentPresentationData.with { $0 })
    let controller = NextgramBottomBarSettingsController(presentationData: presentationData,
        updatedPresentationData: context.sharedContext.presentationData |> map { ItemListPresentationData($0) },
        state: signal, tabBarItem: nil)
    controller.navigationPresentation = .default
    controller.setReorderEntry({ (from: Int, to: Int, entries: [NagramBottomBarEntry]) -> Signal<Bool, NoError> in
        guard entries.indices.contains(from), case let .page(sourceIndex, id, _, _, true) = entries[from] else { return .single(false) }
        var settings = nagramBottomBarSettings(NagramSettings.shared.bottomBarSettings, applyingShowCallsTab: currentShowCallsTab)
        var pages = nextgramBottomBarPages(settings)
        guard let source = pages.firstIndex(of: id), !pages.isEmpty else { return .single(false) }
        let target = min(pages.count - 1, max(0, Int(sourceIndex) + to - from))
        guard source != target else { return .single(false) }
        pages.remove(at: source)
        pages.insert(id, at: target)
        settings.reorderPages(pages)
        saveSettings(settings)
        bump()
        return .single(true)
    })
    presentControllerImpl = { [weak controller] c, presentationArguments in
        controller?.present(c, in: .window(.root), with: presentationArguments)
    }
    return controller
}

private final class NagramBottomBarPreviewItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let settings: NagramBottomBarSettings
    let strings: PresentationStrings
    let itemTitles: [NagramBottomBarItemId: String]
    let topSearchTitle: String
    let topSearchVisibleHint: String
    let topSearchHiddenHint: String
    let bottomBarTitle: String
    let emptyBottomTitle: String
    let sectionId: ItemListSectionId
    init(theme: PresentationTheme, settings: NagramBottomBarSettings, strings: PresentationStrings, itemTitles: [NagramBottomBarItemId: String], topSearchTitle: String, topSearchVisibleHint: String, topSearchHiddenHint: String, bottomBarTitle: String, emptyBottomTitle: String, sectionId: ItemListSectionId) {
        self.theme = theme
        self.settings = settings
        self.strings = strings
        self.itemTitles = itemTitles
        self.topSearchTitle = topSearchTitle
        self.topSearchVisibleHint = topSearchVisibleHint
        self.topSearchHiddenHint = topSearchHiddenHint
        self.bottomBarTitle = bottomBarTitle
        self.emptyBottomTitle = emptyBottomTitle
        self.sectionId = sectionId
    }

    var selectable: Bool {
        return false
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = NagramBottomBarPreviewItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? NagramBottomBarPreviewItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
                    Queue.mainQueue().async {
                        completion(layout, { _ in apply() })
                    }
                }
            }
        }
    }
}

private final class NagramBottomBarPreviewItemNode: ListViewItemNode, ItemListItemNode {
    private var item: NagramBottomBarPreviewItem?
    private let topSearchTitleLabel = UILabel()
    private let topSearchHintLabel = UILabel()
    private let bottomBarTitleLabel = UILabel()
    private let emptyBottomLabel = UILabel()
    private let backgroundView = UIView()
    private lazy var topSearchView = NavigationSearchView(action: {}, closeAction: {})
    private let tabBarComponentView = ComponentView<Empty>()

    var tag: ItemListItemTag? {
        return nil
    }

    init() {
        super.init(layerBacked: false)
    }

    override func didLoad() {
        super.didLoad()
        self.view.addSubview(self.backgroundView)
        self.backgroundView.addSubview(self.topSearchTitleLabel)
        self.backgroundView.addSubview(self.topSearchView)
        self.backgroundView.addSubview(self.topSearchHintLabel)
        self.backgroundView.addSubview(self.bottomBarTitleLabel)
        self.backgroundView.addSubview(self.emptyBottomLabel)
        self.topSearchView.isUserInteractionEnabled = false
    }

    func asyncLayout() -> (_ item: NagramBottomBarPreviewItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { [self] item, params, neighbors in
            let height: CGFloat = 228.0
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: height), insets: itemListNeighborsGroupedInsets(neighbors, params))
            return (layout, { [weak self] in
                guard let self else {
                    return
                }
                self.item = item
                self.backgroundColor = item.theme.list.blocksBackgroundColor
                self.configure(theme: item.theme, params: params, height: height)
            })
        }
    }

    private func configure(theme: PresentationTheme, params: ListViewItemLayoutParams, height: CGFloat) {
        guard let item = self.item else {
            return
        }

        let controlLeftInset = params.leftInset + 16.0
        let controlRightInset = params.rightInset + 16.0
        let controlWidth = params.width - controlLeftInset - controlRightInset

        self.backgroundView.frame = CGRect(x: 0.0, y: 8.0, width: params.width, height: height - 16.0)
        self.backgroundView.backgroundColor = .clear
        self.backgroundView.layer.cornerRadius = 0.0
        self.backgroundView.clipsToBounds = false

        self.topSearchTitleLabel.frame = CGRect(x: controlLeftInset, y: 14.0, width: controlWidth, height: 18.0)
        self.topSearchTitleLabel.text = item.topSearchTitle
        self.topSearchTitleLabel.font = Font.regular(11.0)
        self.topSearchTitleLabel.textColor = theme.list.itemSecondaryTextColor

        let topSearchFrame = CGRect(x: controlLeftInset, y: 36.0, width: controlWidth, height: 42.0)
        self.topSearchView.frame = topSearchFrame
        self.topSearchView.update(size: topSearchFrame.size, theme: theme, strings: item.strings, isActive: false, isExpanded: true, transition: .immediate)
        self.topSearchView.alpha = item.settings.topSearchVisible ? 1.0 : 0.35

        self.topSearchHintLabel.frame = CGRect(x: controlLeftInset, y: 80.0, width: controlWidth, height: 16.0)
        self.topSearchHintLabel.text = item.settings.topSearchVisible ? item.topSearchVisibleHint : item.topSearchHiddenHint
        self.topSearchHintLabel.font = Font.regular(10.0)
        self.topSearchHintLabel.textColor = item.settings.topSearchVisible ? theme.list.itemSecondaryTextColor : theme.list.itemDisabledTextColor

        self.bottomBarTitleLabel.frame = CGRect(x: controlLeftInset, y: 104.0, width: controlWidth, height: 18.0)
        self.bottomBarTitleLabel.text = item.bottomBarTitle
        self.bottomBarTitleLabel.font = Font.regular(11.0)
        self.bottomBarTitleLabel.textColor = theme.list.itemSecondaryTextColor

        self.emptyBottomLabel.text = item.emptyBottomTitle
        self.emptyBottomLabel.textAlignment = .center
        self.emptyBottomLabel.font = Font.regular(13.0)
        self.emptyBottomLabel.textColor = theme.list.itemSecondaryTextColor
        self.emptyBottomLabel.backgroundColor = theme.list.itemInputField.backgroundColor
        self.emptyBottomLabel.layer.cornerRadius = 16.0
        self.emptyBottomLabel.layer.masksToBounds = true

        self.updateTabBarPreview(theme: theme, originX: params.leftInset, contentWidth: params.width - params.leftInset - params.rightInset)
    }

    private func updateTabBarPreview(theme: PresentationTheme, originX: CGFloat, contentWidth: CGFloat) {
        guard let item = self.item else {
            return
        }

        var previewSettings = item.settings
        previewSettings.isBottomBarVisible = true

        let componentId: (NagramBottomBarItemId) -> AnyHashable = { AnyHashable("nagram.preview.\($0.rawValue)") }
        let makeComponentItem: (NagramBottomBarItemId) -> TabBarComponent.Item = { id in

            let icon: TabBarComponent.Item.Content.CustomItem.Icon
            switch id {
            case .contacts:
                icon = .animation(name: "TabContacts", offset: .zero)
            case .calls:
                icon = .animation(name: "TabCalls", offset: .zero)
            case .chats:
                icon = .animation(name: "TabChats", offset: .zero)
            case .settings:
                icon = .animation(name: "TabSettings", offset: .zero)
            case .profile:
                icon = .bundleIcon(name: "Item List/Icons/Profile")
            case .feed:
                icon = .bundleIcon(name: "Chat List/Tabs/IconNews")
            case .savedMessages:
                icon = .bundleIcon(name: "Instant View/Bookmark")
            case .search:
                icon = .bundleIcon(name: "Navigation/Search")
            }

            return TabBarComponent.Item(
                content: .customItem(TabBarComponent.Item.Content.CustomItem(id: componentId(id), title: item.itemTitles[id] ?? id.rawValue, icon: icon)),
                action: { _ in },
                doubleTapAction: nil,
                contextAction: nil
            )
        }

        let visibleBottomItems = previewSettings.visibleBottomItems
        let visibleComponentItems = visibleBottomItems.map(makeComponentItem)
        let externalComponentItem: TabBarComponent.Item?
        if let externalItem = previewSettings.externalItem, externalItem != .search, !previewSettings.hiddenItems.contains(externalItem) {
            externalComponentItem = makeComponentItem(externalItem)
        } else {
            externalComponentItem = nil
        }

        let searchIsVisible = previewSettings.isVisible(.search)
        let search = searchIsVisible ? TabBarComponent.Search(
            isActive: false,
            showsButton: previewSettings.searchMode != .bar,
            activate: {},
            deactivate: {}
        ) : nil

        let selectedPage = visibleBottomItems.contains(.chats) ? NagramBottomBarItemId.chats : visibleBottomItems.first ?? previewSettings.externalItem
        let selectedId = selectedPage.map(componentId)
        let layoutItemCount = max(visibleComponentItems.count, NagramBottomBarSettings.minimumLayoutItemCount)
        let sideInset: CGFloat = 12.0
        let previewOriginX = originX + sideInset
        let availableWidth = max(0.0, contentWidth - sideInset * 2.0)
        let allButtonsHidden = visibleComponentItems.isEmpty && externalComponentItem == nil && !searchIsVisible
        if allButtonsHidden {
            self.emptyBottomLabel.isHidden = false
            self.emptyBottomLabel.frame = CGRect(x: previewOriginX, y: 130.0, width: availableWidth, height: 64.0)
            self.tabBarComponentView.view?.isHidden = true
            return
        } else {
            self.emptyBottomLabel.isHidden = true
        }
        let tabBarSize = self.tabBarComponentView.update(
            transition: .immediate,
            component: AnyComponent(TabBarComponent(
                theme: theme,
                strings: item.strings,
                items: visibleComponentItems,
                externalItem: externalComponentItem,
                search: search,
                selectedId: selectedId,
                outerInsets: .zero,
                layoutItemCount: layoutItemCount,
                isAdaptiveWidth: false,
                alignItemsToLeft: previewSettings.alignment == .spaceBetween,
                centerItemsInAvailableWidth: previewSettings.alignment == .center,
                showItemTitles: previewSettings.showLabels,
                buttonWidthFillRatio: CGFloat(previewSettings.buttonWidthFillRatio) / 100.0
            )),
            environment: {},
            containerSize: CGSize(width: availableWidth, height: 80.0)
        )

        if let tabBarView = self.tabBarComponentView.view {
            if tabBarView.superview !== self.backgroundView {
                self.backgroundView.addSubview(tabBarView)
            }
            tabBarView.isHidden = false

            let onlySearchButton = searchIsVisible && previewSettings.searchMode != .bar && visibleComponentItems.isEmpty && externalComponentItem == nil
            let tabBarX: CGFloat
            if onlySearchButton {
                tabBarX = previewOriginX + max(0.0, availableWidth - tabBarSize.width)
            } else if previewSettings.alignment == .spaceBetween {
                tabBarX = previewOriginX
            } else {
                tabBarX = previewOriginX + floor(max(0.0, availableWidth - tabBarSize.width) * 0.5)
            }
            let tabBarFrame = CGRect(origin: CGPoint(x: tabBarX, y: 130.0), size: tabBarSize)
            tabBarView.frame = tabBarFrame
            tabBarView.isUserInteractionEnabled = false
            tabBarView.alpha = item.settings.isBottomBarVisible ? 1.0 : 0.45
        }
    }
}
