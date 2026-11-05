import Foundation

// MARK: NAGRAM — 设置搜索的中文子串匹配。
// 上游按系统分词做词前缀匹配，中文只能从词首搜到（「秒」搜不到「显示秒数」取决于分词）。
// 这里只对含 CJK 字符的查询词做子串匹配，其余词仍走调用方的词前缀匹配，避免 "id" 命中 "hide" 这类噪声。
private func nagramSearchWordContainsCJK(_ word: String) -> Bool {
    for scalar in word.unicodeScalars {
        switch scalar.value {
        case 0x3040 ... 0x30FF, 0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF, 0xF900 ... 0xFAFF, 0x20000 ... 0x2FA1F:
            return true
        default:
            break
        }
    }
    return false
}

/// 查询里没有 CJK 词时返回 false（交给调用方原有的匹配）；否则要求每个词都命中。
public func nagramSettingsSearchMatchesSubstring(query: String, text: String, matchesWord: (String) -> Bool) -> Bool {
    let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard words.contains(where: nagramSearchWordContainsCJK) else {
        return false
    }
    let text = text.lowercased()
    for word in words {
        if nagramSearchWordContainsCJK(word) {
            if !text.contains(word) {
                return false
            }
        } else if !matchesWord(word) {
            return false
        }
    }
    return true
}
