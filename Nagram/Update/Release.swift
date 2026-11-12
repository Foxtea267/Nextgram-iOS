import Foundation

public enum NextgramUpdateError: Error {
    case unsupportedInstallation
    case invalidRelease
    case unavailableAsset
    case invalidDownload
    case invalidPackage
}

struct NextgramReleaseVersion: Comparable, Codable, Sendable {
    let value: String
    private let components: [UInt32]

    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            return nil
        }
        let components = parts.compactMap { part -> UInt32? in
            guard let number = UInt32(part), String(number) == part else {
                return nil
            }
            return number
        }
        guard components.count == 4 else {
            return nil
        }
        self.value = value
        self.components = components
    }

    var baseVersion: String {
        return value.split(separator: ".").prefix(3).joined(separator: ".")
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

public struct NextgramUpdateRelease: Equatable, Codable, Sendable {
    static let repository = "Foxtea267/Nextgram-iOS"
    public static let releasesPage = URL(string: "https://github.com/\(repository)/releases")!
    static let latestEndpoint = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let state: String
            let size: Int64
            let digest: String?
            let browser_download_url: URL
        }

        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }

    private static let assetNames = [
        "xyz.nextalone.nagram": "Nextgram-Nagram.ipa",
        "app.nicegram": "Nextgram-Nicegram.ipa",
        "com.olcorporation.olai": "Nextgram-OLAI.ipa",
        "com.seastar.turrit": "Nextgram-Turrit.ipa"
    ]

    let version: NextgramReleaseVersion
    let bundleIdentifier: String
    public let assetName: String
    let downloadURL: URL
    let size: Int64
    let sha256: String

    public var versionName: String {
        return version.value
    }

    public var pageURL: URL {
        return Self.releasesPage.appendingPathComponent("tag").appendingPathComponent(version.value)
    }

    static func parse(_ data: Data, bundleIdentifier: String, installedVersion: String) throws -> Self? {
        guard let current = NextgramReleaseVersion(installedVersion),
              let assetName = assetNames[bundleIdentifier] else {
            throw NextgramUpdateError.unsupportedInstallation
        }
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
              !release.draft, !release.prerelease else {
            throw NextgramUpdateError.invalidRelease
        }
        guard let version = NextgramReleaseVersion(release.tag_name) else {
            throw NextgramUpdateError.unavailableAsset
        }
        guard version > current else {
            return nil
        }
        let matching = release.assets.filter { $0.name == assetName }
        let expectedURL = releasesPage.appendingPathComponent("download")
            .appendingPathComponent(version.value).appendingPathComponent(assetName)
        guard matching.count == 1, let asset = matching.first,
              asset.state == "uploaded", asset.size > 0, asset.size <= 1024 * 1024 * 1024,
              asset.browser_download_url.absoluteString == expectedURL.absoluteString,
              let digest = asset.digest, digest.hasPrefix("sha256:") else {
            throw NextgramUpdateError.unavailableAsset
        }
        let sha256 = digest.dropFirst("sha256:".count).lowercased()
        guard sha256.utf8.count == 64, sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw NextgramUpdateError.unavailableAsset
        }
        return Self(version: version, bundleIdentifier: bundleIdentifier, assetName: assetName,
                    downloadURL: expectedURL, size: asset.size, sha256: sha256)
    }

    static func supports(bundleIdentifier: String, version: String) -> Bool {
        return assetNames[bundleIdentifier] != nil && NextgramReleaseVersion(version) != nil
    }

    func isApplicable(bundleIdentifier: String, installedVersion: String) -> Bool {
        guard let installed = NextgramReleaseVersion(installedVersion) else { return false }
        return self.bundleIdentifier == bundleIdentifier && Self.assetNames[bundleIdentifier] == assetName
            && NextgramReleaseVersion(version.value) == version && version > installed
            && size > 0 && size <= 1024 * 1024 * 1024
            && sha256.utf8.count == 64 && sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
            && downloadURL == Self.releasesPage.appendingPathComponent("download")
                .appendingPathComponent(version.value).appendingPathComponent(assetName)
    }

    func matchesPackageInfo(_ info: [String: Any]) -> Bool {
        return info["CFBundleIdentifier"] as? String == bundleIdentifier
            && info["CFBundleDisplayName"] as? String == "Nextgram"
            && info["CFBundlePackageType"] as? String == "APPL"
            && info["CFBundleShortVersionString"] as? String == version.baseVersion
            && info["NextgramVersion"] as? String == version.value
    }
}
