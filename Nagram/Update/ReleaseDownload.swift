import CryptoKit
import Foundation
import NextgramUpdateArchive

public final class NextgramUpdatePackage: Equatable, Sendable {
    public let url: URL
    let build: String
    private let temporaryDirectory: URL?

    init(url: URL, directory: URL?, build: String) {
        self.url = url
        self.temporaryDirectory = directory
        self.build = build
    }

    deinit {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    public static func == (lhs: NextgramUpdatePackage, rhs: NextgramUpdatePackage) -> Bool {
        return lhs.url == rhs.url
    }
}

private final class NextgramUpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let release: NextgramUpdateRelease
    private let progress: @Sendable (Int) -> Void

    init(release: NextgramUpdateRelease, progress: @escaping @Sendable (Int) -> Void) {
        self.release = release
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(request.url.map(isAllowed) == true ? request : nil)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesWritten > release.size || totalBytesExpectedToWrite > release.size {
            downloadTask.cancel()
        } else {
            progress(Int(max(0, totalBytesWritten) * 100 / release.size))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // URLSession's async download API supplies the completed file.
    }

    func isAllowed(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || url.port == 443 else {
            return false
        }
        switch url.host {
        case "github.com":
            return url.absoluteString == release.downloadURL.absoluteString
        case "release-assets.githubusercontent.com", "objects.githubusercontent.com":
            return true
        default:
            return false
        }
    }
}

public enum NextgramUpdateClient {
    private static func cacheDirectory() throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("NextgramUpdates", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        return directory
    }

    public static func restore(bundleIdentifier: String, installedVersion: String) async -> (NextgramUpdateRelease, NextgramUpdatePackage)? {
        guard let directory = try? cacheDirectory() else { return nil }
        let manifest = directory.appendingPathComponent("Latest.plist")
        guard let metadata = try? Data(contentsOf: manifest), metadata.count <= 16 * 1024,
              let release = try? PropertyListDecoder().decode(NextgramUpdateRelease.self, from: metadata) else {
            return nil
        }
        guard release.isApplicable(bundleIdentifier: bundleIdentifier, installedVersion: installedVersion) else {
            if release.sha256.utf8.count == 64 && release.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(release.sha256, isDirectory: true))
            }
            try? FileManager.default.removeItem(at: manifest)
            return nil
        }
        let url = directory.appendingPathComponent(release.sha256, isDirectory: true).appendingPathComponent(release.assetName)
        guard let build = try? verify(url, release: release) else { return nil }
        return (release, NextgramUpdatePackage(url: url, directory: nil, build: build))
    }

    private static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    public static func check(bundleIdentifier: String, installedVersion: String) async throws -> NextgramUpdateRelease? {
        guard NextgramUpdateRelease.supports(bundleIdentifier: bundleIdentifier, version: installedVersion) else {
            throw NextgramUpdateError.unsupportedInstallation
        }
        let session = URLSession(configuration: configuration())
        defer {
            session.finishTasksAndInvalidate()
        }
        let endpoint = NextgramUpdateRelease.latestEndpoint
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Nextgram-iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url == endpoint, data.count <= 2 * 1024 * 1024 else {
            throw NextgramUpdateError.invalidRelease
        }
        return try NextgramUpdateRelease.parse(data, bundleIdentifier: bundleIdentifier, installedVersion: installedVersion)
    }

    public static func download(_ release: NextgramUpdateRelease, progress: @escaping @Sendable (Int) -> Void) async throws -> NextgramUpdatePackage {
        if let cache = try? cacheDirectory() {
            let cached = cache.appendingPathComponent(release.sha256, isDirectory: true).appendingPathComponent(release.assetName)
            if let build = try? verify(cached, release: release) {
                return NextgramUpdatePackage(url: cached, directory: nil, build: build)
            }
        }
        try Task.checkCancellation()
        let delegate = NextgramUpdateDownloadDelegate(release: release, progress: progress)
        let session = URLSession(configuration: configuration())
        defer {
            session.finishTasksAndInvalidate()
        }
        let (temporaryURL, response) = try await session.download(for: URLRequest(url: release.downloadURL), delegate: delegate)
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let url = response.url, delegate.isAllowed(url) else {
            throw NextgramUpdateError.invalidDownload
        }
        let build = try verify(temporaryURL, release: release)
        try Task.checkCancellation()
        let manager = FileManager.default
        if let cache = try? cacheDirectory() {
            let folder = cache.appendingPathComponent(release.sha256, isDirectory: true)
            let destination = folder.appendingPathComponent(release.assetName)
            do {
                try manager.createDirectory(at: folder, withIntermediateDirectories: true)
                if manager.fileExists(atPath: destination.path) {
                    _ = try manager.replaceItemAt(destination, withItemAt: temporaryURL)
                } else {
                    try manager.moveItem(at: temporaryURL, to: destination)
                }
                if let metadata = try? PropertyListEncoder().encode(release) {
                    try? metadata.write(to: cache.appendingPathComponent("Latest.plist"), options: .atomic)
                }
                return NextgramUpdatePackage(url: destination, directory: nil, build: build)
            } catch {
                // A full cache volume can still allow a one-time update from the download directory.
            }
        }
        let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        let destination = directory.appendingPathComponent(release.assetName)
        do {
            try manager.moveItem(at: temporaryURL, to: destination)
            return NextgramUpdatePackage(url: destination, directory: directory, build: build)
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    static func verify(_ url: URL, release: NextgramUpdateRelease) throws -> String {
        guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == Int(release.size) else {
            throw NextgramUpdateError.invalidDownload
        }
        let file = try FileHandle(forReadingFrom: url)
        defer {
            try? file.close()
        }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == release.sha256 else {
            throw NextgramUpdateError.invalidDownload
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let infoURL = directory.appendingPathComponent("Info.plist")
        guard let info = NextgramUpdateReadAppInfo(url.path, infoURL.path), release.matchesPackageInfo(info),
              let build = info["CFBundleVersion"] as? String, build.utf8.count <= 24,
              !build.isEmpty, build.utf8.allSatisfy({ (48...57).contains($0) || $0 == 46 }),
              build.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ UInt64($0) != nil }) else {
            throw NextgramUpdateError.invalidPackage
        }
        return build
    }
}
