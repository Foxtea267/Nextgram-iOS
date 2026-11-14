import Foundation
import TelegramCore

/// Plain authored content for preview/upload. Does not load media, embeds, URLs or a browser module.
func nextgramSummaryText(_ page: InstantPage) -> String {
    var output = ""
    var remaining = 4096
    func consume() -> Bool {
        guard remaining > 0, output.utf8.count <= 64000 else {
            if output.utf8.count <= 64000 { output.append(String(repeating: "!", count: 64001)) }
            return false
        }
        remaining -= 1
        return true
    }
    func append(_ text: String) {
        guard output.utf8.count <= 64000 else { return }
        if !output.isEmpty { output.append("\n") }
        // Keep an over-limit sentinel so the caller rejects rather than uploading silently truncated content.
        output.append(contentsOf: text.prefix(64001))
    }
    func blocks(_ values: [InstantPageBlock], depth: Int) {
        guard depth < 32 else { append(String(repeating: "!", count: 64001)); return }
        for block in values {
            guard consume() else { return }
            switch block {
            case let .title(text), let .subtitle(text), let .header(text), let .subheader(text),
                 let .paragraph(text), let .footer(text), let .kicker(text), let .thinking(text): append(text.plainText)
            case let .heading(text, _), let .preformatted(text, _), let .authorDate(text, _): append(text.plainText)
            case let .formula(latex): append(latex)
            case let .blockQuote(children, caption, _): blocks(children, depth: depth + 1); append(caption.plainText)
            case let .pullQuote(text, caption): append(text.plainText); append(caption.plainText)
            case let .details(title, children, _): append(title.plainText); blocks(children, depth: depth + 1)
            case let .cover(child): blocks([child], depth: depth + 1)
            case let .list(items, _):
                for item in items {
                    guard consume() else { return }
                    switch item {
                    case let .text(text, _, checked): append((checked.map { $0 ? "[x] " : "[ ] " } ?? "• ") + text.plainText)
                    case let .blocks(children, _, _): blocks(children, depth: depth + 1)
                    case .unknown: break
                    }
                }
            case let .table(title, rows, _, _, _):
                append(title.plainText)
                for row in rows {
                    guard consume() else { return }
                    var cells: [String] = []
                    var rowBytes = 0
                    for cell in row.cells {
                        guard consume() else { return }
                        let text = String((cell.text?.plainText ?? "").prefix(64001))
                        rowBytes += text.utf8.count + 3
                        guard rowBytes <= 64000 else { append(String(repeating: "!", count: 64001)); return }
                        cells.append(text)
                    }
                    append(cells.joined(separator: " | "))
                }
            case let .collage(children, caption), let .slideshow(children, caption):
                blocks(children, depth: depth + 1); append(caption.text.plainText)
            case let .image(_, caption, _, _, _), let .video(_, caption, _, _, _), let .audio(_, caption), let .document(_, caption):
                append(caption.text.plainText)
            case let .buttonRow(_, buttons):
                for button in buttons {
                    guard consume() else { return }
                    append(button.text.plainText)
                }
            default: break
            }
        }
    }
    blocks(page.blocks, depth: 0)
    return output
}
