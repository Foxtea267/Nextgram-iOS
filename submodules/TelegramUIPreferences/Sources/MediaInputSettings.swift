import Foundation
import TelegramCore
import SwiftSignalKit

public struct MediaInputSettings: Codable, Equatable {
    public let enableRaiseToSpeak: Bool
    public let pauseMusicOnRecording: Bool
    // MARK: NAGRAM — 与 Android 一致，把贴耳录音从 enableRaiseToSpeak（贴耳收听）中拆出，默认关闭。
    public let nagramEnableRaiseToRecord: Bool
    
    public static var defaultSettings: MediaInputSettings {
        return MediaInputSettings(enableRaiseToSpeak: true, pauseMusicOnRecording: true, nagramEnableRaiseToRecord: false)
    }
    
    public init(enableRaiseToSpeak: Bool, pauseMusicOnRecording: Bool, nagramEnableRaiseToRecord: Bool) {
        self.enableRaiseToSpeak = enableRaiseToSpeak
        self.pauseMusicOnRecording = pauseMusicOnRecording
        self.nagramEnableRaiseToRecord = nagramEnableRaiseToRecord
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.enableRaiseToSpeak = (try container.decode(Int32.self, forKey: "enableRaiseToSpeak")) != 0
        self.pauseMusicOnRecording = (try container.decodeIfPresent(Int32.self, forKey: "pauseMusicOnRecording_v2") ?? 1) != 0
        self.nagramEnableRaiseToRecord = (try container.decodeIfPresent(Int32.self, forKey: "nagram.enableRaiseToRecord") ?? 0) != 0 // MARK: NAGRAM
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode((self.enableRaiseToSpeak ? 1 : 0) as Int32, forKey: "enableRaiseToSpeak")
        try container.encode((self.pauseMusicOnRecording ? 1 : 0) as Int32, forKey: "pauseMusicOnRecording_v2")
        try container.encode((self.nagramEnableRaiseToRecord ? 1 : 0) as Int32, forKey: "nagram.enableRaiseToRecord") // MARK: NAGRAM
    }
    
    public static func ==(lhs: MediaInputSettings, rhs: MediaInputSettings) -> Bool {
        return lhs.enableRaiseToSpeak == rhs.enableRaiseToSpeak && lhs.pauseMusicOnRecording == rhs.pauseMusicOnRecording && lhs.nagramEnableRaiseToRecord == rhs.nagramEnableRaiseToRecord // MARK: NAGRAM
    }
    
    public func withUpdatedEnableRaiseToSpeak(_ enableRaiseToSpeak: Bool) -> MediaInputSettings {
        return MediaInputSettings(enableRaiseToSpeak: enableRaiseToSpeak, pauseMusicOnRecording: self.pauseMusicOnRecording, nagramEnableRaiseToRecord: self.nagramEnableRaiseToRecord)
    }
    
    public func withUpdatedPauseMusicOnRecording(_ pauseMusicOnRecording: Bool) -> MediaInputSettings {
        return MediaInputSettings(enableRaiseToSpeak: self.enableRaiseToSpeak, pauseMusicOnRecording: pauseMusicOnRecording, nagramEnableRaiseToRecord: self.nagramEnableRaiseToRecord)
    }
    
    // MARK: NAGRAM
    public func withUpdatedNagramEnableRaiseToRecord(_ nagramEnableRaiseToRecord: Bool) -> MediaInputSettings {
        return MediaInputSettings(enableRaiseToSpeak: self.enableRaiseToSpeak, pauseMusicOnRecording: self.pauseMusicOnRecording, nagramEnableRaiseToRecord: nagramEnableRaiseToRecord)
    }
}

public func updateMediaInputSettingsInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (MediaInputSettings) -> MediaInputSettings) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.mediaInputSettings, { entry in
            let currentSettings: MediaInputSettings
            if let entry = entry?.get(MediaInputSettings.self) {
                currentSettings = entry
            } else {
                currentSettings = MediaInputSettings.defaultSettings
            }
            return SharedPreferencesEntry(f(currentSettings))
        })
    }
}
