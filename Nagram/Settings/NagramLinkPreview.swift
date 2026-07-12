import Foundation

/// Returns the URL used only to generate a webpage preview. The message text keeps
/// the original URL, allowing Telegram to attach the improved preview without
/// changing the link visible to recipients.
public func nagramLinkPreviewUrl(_ value: String) -> String {
    let parsedValue: String
    if value.range(of: "://") == nil {
        parsedValue = "https://\(value)"
    } else {
        parsedValue = value
    }

    guard var components = URLComponents(string: parsedValue), let host = components.host?.lowercased() else {
        return value
    }
    guard host == "x.com" || host == "www.x.com" else {
        return value
    }

    components.host = "fixupx.com"
    return components.string ?? value
}
