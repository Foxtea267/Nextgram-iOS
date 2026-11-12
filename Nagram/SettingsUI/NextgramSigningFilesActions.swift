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

    func pick() {
        guard !current.importing else {
            return
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: false)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        context.sharedContext.applicationBindings.presentNativeController(picker)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let certificates = urls.filter { ["p12", "pfx"].contains($0.pathExtension.lowercased()) }
        let profiles = urls.filter { $0.pathExtension.lowercased() == "mobileprovision" }
        guard certificates.count == 1, let certificate = certificates.first, urls.count <= 16,
              urls.count == certificates.count + profiles.count else {
            setError("Nagram.Update.Signing.Selection")
            return
        }
        if controller.presentingViewController != nil {
            controller.dismiss(animated: true) { [weak self] in
                self?.requestPassword(certificate: certificate, profiles: profiles)
            }
        } else {
            requestPassword(certificate: certificate, profiles: profiles)
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

    private func requestPassword(certificate: URL, profiles: [URL]) {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let lang = data.strings.baseLanguageCode
        let title = ngI18n("Nagram.Update.Signing.Password", lang)
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.isSecureTextEntry = true
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: data.strings.Common_Cancel, style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: ngI18n("Nagram.Update.Signing.Save", lang), style: .default) { [weak self, weak alert] _ in
            let password = alert?.textFields?.first?.text ?? ""
            self?.importFiles(certificate: certificate, password: password, profiles: profiles)
        })
        context.sharedContext.applicationBindings.presentNativeController(alert)
    }

    private func importFiles(certificate: URL, password: String, profiles: [URL]) {
        current.errorKey = nil
        current.importing = true
        status.set(current)
        let bundleIdentifier = self.bundleIdentifier
        Task { @MainActor [weak self] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    let files = try NextgramSigningFiles.validated(
                        certificate: Self.read(certificate),
                        password: password,
                        profiles: profiles.map(Self.read),
                        bundleIdentifier: bundleIdentifier
                    )
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
                case .invalidFileSelection, .missingSigningFiles, .signingFilesChanged, nil:
                    self?.setError("Nagram.Update.Signing.Selection")
                }
            }
        }
    }

    nonisolated private static func read(_ url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result {
                let maxSize = 4 * 1024 * 1024
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maxSize else {
                    throw NextgramSigningFilesError.invalidFileSelection
                }
                let file = try FileHandle(forReadingFrom: url)
                defer {
                    try? file.close()
                }
                guard let data = try file.read(upToCount: maxSize + 1), data.count == size else {
                    throw NextgramSigningFilesError.invalidFileSelection
                }
                return data
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        guard let result else {
            throw NextgramSigningFilesError.invalidFileSelection
        }
        return try result.get()
    }

    private func reload() {
        do {
            let files = try NextgramSigningFiles.saved(bundleIdentifier: bundleIdentifier)
            current = Status(profileName: files?.profileName, expiration: files?.expiration)
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
