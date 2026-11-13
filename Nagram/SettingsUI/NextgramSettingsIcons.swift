import UIKit

enum NextgramSettingsIcons {
    private static let bottomBar = make("rectangle.bottomthird.inset.filled", color: 0x5856d6)
    private static let badge = make("camera.viewfinder", color: 0x5856d6)
    private static let backup = make("externaldrive.fill", color: 0x00a6a6)
    private static let update = make("arrow.triangle.2.circlepath", color: 0x007aff)
    private static let plugins = make("puzzlepiece.extension.fill", color: 0xaf52de)
    private static let feed = make("newspaper.fill", color: 0xff9500)
    private static let translation = make("character.bubble.fill", color: 0xaf52de)
    private static let transcription = make("waveform", color: 0xff9500)
    private static let filters = make("line.3.horizontal.decrease.circle.fill", color: 0x34a853)
    private static let messageMenu = make("list.bullet.rectangle", color: 0xff9500)
    private static let diagnostics = make("waveform.path.ecg", color: 0x007aff)
    private static let profile = make("person.crop.rectangle", color: 0x007aff)
    private static let appIcon = make("app.fill", color: 0xaf52de)

    static func icon(for titleKey: String) -> UIImage? {
        switch titleKey {
        case "Nagram.BottomBarLayout": return self.bottomBar
        case "Nagram.Settings.AppIcons": return self.appIcon
        case "Nagram.BadgeStyle": return self.badge
        case "Nagram.Settings.Backup", "Nagram.SessionBackup",
             "Nagram.DeletedMessages.Export", "Nagram.DeletedMessages.Import": return self.backup
        case "Nagram.Update.Title": return self.update
        case "Nagram.ExteraPlugins": return self.plugins
        case "Nagram.ChannelFeed": return self.feed
        case "Nagram.TranslationLLMSettings": return self.translation
        case "Nagram.STTSettings": return self.transcription
        case "Nagram.AntiRecallRules", "Nagram.RegexFilters", "Nagram.InlineBotRules": return self.filters
        case "Nagram.MessageMenu": return self.messageMenu
        case "Nagram.TelegramLatency", "Nagram.NotificationDiagnostics": return self.diagnostics
        case "Nagram.GroupProfileSettings": return self.profile
        case "Nagram.About": return nextgramSettingsLogo
        default: return nil
        }
    }

    private static func make(_ name: String, color: UInt32) -> UIImage? {
        guard let symbol = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.0, weight: .semibold)) else {
            return nil
        }
        return UIGraphicsImageRenderer(size: CGSize(width: 30.0, height: 30.0)).image { _ in
            UIColor(red: CGFloat((color >> 16) & 0xff) / 255.0,
                green: CGFloat((color >> 8) & 0xff) / 255.0,
                blue: CGFloat(color & 0xff) / 255.0, alpha: 1.0).setFill()
            UIBezierPath(roundedRect: CGRect(x: 0.0, y: 0.0, width: 30.0, height: 30.0), cornerRadius: 7.0).fill()
            let scale = min(1.0, 19.0 / max(symbol.size.width, symbol.size.height))
            let size = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
            symbol.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: CGRect(
                x: (30.0 - size.width) * 0.5, y: (30.0 - size.height) * 0.5,
                width: size.width, height: size.height))
        }.withRenderingMode(.alwaysOriginal)
    }
}
