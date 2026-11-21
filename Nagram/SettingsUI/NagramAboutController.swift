import AccountContext
import Display
import Foundation
import ItemListUI
import NagramStrings
import SwiftSignalKit
import TelegramPresentationData

private final class NagramAboutArguments {
    let openUrl: (String) -> Void
    let openUpdater: () -> Void

    init(openUrl: @escaping (String) -> Void, openUpdater: @escaping () -> Void) {
        self.openUrl = openUrl
        self.openUpdater = openUpdater
    }
}

private enum NagramAboutEntryStableId: Int32 {
    case description
    case update
    case github
    case group
    case channel
    case agreement
    case disclaimer
}

private enum NagramAboutEntry: ItemListNodeEntry {
    case description(String)
    case update(String)
    case github(String)
    case group(String)
    case channel(String)
    case agreement(String)
    case disclaimer(String)

    var section: ItemListSectionId {
        switch self {
        case .description:
            return 0
        case .update:
            return 1
        case .github, .group, .channel, .agreement:
            return 2
        case .disclaimer:
            return 3
        }
    }

    var stableId: NagramAboutEntryStableId {
        switch self {
        case .description:
            return .description
        case .update:
            return .update
        case .github:
            return .github
        case .group:
            return .group
        case .channel:
            return .channel
        case .agreement:
            return .agreement
        case .disclaimer:
            return .disclaimer
        }
    }

    private var sortIndex: Int32 {
        return self.stableId.rawValue
    }

    static func ==(lhs: NagramAboutEntry, rhs: NagramAboutEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.description(lhsText), .description(rhsText)),
             let (.update(lhsText), .update(rhsText)),
             let (.github(lhsText), .github(rhsText)),
             let (.group(lhsText), .group(rhsText)),
             let (.channel(lhsText), .channel(rhsText)),
             let (.agreement(lhsText), .agreement(rhsText)),
             let (.disclaimer(lhsText), .disclaimer(rhsText)):
            return lhsText == rhsText
        default:
            return false
        }
    }

    static func <(lhs: NagramAboutEntry, rhs: NagramAboutEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NagramAboutArguments
        switch self {
        case let .description(text), let .disclaimer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .update(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title,
                label: "", sectionId: self.section, style: .blocks, action: arguments.openUpdater)
        case let .github(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.openUrl("https://github.com/Foxtea267/Nextgram-iOS")
            })
        case let .group(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.openUrl("https://t.me/Nextgram_Chat")
            })
        case let .channel(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.openUrl("https://t.me/Nextgram_iOS")
            })
        case let .agreement(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.openUrl("https://github.com/Foxtea267/Nextgram-iOS/blob/main/USAGE_AGREEMENT.md")
            })
        }
    }
}

public func nagramAboutController(context: AccountContext) -> ViewController {
    var openUrlImpl: ((String) -> Void)?
    var openUpdaterImpl: (() -> Void)?
    let arguments = NagramAboutArguments(openUrl: { url in
        openUrlImpl?(url)
    }, openUpdater: {
        openUpdaterImpl?()
    })

    let state = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let version = Bundle.main.object(forInfoDictionaryKey: "NextgramVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "—"
        let entries: [NagramAboutEntry] = [
            .description(ngI18n("Nagram.About.Description", lang) + "\n\nNextgram " + version),
            .update(ngI18n("Nagram.Update.Title", lang)),
            .github(ngI18n("Nagram.About.GitHub", lang)),
            .group(ngI18n("Nagram.About.Group", lang)),
            .channel(ngI18n("Nagram.About.Channel", lang)),
            .agreement(ngI18n("Nagram.About.Agreement", lang)),
            .disclaimer(ngI18n("Nagram.About.Disclaimer", lang))
        ]
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(ngI18n("Nagram.About", lang)),
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

    let controller = ItemListController(context: context, state: state)
    controller.navigationPresentation = .default
    openUpdaterImpl = { [weak controller] in
        Task { @MainActor in
            guard let navigationController = controller?.navigationController as? NavigationController else { return }
            navigationController.pushViewController(nextgramUpdateController(context: context), animated: true)
        }
    }
    openUrlImpl = { [weak controller] url in
        context.sharedContext.openExternalUrl(
            context: context,
            urlContext: .generic,
            url: url,
            forceExternal: url.contains("github.com"),
            presentationData: context.sharedContext.currentPresentationData.with { $0 },
            navigationController: controller?.navigationController as? NavigationController,
            dismissInput: {}
        )
    }
    return controller
}
