import CryptoKit
import Foundation
import NextgramUpdateArchive

public final class NextgramUpdatePackage: Equatable, Sendable {
    public let url: URL
    private let directory: URL

    fileprivate init(url: URL, directory: URL) {
        self.url = url
        self.directory = directory
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    public static func == (lhs: NextgramUpdatePackage, rhs: NextgramUpdatePackage) -> Bool {
        return lhs.url == rhs.url
    }
}

private final class NextgramUpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let release: NextgramUpdateRelease

    init(release: NextgramUpdateRelease) {
        self.release = release
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

    public static func download(_ release: NextgramUpdateRelease) async throws -> NextgramUpdatePackage {
        let delegate = NextgramUpdateDownloadDelegate(release: release)
        let session = URLSession(configuration: configuration())
        defer {
            session.finishTasksAndInvalidate()
        }
        let (temporaryURL, response) = try await session.download(for: URLRequest(url: release.downloadURL), delegate: delegate)
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let url = response.url, delegate.isAllowed(url),
              try temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize == Int(release.size) else {
            throw NextgramUpdateError.invalidDownload
        }
        let file = try FileHandle(forReadingFrom: temporaryURL)
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
        do {
            let infoURL = directory.appendingPathComponent("Info.plist")
            guard let info = NextgramUpdateReadAppInfo(temporaryURL.path, infoURL.path), release.matchesPackageInfo(info) else {
                throw NextgramUpdateError.invalidPackage
            }
            try FileManager.default.removeItem(at: infoURL)
            try Task.checkCancellation()
            let destination = directory.appendingPathComponent(release.assetName)
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            return NextgramUpdatePackage(url: destination, directory: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
