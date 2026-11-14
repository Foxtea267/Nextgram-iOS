import Foundation
import NagramSettings
import SwiftSignalKit

public struct NextgramSummaryError: Error {
    public let message: String
}

/// No automatic invocation: the caller must preview the payload and obtain explicit upload consent.
public func nextgramSummarizeMessages(text: String, language: String, configuration: NextgramSummarySettings.Configuration, apiKey: String, test: Bool = false) -> Signal<String, NextgramSummaryError> {
    guard configuration.enabled, !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !text.isEmpty, text.utf8.count <= 64000, let url = NextgramSummarySettings.requestURL(configuration),
          configuration.model.utf8.count <= 512, configuration.prompt.utf8.count <= 16384,
          configuration.temperature.isFinite, (0 ... 1).contains(configuration.temperature),
          ["openai", "anthropic"].contains(configuration.format) else {
        return .fail(NextgramSummaryError(message: "Invalid summary configuration or message size."))
    }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60.0)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let prompt = test ? "Reply PONG only." : configuration.prompt.replacingOccurrences(of: "@toLang", with: language)
    let body: [String: Any]
    if configuration.format == "anthropic" {
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        body = ["model": configuration.model, "system": prompt, "messages": [["role": "user", "content": text]], "max_tokens": 4096, "temperature": configuration.temperature]
    } else {
        if !apiKey.isEmpty { request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization") }
        body = ["model": configuration.model, "messages": [["role": "system", "content": prompt], ["role": "user", "content": text]], "temperature": configuration.temperature]
    }
    guard let data = try? JSONSerialization.data(withJSONObject: body) else { return .fail(NextgramSummaryError(message: "Invalid request.")) }
    request.httpBody = data
    return Signal { subscriber in
        let task = NextgramSummaryRequest(request: request, format: configuration.format) { result in
            switch result {
            case let .success(value): subscriber.putNext(value); subscriber.putCompletion()
            case let .failure(error): subscriber.putError(error)
            }
        }
        return ActionDisposable { task.cancel() }
    }
}

private final class NextgramSummaryRequest: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var data = Data()
    private var statusCode = 0
    private let format: String
    private var completion: ((Result<String, NextgramSummaryError>) -> Void)?

    init(request: URLRequest, format: String, completion: @escaping (Result<String, NextgramSummaryError>) -> Void) {
        self.format = format
        self.completion = completion
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 90
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        session.dataTask(with: request).resume()
    }

    func cancel() { self.session?.invalidateAndCancel() }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward message contents or credentials to a redirect target.
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        completionHandler(response.expectedContentLength > 1024 * 1024 ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard self.data.count + data.count <= 1024 * 1024 else { dataTask.cancel(); return }
        self.data.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { self.completion = nil; self.session = nil; session.finishTasksAndInvalidate() }
        if error != nil { self.completion?(.failure(NextgramSummaryError(message: "Summary request failed. Check your connection and endpoint."))); return }
        guard (200 ... 299).contains(self.statusCode) else { self.completion?(.failure(NextgramSummaryError(message: "HTTP \(self.statusCode). Check the model, endpoint and API key."))); return }
        guard let object = (try? JSONSerialization.jsonObject(with: self.data)) as? [String: Any] else { self.completion?(.failure(NextgramSummaryError(message: "Invalid model response."))); return }
        let text: String?
        if self.format == "anthropic" {
            text = (object["content"] as? [[String: Any]])?.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        } else {
            let message = (object["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
            text = message?["content"] as? String
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { self.completion?(.failure(NextgramSummaryError(message: "The model returned no summary."))); return }
        self.completion?(.success(text))
    }
}
