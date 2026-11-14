import CryptoKit
import Foundation

public enum NextgramFontDownload: CaseIterable {
    case sourceSans3, notoSerifSC

    public var name: String { self == .sourceSans3 ? "Source Sans 3" : "Noto Serif SC" }
    private var folder: String { self == .sourceSans3 ? "sourcesans3" : "notoserifsc" }
    private var filename: String { self == .sourceSans3 ? "SourceSans3[wght].ttf" : "NotoSerifSC[wght].ttf" }
    fileprivate var size: Int { self == .sourceSans3 ? 646340 : 25125512 }
    fileprivate var digest: String {
        self == .sourceSans3 ? "042fe2cc0b933e328410d7acbd0aa6a1873dca5aef81875f4bc214b08825c7b9" : "050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"
    }
    private var base: URL {
        URL(string: "https://raw.githubusercontent.com/google/fonts/cc39c4c2c304bc368c9b7c311ea2bcc6013299fe/ofl/")!.appendingPathComponent(self.folder)
    }
    public var licenseURL: URL { self.base.appendingPathComponent("OFL.txt") }
    public var sourceURL: URL { self.base.appendingPathComponent(self.filename) }
    public var sizeDescription: String { ByteCountFormatter.string(fromByteCount: Int64(self.size), countStyle: .file) }

    /// Explicit user action only. Fixed source revision and SHA-256; no credentials, cookies or rendering-time requests.
    public func download(completion: @escaping (Result<[NextgramImportedFont], Error>) -> Void) -> NextgramFontDownloadRequest {
        return NextgramFontDownloadRequest(font: self, completion: completion)
    }
}

public final class NextgramFontDownloadRequest: NSObject, URLSessionDataDelegate {
    private let font: NextgramFontDownload
    private var session: URLSession?
    private var data = Data()
    private var statusCode = 0
    private var cancelled = false
    private let lock = NSLock()
    private var completion: ((Result<[NextgramImportedFont], Error>) -> Void)?

    fileprivate init(font: NextgramFontDownload, completion: @escaping (Result<[NextgramImportedFont], Error>) -> Void) {
        self.font = font
        self.completion = completion
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        session.dataTask(with: font.sourceURL).resume()
    }
    public func cancel() {
        self.lock.lock(); self.cancelled = true; self.completion = nil; self.lock.unlock()
        self.session?.invalidateAndCancel()
    }
    private var isCancelled: Bool { self.lock.lock(); defer { self.lock.unlock() }; return self.cancelled }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        completionHandler(self.statusCode == 200 && response.expectedContentLength <= Int64(self.font.size) ? .allow : .cancel)
    }
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard self.data.count + data.count <= self.font.size else { dataTask.cancel(); return }
        self.data.append(data)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { self.session = nil; session.finishTasksAndInvalidate() }
        guard !self.isCancelled else { return }
        let result: Result<[NextgramImportedFont], Error>
        do {
            if let error { throw error }
            guard self.statusCode == 200, self.data.count == self.font.size,
                  SHA256.hash(data: self.data).map({ String(format: "%02x", $0) }).joined() == self.font.digest else { throw NextgramFontError.invalidFile }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent("font.ttf")
            try self.data.write(to: file, options: .atomic)
            guard !self.isCancelled else { return }
            result = .success(try NextgramTypography.shared.importFile(file))
        } catch { result = .failure(error) }
        // Keep the request alive until its terminal callback even if URLSession releases its delegate first.
        DispatchQueue.main.async {
            self.lock.lock(); let completion = self.cancelled ? nil : self.completion; self.completion = nil; self.lock.unlock()
            completion?(result)
        }
    }
}
