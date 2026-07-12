import AccountContext
import Display
import ItemListUI
import NagramLinkMetadata
import NagramStrings
import PresentationDataUtils
import SwiftSignalKit
import TelegramPresentationData

private final class NagramInlineBotRulesArguments {
}

private enum NagramInlineBotRulesEntry: ItemListNodeEntry {
    case rule(Int, String, String)
    case footer(Int, String)

    var section: ItemListSectionId { return 0 }
    var stableId: Int { switch self { case let .rule(index, _, _): return index; case let .footer(index, _): return index } }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .rule(_, username, patterns):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "@\(username)", label: patterns, sectionId: self.section, style: .blocks, action: nil)
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func nagramInlineBotRulesController(context: AccountContext) -> ViewController {
    NagramLinkMetadata.shared.refreshIfNeeded(engine: context.engine)
    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        var entries: [NagramInlineBotRulesEntry] = []
        for (index, rule) in NagramLinkMetadata.shared.currentInlineBotRules().enumerated() {
            entries.append(.rule(index, rule.username, rule.rules.joined(separator: "\n")))
        }
        entries.append(.footer(entries.count, ngI18n("Nagram.InlineBotRules.Footer", lang)))
        return (
            ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ngI18n("Nagram.InlineBotRules", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)),
            (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks), NagramInlineBotRulesArguments())
        )
    }
    return ItemListController(context: context, state: signal)
}
