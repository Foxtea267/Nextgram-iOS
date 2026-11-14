import AccountContext
import Foundation
import NagramStrings
import NextgramUpdate
import SwiftSignalKit
import UIKit
import UniformTypeIdentifiers

@MainActor
final class NextgramSigningFilesActions: NSObject, UIDocumentPickerDelegate {
    struct Status: Equatable {
        var profileName: String?
        var expiration: Date?
        var profileCount = 0
        var hasCertificate = false
        var errorKey: String?
        var importing = false
    }

    let status = ValuePromise<Status>(Status(), ignoreRepeated: true)
    private let context: AccountContext
    private let bundleIdentifier: String
    private var current = Status()

    init(context: AccountContext, bundleIdentifier: String) {
        self.context = context
        self.bundleIdentifier = bundleIdentifier
        super.init()
        reload()
    }

    func pick(profilesOnly: Bool = false) {
        guard !current.importing else {
            return
        }
        self.profilesOnly = profilesOnly
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        context.sharedContext.applicationBindings.presentNativeController(picker)
    }

    private var profilesOnly = false

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let profilesOnly = self.profilesOnly
        current.errorKey = nil
        current.importing = true
        status.set(current)
        let read: () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let files = try await Task.detached(priority: .userInitiated) { try NextgramSigningImport.read(urls) }.value
                    if profilesOnly, files.certificate != nil { throw NextgramSigningFilesError.invalidFileSelection }
                    if let certificate = files.certificate {
                        self.requestPassword(certificate: certificate, name: files.certificateName ?? "", profiles: files.profiles)
                    } else {
                        self.importFiles(certificate: nil, password: "", profiles: files.profiles)
                    }
                } catch {
                    self.setError("Nagram.Update.Signing.Selection")
                }
            }
        }
        if controller.presentingViewController != nil {
            controller.dismiss(animated: true, completion: read)
        } else {
            read()
        }
    }

    func remove() {
        guard !current.importing else {
            return
        }
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let lang = data.strings.baseLanguageCode
        let title = ngI18n("Nagram.Update.Signing.Remove", lang)
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: data.strings.Common_Cancel, style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: title, style: .destructive) { [weak self] _ in
            guard let self else {
                return
            }
            do {
                try NextgramSigningFiles.remove(bundleIdentifier: self.bundleIdentifier)
                self.reload()
            } catch {
                self.setError("Nagram.Update.Signing.Storage")
            }
        })
        context.sharedContext.applicationBindings.presentNativeController(alert)
    }

    private func requestPassword(certificate: Data, name: String, profiles: [Data]) {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let lang = data.strings.baseLanguageCode
        let title = ngI18n("Nagram.Update.Signing.Password", lang)
        let alert = UIAlertController(title: title, message: name, preferredStyle: .alert)
        alert.addTextField { field in
            field.isSecureTextEntry = true
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: data.strings.Common_Cancel, style: .cancel) { [weak self] _ in self?.reload() })
        alert.addAction(UIAlertAction(title: ngI18n("Nagram.Update.Signing.Save", lang), style: .default) { [weak self, weak alert] _ in
            let password = alert?.textFields?.first?.text ?? ""
            self?.importFiles(certificate: certificate, password: password, profiles: profiles)
        })
        context.sharedContext.applicationBindings.presentNativeController(alert)
    }

    private func importFiles(certificate: Data?, password: String, profiles: [Data]) {
        current.errorKey = nil
        current.importing = true
        status.set(current)
        let bundleIdentifier = self.bundleIdentifier
        Task { @MainActor [weak self] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    let files: NextgramSigningFiles
                    if let certificate {
                        files = try .validated(certificate: certificate, password: password, profiles: profiles, bundleIdentifier: bundleIdentifier)
                    } else {
                        guard let saved = try NextgramSigningFiles.saved(bundleIdentifier: bundleIdentifier) else {
                            throw NextgramSigningFilesError.missingSigningFiles
                        }
                        files = try saved.addingProfiles(profiles, bundleIdentifier: bundleIdentifier)
                    }
                    try files.save(bundleIdentifier: bundleIdentifier)
                }.value
                self?.reload()
            } catch {
                switch error as? NextgramSigningFilesError {
                case .invalidCertificate:
                    self?.setError("Nagram.Update.Signing.CertificateError")
                case .invalidProfile:
                    self?.setError("Nagram.Update.Signing.ProfileError")
                case .keychain:
                    self?.setError("Nagram.Update.Signing.Storage")
                case .missingSigningFiles:
                    self?.setError("Nagram.Update.Signing.CertificateRequired")
                case .invalidFileSelection, .signingFilesChanged, nil:
                    self?.setError("Nagram.Update.Signing.Selection")
                }
            }
        }
    }


    private func reload() {
        do {
            let files = try NextgramSigningFiles.saved(bundleIdentifier: bundleIdentifier)
            current = Status(profileName: files?.profileName, expiration: files?.expiration, profileCount: files?.profileCount ?? 0, hasCertificate: files != nil)
            status.set(current)
        } catch {
            setError("Nagram.Update.Signing.Storage")
        }
    }

    private func setError(_ key: String) {
        current.importing = false
        current.errorKey = key
        status.set(current)
    }
}
