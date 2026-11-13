public enum NextgramSettingsCategory: String, CaseIterable {
    case chat
    case input
    case translation
    case privacy
    case media
    case appearance
    case notifications
    case network
    case tools
    case showcase

    public var titleKey: String {
        "Nagram.Settings.Category.\(self.rawValue)"
    }

    public var descriptionKey: String {
        "\(self.titleKey).Description"
    }
}
