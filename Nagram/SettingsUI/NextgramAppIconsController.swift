import AccountContext
import Display
import ItemListUI
import NagramSettingsSignal
import NagramStrings
import PresentationDataUtils
import SwiftSignalKit
import TelegramPresentationData
import UIKit

private struct NextgramAppIconEntry: ItemListNodeEntry {
    let stableId: Int
    let icon: PresentationAppIcon
    let title: String
    let subtitle: String?
    let selected: Bool
    let enabled: Bool

    var section: ItemListSectionId { return 0 }

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let select = arguments as! (PresentationAppIcon) -> Void
        let preview = UIImage(bundleImageName: self.icon.imageName).map { image in
            UIGraphicsImageRenderer(size: CGSize(width: 30.0, height: 30.0)).image { _ in
                let bounds = CGRect(x: 0.0, y: 0.0, width: 30.0, height: 30.0)
                UIBezierPath(roundedRect: bounds, cornerRadius: 7.0).addClip()
                image.draw(in: bounds)
            }
        }
        return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass,
            icon: preview, title: self.title, subtitle: self.subtitle, style: .right,
            checked: self.selected, enabled: self.enabled, zeroSeparatorInsets: false, sectionId: self.section,
            action: { select(self.icon) })
    }
}

private func nextgramAppIconTitle(_ icon: PresentationAppIcon, strings: PresentationStrings) -> String {
    switch icon.name {
    case "Nextgram": return "Nextgram"
    case "NextgramClassic": return "Nextgram · \(strings.Appearance_AppIconClassic)"
    case "Telegram": return "Telegram"
    case "BlueIcon": return strings.Appearance_AppIconDefault
    case "BlackIcon": return strings.Appearance_AppIconDefaultX
    case "BlueClassicIcon": return strings.Appearance_AppIconClassic
    case "BlackClassicIcon": return strings.Appearance_AppIconClassicX
    case "BlueFilledIcon": return strings.Appearance_AppIconFilled
    case "BlackFilledIcon": return strings.Appearance_AppIconFilledX
    case "WhiteFilledIcon": return ngI18n("Nagram.Settings.AppIcons.White", strings.baseLanguageCode)
    case "New1": return strings.Appearance_AppIconNew1
    case "New2": return strings.Appearance_AppIconNew2
    case "Premium": return strings.Appearance_AppIconPremium
    case "PremiumBlack": return strings.Appearance_AppIconBlack
    case "PremiumTurbo": return strings.Appearance_AppIconTurbo
    default: return icon.name
    }
}

func nextgramAppIconsController(context: AccountContext) -> ViewController {
    let bindings = context.sharedContext.applicationBindings
    let icons = bindings.getAvailableAlternateIcons()
    let updates = ValuePromise<Int>(0, ignoreRepeated: false)
    var revision = 0
    var changing = false
    let refresh = {
        revision += 1
        updates.set(revision)
    }
    var present: ((ViewController) -> Void)?
    let select: (PresentationAppIcon) -> Void = { icon in
        let name = icon.isDefault ? nil : icon.name
        guard !changing, name != bindings.getAlternateIconName() else { return }
        changing = true
        refresh()
        bindings.requestSetAlternateIconName(name) { success in
            Queue.mainQueue().async {
                changing = false
                refresh()
                if !success {
                    let data = context.sharedContext.currentPresentationData.with { $0 }
                    present?(textAlertController(context: context,
                        title: ngI18n("Nagram.Settings.AppIcons", data.strings.baseLanguageCode),
                        text: ngI18n("Nagram.Settings.AppIcons.Failed", data.strings.baseLanguageCode),
                        actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]))
                }
            }
        }
    }
    let state = combineLatest(context.sharedContext.presentationData, updates.get(), nagramSettingsRestoredSignal())
    |> deliverOnMainQueue
    |> map { presentationData, _, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let data = ItemListPresentationData(presentationData)
        let strings = presentationData.strings
        let current = bindings.getAlternateIconName()
        let entries = icons.enumerated().map { index, icon in
            NextgramAppIconEntry(stableId: index, icon: icon, title: nextgramAppIconTitle(icon, strings: strings),
                subtitle: icon.isDefault ? strings.Appearance_AppIconDefault : nil,
                selected: icon.isDefault ? current == nil : current == icon.name, enabled: !changing)
        }
        return (ItemListControllerState(presentationData: data,
            title: .text(ngI18n("Nagram.Settings.AppIcons", strings.baseLanguageCode)),
            leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: strings.Common_Back)),
            (ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false), select))
    }
    let controller = ItemListController(context: context, state: state)
    controller.didAppear = { _ in refresh() }
    present = { [weak controller] value in
        controller?.present(value, in: .window(.root))
    }
    return controller
}
