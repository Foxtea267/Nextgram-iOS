import AccountContext
import Display
import ItemListUI
import NagramSettings
import NagramSettingsSignal
import NagramStrings
import SwiftSignalKit
import TelegramPresentationData
import UIKit

public let nextgramSettingsLogo: UIImage? = {
    guard let image = UIImage(bundleImageName: "NextgramSettingsLogo") else { return nil }
    return UIGraphicsImageRenderer(size: CGSize(width: 30.0, height: 30.0)).image { _ in
        image.draw(in: CGRect(x: 0.0, y: 0.0, width: 30.0, height: 30.0))
    }
}()

private enum NextgramBadgeStyle: String, CaseIterable {
    case classic, purple, green, sunset

    var asset: String {
        switch self {
        case .classic: return "Components/AppBadge"
        case .purple: return "Components/NextgramBadgePurple"
        case .green: return "Components/NextgramBadgeGreen"
        case .sunset: return "Components/NextgramBadgeSunset"
        }
    }
}

public func nextgramScreenshotBadgeImage(style: String) -> UIImage? {
    return UIImage(bundleImageName: (NextgramBadgeStyle(rawValue: style) ?? .classic).asset)
}

private struct BadgeStyleEntry: ItemListNodeEntry {
    let stableId: String
    let index: Int
    let title: String
    let selected: Bool
    var section: ItemListSectionId { return 0 }

    static func < (lhs: Self, rhs: Self) -> Bool { return lhs.index < rhs.index }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let preview = nextgramScreenshotBadgeImage(style: self.stableId)
        return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: self.title,
            titleBadge: self.selected ? "✓" : nil, label: "",
            labelStyle: preview.map { .image(image: $0, size: $0.size) } ?? .text,
            sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                NagramSettings.shared.screenshotBadgeStyle = self.stableId
            })
    }
}

func nextgramBadgeSettingsController(context: AccountContext) -> ViewController {
    let state = combineLatest(context.sharedContext.presentationData,
                              nagramStringSignal("nagram.screenshotBadgeStyle", defaultValue: "classic"))
    |> deliverOnMainQueue
    |> map { presentationData, value -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = presentationData.strings
        let data = ItemListPresentationData(presentationData)
        let selected = NextgramBadgeStyle(rawValue: value) ?? .classic
        let entries = NextgramBadgeStyle.allCases.enumerated().map { index, style in
            BadgeStyleEntry(stableId: style.rawValue, index: index,
                            title: ngI18n("Nagram.BadgeStyle.\(style.rawValue)", strings.baseLanguageCode), selected: style == selected)
        }
        return (ItemListControllerState(presentationData: data, title: .text(ngI18n("Nagram.BadgeStyle", strings.baseLanguageCode)),
                                        leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: strings.Common_Back)),
                (ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false), selected))
    }
    return ItemListController(context: context, state: state)
}
