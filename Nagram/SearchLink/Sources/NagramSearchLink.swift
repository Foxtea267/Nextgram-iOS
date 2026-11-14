import Foundation

// MARK: NAGRAM — 识别聊天列表搜索框里粘贴的 Telegram 链接。
// 只做文本判断，不发请求；结果交给通用链接打开流程（openUserGeneratedUrl），
// 所以打开时的确认、登录名检查和各类链接处理都与在聊天中点击链接一致。

public struct NagramSearchLink: Equatable {
    public enum Kind: Equatable {
        case message
        case invite
        case generic
    }

    /// 交给链接打开流程的地址：t.me 链接统一带 https，deeplink 保持原样。
    public let url: String
    /// 可交给 `resolveUrl` 预取消息的 t.me 地址；deeplink 为 nil。
    public let resolvableUrl: String?
    public let kind: Kind
    /// 搜索词没有写域名，由路径形态推断出的链接。
    public let isInferred: Bool

    /// 入口行展示的地址（去掉 https://）。
    public var displayUrl: String {
        if let resolvableUrl, resolvableUrl.hasPrefix("https://") {
            return String(resolvableUrl.dropFirst("https://".count))
        }
        return self.url
    }
}

private let telegramMeHosts: Set<String> = ["t.me", "telegram.me", "telegram.dog"]
// resolveUrl 把这些当作网页版短链直接外部打开，不是用户名子域。
private let telegramWebShortLinkHosts: Set<String> = ["a.t.me", "k.t.me", "z.t.me"]
// 用户名路径首段不可能是这些保留路径。
private let reservedFirstComponents: Set<String> = ["joinchat", "joinchannel", "addstickers", "addemoji", "addtheme", "addlist", "setlanguage", "share", "login", "proxy", "socks", "bg", "invoice", "boost", "giftcode", "contact", "iv", "s", "c", "m", "nft", "auction", "stars", "settings", "nasettings"]

private let maxQueryLength = 2048

public func nagramSearchLink(query: String, appSpecificScheme: String?) -> NagramSearchLink? {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed.count > maxQueryLength {
        return nil
    }
    if trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
        return nil
    }
    let lowercased = trimmed.lowercased()

    var deeplinkSchemes = ["tg"]
    if let appSpecificScheme, !appSpecificScheme.isEmpty, appSpecificScheme.lowercased() != "tg" {
        deeplinkSchemes.append(appSpecificScheme.lowercased())
    }
    for scheme in deeplinkSchemes where lowercased.hasPrefix(scheme + "://") {
        return deeplink(trimmed)
    }

    var rest = trimmed
    var hadScheme = false
    for prefix in ["https://", "http://"] where lowercased.hasPrefix(prefix) {
        rest = String(trimmed.dropFirst(prefix.count))
        hadScheme = true
        break
    }
    if rest.contains("://") {
        return nil
    }

    let hostEnd = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? rest.endIndex
    let host = rest[..<hostEnd].lowercased()
    let pathAndQuery = String(rest[hostEnd...])

    if telegramMeHosts.contains(host) {
        let components = pathComponents(pathAndQuery)
        if components.isEmpty {
            return nil
        }
        let url = "https://" + rest
        return NagramSearchLink(url: url, resolvableUrl: url, kind: classify(components), isInferred: false)
    }
    if host.hasSuffix(".t.me"), !telegramWebShortLinkHosts.contains(host) {
        let username = String(host.dropLast(".t.me".count))
        guard isUsername(username) else {
            return nil
        }
        let url = "https://" + rest
        let kind: NagramSearchLink.Kind = classify([username] + pathComponents(pathAndQuery))
        return NagramSearchLink(url: url, resolvableUrl: url, kind: kind, isInferred: false)
    }
    if hadScheme || host.contains(".") {
        return nil
    }
    return inferredLink(trimmed)
}

private func deeplink(_ url: String) -> NagramSearchLink? {
    guard let components = URLComponents(string: url), let host = components.host?.lowercased(), !host.isEmpty else {
        return nil
    }
    let queryNames = Set((components.queryItems ?? []).map { $0.name.lowercased() })
    let kind: NagramSearchLink.Kind
    switch host {
    case "join":
        kind = queryNames.contains("invite") ? .invite : .generic
    case "privatepost":
        kind = .message
    case "resolve":
        kind = queryNames.contains("post") ? .message : .generic
    default:
        kind = .generic
    }
    return NagramSearchLink(url: url, resolvableUrl: nil, kind: kind, isInferred: false)
}

/// 不带域名时只接受形态足够明确、不会和普通搜索词混淆的路径：
/// `+邀请码`、`joinchat/邀请码`、`c/频道ID/消息ID`、`用户名/消息ID`（可带话题 ID 和 `?` 参数）。
private func inferredLink(_ query: String) -> NagramSearchLink? {
    var path = query
    if path.hasPrefix("@") {
        path.removeFirst()
    }
    let components = pathComponents("/" + path)
    guard !components.isEmpty, path.first != "/" else {
        return nil
    }
    let kind: NagramSearchLink.Kind
    if components.count == 1, components[0].hasPrefix("+"), isInviteHash(String(components[0].dropFirst())) {
        kind = .invite
    } else if components.count == 2, ["joinchat", "joinchannel"].contains(components[0].lowercased()), isInviteHash(components[1]) {
        kind = .invite
    } else if (3 ... 4).contains(components.count), components[0].lowercased() == "c", components.dropFirst().allSatisfy(isNumber) {
        kind = .message
    } else if (2 ... 3).contains(components.count), isUsername(components[0]), !reservedFirstComponents.contains(components[0].lowercased()), components.dropFirst().allSatisfy(isNumber) {
        kind = .message
    } else {
        return nil
    }
    let url = "https://t.me/" + path
    guard URL(string: url) != nil else {
        return nil
    }
    return NagramSearchLink(url: url, resolvableUrl: url, kind: kind, isInferred: true)
}

private func classify(_ components: [String]) -> NagramSearchLink.Kind {
    guard let first = components.first else {
        return .generic
    }
    let lowercasedFirst = first.lowercased()
    // `t.me/s/<频道>/<消息>` 是网页预览形式，parseInternalUrl 会去掉 `s/` 前缀。
    if lowercasedFirst == "s", components.count >= 2 {
        return classify(Array(components.dropFirst()))
    }
    if first.hasPrefix("+") {
        // 纯数字的 `+号码` 是手机号链接。
        return isInviteHash(String(first.dropFirst())) ? .invite : .generic
    }
    if lowercasedFirst == "joinchat" || lowercasedFirst == "joinchannel" {
        return components.count >= 2 ? .invite : .generic
    }
    if lowercasedFirst == "c" {
        return components.count >= 3 && components.dropFirst().allSatisfy(isNumber) ? .message : .generic
    }
    if components.count >= 2, !reservedFirstComponents.contains(lowercasedFirst), isUsername(first), let last = components.last, isNumber(last) {
        return .message
    }
    return .generic
}

private func pathComponents(_ pathAndQuery: String) -> [String] {
    let pathEnd = pathAndQuery.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? pathAndQuery.endIndex
    return pathAndQuery[..<pathEnd].split(separator: "/", omittingEmptySubsequences: true).map(String.init)
}

private func isNumber(_ value: String) -> Bool {
    return !value.isEmpty && value.count <= 19 && value.allSatisfy { $0.isASCII && $0.isNumber }
}

private func isUsername(_ value: String) -> Bool {
    guard (4 ... 32).contains(value.count), let first = value.first, first.isASCII, first.isLetter else {
        return false
    }
    return value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
}

/// 邀请码是 base64url，至少含一个非数字字符，避免和 `+手机号` 混淆。
private func isInviteHash(_ value: String) -> Bool {
    guard value.count >= 8, value.count <= 64 else {
        return false
    }
    guard value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else {
        return false
    }
    return value.contains(where: { !$0.isNumber })
}
