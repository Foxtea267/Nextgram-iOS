import AccountContext
import Display
import Foundation
import ItemListUI
import NagramSettings
import NagramStrings
import SwiftSignalKit
import TelegramPresentationData
import UIKit

private final class NagramAntiRecallRulesArguments {
    let updateWhitelist: (String) -> Void
    let updateBlacklist: (String) -> Void
    let updateKeywords: (String) -> Void

    init(updateWhitelist: @escaping (String) -> Void, updateBlacklist: @escaping (String) -> Void, updateKeywords: @escaping (String) -> Void) {
        self.updateWhitelist = updateWhitelist
        self.updateBlacklist = updateBlacklist
        self.updateKeywords = updateKeywords
    }
}

private enum NagramAntiRecallRulesEntry: ItemListNodeEntry {
    case header(Int32, Int32, String)
    case input(Int32, Int32, String, String, Int)
    case footer(Int32, Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .input(_, section, _, _, _), let .footer(_, section, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(id, _, _), let .input(id, _, _, _, _), let .footer(id, _, _):
            return id
        }
    }

    static func ==(lhs: NagramAntiRecallRulesEntry, rhs: NagramAntiRecallRulesEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(lId, lSection, lText), .header(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        case let (.footer(lId, lSection, lText), .footer(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        case let (.input(lId, lSection, lText, lPlaceholder, lIndex), .input(rId, rSection, rText, rPlaceholder, rIndex)):
            return lId == rId && lSection == rSection && lText == rText && lPlaceholder == rPlaceholder && lIndex == rIndex
        default:
            return false
        }
    }

    static func <(lhs: NagramAntiRecallRulesEntry, rhs: NagramAntiRecallRulesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NagramAntiRecallRulesArguments
        switch self {
        case let .header(_, section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .input(_, section, text, placeholder, index):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: text, placeholder: placeholder, maxLength: nil, sectionId: section, style: .blocks, capitalization: false, autocorrection: false, returnKeyType: .default, minimalHeight: 110.0, maximalHeight: 220.0, textUpdated: { value in
                switch index {
                case 0:
                    arguments.updateWhitelist(value)
                case 1:
                    arguments.updateBlacklist(value)
                default:
                    arguments.updateKeywords(value)
                }
            })
        case let .footer(_, section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

func nagramAntiRecallRulesController(context: AccountContext) -> ViewController {
    let arguments = NagramAntiRecallRulesArguments(updateWhitelist: { value in
        NagramSettings.shared.antiRecallWhitelist = value
    }, updateBlacklist: { value in
        NagramSettings.shared.antiRecallBlacklist = value
    }, updateKeywords: { value in
        NagramSettings.shared.antiRecallExcludedKeywords = value
    })

    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let entries: [NagramAntiRecallRulesEntry] = [
            .header(0, 0, ngI18n("Nagram.AntiRecallRules.Whitelist", lang)),
            .input(1, 0, NagramSettings.shared.antiRecallWhitelist, ngI18n("Nagram.AntiRecallRules.List.Placeholder", lang), 0),
            .footer(2, 0, ngI18n("Nagram.AntiRecallRules.Whitelist.Footer", lang)),
            .header(3, 1, ngI18n("Nagram.AntiRecallRules.Blacklist", lang)),
            .input(4, 1, NagramSettings.shared.antiRecallBlacklist, ngI18n("Nagram.AntiRecallRules.List.Placeholder", lang), 1),
            .footer(5, 1, ngI18n("Nagram.AntiRecallRules.Blacklist.Footer", lang)),
            .header(6, 2, ngI18n("Nagram.AntiRecallRules.Keywords", lang)),
            .input(7, 2, NagramSettings.shared.antiRecallExcludedKeywords, ngI18n("Nagram.AntiRecallRules.Keywords.Placeholder", lang), 2),
            .footer(8, 2, ngI18n("Nagram.AntiRecallRules.Keywords.Footer", lang))
        ]
        return (
            ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ngI18n("Nagram.AntiRecallRules", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)),
            (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks), arguments)
        )
    }
    return ItemListController(context: context, state: signal)
}
