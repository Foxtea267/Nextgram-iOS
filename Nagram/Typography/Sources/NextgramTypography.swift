import CoreText
import CryptoKit
import Foundation
import NagramSettings
import UIKit

public struct NextgramImportedFont: Codable, Equatable {
    public let id: String
    public let file: String
    public let faceIndex: Int
    public var name: String
}

public enum NextgramFontError: Error {
    case invalidFile, tooLarge, registrationFailed
}

/// A process-wide, local font registry. Rendering never downloads fonts or re-reads font files.
public final class NextgramTypography {
    public static let shared = NextgramTypography()
    public static let maximumFileSize = 64 * 1024 * 1024
    private let lock = NSRecursiveLock()
    private var descriptors: [String: UIFontDescriptor] = [:]
    private var fontCache: [String: UIFont] = [:]
    private var fonts: [NextgramImportedFont] = []
    private var configuration = NextgramFontConfiguration.current
    private var observer: NSObjectProtocol?
    private let directory: URL
    private static let cjkCharacters: CharacterSet = {
        var set = CharacterSet()
        for range in [0x2e80...0x303f, 0x3040...0x31ff, 0x3400...0x9fff, 0xac00...0xd7af, 0xf900...0xfaff, 0xff01...0xff60, 0xffe0...0xffe6, 0x20000...0x323af] {
            if let lower = UnicodeScalar(range.lowerBound), let upper = UnicodeScalar(range.upperBound) { set.insert(charactersIn: lower ... upper) }
        }
        return set
    }()

    private init() {
        self.directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(NagramDemoMode.isEnabled ? "NextgramFonts-Demo" : "NextgramFonts", isDirectory: true)
        if let data = try? Data(contentsOf: self.directory.appendingPathComponent("index.json")), data.count <= 1024 * 1024,
           let fonts = try? JSONDecoder().decode([NextgramImportedFont].self, from: data) {
            // The manifest is local, but validate paths before opening anything outside the font store.
            self.fonts = Array(fonts.filter { Self.validFileName($0.file) && $0.faceIndex >= 0 && $0.faceIndex < 256 }.prefix(256))
            for file in Set(self.fonts.map { $0.file }) { self.register(file: file) }
        }
        self.observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.configuration = NextgramFontConfiguration.current
            self.fontCache.removeAll()
            self.lock.unlock()
        }
    }

    deinit { if let observer = self.observer { NotificationCenter.default.removeObserver(observer) } }

    public var importedFonts: [NextgramImportedFont] {
        self.lock.lock(); defer { self.lock.unlock() }
        return self.fonts
    }

    private static func validFileName(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 2 && parts[0].count == 64 && parts[0].allSatisfy { $0.isHexDigit }
            && ["ttf", "otf", "ttc"].contains(String(parts[1]))
    }

    private func register(file: String) {
        let url = self.directory.appendingPathComponent(file)
        guard let values = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], values.count <= 256 else { return }
        // CoreText can report already-registered when faces overlap another file; the descriptors remain usable.
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        for font in self.fonts where font.file == file && values.indices.contains(font.faceIndex) {
            self.descriptors[font.id] = (CTFontCreateWithFontDescriptor(values[font.faceIndex], 16, nil) as UIFont).fontDescriptor
        }
    }

    private func saveIndex() throws {
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(self.fonts).write(to: self.directory.appendingPathComponent("index.json"), options: .atomic)
    }

    @discardableResult
    public func importFile(_ url: URL) throws -> [NextgramImportedFont] {
        guard url.isFileURL, ["ttf", "otf", "ttc"].contains(url.pathExtension.lowercased()) else { throw NextgramFontError.invalidFile }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: Self.maximumFileSize + 1), !data.isEmpty else { throw NextgramFontError.invalidFile }
        guard data.count <= Self.maximumFileSize else { throw NextgramFontError.tooLarge }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let file = digest + "." + url.pathExtension.lowercased()
        self.lock.lock(); defer { self.lock.unlock() }
        let existing = self.fonts.filter { $0.file == file }
        if !existing.isEmpty { return existing }
        guard self.fonts.count < 256 else { throw NextgramFontError.tooLarge }
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        let destination = self.directory.appendingPathComponent(file)
        try data.write(to: destination, options: .atomic)
        guard let values = CTFontManagerCreateFontDescriptorsFromURL(destination as CFURL) as? [CTFontDescriptor],
              !values.isEmpty, values.count <= 256, self.fonts.count + values.count <= 256 else {
            try? FileManager.default.removeItem(at: destination)
            throw NextgramFontError.invalidFile
        }
        let imported = values.enumerated().map { index, value in
            NextgramImportedFont(id: digest + ":" + String(index), file: file, faceIndex: index,
                name: (CTFontDescriptorCopyAttribute(value, kCTFontDisplayNameAttribute) as? String) ?? url.deletingPathExtension().lastPathComponent)
        }
        let oldFonts = self.fonts
        self.fonts.append(contentsOf: imported)
        do { try self.saveIndex() }
        catch { self.fonts = oldFonts; try? FileManager.default.removeItem(at: destination); throw error }
        self.register(file: file)
        self.fontCache.removeAll()
        return imported
    }

    public func rename(id: String, name: String) throws {
        self.lock.lock(); defer { self.lock.unlock() }
        guard let index = self.fonts.firstIndex(where: { $0.id == id }), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NextgramFontError.invalidFile }
        let old = self.fonts
        self.fonts[index].name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        do { try self.saveIndex() } catch { self.fonts = old; throw error }
    }

    public func remove(id: String) throws {
        self.lock.lock(); defer { self.lock.unlock() }
        guard let font = self.fonts.first(where: { $0.id == id }) else { return }
        let old = self.fonts
        self.fonts.removeAll { $0.id == id }
        do { try self.saveIndex() } catch { self.fonts = old; throw error }
        self.descriptors.removeValue(forKey: id)
        self.fontCache.removeAll()
        var configuration = NextgramFontConfiguration.current
        if configuration.interfaceLatin == id { configuration.interfaceLatin = "system" }
        if configuration.interfaceCJK == id { configuration.interfaceCJK = "system" }
        if configuration.messageLatin == id { configuration.messageLatin = "system" }
        if configuration.messageCJK == id { configuration.messageCJK = "system" }
        NextgramFontConfiguration.current = configuration
        // Keep other faces from a TTC intact. Registered UIFont instances remain valid for existing layouts.
        if !self.fonts.contains(where: { $0.file == font.file }) {
            try FileManager.default.removeItem(at: self.directory.appendingPathComponent(font.file))
        }
    }

    public func preview(id: String, size: CGFloat) -> UIFont {
        self.lock.lock(); defer { self.lock.unlock() }
        return self.face(id: id, size: size, weight: .regular, italic: false)
    }

    private func face(id: String, size: CGFloat, weight: UIFont.Weight, italic: Bool) -> UIFont {
        let native = UIFont.systemFont(ofSize: size, weight: weight)
        var descriptor = self.descriptors[id] ?? native.fontDescriptor
        if id == "rounded" { descriptor = native.fontDescriptor.withDesign(.rounded) ?? descriptor }
        if id == "serif" { descriptor = native.fontDescriptor.withDesign(.serif) ?? descriptor }
        if id == "monospace" { descriptor = native.fontDescriptor.withDesign(.monospaced) ?? descriptor }
        let font = UIFont(descriptor: descriptor, size: size)
        var variations: [NSNumber: NSNumber] = [:]
        var variableWeight = false
        var variableItalic = false
        if let axes = CTFontCopyVariationAxes(font as CTFont) as? [[String: Any]] {
            for axis in axes {
                guard let identifier = axis[kCTFontVariationAxisIdentifierKey as String] as? NSNumber else { continue }
                let desired: Double
                switch identifier.uint32Value {
                case 0x77676874:
                    variableWeight = true
                    desired = weight >= .heavy ? 800 : weight >= .bold ? 700 : weight >= .semibold ? 600 : weight >= .medium ? 500 : weight <= .thin ? 200 : weight <= .light ? 300 : 400
                case 0x6f70737a: desired = Double(size)
                case 0x6974616c: variableItalic = true; desired = italic ? 1 : 0
                case 0x736c6e74: variableItalic = true; desired = italic ? -10 : 0
                default: continue
                }
                let low = (axis[kCTFontVariationAxisMinimumValueKey as String] as? NSNumber)?.doubleValue ?? desired
                let high = (axis[kCTFontVariationAxisMaximumValueKey as String] as? NSNumber)?.doubleValue ?? desired
                variations[identifier] = NSNumber(value: min(high, max(low, desired)))
            }
        }
        if !variations.isEmpty { descriptor = descriptor.addingAttributes([UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variations]) }
        var traits = descriptor.symbolicTraits
        if weight >= .semibold && !variableWeight { traits.insert(.traitBold) }
        if italic && !variableItalic { traits.insert(.traitItalic) }
        descriptor = descriptor.withSymbolicTraits(traits) ?? descriptor
        return UIFont(descriptor: descriptor, size: size)
    }

    public func font(message: Bool = false, size: CGFloat, weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont? {
        self.lock.lock(); defer { self.lock.unlock() }
        let latin = message ? self.configuration.messageLatin : self.configuration.interfaceLatin
        let cjk = message ? self.configuration.messageCJK : self.configuration.interfaceCJK
        guard latin != "system" || cjk != "system" else { return nil }
        let key = "\(latin)|\(cjk)|\(size)|\(weight.rawValue)|\(italic)"
        if let cached = self.fontCache[key] { return cached }
        let primary = self.face(id: latin, size: size, weight: weight, italic: italic)
        let fallback: UIFont
        if cjk == "system" {
            let native = self.face(id: "system", size: size, weight: weight, italic: italic)
            fallback = CTFontCreateForString(native as CTFont, "中文漢字" as CFString, CFRange(location: 0, length: 4)) as UIFont
        } else { fallback = self.face(id: cjk, size: size, weight: weight, italic: italic) }
        let nativeFallback = CTFontCopyDefaultCascadeListForLanguages(primary as CTFont, ["zh-Hans", "zh-Hant", "ja", "ko"] as CFArray) as? [CTFontDescriptor] ?? []
        let primaryCharacters = (CTFontCopyCharacterSet(primary as CTFont) as CharacterSet).subtracting(Self.cjkCharacters)
        let fallbackCharacters = (CTFontCopyCharacterSet(fallback as CTFont) as CharacterSet).intersection(Self.cjkCharacters)
        let restrictedFallback = fallback.fontDescriptor.addingAttributes([UIFontDescriptor.AttributeName(rawValue: kCTFontCharacterSetAttribute as String): fallbackCharacters as NSCharacterSet])
        let descriptor = primary.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: kCTFontCharacterSetAttribute as String): primaryCharacters as NSCharacterSet,
            .cascadeList: [restrictedFallback] + nativeFallback.map { (CTFontCreateWithFontDescriptor($0, size, nil) as UIFont).fontDescriptor }
        ])
        let result = UIFont(descriptor: descriptor, size: size)
        if self.fontCache.count >= 512 { self.fontCache.removeAll(keepingCapacity: true) }
        self.fontCache[key] = result
        return result
    }
}
