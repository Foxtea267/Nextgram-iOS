import Foundation

struct NextgramDNSDiagnosticResult: Equatable {
    let milliseconds: Int
    let addresses: [String]
}

/// A fresh, bounded DNS JSON query, not an HTTP reachability measurement.
final class NextgramDNSDiagnosticQuery: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var data = Data()
    private var started = Date()
    private var completion: ((NextgramDNSDiagnosticResult?) -> Void)?
    private let recordType: Int

    init(provider: String, recordType: Int, completion: @escaping (NextgramDNSDiagnosticResult?) -> Void) {
        self.recordType = recordType
        self.completion = completion
        super.init()
        var components = URLComponents(string: provider)!
        components.queryItems = [URLQueryItem(name: "name", value: "telegram.org"), URLQueryItem(name: "type", value: String(recordType))]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 8.0
        configuration.timeoutIntervalForResource = 10.0
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        self.started = Date()
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    func cancel() {
        self.task?.cancel()
        self.session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, response.expectedContentLength <= 65536 else {
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard self.data.count + data.count <= 65536 else {
            dataTask.cancel()
            return
        }
        self.data.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        var result: NextgramDNSDiagnosticResult?
        if error == nil,
           let object = (try? JSONSerialization.jsonObject(with: self.data)) as? [String: Any],
           let status = object["Status"] as? Int, status == 0,
           let answers = object["Answer"] as? [[String: Any]] {
            let addresses = answers.compactMap { answer -> String? in
                guard answer["type"] as? Int == self.recordType, let address = answer["data"] as? String else { return nil }
                // Resolver answers are shown verbatim in returned order, never used as a connection policy.
                return address
            }
            if !addresses.isEmpty {
                result = NextgramDNSDiagnosticResult(milliseconds: max(0, Int(Date().timeIntervalSince(self.started) * 1000.0)), addresses: addresses)
            }
        }
        let completion = self.completion
        self.completion = nil
        self.task = nil
        self.session = nil
        session.finishTasksAndInvalidate()
        DispatchQueue.main.async { completion?(result) }
    }
}
