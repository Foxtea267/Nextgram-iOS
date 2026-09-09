import Foundation

public enum NagramAntiRecallEntityKind: String {
    case user
    case bot
    case group
    case channel
}

public struct NagramAntiRecallEntity {
    public let id: Int64
    public let usernames: [String]
    public let kind: NagramAntiRecallEntityKind

    public init(id: Int64, usernames: [String], kind: NagramAntiRecallEntityKind) {
        self.id = id
        self.usernames = usernames
        self.kind = kind
    }
}

/// Parsed anti-recall rules. One rule can be written per line or separated with commas.
/// Supported forms: `123`, `id:123`, `@name`, `user:123`, `bot:@name`,
/// `group:@name`, `channel:123`, and the type-only rules `user`, `bot`, `group`, `channel`.
public struct NagramAntiRecallFilters {
    private struct Rule {
        let kind: NagramAntiRecallEntityKind?
        let id: Int64?
        let username: String?
    }

    private let whitelist: [Rule]
    private let blacklist: [Rule]
    private let excludedKeywords: [String]

    public init(whitelist: String, blacklist: String, excludedKeywords: String) {
        self.whitelist = Self.parseRules(whitelist)
        self.blacklist = Self.parseRules(blacklist)
        self.excludedKeywords = Self.components(excludedKeywords).map { $0.lowercased() }
    }

    public func shouldPreserve(entities: [NagramAntiRecallEntity], text: String) -> Bool {
        let normalizedText = text.lowercased()
        if self.excludedKeywords.contains(where: { normalizedText.contains($0) }) {
            return false
        }
        if self.blacklist.contains(where: { Self.matches($0, entities: entities) }) {
            return false
        }
        return self.whitelist.isEmpty || self.whitelist.contains(where: { Self.matches($0, entities: entities) })
    }

    private static func components(_ value: String) -> [String] {
        return value
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",，")))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private static func parseRules(_ value: String) -> [Rule] {
        return self.components(value).compactMap { component in
            var token = component.lowercased()
            var kind: NagramAntiRecallEntityKind?
            if let separator = token.firstIndex(of: ":") {
                let prefix = String(token[..<separator])
                if let parsedKind = NagramAntiRecallEntityKind(rawValue: prefix) {
                    kind = parsedKind
                    token = String(token[token.index(after: separator)...])
                } else if prefix == "id" {
                    token = String(token[token.index(after: separator)...])
                }
            }
            token = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty, let kind {
                return Rule(kind: kind, id: nil, username: nil)
            }
            if let typeOnlyKind = NagramAntiRecallEntityKind(rawValue: token), kind == nil {
                return Rule(kind: typeOnlyKind, id: nil, username: nil)
            }
            if let id = Int64(token) {
                return Rule(kind: kind, id: id, username: nil)
            }
            if token.hasPrefix("@") {
                token.removeFirst()
            }
            guard !token.isEmpty else {
                return nil
            }
            return Rule(kind: kind, id: nil, username: token)
        }
    }

    private static func matches(_ rule: Rule, entities: [NagramAntiRecallEntity]) -> Bool {
        return entities.contains(where: { entity in
            if let kind = rule.kind, entity.kind != kind {
                return false
            }
            if let id = rule.id {
                return entity.id == id || (id != Int64.min && entity.id == -id)
            }
            if let username = rule.username {
                return entity.usernames.contains(where: { $0.lowercased() == username })
            }
            return rule.kind != nil
        })
    }
}
