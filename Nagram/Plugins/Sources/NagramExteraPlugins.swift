import Foundation
import NagramExteraPythonAPI

public struct NagramExteraPlugin: Codable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let author: String
    public let version: String
}

public struct NagramExteraMenuItem: Decodable {
    public let pluginId: String
    public let id: String
    public let title: String
    let priority: Int
}

public struct NagramExteraSetting: Decodable, Equatable {
    public let kind: String
    public let text: String
    public let key: String?
    public let subtext: String?
    public let stringValue: String?
    public let boolValue: Bool?

    private enum CodingKeys: String, CodingKey {
        case kind, text, key, subtext, value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decode(String.self, forKey: .kind)
        self.text = try container.decode(String.self, forKey: .text)
        self.key = try container.decodeIfPresent(String.self, forKey: .key)
        self.subtext = try container.decodeIfPresent(String.self, forKey: .subtext)
        self.stringValue = self.kind == "Input" ? try container.decode(String.self, forKey: .value) : nil
        self.boolValue = self.kind == "Switch" ? try container.decode(Bool.self, forKey: .value) : nil
    }
}

private struct NagramExteraError: LocalizedError {
    let message: String
    var errorDescription: String? { self.message }
}

private struct NagramExteraResponse<Value: Decodable>: Decodable {
    let result: Value?
    let error: String?
    let enabled: [String]?
    let hasSendHook: Bool?
    let menus: [NagramExteraMenuItem]?
}

private final class NagramExteraOperation {
    var completed = false
}

/// Public operations and snapshots are main-thread only. Python runs on a serial worker.
public final class NagramExteraPlugins {
    public static let shared = NagramExteraPlugins()

    private let worker = DispatchQueue(label: "Nextgram.ExteraPlugins")
    private let directory: URL
    private var pending = false
    public private(set) var plugins: [NagramExteraPlugin] = []
    public private(set) var enabled: Set<String> = []
    public private(set) var menuItems: [NagramExteraMenuItem] = []
    public private(set) var hasSendHook = false

    private init() {
        self.directory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/NextgramExtera", isDirectory: true)
        if let files = try? FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil) {
            self.plugins = files.filter { $0.pathExtension == "manifest" }.compactMap { file in
                guard let data = try? Data(contentsOf: file),
                      let manifest = try? JSONDecoder().decode(NagramExteraPlugin.self, from: data),
                      manifest.id.range(of: "^[A-Za-z][A-Za-z0-9_-]{1,31}$", options: .regularExpression) != nil,
                      manifest.id == file.deletingPathExtension().lastPathComponent else {
                    return nil
                }
                return manifest
            }.sorted { $0.id < $1.id }
        }
    }

    public func inspect(source: String, completion: @escaping (Result<NagramExteraPlugin, Error>) -> Void) {
        self.perform(["operation": "inspect", "source": source], completion: completion)
    }

    public func install(source: String, plugin: NagramExteraPlugin) throws {
        guard !self.plugins.contains(where: { $0.id.caseInsensitiveCompare(plugin.id) == .orderedSame }) else {
            throw NagramExteraError(message: "A plugin with this ID is already installed. Remove it before reinstalling.")
        }
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        let sourceURL = self.url(plugin.id, "plugin")
        try Data(source.utf8).write(to: sourceURL, options: .atomic)
        try JSONEncoder().encode(plugin).write(to: self.url(plugin.id, "manifest"), options: .atomic)
        self.plugins.append(plugin)
        self.plugins.sort { $0.id < $1.id }
    }

    public func remove(_ plugin: NagramExteraPlugin) throws {
        guard !self.enabled.contains(plugin.id), self.plugins.contains(plugin) else {
            throw NagramExteraError(message: "Disable the plugin before removing it.")
        }
        try FileManager.default.removeItem(at: self.url(plugin.id, "manifest"))
        self.plugins.removeAll(where: { $0.id == plugin.id })
        // Keep the plugin's settings for a future reinstall.
        try FileManager.default.removeItem(at: self.url(plugin.id, "plugin"))
    }

    public func setEnabled(_ plugin: NagramExteraPlugin, enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard self.plugins.contains(plugin), self.enabled.contains(plugin.id) != enabled else {
            completion(.failure(NagramExteraError(message: "The plugin state changed. Reopen its settings.")))
            return
        }
        var request: [String: Any] = ["operation": enabled ? "enable" : "disable", "id": plugin.id]
        if enabled {
            do {
                request["source"] = try String(contentsOf: self.url(plugin.id, "plugin"), encoding: .utf8)
                request["settingsPath"] = self.url(plugin.id, "json").path
            } catch {
                completion(.failure(error))
                return
            }
        }
        self.performAction(request, completion: completion)
    }

    public func settings(_ id: String, completion: @escaping (Result<[NagramExteraSetting], Error>) -> Void) {
        self.perform(["operation": "settings", "id": id], completion: completion)
    }

    public func setSetting(_ id: String, key: String, value: Any, completion: @escaping (Result<Void, Error>) -> Void) {
        self.performAction(["operation": "setSetting", "id": id, "key": key, "value": value], completion: completion)
    }

    public func invoke(_ item: NagramExteraMenuItem, context: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        self.performAction(["operation": "invoke", "id": item.pluginId, "itemId": item.id, "context": context], completion: completion)
    }

    public func transformOutgoing(account: Int64, dialogId: Int64, messages: [String?], completion: @escaping (Result<[String?], Error>) -> Void) {
        self.perform([
            "operation": "send", "account": account, "dialogId": dialogId,
            "messages": messages.map { message -> Any in
                if let message { return message }
                return NSNull()
            },
        ], completion: completion)
    }

    private func url(_ id: String, _ fileExtension: String) -> URL {
        return self.directory.appendingPathComponent(id).appendingPathExtension(fileExtension)
    }

    private func performAction(_ request: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        self.execute(request, response: Bool.self) { result in
            completion(result.map { _ in Void() })
        }
    }

    private func perform<Value: Decodable>(_ request: [String: Any], completion: @escaping (Result<Value, Error>) -> Void) {
        self.execute(request, response: Value.self) { result in
            completion(result.flatMap { response in
                guard let value = response.result else {
                    return .failure(NagramExteraError(message: "The plugin engine returned no result."))
                }
                return .success(value)
            })
        }
    }

    private func execute<Value: Decodable>(_ request: [String: Any], response: Value.Type, completion: @escaping (Result<NagramExteraResponse<Value>, Error>) -> Void) {
        precondition(Thread.isMainThread)
        guard !self.pending else {
            completion(.failure(NagramExteraError(message: "A plugin is still running. Wait, or restart Nextgram if it is stuck.")))
            return
        }
        self.pending = true
        let operation = NagramExteraOperation()
        let timeout = DispatchWorkItem {
            operation.completed = true
            completion(.failure(NagramExteraError(message: "The plugin did not respond. Restart Nextgram to disable all plugins.")))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timeout)
        self.worker.async {
            let result: Result<NagramExteraResponse<Value>, Error> = Result {
                guard let host = NSClassFromString("NextgramExteraPythonHost") as? NagramExteraPythonHost.Type else {
                    throw NagramExteraError(message: "Extera plugins are available only in the Nextgram application.")
                }
                guard let stdlib = Bundle.main.url(forResource: "NextgramPython311", withExtension: "zip"),
                      let bootstrap = Bundle.main.url(forResource: "NextgramExteraRuntime", withExtension: "py") else {
                    throw NagramExteraError(message: "The app build is missing the bundled Python runtime resources.")
                }
                let code = try String(contentsOf: bootstrap, encoding: .utf8)
                let input = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
                let output = host.run(stdlibPath: stdlib.path, bootstrap: code, request: input)
                return try JSONDecoder().decode(NagramExteraResponse<Value>.self, from: Data(output.utf8))
            }
            DispatchQueue.main.async {
                self.pending = false
                timeout.cancel()
                if case let .success(response) = result {
                    if let enabled = response.enabled {
                        self.enabled = Set(enabled)
                    }
                    if let hasSendHook = response.hasSendHook {
                        self.hasSendHook = hasSendHook
                    }
                    if let menus = response.menus {
                        self.menuItems = menus.sorted { $0.priority > $1.priority }
                    }
                }
                if !operation.completed {
                    operation.completed = true
                    completion(result.flatMap { response in
                        if let error = response.error {
                            return .failure(NagramExteraError(message: error))
                        }
                        return .success(response)
                    })
                }
            }
        }
    }
}
