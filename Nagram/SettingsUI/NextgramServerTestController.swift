import AccountContext
import Display
import Foundation
import ItemListUI
import NagramStrings
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import UIKit
import UndoUI

private struct NextgramServerTestState: Equatable {
    var running = false
    var accountLatency: Int?
    var accountCompleted = false
    var samples: [Int: [Int?]] = [:]
    var completed: Set<Int> = []
    var dnsResults: [String: NextgramDNSDiagnosticResult] = [:]
    var dnsFinished: Set<String> = []
    var dnsCompleted: Bool { self.dnsFinished.count == 4 }
}

private enum NextgramServerTestEntry: ItemListNodeEntry {
    case value(Int32, String, String)
    case header(Int32, String)
    case action(Int32, String)
    case footer(Int32, String)

    var stableId: Int32 {
        switch self {
        case let .value(id, _, _), let .header(id, _), let .action(id, _), let .footer(id, _):
            return id
        }
    }

    var section: ItemListSectionId { self.stableId / 10 }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .value(_, title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .header(_, title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: self.section)
        case let .action(id, title):
            let action = arguments as! (Int32) -> Void
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { action(id) })
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

func nextgramServerTestController(context: AccountContext) -> ViewController {
    let network = context.account.network
    let result = ValuePromise(NextgramServerTestState(), ignoreRepeated: true)
    var snapshot = NextgramServerTestState()
    let disposable = MetaDisposable()
    var generation = UUID()
    var currentRoute: String?
    var reportCopied: (() -> Void)?
    let publish = { result.set(snapshot) }
    let cancel: () -> Void = {
        generation = UUID()
        disposable.set(nil)
        snapshot.running = false
        publish()
    }
    let backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in cancel() }
    let run: () -> Void = {
        let id = UUID()
        generation = id
        snapshot = NextgramServerTestState()
        snapshot.running = true
        publish()
        let batch = DisposableSet()
        disposable.set(batch)
        for (provider, endpoint) in [("Cloudflare", "https://cloudflare-dns.com/dns-query"), ("Google", "https://dns.google/resolve")] {
            for (type, label) in [(1, "A"), (28, "AAAA")] {
                let name = provider + " · " + label
                let task = NextgramDNSDiagnosticQuery(provider: endpoint, recordType: type) { value in
                    guard generation == id else { return }
                    snapshot.dnsResults[name] = value
                    snapshot.dnsFinished.insert(name)
                    snapshot.running = !snapshot.accountCompleted || snapshot.completed.count < 5 || !snapshot.dnsCompleted
                    publish()
                }
                batch.add(ActionDisposable { task.cancel() })
            }
        }
        batch.add((network.nextgramConnectionLatency()
        |> deliverOnMainQueue).start(next: { value in
            guard generation == id else { return }
            snapshot.accountLatency = value
            snapshot.accountCompleted = true
            snapshot.running = snapshot.completed.count < 5 || !snapshot.dnsCompleted
            publish()
        }))
        for dc in 1...5 {
            batch.add((network.nextgramDatacenterSamples(dc)
            |> deliverOnMainQueue).start(next: { sample in
                guard generation == id else { return }
                snapshot.samples[dc, default: []].append(sample)
                publish()
            }, completed: {
                guard generation == id else { return }
                snapshot.completed.insert(dc)
                snapshot.running = !snapshot.accountCompleted || snapshot.completed.count < 5 || !snapshot.dnsCompleted
                publish()
            }))
        }
    }
    let action: (Int32) -> Void = { actionId in
        switch actionId {
        case 70:
            if snapshot.running {
                cancel()
            } else {
                run()
            }
        case 71:
            let report = (1...5).map { dc in
                let samples = snapshot.samples[dc, default: []].dropFirst().compactMap { $0 }
                let average = samples.isEmpty ? "—" : "\(samples.reduce(0, +) / samples.count) ms"
                return "DC \(dc): \(average)"
            }
            UIPasteboard.general.string = report.joined(separator: "\n")
            reportCopied?()
        default:
            break
        }
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
        // A proxy switch invalidates comparisons with the previous network route.
        if case let .online(proxyAddress) = connection {
            let routeIdentity = proxyAddress ?? "direct"
            if let previous = currentRoute, previous != routeIdentity, result.running {
                Queue.mainQueue().async { cancel() }
            }
            currentRoute = routeIdentity
        }
        var entries: [NextgramServerTestEntry] = [
            .value(0, string("Datacenter"), "DC \(network.datacenterId)"),
            .value(1, string("Connection"), route)
        ]
        func milliseconds(_ value: Int?) -> String {
            value.map { String(format: string("Milliseconds"), $0) } ?? "—"
        }
        let accountValue: String
        if result.accountCompleted, result.accountLatency == nil {
            accountValue = string("Unavailable")
        } else if result.running && !result.accountCompleted {
            accountValue = string("Running")
        } else {
            accountValue = milliseconds(result.accountLatency)
        }
        entries.append(.value(2, string("Measurement"), accountValue))
        for dc in 1...5 {
            let id = Int32(dc * 10)
            let values = result.samples[dc, default: []]
            let samples = values.dropFirst().compactMap { $0 }
            let average = samples.isEmpty ? nil : samples.reduce(0, +) / samples.count
            let spread: Int?
            if let min = samples.min(), let max = samples.max(), samples.count > 1 {
                spread = max - min
            } else {
                spread = nil
            }
            let waiting = result.running && !result.completed.contains(dc)
            let region = dc == 5 ? "Singapore" : (dc % 2 == 0 ? "Amsterdam" : "Miami")
            entries.append(.header(id, "DC \(dc) · \(region)"))
            entries.append(.value(id + 1, string("FirstRequest"), values.isEmpty && waiting ? string("Running") : milliseconds(values.first ?? nil)))
            entries.append(.value(id + 2, string("Average"), milliseconds(average)))
            entries.append(.value(id + 3, string("Minimum"), milliseconds(samples.min())))
            entries.append(.value(id + 4, string("Spread"), milliseconds(spread)))
            entries.append(.value(id + 5, string("Failures"), "\(values.filter { $0 == nil }.count)"))
        }
        entries.append(.header(60, string("DNS")))
        for (index, name) in ["Cloudflare · A", "Cloudflare · AAAA", "Google · A", "Google · AAAA"].enumerated() {
            let value: String
            if let answer = result.dnsResults[name] {
                value = milliseconds(answer.milliseconds) + " · " + answer.addresses.joined(separator: ", ")
            } else {
                value = result.running && !result.dnsFinished.contains(name) ? string("Running") : "—"
            }
            entries.append(.value(Int32(61 + index), name, value))
        }
        entries.append(.action(70, result.running ? data.strings.Common_Cancel : string("Retry")))
        if !result.running && !result.samples.isEmpty {
            entries.append(.action(71, string("CopyAverages")))
        }
        entries.append(.footer(72, string("DCExplanation")))
        entries.append(.footer(73, string("DNSExplanation")))
        let presentation = ItemListPresentationData(data)
        return (
            ItemListControllerState(presentationData: presentation, title: .text(ngI18n("Nagram.TelegramLatency", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back)),
            (ItemListNodeState(presentationData: presentation, entries: entries, style: .blocks, animateChanges: false), action)
        )
    }
    |> afterDisposed {
        disposable.dispose()
        NotificationCenter.default.removeObserver(backgroundObserver)
    }
    let controller = ItemListController(context: context, state: state)
    controller.navigationPresentation = .default
    controller.willDisappear = { _ in cancel() }
    reportCopied = { [weak controller] in
        let data = context.sharedContext.currentPresentationData.with { $0 }
        HapticFeedback().tap()
        controller?.present(UndoOverlayController(presentationData: data,
            content: .linkCopied(title: nil, text: ngI18n("Nagram.TelegramLatency.Copied", data.strings.baseLanguageCode)),
            elevatedLayout: false, animateInAsReplacement: false, action: { _ in false }), in: .current)
    }
    return controller
}
