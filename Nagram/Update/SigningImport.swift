import Foundation
import NextgramUpdateArchive

public struct NextgramSigningImport: Sendable {
    public let certificateName: String?
    public let certificate: Data?
    public let profiles: [Data]
    private static let limit = 4 * 1024 * 1024

    public static func read(_ urls: [URL]) throws -> Self {
        guard (1...16).contains(urls.count) else { throw NextgramSigningFilesError.invalidFileSelection }
        var certificate: (String, Data)?
        var profiles: [Data] = []
        func add(name: String, data: Data) throws {
            switch (name as NSString).pathExtension.lowercased() {
            case "p12", "pfx":
                guard certificate == nil else { throw NextgramSigningFilesError.invalidFileSelection }
                certificate = (name, data)
            case "mobileprovision":
                if !profiles.contains(data) { profiles.append(data) }
            default:
                throw NextgramSigningFilesError.invalidFileSelection
            }
        }
        for url in urls {
            guard url.isFileURL else { throw NextgramSigningFilesError.invalidFileSelection }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            guard let data = try file.read(upToCount: Self.limit + 1), !data.isEmpty, data.count <= Self.limit else {
                throw NextgramSigningFilesError.invalidFileSelection
            }
            if url.pathExtension.lowercased() == "zip" {
                guard urls.count == 1 else { throw NextgramSigningFilesError.invalidFileSelection }
                let manager = FileManager.default
                let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.protectionKey: FileProtectionType.complete])
                defer { try? manager.removeItem(at: directory) }
                let copy = directory.appendingPathComponent("credentials.zip")
                try data.write(to: copy, options: .completeFileProtection)
                guard let files = NextgramUpdateReadSigningArchive(copy.path) else { throw NextgramSigningFilesError.invalidFileSelection }
                for name in files.keys.sorted() {
                    if let contents = files[name] { try add(name: name, data: contents) }
                }
            } else {
                try add(name: url.lastPathComponent, data: data)
            }
        }
        guard profiles.count <= 15, profiles.reduce(certificate?.1.count ?? 0, { $0 + $1.count }) <= Self.limit,
              certificate != nil || !profiles.isEmpty else { throw NextgramSigningFilesError.invalidFileSelection }
        return Self(certificateName: certificate?.0, certificate: certificate?.1, profiles: profiles)
    }
}
