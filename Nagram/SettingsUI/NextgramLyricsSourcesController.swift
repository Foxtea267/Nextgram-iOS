import AccountContext
import Display
import ItemListUI
import NagramSettings
import NagramSettingsSignal
import NagramStrings
import SwiftSignalKit
import TelegramPresentationData
import UIKit

private enum NextgramLyricsSourceEntry: ItemListNodeEntry {
    case source(index: Int, source: NextgramLyricsSource, title: String)
    case hint(String)

    var section: ItemListSectionId { 0 }
    var stableId: String {
        switch self {
        case let .source(_, source, _): return source.rawValue
        case .hint: return "hint"
        }
    }

    private var index: Int {
        switch self {
        case let .source(index, _, _): return index
        case .hint: return NextgramLyricsSource.allCases.count
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.index < rhs.index }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .source(index, _, title):
            // MARK: NEXTGRAM — Keep the reorder handle readable in dark themes.
            let icon = PresentationResourcesItemList.itemListReorderIndicatorIcon(presentationData.theme)
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass,
                title: "\(index + 1).  \(title)", label: "",
                labelStyle: icon.map { .image(image: $0, size: CGSize(width: 18, height: 16)) } ?? .text,
                sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil, nextgramReorderable: true)
        case let .hint(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class NextgramLyricsSourcesList: ItemListController {
    override func loadDisplayNode() {
        super.loadDisplayNode()
        (self.displayNode as? ItemListControllerNode)?.listNode.reorderingRequiresLongPress = true
    }
}

func nextgramLyricsSourcesController(context: AccountContext) -> ViewController {
    let presentation = context.sharedContext.presentationData |> map { ItemListPresentationData($0) }
    let order = nagramStringSignal("nagram.musicPlayerLyricsSourceOrder", defaultValue: NextgramLyricsSource.defaultOrder)
    let state = combineLatest(presentation, order)
    |> deliverOnMainQueue
    |> map { data, order -> (ItemListControllerState, (ItemListNodeState, Bool)) in
        let language = data.strings.baseLanguageCode
        let sources = NextgramLyricsSource.ordered(order)
        var entries: [NextgramLyricsSourceEntry] = sources.enumerated().map { index, source in
            .source(index: index, source: source, title: ngI18n("Nagram.MusicPlayer.Source." + source.rawValue, language))
        }
        entries.append(.hint(ngI18n("Nagram.MusicPlayer.SourcePriorityHint", language)))
        let reset = ItemListNavigationButton(content: .text(ngI18n("Nagram.MusicPlayer.ResetSources", language)), style: .regular,
            enabled: sources != NextgramLyricsSource.allCases, action: {
                NagramSettings.shared.musicPlayerLyricsSourceOrder = NextgramLyricsSource.defaultOrder
            })
        return (ItemListControllerState(presentationData: data, title: .text(ngI18n("Nagram.MusicPlayer.SourcePriority", language)),
            leftNavigationButton: nil, rightNavigationButton: reset, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back)),
            (ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false), false))
    }
    let controller = NextgramLyricsSourcesList(presentationData: ItemListPresentationData(context.sharedContext.currentPresentationData.with { $0 }),
        updatedPresentationData: presentation, state: state, tabBarItem: nil)
    controller.navigationPresentation = .default
    controller.setReorderEntry { (from: Int, to: Int, entries: [NextgramLyricsSourceEntry]) -> Signal<Bool, NoError> in
        guard entries.indices.contains(from), case let .source(index, source, _) = entries[from] else { return .single(false) }
        var sources = NextgramLyricsSource.ordered(NagramSettings.shared.musicPlayerLyricsSourceOrder)
        guard let current = sources.firstIndex(of: source) else { return .single(false) }
        let target = max(0, min(sources.count - 1, index + to - from))
        guard current != target else { return .single(false) }
        sources.remove(at: current)
        sources.insert(source, at: target)
        NagramSettings.shared.musicPlayerLyricsSourceOrder = sources.map(\.rawValue).joined(separator: ",")
        return .single(true)
    }
    return controller
}
