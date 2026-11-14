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

private enum NextgramUpdateMethod: String, CaseIterable {
    case certificate, trollStore

    static var current: Self {
        if let method = Self(rawValue: NagramSettings.shared.updateInstallMethod) { return method }
        let marker = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("_TrollStore")
        return FileManager.default.fileExists(atPath: marker.path) ? .trollStore : .certificate
    }
}

private enum UpdateState: Equatable {
    case idle
    case checking
    case clearing
    case cacheCleared
    case current
    case available(NextgramUpdateRelease)
    case downloading(NextgramUpdateRelease, Int?)
    case downloaded(NextgramUpdateRelease, NextgramUpdatePackage, String?)
    case signing(NextgramUpdateRelease)
    case signed(NextgramUpdateRelease, NextgramUpdatePackage, NextgramSignedUpdate, String?)
    case installing(NextgramUpdateRelease, NextgramUpdatePackage, NextgramSignedUpdate?, Bool)
    case trollStoreResult(NextgramUpdateRelease, NextgramUpdatePackage, String)
    case failed(String, NextgramUpdateRelease?)
}

private struct UpdatePreferences: Equatable {
    let automaticChecks = NagramSettings.shared.autoCheckForUpdates
    let autoPrepare = NagramSettings.shared.updateAutoPrepare
    let method = NextgramUpdateMethod.current
    let preferredNode = NagramSettings.shared.updateLCSignNode
}

@MainActor
private final class UpdateActions {
    let state = ValuePromise<UpdateState>(.idle, ignoreRepeated: false)
    private var task: Task<Void, Never>?
    private var downloadID: UUID?
    private var lastProgress: Int?
    private var installation: NextgramInstallSession?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    func clearCache() {
        guard task == nil else { return }
        state.set(.clearing)
        task = Task { @MainActor [weak self] in
            let succeeded = await Task.detached(priority: .utility) {
                (try? NextgramUpdateClient.clearCache()) != nil
            }.value
            self?.task = nil
            self?.state.set(succeeded ? .cacheCleared : .failed("Nagram.Update.Cache.Error", nil))
        }
    }

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

    func restore(bundleIdentifier: String, installedVersion: String, incomingRelease: NextgramUpdateRelease?) {
        state.set(.checking)
        task = Task { @MainActor [weak self] in
            let restored = await NextgramUpdateClient.restore(bundleIdentifier: bundleIdentifier, installedVersion: installedVersion)
            let restoredSignature: NextgramSignedUpdate?
            if let (release, package) = restored, NextgramUpdateMethod.current == .certificate {
                restoredSignature = await NextgramSigningFiles.restoreSignedUpdate(release: release, package: package)
            } else { restoredSignature = nil }
            if !Task.isCancelled {
                self?.task = nil
                if let (release, package) = restored {
                    if let restoredSignature { self?.state.set(.signed(release, package, restoredSignature, nil)) }
                    else { self?.didDownload(release, package: package) }
                } else if let incomingRelease {
                    self?.didFind(incomingRelease)
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
            do {
                let release = try await NextgramUpdateClient.check(bundleIdentifier: bundleIdentifier, installedVersion: version)
                try Task.checkCancellation()
                self?.task = nil
                if let release {
                    self?.didFind(release)
                } else {
                    self?.state.set(.current)
                }
            } catch {
                if !Task.isCancelled {
                    self?.task = nil
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
                self?.task = nil
                self?.didDownload(release, package: downloadedPackage)
            } catch {
                if !Task.isCancelled {
                    self?.downloadID = nil
                    self?.task = nil
                    self?.state.set(.failed(Self.errorKey(error, fallback: "Nagram.Update.DownloadFailed"), release))
                }
            }
        }
    }

    private func didFind(_ release: NextgramUpdateRelease) {
        if NagramSettings.shared.updateAutoPrepare {
            download(release)
        } else {
            state.set(.available(release))
        }
    }

    private func didDownload(_ release: NextgramUpdateRelease, package: NextgramUpdatePackage) {
        if NagramSettings.shared.updateAutoPrepare, NextgramUpdateMethod.current == .certificate,
           let files = try? NextgramSigningFiles.saved(bundleIdentifier: release.bundleIdentifier),
           let expiration = files.expiration, expiration > Date() {
            sign(release, package: package)
        } else {
            state.set(.downloaded(release, package, nil))
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

    func install(_ release: NextgramUpdateRelease, package: NextgramUpdatePackage, signed: NextgramSignedUpdate?) {
        guard task == nil else { return }
        state.set(.installing(release, package, signed, false))
        let preferredNode = NagramSettings.shared.updateLCSignNode
        task = Task { @MainActor [weak self] in
            func result(_ key: String, trollStoreKey: String? = nil) -> UpdateState {
                if let signed { return .signed(release, package, signed, key) }
                return .trollStoreResult(release, package, trollStoreKey ?? key)
            }
            defer {
                if !Task.isCancelled {
                    self?.stopInstallation()
                    self?.task = nil
                }
            }
            do {
                let session: NextgramInstallSession
                if let signed {
                    session = try await NextgramInstallSession.prepare(signed, preferredNode: preferredNode)
                } else {
                    session = try await Task.detached(priority: .userInitiated) {
                        try await NextgramInstallSession.prepareForTrollStore(package, release: release)
                    }.value
                }
                try Task.checkCancellation()
                guard let self else { return }
                self.installation = session
                self.backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Nextgram update delivery") { [weak self] in
                    Task { @MainActor in
                        guard let self, self.installation === session else { return }
                        self.task?.cancel()
                        self.task = nil
                        self.stopInstallation()
                        self.state.set(result("Nagram.Update.Install.NoTransfer"))
                    }
                }
                guard await UIApplication.shared.open(session.installationURL) else {
                    self.state.set(result("Nagram.Update.Install.Rejected", trollStoreKey: "Nagram.Update.TrollStore.Unavailable"))
                    return
                }
                try Task.checkCancellation()
                for attempt in 0..<300 {
                    if await session.transferComplete() {
                        self.state.set(result("Nagram.Update.Install.Delivered"))
                        return
                    }
                    if attempt == 29 {
                        if await session.transferStarted() {
                            self.state.set(.installing(release, package, signed, true))
                        } else {
                            self.state.set(result("Nagram.Update.Install.NoTransfer"))
                            return
                        }
                    }
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
                self.state.set(result("Nagram.Update.Install.NoTransfer"))
            } catch {
                if !Task.isCancelled {
                    if (error as? NextgramSigningFilesError) == .signingFilesChanged {
                        self?.state.set(.downloaded(release, package, nil))
                    } else {
                        self?.state.set(result("Nagram.Update.Install.Failed"))
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
        case versionHeader, installed, availableVersion, notes, status, signingNotice, check, download, sign, install, cancel, export, release
        case installHeader, method, automaticChecks, automaticPrepare, node, methodHelp
        case signingHeader, signingStatus, importSigningFiles, importProfiles, removeSigningFiles, signingHelp
        case cacheHeader, clearCache, cacheHelp
    }

    let id: Id
    let title: String
    var switchValue: Bool? = nil
    var detail: String? = nil

    var stableId: Int32 {
        return id.rawValue
    }

    var section: ItemListSectionId {
        switch id {
        case .importSigningFiles, .importProfiles, .removeSigningFiles, .signingStatus, .signingHelp, .signingHeader:
            return 2
        case .installHeader, .method, .automaticChecks, .automaticPrepare, .node, .methodHelp:
            return 1
        case .cacheHeader, .clearCache, .cacheHelp:
            return 3
        default:
            return 0
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        if id == .versionHeader || id == .installHeader || id == .signingHeader || id == .cacheHeader {
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: section)
        }
        if id == .status || id == .signingNotice || id == .signingStatus || id == .signingHelp || id == .methodHelp || id == .cacheHelp {
            return ItemListTextItem(presentationData: presentationData, text: .plain(title), sectionId: section)
        }
        let perform = arguments as! @MainActor (Id) -> Void
        if let detail {
            let action: (() -> Void)?
            if id == .installed || id == .availableVersion {
                action = nil
            } else {
                action = { Task { @MainActor in perform(id) } }
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title,
                label: detail, sectionId: section, style: .blocks,
                disclosureStyle: action == nil ? .none : .optionArrows, action: action)
        }
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
    return nextgramUpdateController(context: context, incomingRelease: nil)
}

@MainActor
private func nextgramUpdateController(context: AccountContext, incomingRelease: NextgramUpdateRelease?) -> ViewController {
    let actions = UpdateActions()
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
    let signing = NextgramSigningFilesActions(context: context, bundleIdentifier: bundleIdentifier)
    let preferences = ValuePromise(UpdatePreferences(), ignoreRepeated: true)
    let installedVersion = Bundle.main.object(forInfoDictionaryKey: "NextgramVersion") as? String ?? ""
    actions.restore(bundleIdentifier: bundleIdentifier, installedVersion: installedVersion, incomingRelease: incomingRelease)
    let versionLabel = installedVersion.isEmpty
        ? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
        : installedVersion
    let buildLabel = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    let state = combineLatest(context.sharedContext.presentationData, actions.state.get(), signing.status.get(), preferences.get())
    |> deliverOnMainQueue
    |> map { presentationData, update, signingStatus, preferencesValue -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let method = preferencesValue.method
        let language = presentationData.strings.baseLanguageCode
        var entries: [UpdateRow] = []
        func add(_ id: UpdateRow.Id, _ key: String, suffix: String = "") {
            entries.append(UpdateRow(id: id, title: ngI18n(key, language) + suffix))
        }
        add(.versionHeader, "Nagram.Update.VersionSection")
        entries.append(UpdateRow(id: .installed, title: ngI18n("Nagram.Update.Installed", language),
            detail: buildLabel.isEmpty ? versionLabel : "\(versionLabel) (\(buildLabel))"))

        var release: NextgramUpdateRelease?
        var downloadedPackage: NextgramUpdatePackage?
        var signedUpdate: NextgramSignedUpdate?
        var cancelState: UpdateState = .idle
        var updating = false
        switch update {
        case .idle:
            add(.check, "Nagram.Update.Check")
        case .checking:
            updating = true
            add(.status, "Nagram.Update.Checking")
            add(.cancel, "Nagram.Update.Cancel")
        case .clearing:
            updating = true
            add(.status, "Nagram.Update.Cache.Clearing")
        case .cacheCleared:
            add(.status, "Nagram.Update.Cache.Cleared")
            add(.check, "Nagram.Update.Check")
        case .current:
            add(.status, "Nagram.Update.Current")
            add(.check, "Nagram.Update.Check")
        case let .available(candidate):
            release = candidate
            add(.download, "Nagram.Update.Download", suffix: " · " + candidate.assetName)
        case let .downloading(candidate, progress):
            updating = true
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
            if method == .trollStore {
                add(.install, "Nagram.Update.TrollStore.Install")
            } else if let expiration = signingStatus.expiration, expiration > Date(), !signingStatus.importing {
                add(.sign, "Nagram.Update.Signing.Prepare")
            } else {
                add(.signingNotice, signingStatus.hasCertificate ? "Nagram.Update.Signing.ProfileRequired" : "Nagram.Update.Signing.CertificateRequired")
            }
            add(.export, "Nagram.Update.Export")
            add(.check, "Nagram.Update.Check")
        case let .signing(candidate):
            updating = true
            release = candidate
            add(.status, "Nagram.Update.Signing.Preparing")
        case let .signed(candidate, downloaded, signed, message):
            release = candidate
            downloadedPackage = downloaded
            signedUpdate = signed
            add(.status, message ?? "Nagram.Update.Signing.Ready")
            add(.install, method == .trollStore ? "Nagram.Update.TrollStore.Install" : "Nagram.Update.Install.Action")
            if method == .certificate { add(.sign, "Nagram.Update.Signing.Prepare") }
            add(.export, "Nagram.Update.Export")
        case let .installing(candidate, downloaded, signed, transferring):
            updating = true
            release = candidate
            cancelState = signed.map { UpdateState.signed(candidate, downloaded, $0, nil) } ?? .downloaded(candidate, downloaded, nil)
            add(.status, transferring ? "Nagram.Update.Install.Transferring" : "Nagram.Update.Install.Requesting")
            add(.cancel, "Nagram.Update.Cancel")
        case let .trollStoreResult(candidate, downloaded, message):
            release = candidate
            downloadedPackage = downloaded
            add(.status, message)
            if method == .trollStore {
                add(.install, "Nagram.Update.TrollStore.Install")
            } else if let expiration = signingStatus.expiration, expiration > Date(), !signingStatus.importing {
                add(.sign, "Nagram.Update.Signing.Prepare")
            }
            add(.export, "Nagram.Update.Export")
        case let .failed(key, candidate):
            release = candidate
            add(.status, key)
            if let candidate {
                add(.download, "Nagram.Update.Download", suffix: " · " + candidate.assetName)
            }
            add(.check, "Nagram.Update.Check")
        }
        if let release {
            entries.append(UpdateRow(id: .availableVersion, title: ngI18n("Nagram.Update.Available", language), detail: release.versionName))
            if let notes = release.notes, !notes.isEmpty { add(.notes, "Nagram.Update.ReleaseNotes") }
        }
        add(.release, "Nagram.Update.ReleasePage")
        add(.installHeader, "Nagram.Update.InstallSection")
        let methodTitle = ngI18n("Nagram.Update.Method." + method.rawValue, language)
        if updating || signingStatus.importing {
            add(.methodHelp, "Nagram.Update.Method." + method.rawValue)
        } else {
            entries.append(UpdateRow(id: .method, title: ngI18n("Nagram.Update.Method", language), detail: methodTitle))
            add(.methodHelp, method == .trollStore ? "Nagram.Update.TrollStore.Help" : "Nagram.Update.Install.Consent")
        }
        entries.append(UpdateRow(id: .automaticChecks, title: ngI18n("Nagram.Update.AutomaticChecks", language), switchValue: preferencesValue.automaticChecks))
        if !updating && !signingStatus.importing {
            entries.append(UpdateRow(id: .automaticPrepare, title: ngI18n(method == .certificate ? "Nagram.Update.AutoPrepare" : "Nagram.Update.AutoDownload", language), switchValue: preferencesValue.autoPrepare))
            if method == .certificate {
                entries.append(UpdateRow(id: .node, title: ngI18n("Nagram.Update.Node", language), detail: preferencesValue.preferredNode.isEmpty ? ngI18n("Nagram.Update.Node.Automatic", language) : preferencesValue.preferredNode.uppercased()))
            }
        }
        if method == .certificate {
            add(.signingHeader, "Nagram.Update.SigningSection")
        }
        if method == .certificate && signingStatus.importing {
            add(.signingStatus, "Nagram.Update.Signing.Importing")
        } else if method == .certificate {
            if !updating {
                add(.importSigningFiles, "Nagram.Update.Signing.Import")
                if signingStatus.hasCertificate {
                    add(.importProfiles, "Nagram.Update.Signing.ImportProfiles")
                    add(.removeSigningFiles, "Nagram.Update.Signing.Remove")
                }
            }
            if let errorKey = signingStatus.errorKey {
                add(.signingStatus, errorKey)
            } else if let profileName = signingStatus.profileName, let expiration = signingStatus.expiration {
                if expiration <= Date() {
                    add(.signingStatus, "Nagram.Update.Signing.Expired", suffix: " " + profileName)
                } else {
                    let date = DateFormatter.localizedString(from: expiration, dateStyle: .medium, timeStyle: .none)
                    add(.signingStatus, "Nagram.Update.Signing.Saved", suffix: " \(profileName) · \(signingStatus.profileCount) · \(date)")
                }
            } else if signingStatus.hasCertificate {
                add(.signingStatus, "Nagram.Update.Signing.ProfileRequired")
            }
        }
        if method == .certificate { add(.signingHelp, "Nagram.Update.Signing.Help") }
        if !updating && !signingStatus.importing {
            add(.cacheHeader, "Nagram.Update.Cache.Section")
            add(.clearCache, "Nagram.Update.Cache.Clear")
            add(.cacheHelp, "Nagram.Update.Cache.Help")
        }

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
                if let release, let downloadedPackage, method == .trollStore || signedUpdate != nil {
                    let title = ngI18n("Nagram.Update.Install.Action", language)
                    let alert = UIAlertController(title: title, message: ngI18n(method == .trollStore ? "Nagram.Update.TrollStore.Help" : "Nagram.Update.Install.Consent", language), preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel, handler: nil))
                    alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                        actions.install(release, package: downloadedPackage, signed: method == .trollStore ? nil : signedUpdate)
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
            case .notes:
                guard let notes = release?.notes else { break }
                let controller = UpdateReleaseNotesController()
                controller.title = ngI18n("Nagram.Update.ReleaseNotes", language)
                controller.notes = notes
                controller.navigationItem.rightBarButtonItem = UIBarButtonItem(title: presentationData.strings.Common_Close, style: .done, target: controller, action: #selector(UpdateReleaseNotesController.close))
                context.sharedContext.applicationBindings.presentNativeController(UINavigationController(rootViewController: controller))
            case .method:
                let alert = UIAlertController(title: ngI18n("Nagram.Update.Method", language), message: nil, preferredStyle: .alert)
                for method in NextgramUpdateMethod.allCases {
                    alert.addAction(UIAlertAction(title: ngI18n("Nagram.Update.Method." + method.rawValue, language), style: .default) { _ in
                        NagramSettings.shared.updateInstallMethod = method.rawValue
                        preferences.set(UpdatePreferences())
                    })
                }
                alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
                context.sharedContext.applicationBindings.presentNativeController(alert)
            case .automaticChecks:
                let enabled = !NagramSettings.shared.autoCheckForUpdates
                NagramSettings.shared.autoCheckForUpdates = enabled
                preferences.set(UpdatePreferences())
            case .automaticPrepare:
                NagramSettings.shared.updateAutoPrepare.toggle()
                preferences.set(UpdatePreferences())
            case .node:
                Task { @MainActor in
                    let nodes = await NextgramInstallSession.availableNodes()
                    let alert = UIAlertController(title: ngI18n("Nagram.Update.Node", language), message: nil, preferredStyle: .alert)
                    func choose(_ node: String) {
                        NagramSettings.shared.updateLCSignNode = node
                        preferences.set(UpdatePreferences())
                    }
                    alert.addAction(UIAlertAction(title: ngI18n("Nagram.Update.Node.Automatic", language), style: .default) { _ in choose("") })
                    for node in nodes {
                        alert.addAction(UIAlertAction(title: node.label, style: .default) { _ in choose(node.code) })
                    }
                    alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
                    context.sharedContext.applicationBindings.presentNativeController(alert)
                }
            case .importSigningFiles:
                signing.pick()
            case .importProfiles:
                signing.pick(profilesOnly: true)
            case .removeSigningFiles:
                signing.remove()
            case .clearCache:
                let title = ngI18n("Nagram.Update.Cache.Clear", language)
                let alert = UIAlertController(title: title, message: ngI18n("Nagram.Update.Cache.Help", language), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
                alert.addAction(UIAlertAction(title: title, style: .destructive) { _ in actions.clearCache() })
                context.sharedContext.applicationBindings.presentNativeController(alert)
            case .installed, .availableVersion, .versionHeader, .status, .signingNotice, .installHeader, .methodHelp, .signingHeader, .signingStatus, .signingHelp, .cacheHeader, .cacheHelp:
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

private final class UpdateReleaseNotesController: UIViewController {
    var notes = ""

    override func loadView() {
        let textView = UITextView()
        textView.backgroundColor = .systemBackground
        textView.textColor = .label
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isEditable = false
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.text = notes
        view = textView
    }

    @objc func close() {
        dismiss(animated: true)
    }
}

@MainActor
public func nextgramCheckForUpdateOnForeground(context: AccountContext, openUpdater: @escaping (ViewController) -> Void) {
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
        alert.addAction(UIAlertAction(title: title, style: .default) { _ in
            openUpdater(nextgramUpdateController(context: context, incomingRelease: release))
        })
        context.sharedContext.applicationBindings.presentNativeController(alert)
    }
}
