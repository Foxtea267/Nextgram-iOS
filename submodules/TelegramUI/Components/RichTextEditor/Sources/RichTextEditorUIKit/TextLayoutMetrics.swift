#if canImport(UIKit)
import UIKit

/// Per-host tunable text-layout metrics for the editor — a growable value set of render-only spacing /
/// line-height knobs. Every field defaults to the editor's built-in (reference-design) document look, so a
/// host that never sets `RichTextEditorView.textLayoutMetrics` is unchanged. The compact chat composer
/// assigns `.compact` (natural line height, no paragraph spacing) so multi-line text reads like the legacy
/// plain-text input rather than carrying the document editor's inter-line/inter-paragraph gaps. Set before
/// seeding the document (the compact-host knob convention).
///
/// More knobs are expected over time; each is a flat, explicitly-named field so additions don't churn the
/// API. Today's fields govern the default text paragraphs (body & caption); headings keep fixed metrics and
/// quotes are tuned separately via `QuoteStyle`.
@available(iOS 13.0, *)
public struct TextLayoutMetrics: Equatable {
    /// Line-height multiple for body & caption text. 1.0 = natural (a plain text field); the document
    /// default 1.10 adds a small inter-line gap. → `StyleSheet.bodyLineHeightMultiple`. An explicit
    /// per-paragraph `lineHeightMultiple` in the model still overrides this.
    public var bodyLineHeightMultiple: CGFloat
    /// Paragraph spacing above each body/caption paragraph, in points. → `StyleSheet.bodyParagraphSpacingBefore`.
    public var bodyParagraphSpacingBefore: CGFloat
    /// Paragraph spacing below each body/caption paragraph, in points — the inter-paragraph gap. The
    /// document default is 8; a compact host sets 0. → `StyleSheet.bodyParagraphSpacingAfter`.
    public var bodyParagraphSpacingAfter: CGFloat

    public init(bodyLineHeightMultiple: CGFloat = 1.10,
                bodyParagraphSpacingBefore: CGFloat = 0,
                bodyParagraphSpacingAfter: CGFloat = 8) {
        self.bodyLineHeightMultiple = bodyLineHeightMultiple
        self.bodyParagraphSpacingBefore = bodyParagraphSpacingBefore
        self.bodyParagraphSpacingAfter = bodyParagraphSpacingAfter
    }

    /// The editor's built-in document look (1.10 line height, 8pt inter-paragraph gap).
    public static let `default` = TextLayoutMetrics()
    /// Tight, plain-text-field metrics for a compact host: natural (1.0) line height, no paragraph spacing.
    public static let compact = TextLayoutMetrics(bodyLineHeightMultiple: 1.0,
                                                  bodyParagraphSpacingBefore: 0,
                                                  bodyParagraphSpacingAfter: 0)
}
#endif
