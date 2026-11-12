import CryptoKit
import Foundation
import NextgramUpdateSigner
import Security

public enum NextgramSigningFilesError: Error, Equatable {
    case invalidFileSelection
    case invalidCertificate
    case invalidProfile
    case keychain
    case missingSigningFiles
    case signingFilesChanged
}

public struct NextgramSigningFiles: Codable, Sendable {
    private let certificate: Data
    private let password: String
    private let profile: Data
    private let additionalProfiles: [Data]?
    public let profileName: String
    public let expiration: Date

    private var fingerprint: Data {
        var hash = SHA256()
        hash.update(data: Data(SHA256.hash(data: certificate)))
        for profile in [profile] + (additionalProfiles ?? []) {
            hash.update(data: Data(SHA256.hash(data: profile)))
        }
        return Data(hash.finalize())
    }

    public static func sign(_ package: NextgramUpdatePackage, release: NextgramUpdateRelease) throws -> NextgramSignedUpdate {
        guard let files = try saved(bundleIdentifier: release.bundleIdentifier), files.expiration > Date() else {
            throw NextgramSigningFilesError.missingSigningFiles
        }
        guard try NextgramUpdateClient.verify(package.url, release: release) == package.build else {
            throw NextgramUpdateError.invalidPackage
        }
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            let scratch = directory.appendingPathComponent("Signing", isDirectory: true)
            try manager.createDirectory(at: scratch, withIntermediateDirectories: false)
            defer {
                try? manager.removeItem(at: scratch)
            }
            let destination = directory.appendingPathComponent("Signed-" + release.assetName)
            if let error = NextgramSignUpdateIPA(package.url.path, destination.path, Bundle.main.bundlePath,
                                                 scratch.path, release.versionName, files.certificate, files.password,
                                                 [files.profile] + (files.additionalProfiles ?? [])) {
                throw error
            }
            let signed = NextgramUpdatePackage(url: destination, directory: directory, build: package.build)
            return NextgramSignedUpdate(package: signed, bundleIdentifier: release.bundleIdentifier, signingFingerprint: files.fingerprint)
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    static func checkFiles(for update: NextgramSignedUpdate) throws {
        guard let files = try saved(bundleIdentifier: update.bundleIdentifier), files.expiration > Date(),
              files.fingerprint == update.signingFingerprint else {
            throw NextgramSigningFilesError.signingFilesChanged
        }
    }

    public static func validated(certificate: Data, password: String, profiles: [Data], bundleIdentifier: String) throws -> Self {
        var result: CFArray?
        let options = [kSecImportExportPassphrase as String: password]
        guard SecPKCS12Import(certificate as CFData, options as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else {
            throw NextgramSigningFilesError.invalidCertificate
        }
        let identities = items.compactMap { $0[kSecImportItemIdentity as String] }
        guard identities.count == 1, let identityValue = identities.first,
              CFGetTypeID(identityValue as CFTypeRef) == SecIdentityGetTypeID() else {
            throw NextgramSigningFilesError.invalidCertificate
        }
        let identity = identityValue as! SecIdentity
        var signingCertificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &signingCertificate) == errSecSuccess, let signingCertificate else {
            throw NextgramSigningFilesError.invalidCertificate
        }
        let certificateData = SecCertificateCopyData(signingCertificate) as Data

        var candidates = profiles
        if let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
           let embedded = try? Data(contentsOf: url), !candidates.contains(embedded) {
            candidates.append(embedded)
        }
        guard !bundleIdentifier.isEmpty, profiles.count <= 15,
              profiles.reduce(certificate.count, { $0 + $1.count }) <= 4 * 1024 * 1024,
              profiles.allSatisfy({ profileInfo($0, certificate: certificateData) != nil }) else {
            throw NextgramSigningFilesError.invalidProfile
        }
        for profile in candidates {
            guard let info = profileInfo(profile, certificate: certificateData),
                  info.pattern == bundleIdentifier || info.pattern == "*" ||
                    (info.pattern.hasSuffix(".*") && bundleIdentifier.hasPrefix(info.pattern.dropLast())) else {
                continue
            }
            return Self(certificate: certificate, password: password, profile: profile,
                        additionalProfiles: profiles.filter { $0 != profile },
                        profileName: String(info.name.prefix(120)), expiration: info.expiration)
        }
        throw NextgramSigningFilesError.invalidProfile
    }

    // Pair files before saving. The signer checks permissions against the installed code signature.
    private static func profileInfo(_ profile: Data, certificate: Data) -> (pattern: String, name: String, expiration: Date)? {
        guard let payload = profilePayload(profile),
              let plist = try? PropertyListSerialization.propertyList(from: payload, format: nil) as? [String: Any],
              let expiration = plist["ExpirationDate"] as? Date, expiration > Date(),
              let profileName = plist["Name"] as? String, !profileName.isEmpty,
              let certificates = plist["DeveloperCertificates"] as? [Data], certificates.contains(certificate),
              let entitlements = plist["Entitlements"] as? [String: Any],
              let identifier = entitlements["application-identifier"] as? String,
              let separator = identifier.firstIndex(of: "."),
              let prefixes = plist["ApplicationIdentifierPrefix"] as? [String],
              prefixes.contains(String(identifier[..<separator])) else {
            return nil
        }
        let pattern = String(identifier[identifier.index(after: separator)...])
        return (pattern, profileName, expiration)
    }

    public static func saved(bundleIdentifier: String) throws -> Self? {
        var query = keychainQuery(bundleIdentifier)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = value as? Data,
              let files = try? PropertyListDecoder().decode(Self.self, from: data) else {
            throw NextgramSigningFilesError.keychain
        }
        return files
    }

    public func save(bundleIdentifier: String) throws {
        let data = try PropertyListEncoder().encode(self)
        let query = Self.keychainQuery(bundleIdentifier)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
            return
        }
        if status == errSecItemNotFound {
            var entry = query
            entry[kSecValueData as String] = data
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            if SecItemAdd(entry as CFDictionary, nil) == errSecSuccess {
                return
            }
        }
        throw NextgramSigningFilesError.keychain
    }

    public static func remove(bundleIdentifier: String) throws {
        let status = SecItemDelete(keychainQuery(bundleIdentifier) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NextgramSigningFilesError.keychain
        }
    }

    private static func keychainQuery(_ bundleIdentifier: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "jp.foxtea.nextgram.update-signing",
            kSecAttrAccount as String: bundleIdentifier,
            kSecAttrSynchronizable as String: false
        ]
    }

    private static func profilePayload(_ profile: Data) -> Data? {
        let signedDataOID = Data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02])
        let dataOID = Data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x01])
        var envelope = DERReader(profile)
        guard var contentInfo = envelope.read(0x30), envelope.isEmpty,
              contentInfo.read(0x06)?.data == signedDataOID,
              var wrapper = contentInfo.read(0xa0), contentInfo.isEmpty,
              var signedData = wrapper.read(0x30), wrapper.isEmpty,
              signedData.read(0x02) != nil, signedData.read(0x31) != nil,
              var encapsulated = signedData.read(0x30), encapsulated.read(0x06)?.data == dataOID,
              var content = encapsulated.read(0xa0), encapsulated.isEmpty,
              let octets = content.read(0x04), content.isEmpty else {
            return nil
        }
        return octets.data
    }
}

public struct NextgramSignedUpdate: Equatable, Sendable {
    let package: NextgramUpdatePackage
    let bundleIdentifier: String
    let signingFingerprint: Data

    public var url: URL { package.url }
}

private struct DERReader {
    private let bytes: Data
    private let end: Int
    private var offset: Int

    init(_ bytes: Data, start: Int? = nil, end: Int? = nil) {
        self.bytes = bytes
        self.offset = start ?? bytes.startIndex
        self.end = end ?? bytes.endIndex
    }

    var isEmpty: Bool { offset == end }
    var data: Data { Data(bytes[offset..<end]) }

    mutating func read(_ tag: UInt8) -> Self? {
        guard end - offset >= 2, bytes[offset] == tag else {
            return nil
        }
        let firstLength = Int(bytes[offset + 1])
        offset += 2
        var length = firstLength
        if firstLength >= 0x80 {
            let lengthBytes = firstLength & 0x7f
            guard (1...4).contains(lengthBytes), end - offset >= lengthBytes, bytes[offset] != 0 else {
                return nil
            }
            length = 0
            for _ in 0..<lengthBytes {
                length = (length << 8) | Int(bytes[offset])
                offset += 1
            }
            guard length >= 0x80 else {
                return nil
            }
        }
        guard length <= end - offset else {
            return nil
        }
        let start = offset
        offset += length
        return Self(bytes, start: start, end: offset)
    }
}
