import AccountContext
import Display
import Foundation
import ItemListUI
import NagramSettings
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
    case downloading(NextgramUpdateRelease, Int?)
    case downloaded(NextgramUpdateRelease, NextgramUpdatePackage, String?)
    case signing(NextgramUpdateRelease)
    case signed(NextgramUpdateRelease, NextgramUpdatePackage, NextgramSignedUpdate, String?)
    case installing(NextgramUpdateRelease, NextgramUpdatePackage, NextgramSignedUpdate, Bool)
    case failed(String, NextgramUpdateRelease?)
}

@MainActor
private final class UpdateActions {
    let state = ValuePromise<UpdateState>(.idle, ignoreRepeated: false)
    private var task: Task<Void, Never>?
    private var downloadID: UUID?
    private var lastProgress: Int?
    private var installation: NextgramInstallSession?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    deinit {
        task?.cancel()
        installation?.stop()
        let identifier = backgroundTask
        if identifier != .invalid {
            Task { @MainActor in
                UIApplication.shared.endBackgroundTask(identifier)
            }
        }
    }

    func restore(bundleIdentifier: String, installedVersion: String) {
        state.set(.checking)
        task = Task { @MainActor [weak self] in
            let restored = await NextgramUpdateClient.restore(bundleIdentifier: bundleIdentifier, installedVersion: installedVersion)
            if !Task.isCancelled {
                self?.task = nil
                if let (release, package) = restored {
                    self?.state.set(.downloaded(release, package, nil))
                } else {
                    self?.state.set(.idle)
                }
            }
        }
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
        let id = UUID()
        downloadID = id
        lastProgress = nil
        state.set(.downloading(release, nil))
        task = Task { @MainActor [weak self] in
            defer {
                if !Task.isCancelled {
                    self?.downloadID = nil
                    self?.task = nil
                }
            }
            do {
                let downloadedPackage = try await NextgramUpdateClient.download(release, progress: { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.downloadID == id, self.lastProgress != progress else { return }
                        self.lastProgress = progress
                        self.state.set(.downloading(release, progress))
                    }
                })
                try Task.checkCancellation()
                self?.downloadID = nil
                self?.state.set(.downloaded(release, downloadedPackage, nil))
            } catch {
                if !Task.isCancelled {
                    self?.downloadID = nil
                    self?.state.set(.failed(Self.errorKey(error, fallback: "Nagram.Update.DownloadFailed"), release))
                }
            }
        }
    }

    func sign(_ release: NextgramUpdateRelease, package: NextgramUpdatePackage) {
        guard task == nil else { return }
        state.set(.signing(release))
        task = Task { @MainActor [weak self] in
            defer { self?.task = nil }
            do {
                let signed = try await Task.detached(priority: .userInitiated) {
                    try NextgramSigningFiles.sign(package, release: release)
                }.value
                try Task.checkCancellation()
                self?.state.set(.signed(release, package, signed, nil))
            } catch {
                if !Task.isCancelled {
                    self?.state.set(.downloaded(release, package, error.localizedDescription))
                }
            }
        }
    }

    func install(_ release: NextgramUpdateRelease, package: NextgramUpdatePackage, signed: NextgramSignedUpdate) {
        guard task == nil else { return }
        state.set(.installing(release, package, signed, false))
        task = Task { @MainActor [weak self] in
            defer {
                if !Task.isCancelled {
                    self?.stopInstallation()
                    self?.task = nil
                }
            }
            do {
                let session = try await NextgramInstallSession.prepare(signed)
                try Task.checkCancellation()
                guard let self else { return }
                self.installation = session
                self.backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Nextgram update delivery") { [weak self] in
                    Task { @MainActor in
                        guard let self, self.installation === session else { return }
                        self.task?.cancel()
                        self.task = nil
                        self.stopInstallation()
                        self.state.set(.signed(release, package, signed, "Nagram.Update.Install.NoTransfer"))
                    }
                }
                guard await UIApplication.shared.open(session.installationURL) else {
                    self.state.set(.signed(release, package, signed, "Nagram.Update.Install.Rejected"))
                    return
                }
                try Task.checkCancellation()
                for attempt in 0..<300 {
                    if await session.transferComplete() {
                        self.state.set(.signed(release, package, signed, "Nagram.Update.Install.Delivered"))
                        return
                    }
                    if attempt == 29 {
                        if await session.transferStarted() {
                            self.state.set(.installing(release, package, signed, true))
                        } else {
                            self.state.set(.signed(release, package, signed, "Nagram.Update.Install.NoTransfer"))
                            return
                        }
                    }
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
                self.state.set(.signed(release, package, signed, "Nagram.Update.Install.NoTransfer"))
            } catch {
                if !Task.isCancelled {
                    if (error as? NextgramSigningFilesError) == .signingFilesChanged {
                        self?.state.set(.downloaded(release, package, nil))
                    } else {
                        self?.state.set(.signed(release, package, signed, "Nagram.Update.Install.Failed"))
                    }
                }
            }
        }
    }

    private func stopInstallation() {
        installation?.stop()
        installation = nil
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    func cancel(returningTo previous: UpdateState) {
        task?.cancel()
        task = nil
        downloadID = nil
        stopInstallation()
        state.set(previous)
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
        case installed, status, check, download, sign, install, cancel, export, release, automaticChecks
        case importSigningFiles, removeSigningFiles, signingStatus, signingHelp
    }

    let id: Id
    let title: String
    var switchValue: Bool? = nil

    var stableId: Int32 {
        return id.rawValue
    }

    var section: ItemListSectionId {
        switch id {
        case .installed, .status:
            return 0
        case .importSigningFiles, .removeSigningFiles, .signingStatus, .signingHelp:
            return 2
        default:
            return 1
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        if section == 0 || id == .signingStatus || id == .signingHelp {
            return ItemListTextItem(presentationData: presentationData, text: .plain(title), sectionId: section)
        }
        let perform = arguments as! @MainActor (Id) -> Void
        if let switchValue {
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: switchValue,
                                      sectionId: section, style: .blocks, updated: { _ in
                Task { @MainActor in perform(id) }
            })
        }
        return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title,
                                  kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: {
            Task { @MainActor in
                perform(id)
            }
        })
    }
}

@MainActor
public func nextgramUpdateController(context: AccountContext) -> ViewController {
    let actions = UpdateActions()
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
    let signing = NextgramSigningFilesActions(context: context, bundleIdentifier: bundleIdentifier)
    let autoCheck = ValuePromise(NagramSettings.shared.autoCheckForUpdates, ignoreRepeated: true)
    let installedVersion = Bundle.main.object(forInfoDictionaryKey: "NextgramVersion") as? String ?? ""
    actions.restore(bundleIdentifier: bundleIdentifier, installedVersion: installedVersion)
    let versionLabel = installedVersion.isEmpty
        ? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
        : installedVersion
    let state = combineLatest(context.sharedContext.presentationData, actions.state.get(), signing.status.get(), autoCheck.get())
    |> deliverOnMainQueue
    |> map { presentationData, update, signingStatus, automaticChecks -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let language = presentationData.strings.baseLanguageCode
        var entries: [UpdateRow] = []
        func add(_ id: UpdateRow.Id, _ key: String, suffix: String = "") {
            entries.append(UpdateRow(id: id, title: ngI18n(key, language) + suffix))
        }
        add(.installed, "Nagram.Update.Installed", suffix: " " + versionLabel)

        var release: NextgramUpdateRelease?
        var downloadedPackage: NextgramUpdatePackage?
        var signedUpdate: NextgramSignedUpdate?
        var cancelState: UpdateState = .idle
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
        case let .downloading(candidate, progress):
            release = candidate
            cancelState = .available(candidate)
            add(.status, "Nagram.Update.Downloading", suffix: progress.map { " \($0)%" } ?? "")
            add(.cancel, "Nagram.Update.Cancel")
        case let .downloaded(candidate, downloaded, signingError):
            release = candidate
            downloadedPackage = downloaded
            if let signingError {
                add(.status, "Nagram.Update.Signing.Failed", suffix: "\n" + signingError)
            } else {
                add(.status, "Nagram.Update.Downloaded")
            }
            if let expiration = signingStatus.expiration, expiration > Date(), !signingStatus.importing {
                add(.sign, "Nagram.Update.Signing.Prepare")
            }
            add(.export, "Nagram.Update.Export")
            add(.check, "Nagram.Update.Check")
        case let .signing(candidate):
            release = candidate
            add(.status, "Nagram.Update.Signing.Preparing")
        case let .signed(candidate, downloaded, signed, message):
            release = candidate
            downloadedPackage = downloaded
            signedUpdate = signed
            add(.status, message ?? "Nagram.Update.Signing.Ready")
            add(.install, "Nagram.Update.Install.Action")
            add(.sign, "Nagram.Update.Signing.Prepare")
            add(.export, "Nagram.Update.Export")
        case let .installing(candidate, downloaded, signed, transferring):
            release = candidate
            cancelState = .signed(candidate, downloaded, signed, nil)
            add(.status, transferring ? "Nagram.Update.Install.Transferring" : "Nagram.Update.Install.Requesting")
            add(.cancel, "Nagram.Update.Cancel")
        case let .failed(key, candidate):
            release = candidate
            add(.status, key)
            if let candidate {
                add(.download, "Nagram.Update.Download", suffix: " · " + candidate.assetName)
            }
            add(.check, "Nagram.Update.Check")
        }
        add(.release, "Nagram.Update.ReleasePage")
        entries.append(UpdateRow(id: .automaticChecks, title: ngI18n("Nagram.Update.AutomaticChecks", language), switchValue: automaticChecks))
        if signingStatus.importing {
            add(.signingStatus, "Nagram.Update.Signing.Importing")
        } else {
            add(.importSigningFiles, "Nagram.Update.Signing.Import")
            if signingStatus.profileName != nil {
                add(.removeSigningFiles, "Nagram.Update.Signing.Remove")
            }
            if let errorKey = signingStatus.errorKey {
                add(.signingStatus, errorKey)
            } else if let profileName = signingStatus.profileName, let expiration = signingStatus.expiration {
                if expiration <= Date() {
                    add(.signingStatus, "Nagram.Update.Signing.Expired", suffix: " " + profileName)
                } else {
                    add(.signingStatus, "Nagram.Update.Signing.Saved", suffix: " " + profileName)
                }
            }
        }
        add(.signingHelp, "Nagram.Update.Signing.Help")

        let perform: @MainActor (UpdateRow.Id) -> Void = { id in
            switch id {
            case .check:
                actions.check(bundleIdentifier: bundleIdentifier, version: installedVersion)
            case .download:
                if let release {
                    actions.download(release)
                }
            case .cancel:
                actions.cancel(returningTo: cancelState)
            case .sign:
                if let release, let downloadedPackage {
                    actions.sign(release, package: downloadedPackage)
                }
            case .install:
                if let release, let downloadedPackage, let signedUpdate {
                    let title = ngI18n("Nagram.Update.Install.Action", language)
                    let alert = UIAlertController(title: title, message: ngI18n("Nagram.Update.Install.Consent", language), preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel, handler: nil))
                    alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                        actions.install(release, package: downloadedPackage, signed: signedUpdate)
                    })
                    context.sharedContext.applicationBindings.presentNativeController(alert)
                }
            case .export:
                if let url = signedUpdate?.url ?? downloadedPackage?.url {
                    let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
                    context.sharedContext.applicationBindings.presentNativeController(picker)
                }
            case .release:
                UIApplication.shared.open(release?.pageURL ?? NextgramUpdateRelease.releasesPage)
            case .automaticChecks:
                let enabled = !NagramSettings.shared.autoCheckForUpdates
                NagramSettings.shared.autoCheckForUpdates = enabled
                autoCheck.set(enabled)
            case .importSigningFiles:
                signing.pick()
            case .removeSigningFiles:
                signing.remove()
            case .installed, .status, .signingStatus, .signingHelp:
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

@MainActor
public func nextgramCheckForUpdateOnForeground(context: AccountContext, openUpdater: @escaping () -> Void) {
    guard NagramSettings.shared.autoCheckForUpdates, NagramSettings.shared.usageAgreementAcceptedVersion > 0,
          let bundleIdentifier = Bundle.main.bundleIdentifier,
          let version = Bundle.main.object(forInfoDictionaryKey: "NextgramVersion") as? String else {
        return
    }
    let defaults = UserDefaults.standard
    let key = "nextgram.update.lastAutomaticCheck"
    let now = Date()
    if let lastCheck = defaults.object(forKey: key) as? Date, lastCheck <= now,
       now.timeIntervalSince(lastCheck) < 6 * 60 * 60 {
        return
    }
    defaults.set(now, forKey: key)
    Task { @MainActor in
        guard let release = try? await NextgramUpdateClient.check(bundleIdentifier: bundleIdentifier, installedVersion: version),
              NagramSettings.shared.autoCheckForUpdates, UIApplication.shared.applicationState == .active else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let language = presentationData.strings.baseLanguageCode
        let title = ngI18n("Nagram.Update.Title", language)
        let message = ngI18n("Nagram.Update.Available", language) + " " + release.versionName
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: title, style: .default) { _ in openUpdater() })
        context.sharedContext.applicationBindings.presentNativeController(alert)
    }
}
