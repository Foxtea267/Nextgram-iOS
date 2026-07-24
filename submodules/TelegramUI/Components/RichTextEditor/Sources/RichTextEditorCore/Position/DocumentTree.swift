import Foundation

/// True when a block quote's body has content that keeps its author line visible: any child that is NOT a
/// text-less, list-less paragraph (a blank line). Structural children — tables, sub-quotes, pull quotes,
/// media, code — count even when empty; an empty list item counts (it is structure the user created).
func quoteBodyHasContent(_ children: [Block]) -> Bool {
    children.contains { block in
        if case let .paragraph(p) = block { return p.utf16Count > 0 || p.list != nil }
        return true
    }
}

public enum DocumentTree {
    /// Builds the `.doc` root node for a document.
    public static func build(from document: Document) -> DocNode {
        .doc(children: document.blocks.map(node(for:)))
    }

    private static func node(for block: Block) -> DocNode {
        switch block {
        case .paragraph(let p):
            return .paragraph(id: p.id,
                              children: [.text(length: p.utf16Count, ref: .paragraph(p.id))])
        case .media(let img):
            if img.kind == .audio {
                // Audio is a caption-less atom — no caption paragraph node (nodeSize = 1 atom + 2 wrapper = 3).
                return .mediaBlock(id: img.id, children: [.mediaAtom(id: img.id)])
            }
            return .mediaBlock(id: img.id, children: [
                .mediaAtom(id: img.id),
                .paragraph(id: img.id,
                           children: [.text(length: img.captionUTF16Count, ref: .caption(img.id))]),
            ])
        case .table(let t):
            return .table(id: t.id, children: t.rows.map { row in
                .row(id: row.id, children: row.cells.map { cell in
                    .cell(id: cell.id, children: cell.blocks.map(node(for:)))
                })
            })
        case .code(let cb):
            // A code block reuses the paragraph node shape (content + 2 tokens); only the ref
            // distinguishes it so position mapping can identify it as code.
            return .paragraph(id: cb.id,
                              children: [.text(length: cb.utf16Count, ref: .code(cb.id))])
        case .pullQuote(let pq):
            // Always a `.blockQuote` container so the pull text stays at nodeStart+1 whether the author is
            // shown or hidden. The trailing author paragraph is present only when the quote has content
            // (author text OR pull text) — else the author region is absent (no tokens, no caret target).
            var children: [DocNode] = [
                .paragraph(id: pq.id, children: [.text(length: pq.utf16Count, ref: .pullQuote(pq.id))]),
            ]
            if pq.authorUTF16Count > 0 || pq.utf16Count > 0 {   // authorUTF16Count>0 mirrors PullQuoteBox.authorLength>0 exactly
                children.append(.paragraph(id: pq.id, children: [.text(length: pq.authorUTF16Count, ref: .quoteAuthor(pq.id))]))
            }
            return .blockQuote(id: pq.id, children: children)
        case .blockQuote(let bq):
            if bq.collapsed {
                // Folded → a caption-less atom, off the editable axis (nodeSize 3), like the old collapsedQuote.
                return .mediaBlock(id: bq.id, children: [.mediaAtom(id: bq.id)])
            }
            // Expanded → recursive container. The trailing author paragraph is present only when the quote
            // has content (author text OR body content — see `quoteBodyHasContent`); else the author region
            // is absent. Children are before the author, so their positions are unaffected either way.
            var children = bq.children.map(node(for:))
            if bq.authorUTF16Count > 0 || quoteBodyHasContent(bq.children) {   // authorUTF16Count>0 mirrors BlockQuoteBox.authorLength>0 exactly
                children.append(.paragraph(id: bq.id, children: [.text(length: bq.authorUTF16Count, ref: .quoteAuthor(bq.id))]))
            }
            return .blockQuote(id: bq.id, children: children)
        }
    }

    /// Maximum valid position (size of the document's content).
    public static func documentSize(_ document: Document) -> Int {
        build(from: document).nodeSize
    }
}
