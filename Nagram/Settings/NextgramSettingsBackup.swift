import Foundation

public struct NextgramSettingsBackup {
    public enum BackupError: Error {
        case invalidFile
        case noSettings
    }

    private enum Kind {
        case boolean
        case integer
        case string
    }

    private enum Value: Codable {
        case boolean(Bool)
        case integer(Int32)
        case string(String)
        case unset

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .unset
            } else if let boolean = try? container.decode(Bool.self) {
                self = .boolean(boolean)
            } else if let integer = try? container.decode(Int32.self) {
                self = .integer(integer)
            } else {
                self = .string(try container.decode(String.self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .boolean(value): try container.encode(value)
            case let .integer(value): try container.encode(value)
            case let .string(value): try container.encode(value)
            case .unset: try container.encodeNil()
            }
        }

        func matches(_ kind: Kind) -> Bool {
            switch (self, kind) {
            case (.unset, _), (.boolean, .boolean), (.integer, .integer), (.string, .string): return true
            default: return false
            }
        }
    }

    private struct RegexFilters: Codable {
        let enabled: Bool
        let filterOutgoing: Bool
        let rules: [NagramRegexFilterRule]
    }

    public struct AppIcon: Codable {
        public let name: String?
    }

    private struct Document: Codable {
        let format: String
        let version: Int
        let preferences: [String: Value]
        let bottomBar: NagramBottomBarSettings?
        let regexFilters: RegexFilters?
        let notificationFallback: Bool?
        let appIcon: AppIcon?
    }

    public static let maximumFileSize = 2 * 1024 * 1024
    public static let didRestoreNotification = Notification.Name("NextgramSettingsDidRestore")
    private static let format = "nextgram-settings"
    private static let version = 1

    // Portable preferences only. Account data, credentials, consent, and iCloud state live outside this list.
    private static let keys: [String: (category: NextgramSettingsCategory, kind: Kind)] = [
        "nagram.hideReactions": (.chat, .boolean),
        "nagram.disableScrollToNextChannel": (.chat, .boolean),
        "nagram.disableScrollToNextTopic": (.chat, .boolean),
        "nagram.secondsInMessages": (.chat, .boolean),
        "nagram.showForwardedMessageDate": (.chat, .boolean),
        "nagram.autoRevealSpoilers": (.chat, .boolean),
        "nagram.hideQuickForwardButton": (.chat, .boolean),
        "nagram.confirmUnpinMessages": (.chat, .boolean),
        "nagram.preselectMessageModerationActions": (.chat, .boolean),
        "nagram.hideChannelBottomButton": (.chat, .boolean),
        "nagram.hideSponsoredMessages": (.chat, .boolean),
        "nagram.hidePrivateChatActivities": (.chat, .boolean),
        "nagram.stayAtLatestMessageAfterRefresh": (.chat, .boolean),
        "nagram.chatListSwipeAction": (.chat, .string),
        "nagram.openArchiveOnPull": (.chat, .boolean),
        "nagram.showArchiveInFolders": (.chat, .boolean),
        "nagram.hideSavedAndArchivedMessagesInList": (.chat, .boolean),
        "nagram.disableCommunityChatGrouping": (.chat, .boolean),
        "nagram.communityAvatarTapAction": (.chat, .string),
        "nagram.chatListStartupFolderMode": (.chat, .string),
        "nagram.chatListFolderTabsCompact": (.chat, .boolean),
        "nagram.hideFolderUnreadCount": (.chat, .boolean),
        "nagram.hideAllChatsFolder": (.chat, .boolean),
        "nagram.showFoldersInShareSheet": (.chat, .boolean),
        "nagram.chatToolsEnabled": (.chat, .boolean),
        "nagram.chooseFolderAfterJoining": (.chat, .boolean),
        "nagram.chatListFolderTabDisplayMode": (.chat, .string),
        "nagram.chatListMessagePreviewStyle": (.chat, .string),
        "nagram.chatListCompact": (.chat, .boolean),
        "nagram.chatListQuickFiltersEnabled": (.chat, .boolean),
        "nagram.chatListQuickFilterReadMode": (.chat, .string),
        "nagram.chatListQuickFilterPeerTypes": (.chat, .integer),
        "nagram.chatListUnreadFirst": (.chat, .boolean),
        "nagram.chatListOldestFirst": (.chat, .boolean),
        "nagram.chatSearchHideRecentListWhenTopPeersVisible": (.chat, .boolean),
        "nagram.chatAutoremoveBadgeEnabled": (.chat, .boolean),
        "nagram.recentChatsEnabled": (.chat, .boolean),
        "nagram.tapMessageRowToOpenContextMenu": (.chat, .boolean),
        "nagram.messageDoubleTapAction": (.chat, .string),
        "nagram.messageDoubleTapActionWithoutEditPermission": (.chat, .string),
        "nagram.wideChannelPosts": (.chat, .boolean),
        "nagram.disableSendAsButton": (.input, .boolean),
        "nagram.hideRecordingButton": (.input, .boolean),
        "nagram.sendWithReturnKey": (.input, .boolean),
        "nagram.defaultMessageFormat": (.input, .string),
        "nagram.showTextStyleToolbar": (.input, .boolean),
        "nagram.enablePanguOnSending": (.input, .boolean),
        "nagram.enablePanguOnEditing": (.input, .boolean),
        "nagram.enablePanguOnReceiving": (.input, .boolean),
        "nagram.autoInlineBotEnabled": (.input, .boolean),
        "nagram.translationProvider": (.translation, .string),
        "nagram.translationLLMAPIFormat": (.translation, .string),
        "nagram.translationLLMBaseURL": (.translation, .string),
        "nagram.translationLLMEndpoint": (.translation, .string),
        "nagram.translationLLMModel": (.translation, .string),
        "nagram.translationLLMPrompt": (.translation, .string),
        "nagram.translationLLMUseContext": (.translation, .boolean),
        "nagram.translationKeepFormatting": (.translation, .boolean),
        "nagram.translationLLMTemperatureTenths": (.translation, .integer),
        "nagram.translateBeforeSend": (.translation, .boolean),
        "nagram.translateBeforeSendTargetLang": (.translation, .string),
        "nagram.sttProvider": (.translation, .string),
        "nagram.sttBaseURL": (.translation, .string),
        "nagram.sttEndpoint": (.translation, .string),
        "nagram.sttModel": (.translation, .string),
        "nagram.sttLanguage": (.translation, .string),
        "nagram.sttPrompt": (.translation, .string),
        "nagram.forceCopyEnabled": (.privacy, .boolean),
        "nagram.antiRecallEnabled": (.privacy, .boolean),
        "nagram.antiRecallWhitelist": (.privacy, .string),
        "nagram.antiRecallBlacklist": (.privacy, .string),
        "nagram.antiRecallExcludedKeywords": (.privacy, .string),
        "nagram.deletedMessageIndicatorStyle": (.privacy, .string),
        "nagram.deletedMessageIndicatorColor": (.privacy, .string),
        "nagram.deletedMessageSemiTransparent": (.privacy, .boolean),
        "nagram.preserveBotMessages": (.privacy, .boolean),
        "nagram.saveMessageEditHistory": (.privacy, .boolean),
        "nagram.ghostModeEnabled": (.privacy, .boolean),
        "nagram.disableReadReceipts": (.privacy, .boolean),
        "nagram.disableTypingStatus": (.privacy, .boolean),
        "nagram.disableOnlineStatus": (.privacy, .boolean),
        "nagram.disableContactPhoneSharingByDefault": (.privacy, .boolean),
        "nagram.disableContactSyncToPhoneByDefault": (.privacy, .boolean),
        "nagram.skipSensitiveContentWarning": (.privacy, .boolean),
        "nagram.ignoreContentRestrictions": (.privacy, .boolean),
        "nagram.hideStories": (.privacy, .boolean),
        "nagram.hideTopStories": (.privacy, .boolean),
        "nagram.disableStoryCameraSwipe": (.privacy, .boolean),
        "nagram.disableChatAvatarStories": (.privacy, .boolean),
        "nagram.disableGalleryCamera": (.media, .boolean),
        "nagram.disableGalleryCameraPreview": (.media, .boolean),
        "nagram.roundVideoCamera": (.media, .string),
        "nagram.stickerSize": (.media, .integer),
        "nagram.stickerTimestamp": (.media, .boolean),
        "nagram.recentStickerLimit": (.media, .integer),
        "nagram.videoPIPSwipeDirection": (.media, .string),
        "nagram.musicPlaylistShowFileSize": (.media, .boolean),
        "nagram.musicPlaylistShowDownloadStatus": (.media, .boolean),
        "nagram.musicPlayerModernUI": (.media, .boolean),
        "nagram.mediaMetadataEnabled": (.media, .boolean),
        "nagram.fixLinkPreviews": (.media, .boolean),
        "nagram.locationIndicatorMode": (.appearance, .string),
        "nagram.screenshotBadgeMode": (.appearance, .string),
        "nagram.screenshotBadgeVerticalOffset": (.appearance, .string),
        "nagram.screenshotBadgeStyle": (.appearance, .string),
        "nagram.showDC": (.appearance, .boolean),
        "nagram.controlHighlightEnabled": (.appearance, .boolean),
        "nagram.glassTransparencyMode": (.appearance, .string),
        "nagram.glassTransparencyPercent": (.appearance, .integer),
        "nagram.hideChatBackUnreadCount": (.appearance, .boolean),
        "nagram.hideChatTitleGlass": (.appearance, .boolean),
        "nagram.chatHeaderBlurEnabled": (.appearance, .boolean),
        "nagram.chatHeaderShadeEnabled": (.appearance, .boolean),
        "nagram.chatHeaderLightShadeOpacity": (.appearance, .integer),
        "nagram.chatHeaderDarkShadeOpacity": (.appearance, .integer),
        "nagram.globalHeaderBlurEnabled": (.appearance, .boolean),
        "nagram.globalHeaderShadeEnabled": (.appearance, .boolean),
        "nagram.showProfileId": (.appearance, .boolean),
        "nagram.hideTabBarPermissionWarnings": (.appearance, .boolean),
        "nagram.showRegDate": (.appearance, .boolean),
        "nagram.groupProfileSettingItems": (.appearance, .string),
        "nagram.hidePhoneInSettings": (.appearance, .boolean),
        "nagram.confirmCalls": (.network, .boolean),
        "nagram.uploadSpeedBoost": (.network, .boolean),
        "nagram.downloadSpeedBoost": (.network, .string),
        "nagram.sessionBackupICloudSync": (.tools, .boolean),
        "nagram.unlimitedAccountsEnabled": (.tools, .boolean),
        "nagram.autoCheckForUpdates": (.tools, .boolean),
        "nagram.localPremiumEnabled": (.showcase, .boolean),
        "nextgram.showLocalProfileCard": (.showcase, .boolean),
        "nextgram.localProfileStars": (.showcase, .string),
        "nextgram.localProfileTon": (.showcase, .string),
        "nextgram.localProfilePhone": (.showcase, .string),
        "nextgram.localProfileRating": (.showcase, .string),
        "nagram.messageMenu.order": (.chat, .string),
        "nagram.messageMenu.disabled": (.chat, .string),
        "nagram.messageMenu.enabledDefaultDisabled": (.chat, .string),
    ]

    private let document: Document

    public static func export(categories: Set<NextgramSettingsCategory>, bottomBar: NagramBottomBarSettings, appIconName: String?) throws -> Data {
        let defaults = NagramDemoMode.userDefaults
        let settings = NagramSettings.shared
        var preferences: [String: Value] = [:]
        for (key, entry) in Self.keys where categories.contains(entry.category) {
            if key == "nagram.chatListMessagePreviewStyle" {
                preferences[key] = .string(settings.chatListMessagePreviewStyleMode.rawValue)
                continue
            }
            guard defaults.object(forKey: key) != nil else {
                preferences[key] = .unset
                continue
            }
            switch entry.kind {
            case .boolean:
                preferences[key] = .boolean(defaults.bool(forKey: key))
            case .integer:
                guard let value = Int32(exactly: defaults.integer(forKey: key)) else { throw BackupError.invalidFile }
                preferences[key] = .integer(value)
            case .string:
                guard let value = defaults.string(forKey: key) else { throw BackupError.invalidFile }
                preferences[key] = .string(value)
            }
        }
        let document = Document(
            format: Self.format,
            version: Self.version,
            preferences: preferences,
            bottomBar: categories.contains(.appearance) ? bottomBar : nil,
            regexFilters: categories.contains(.privacy) ? RegexFilters(enabled: settings.regexFiltersEnabled,
                filterOutgoing: settings.regexFiltersFilterOutgoing, rules: settings.regexFilterRules) : nil,
            notificationFallback: categories.contains(.notifications) ? settings.localNotificationFallbackEnabled : nil,
            appIcon: categories.contains(.appearance) ? AppIcon(name: appIconName) : nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        guard !categories.isEmpty, data.count <= Self.maximumFileSize else { throw BackupError.invalidFile }
        return data
    }

    public init(data: Data) throws {
        guard !data.isEmpty, data.count <= Self.maximumFileSize else { throw BackupError.invalidFile }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.format == Self.format, document.version == Self.version else { throw BackupError.invalidFile }
        for (key, value) in document.preferences {
            if let entry = Self.keys[key], !value.matches(entry.kind) {
                throw BackupError.invalidFile
            }
        }
        if let rules = document.regexFilters?.rules {
            var ids = Set<String>()
            for rule in rules {
                guard !rule.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      ids.insert(rule.id).inserted,
                      rule.authorPeerId.map({ $0 > 0 }) ?? true else { throw BackupError.invalidFile }
                if !rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || rule.authorPeerId == nil {
                    guard NagramRegexFilterRule.isValidPattern(rule.pattern) else { throw BackupError.invalidFile }
                }
            }
        }
        self.document = document
        guard !self.counts.isEmpty else { throw BackupError.noSettings }
    }

    public var counts: [NextgramSettingsCategory: Int] {
        var result: [NextgramSettingsCategory: Int] = [:]
        for key in self.document.preferences.keys {
            if let entry = Self.keys[key] { result[entry.category, default: 0] += 1 }
        }
        if self.document.bottomBar != nil { result[.appearance, default: 0] += 1 }
        if self.document.regexFilters != nil { result[.privacy, default: 0] += 1 }
        if self.document.notificationFallback != nil { result[.notifications, default: 0] += 1 }
        if self.document.appIcon != nil { result[.appearance, default: 0] += 1 }
        return result
    }

    public func notificationFallback(in categories: Set<NextgramSettingsCategory>) -> Bool? {
        return categories.contains(.notifications) ? self.document.notificationFallback : nil
    }

    public func appIcon(in categories: Set<NextgramSettingsCategory>) -> AppIcon? {
        return categories.contains(.appearance) ? self.document.appIcon : nil
    }

    // Apply only present keys. Explicit null restores the built-in default.
    @discardableResult
    public func restore(categories: Set<NextgramSettingsCategory>) -> NagramBottomBarSettings? {
        let settings = NagramSettings.shared
        let sync = NagramSettingsCloudSync.shared
        for (key, value) in self.document.preferences {
            guard let entry = Self.keys[key], categories.contains(entry.category) else { continue }
            switch value {
            case let .boolean(value): sync.set(value, forKey: key)
            case let .integer(value): sync.set(Self.validatedInteger(value, forKey: key), forKey: key)
            case let .string(value): sync.set(value, forKey: key)
            case .unset: sync.removeObject(forKey: key)
            }
        }
        if categories.contains(.chat) {
            if self.document.preferences["nagram.chatListMessagePreviewStyle"] != nil {
                sync.removeObject(forKey: "nagram.chatListLines")
            }
            if settings.chatListCompact {
                settings.chatListMessagePreviewStyle = NagramChatListMessagePreviewStyle.two.rawValue
            }
            if settings.chatListUnreadFirst && settings.chatListOldestFirst {
                settings.chatListOldestFirst = false
            }
            if settings.chatListStartupFolderModeValue == .specific,
               self.document.preferences["nagram.chatListStartupFolderMode"] != nil {
                settings.chatListStartupFolderMode = NagramChatListStartupFolderMode.telegramDefault.rawValue
            }
        }
        if categories.contains(.privacy), let filters = self.document.regexFilters {
            settings.regexFiltersEnabled = filters.enabled
            settings.regexFiltersFilterOutgoing = filters.filterOutgoing
            settings.regexFilterRules = filters.rules
        }
        var restoredBottomBar: NagramBottomBarSettings?
        if categories.contains(.appearance), var bottomBar = self.document.bottomBar {
            if bottomBar.searchMode == .bar && !bottomBar.visibleBottomItems.isEmpty {
                bottomBar.setSearchMode(.button)
            }
            settings.bottomBarSettings = bottomBar
            restoredBottomBar = settings.bottomBarSettings
        }
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: NagramDemoMode.userDefaults)
        NotificationCenter.default.post(name: Self.didRestoreNotification, object: nil)
        return restoredBottomBar
    }

    private static func validatedInteger(_ value: Int32, forKey key: String) -> Int32 {
        switch key {
        case "nagram.glassTransparencyPercent", "nagram.chatHeaderLightShadeOpacity", "nagram.chatHeaderDarkShadeOpacity":
            return min(100, max(0, value))
        case "nagram.stickerSize":
            return min(200, max(50, value))
        case "nagram.translationLLMTemperatureTenths":
            return min(20, max(0, value))
        case "nagram.chatListQuickFilterPeerTypes":
            return value & 31
        default:
            return value
        }
    }
}
