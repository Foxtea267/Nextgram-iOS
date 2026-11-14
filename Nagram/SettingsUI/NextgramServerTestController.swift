import AccountContext
import Display
import Foundation
import ItemListUI
import NagramStrings
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData

private enum NextgramServerTestState: Equatable {
    case running
    case finished(Int?)
}

private enum NextgramServerTestEntry: ItemListNodeEntry {
    case value(Int32, String, String)
    case retry(String)
    case footer(String)

    var stableId: Int32 {
        switch self {
        case let .value(id, _, _): return id
        case .retry: return 3
        case .footer: return 4
        }
    }

    var section: ItemListSectionId { self.stableId < 3 ? 0 : 1 }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .value(_, title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .retry(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments as! () -> Void)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

func nextgramServerTestController(context: AccountContext) -> ViewController {
    let network = context.account.network
    let result = ValuePromise<NextgramServerTestState>(.running, ignoreRepeated: true)
    let disposable = MetaDisposable()
    let run: () -> Void = {
        result.set(.running)
        disposable.set((network.nextgramConnectionLatency()
        |> deliverOnMainQueue).start(next: { result.set(.finished($0)) }))
    }
    let state = combineLatest(context.sharedContext.presentationData, network.connectionStatus, result.get())
    |> deliverOnMainQueue
    |> map { data, connection, result -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = data.strings.baseLanguageCode
        func string(_ key: String) -> String { ngI18n("Nagram.TelegramLatency." + key, lang) }
        let route: String
        switch connection {
        case .waitingForNetwork:
            route = string("Offline")
        case .connecting, .updating:
            route = string("Connecting")
        case let .online(proxyAddress):
            route = string(proxyAddress == nil ? "Direct" : "Proxy")
        }
        var entries: [NextgramServerTestEntry] = [
            .value(0, string("Datacenter"), "DC \(network.datacenterId)"),
            .value(1, string("Connection"), route)
        ]
        switch result {
        case .running:
            entries.append(.value(2, string("Measurement"), string("Running")))
        case let .finished(milliseconds):
            entries.append(.value(2, string("Measurement"), milliseconds.map { String(format: string("Milliseconds"), $0) } ?? string("Unavailable")))
            entries.append(.retry(string("Retry")))
        }
        if case .finished(nil) = result {
            entries.append(.footer(string("Failed")))
        } else {
            entries.append(.footer(string("Explanation")))
        }
        let presentation = ItemListPresentationData(data)
        return (
            ItemListControllerState(presentationData: presentation, title: .text(ngI18n("Nagram.TelegramLatency", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back)),
            (ItemListNodeState(presentationData: presentation, entries: entries, style: .blocks, animateChanges: false), run)
        )
    }
    |> afterDisposed { disposable.dispose() }
    let controller = ItemListController(context: context, state: state)
    controller.navigationPresentation = .default
    run()
    return controller
}
