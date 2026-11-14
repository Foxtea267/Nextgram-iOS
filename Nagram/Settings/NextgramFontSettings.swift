import Foundation

public struct NextgramFontConfiguration: Codable, Equatable {
    public var interfaceLatin = "system"
    public var interfaceCJK = "system"
    public var messageLatin = "system"
    public var messageCJK = "system"

    public init() {}

    public static var current: NextgramFontConfiguration {
        get {
            guard let data = NagramDemoMode.userDefaults.data(forKey: "nextgram.fonts.configuration"),
                  let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
            return value
        }
        set {
            NagramDemoMode.userDefaults.set(try? JSONEncoder().encode(newValue), forKey: "nextgram.fonts.configuration")
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: NagramDemoMode.userDefaults)
        }
    }
}
