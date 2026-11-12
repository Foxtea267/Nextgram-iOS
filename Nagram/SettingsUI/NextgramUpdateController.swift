import AccountContext
import Display
import Foundation
import ItemListUI
import NagramStrings
import NextgramUpdate
import SwiftSignalKit
import TelegramPresentationData
import UIKit

private enum UpdateState: Equatable {
    case idle
    case checking
    case current
    case available(NextgramUpdateRelease)
    case downloading(NextgramUpdateRelease)
    case downloaded(NextgramUpdateRelease, NextgramUpdatePackage)
    case failed(String, NextgramUpdateRelease?)
}

private final class UpdateActions {
    let state = ValuePromise<UpdateState>(.idle, ignoreRepeated: false)
    private var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }

    func check(bundleIdentifier: String, version: String) {
        guard task == nil else {
            return
        }
        state.set(.checking)
        task = Task { @MainActor [weak self] in
            defer {
                if !Task.isCancelled {
                    self?.task = nil
                }
            }
            do {
                let release = try await NextgramUpdateClient.check(bundleIdentifier: bundleIdentifier, installedVersion: version)
                try Task.checkCancellation()
                self?.state.set(release.map(UpdateState.available) ?? .current)
            } catch {
                if !Task.isCancelled {
                    self?.state.set(.failed(Self.errorKey(error, fallback: "Nagram.Update.CheckFailed"), nil))
                }
            }
        }
    }

    func download(_ release: NextgramUpdateRelease) {
        guard task == nil else {
            return
        }
        state.set(.downloading(release))
        task = Task { @MainActor [weak self] in
            defer {
                if !Task.isCancelled {
                    self?.task = nil
                }
            }
            do {
                let downloadedPackage = try await NextgramUpdateClient.download(release)
                try Task.checkCancellation()
                self?.state.set(.downloaded(release, downloadedPackage))
            } catch {
                if !Task.isCancelled {
                    self?.state.set(.failed(Self.errorKey(error, fallback: "Nagram.Update.DownloadFailed"), release))
                }
            }
        }
    }

    func cancel(returningTo release: NextgramUpdateRelease?) {
        task?.cancel()
        task = nil
        state.set(release.map(UpdateState.available) ?? .idle)
    }

    private static func errorKey(_ error: Error, fallback: String) -> String {
        switch error as? NextgramUpdateError {
        case .unsupportedInstallation:
            return "Nagram.Update.Unsupported"
        case .unavailableAsset:
            return "Nagram.Update.AssetUnavailable"
        case .invalidDownload, .invalidPackage:
            return "Nagram.Update.VerificationFailed"
        case .invalidRelease, nil:
            return fallback
        }
    }
}

private struct UpdateRow: ItemListNodeEntry {
    enum Id: Int32 {
        case installed, status, check, download, cancel, export, release
    }

    let id: Id
    let title: String

    var stableId: Int32 {
        return id.rawValue
    }

    var section: ItemListSectionId {
        return id == .installed || id == .status ? 0 : 1
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        if section == 0 {
            return ItemListTextItem(presentationData: presentationData, text: .plain(title), sectionId: section)
        }
        let perform = arguments as! (Id) -> Void
        return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title,
                                  kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: {
            perform(id)
        })
    }
}

func nextgramUpdateController(context: AccountContext) -> ViewController {
    let actions = UpdateActions()
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
    let installedVersion = Bundle.main.object(forInfoDictionaryKey: "NextgramVersion") as? String ?? ""
    let versionLabel = installedVersion.isEmpty
        ? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
        : installedVersion
    let state = combineLatest(context.sharedContext.presentationData, actions.state.get())
    |> map { presentationData, update -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let language = presentationData.strings.baseLanguageCode
        var entries: [UpdateRow] = []
        func add(_ id: UpdateRow.Id, _ key: String, suffix: String = "") {
            entries.append(UpdateRow(id: id, title: ngI18n(key, language) + suffix))
        }
        add(.installed, "Nagram.Update.Installed", suffix: " " + versionLabel)

        var release: NextgramUpdateRelease?
        var downloadedPackage: NextgramUpdatePackage?
        switch update {
        case .idle:
            add(.check, "Nagram.Update.Check")
        case .checking:
            add(.status, "Nagram.Update.Checking")
            add(.cancel, "Nagram.Update.Cancel")
        case .current:
            add(.status, "Nagram.Update.Current")
            add(.check, "Nagram.Update.Check")
        case let .available(candidate):
            release = candidate
            add(.status, "Nagram.Update.Available", suffix: " " + candidate.versionName)
            add(.download, "Nagram.Update.Download", suffix: " · " + candidate.assetName)
        case let .downloading(candidate):
            release = candidate
            add(.status, "Nagram.Update.Downloading")
            add(.cancel, "Nagram.Update.Cancel")
        case let .downloaded(candidate, downloaded):
            release = candidate
            downloadedPackage = downloaded
            add(.status, "Nagram.Update.Downloaded")
            add(.export, "Nagram.Update.Export")
        case let .failed(key, candidate):
            release = candidate
            add(.status, key)
            if let candidate {
                add(.download, "Nagram.Update.Download", suffix: " · " + candidate.assetName)
            }
            add(.check, "Nagram.Update.Check")
        }
        add(.release, "Nagram.Update.ReleasePage")

        let perform: (UpdateRow.Id) -> Void = { id in
            switch id {
            case .check:
                actions.check(bundleIdentifier: bundleIdentifier, version: installedVersion)
            case .download:
                if let release {
                    actions.download(release)
                }
            case .cancel:
                actions.cancel(returningTo: release)
            case .export:
                if let downloadedPackage {
                    let picker = UIDocumentPickerViewController(forExporting: [downloadedPackage.url], asCopy: true)
                    context.sharedContext.applicationBindings.presentNativeController(picker)
                }
            case .release:
                UIApplication.shared.open(release?.pageURL ?? NextgramUpdateRelease.releasesPage)
            case .installed, .status:
                break
            }
        }
        let data = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(
            presentationData: data,
            title: .text(ngI18n("Nagram.Update.Title", language)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: data, entries: entries.sorted(), style: .blocks, animateChanges: false)
        return (controllerState, (listState, perform))
    }
    let controller = ItemListController(context: context, state: state)
    controller.navigationPresentation = .default
    return controller
}
