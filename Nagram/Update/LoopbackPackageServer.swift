import Foundation
import Network

enum NextgramInstallError: Error {
    case transport
    case manifest
}

final class LoopbackPackageServer: @unchecked Sendable {
    private let package: NextgramUpdatePackage
    private let route = "/" + UUID().uuidString + "/Nextgram.ipa"
    private let queue = DispatchQueue(label: "Nextgram.Update.Loopback")
    private let length: Int64
    private var listener: NWListener?
    private var startup: CheckedContinuation<URL, Error>?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var transferStarted = false
    private var covered: [Range<Int64>] = []

    init(package: NextgramUpdatePackage) throws {
        self.package = package
        guard let size = try package.url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
            throw NextgramInstallError.transport
        }
        length = Int64(size)
    }

    func start() async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.listener == nil else {
                    continuation.resume(throwing: NextgramInstallError.transport)
                    return
                }
                self.startup = continuation
                do {
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                    let listener = try NWListener(using: parameters)
                    self.listener = listener
                    listener.newConnectionHandler = { [weak self] connection in
                        self?.accept(connection)
                    }
                    listener.stateUpdateHandler = { [weak self, weak listener] state in
                        guard let self else { return }
                        switch state {
                        case .ready:
                            if let port = listener?.port, let url = URL(string: "http://127.0.0.1:\(port.rawValue)\(self.route)") {
                                self.finishStartup(.success(url))
                            } else {
                                self.finishStartup(.failure(NextgramInstallError.transport))
                            }
                        case .failed, .cancelled:
                            self.finishStartup(.failure(NextgramInstallError.transport))
                        default:
                            break
                        }
                    }
                    listener.start(queue: self.queue)
                    self.queue.asyncAfter(deadline: .now() + 10) {
                        self.finishStartup(.failure(NextgramInstallError.transport))
                    }
                } catch {
                    self.finishStartup(.failure(error))
                }
            }
        }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            for connection in self.connections.values {
                connection.cancel()
            }
            self.connections.removeAll()
            self.finishStartup(.failure(NextgramInstallError.transport))
        }
    }

    func hasStarted() async -> Bool {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.transferStarted)
            }
        }
    }

    func isComplete() async -> Bool {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.covered == [0..<self.length])
            }
        }
    }

    private func finishStartup(_ result: Result<URL, Error>) {
        let pending = startup
        startup = nil
        pending?.resume(with: result)
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < 8 else {
            connection.cancel()
            return
        }
        connections[ObjectIdentifier(connection)] = connection
        connection.start(queue: queue)
        receive(connection, buffered: Data())
    }

    private func receive(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] chunk, _, complete, error in
            guard let self else { return }
            var buffer = buffered
            if let chunk {
                buffer.append(chunk)
            }
            guard error == nil, buffer.count <= 8192 else {
                self.close(connection)
                return
            }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)),
               let header = String(data: buffer[..<end.lowerBound], encoding: .ascii) {
                self.respond(connection, header: header)
            } else if !complete {
                self.receive(connection, buffered: buffer)
            } else {
                self.close(connection)
            }
        }
    }

    private func respond(_ connection: NWConnection, header: String) {
        let lines = header.components(separatedBy: "\r\n")
        let request = lines.first?.split(separator: " ") ?? []
        guard request.count == 3, request[1] == route, request[0] == "GET" || request[0] == "HEAD" else {
            sendHeader(connection, status: "404 Not Found", fields: "Content-Length: 0\r\n") { [weak self] _ in self?.close(connection) }
            return
        }
        let ranges = lines.dropFirst().filter { $0.lowercased().hasPrefix("range:") }
        let range: Range<Int64>
        if ranges.isEmpty {
            range = 0..<length
        } else if ranges.count == 1, let line = ranges.first, let value = parseRange(line.dropFirst("Range:".count)) {
            range = value
        } else {
            sendHeader(connection, status: "416 Range Not Satisfiable", fields: "Content-Length: 0\r\nContent-Range: bytes */\(length)\r\n") { [weak self] _ in self?.close(connection) }
            return
        }
        let partial = !ranges.isEmpty
        let fields = "Content-Type: application/octet-stream\r\nAccept-Ranges: bytes\r\nContent-Length: \(range.count)\r\n"
            + (partial ? "Content-Range: bytes \(range.lowerBound)-\(range.upperBound - 1)/\(length)\r\n" : "")
        if request[0] == "HEAD" {
            sendHeader(connection, status: partial ? "206 Partial Content" : "200 OK", fields: fields) { [weak self] _ in self?.close(connection) }
            return
        }
        guard let file = try? FileHandle(forReadingFrom: package.url) else {
            close(connection)
            return
        }
        do {
            try file.seek(toOffset: UInt64(range.lowerBound))
        } catch {
            try? file.close()
            close(connection)
            return
        }
        transferStarted = true
        sendHeader(connection, status: partial ? "206 Partial Content" : "200 OK", fields: fields) { [weak self] error in
            if error == nil, let self {
                self.sendBytes(connection, file: file, remaining: range.count, range: range)
            } else {
                try? file.close()
                self?.close(connection)
            }
        }
    }

    private func parseRange(_ value: Substring) -> Range<Int64>? {
        let value = value.trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("bytes=") else { return nil }
        let limits = value.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard limits.count == 2 else { return nil }
        if limits[0].isEmpty, let suffix = Int64(limits[1]), suffix > 0 {
            return max(0, length - suffix)..<length
        }
        guard let first = Int64(limits[0]), first >= 0, first < length else { return nil }
        if limits[1].isEmpty { return first..<length }
        guard let last = Int64(limits[1]), last >= first else { return nil }
        return first..<(min(last, length - 1) + 1)
    }

    private func sendHeader(_ connection: NWConnection, status: String, fields: String, completion: @escaping @Sendable (NWError?) -> Void) {
        let data = Data("HTTP/1.1 \(status)\r\nConnection: close\r\n\(fields)\r\n".utf8)
        connection.send(content: data, completion: .contentProcessed(completion))
    }

    private func sendBytes(_ connection: NWConnection, file: FileHandle, remaining: Int, range: Range<Int64>) {
        if remaining == 0 {
            covered.append(range)
            covered.sort { $0.lowerBound < $1.lowerBound }
            var merged: [Range<Int64>] = []
            for next in covered {
                if let last = merged.last, next.lowerBound <= last.upperBound {
                    merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, next.upperBound)
                } else {
                    merged.append(next)
                }
            }
            covered = merged
            try? file.close()
            close(connection)
            return
        }
        guard let data = try? file.read(upToCount: min(remaining, 128 * 1024)), !data.isEmpty else {
            try? file.close()
            close(connection)
            return
        }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if error == nil, let self {
                self.sendBytes(connection, file: file, remaining: remaining - data.count, range: range)
            } else {
                try? file.close()
                self?.close(connection)
            }
        })
    }

    private func close(_ connection: NWConnection) {
        connection.cancel()
        connections.removeValue(forKey: ObjectIdentifier(connection))
    }
}
