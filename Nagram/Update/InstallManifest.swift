import Foundation

private final class ManifestRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public final class NextgramInstallSession: Sendable {
    public let installationURL: URL
    private let server: LoopbackPackageServer

    private init(installationURL: URL, server: LoopbackPackageServer) {
        self.installationURL = installationURL
        self.server = server
    }

    public static func prepare(_ update: NextgramSignedUpdate) async throws -> NextgramInstallSession {
        try NextgramSigningFiles.checkFiles(for: update)
        let server = try LoopbackPackageServer(package: update.package)
        do {
            let packageURL = try await server.start()
            let url = try await installationURL(packageURL: packageURL, bundleIdentifier: update.bundleIdentifier, build: update.package.build)
            try Task.checkCancellation()
            return NextgramInstallSession(installationURL: url, server: server)
        } catch {
            server.stop()
            throw error
        }
    }

    public func stop() { server.stop() }
    public func transferStarted() async -> Bool { await server.hasStarted() }
    public func transferComplete() async -> Bool { await server.isComplete() }

    deinit {
        server.stop()
    }

    private struct Node: Decodable {
        let code: String
        let base_url: URL
        let enabled: Bool
        let priority: Int

        var isTrusted: Bool {
            return enabled && !code.isEmpty && code.utf8.count <= 24
                && code.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 })
                && base_url.scheme == "https" && base_url.host == code + "-i.lcsignx.com"
                && base_url.user == nil && base_url.password == nil && base_url.fragment == nil
                && (base_url.path.isEmpty || base_url.path == "/") && base_url.query == nil
                && (base_url.port == nil || base_url.port == 443 || (code == "gz" && base_url.port == 8082))
        }
    }

    private static func installationURL(packageURL: URL, bundleIdentifier: String, build: String) async throws -> URL {
        struct NodeList: Decodable { let services: [Node] }
        struct TokenResponse: Decodable { let token: String }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: ManifestRedirectPolicy(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var nodes = ["jp", "cf", "hk"].map { URL(string: "https://\($0)-i.lcsignx.com")! }
        let listURL = URL(string: "https://support.lcsignx.com/install/services")!
        if let (data, response) = try? await session.data(from: listURL), successful(response, at: listURL, data: data),
           let list = try? JSONDecoder().decode(NodeList.self, from: data), list.services.count <= 32 {
            let active = list.services.filter(\.isTrusted).sorted { $0.priority < $1.priority }
            if !active.isEmpty {
                nodes = Array(active.prefix(4).map(\.base_url))
            }
        }
        let payload = try JSONSerialization.data(withJSONObject: [
            "bundle_id": bundleIdentifier, "version": build, "title": "Nextgram", "ipa_url": packageURL.absoluteString
        ])
        for node in nodes {
            try Task.checkCancellation()
            do {
                let endpoint = node.appendingPathComponent("ota").appendingPathComponent("manifest")
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.httpBody = payload
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let (responseData, response) = try await session.data(for: request)
                guard successful(response, at: endpoint, data: responseData),
                      let token = try? JSONDecoder().decode(TokenResponse.self, from: responseData).token,
                      (6...128).contains(token.utf8.count),
                      token.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else {
                    continue
                }
                let manifest = node.appendingPathComponent("ota").appendingPathComponent("m").appendingPathComponent(token)
                let (data, manifestResponse) = try await session.data(from: manifest)
                guard successful(manifestResponse, at: manifest, data: data),
                      matches(data, bundleIdentifier: bundleIdentifier, build: build, packageURL: packageURL) else {
                    continue
                }
                var install = URLComponents()
                install.scheme = "itms-services"
                install.host = ""
                install.queryItems = [URLQueryItem(name: "action", value: "download-manifest"),
                                      URLQueryItem(name: "url", value: manifest.absoluteString)]
                if let url = install.url {
                    return url
                }
            } catch {
                try Task.checkCancellation()
            }
        }
        throw NextgramInstallError.manifest
    }

    private static func successful(_ response: URLResponse, at url: URL, data: Data) -> Bool {
        return (response as? HTTPURLResponse)?.statusCode == 200 && response.url == url && data.count <= 1024 * 1024
    }

    private static func matches(_ data: Data, bundleIdentifier: String, build: String, packageURL: URL) -> Bool {
        guard let manifest = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let items = manifest["items"] as? [[String: Any]], items.count == 1,
              let metadata = items.first?["metadata"] as? [String: Any],
              metadata["bundle-identifier"] as? String == bundleIdentifier,
              metadata["bundle-version"] as? String == build,
              metadata["kind"] as? String == "software",
              let assets = items.first?["assets"] as? [[String: Any]], assets.count == 1,
              assets.first?["kind"] as? String == "software-package" else {
            return false
        }
        return assets.first?["url"] as? String == packageURL.absoluteString
    }
}
