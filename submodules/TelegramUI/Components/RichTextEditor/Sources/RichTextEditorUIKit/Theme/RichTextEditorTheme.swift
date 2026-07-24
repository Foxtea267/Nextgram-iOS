#if canImport(UIKit)
import UIKit

/// Host-settable colors for the editor. Set via `RichTextEditorView.theme`; applied at render time only and
/// never written into the `Document` model. `default` reproduces the editor's prior hardcoded colors, so the
/// look is unchanged until a host assigns a theme.
@available(iOS 13.0, *)
public struct RichTextEditorTheme {
    /// Default foreground for runs without an explicit color (and for list markers' conceptual text color).
    public var primaryText: UIColor
    /// Default foreground for `.caption`-style runs. Defaults to the same value as `primaryText` until a
    /// host assigns a distinct color.
    public var secondaryText: UIColor
    /// Empty-paragraph, marked-text, and media placeholder ("ghost") text.
    public var placeholder: UIColor
    /// Placeholder ("ghost") text INSIDE containers — the pull-quote / block-quote / code-block empty hints and
    /// the code-block language label — so a host can contrast them against the container fill. Defaults to
    /// `placeholder`.
    public var containerPlaceholder: UIColor
    /// Accent color. Drives link-text foreground, the blockquote bar + fill, the caret, and the selection
    /// highlight (these render sites are wired to read this across the theme feature's tasks).
    public var accent: UIColor
    /// The "shadow" caret drawn during a long-press magnifier (loupe) drag: it marks the snapped real-caret
    /// position while the accent-colored gliding cursor follows the finger. Render-only; defaults to a light gray.
    public var shadowCursor: UIColor
    /// Table grid lines.
    public var tableBorder: UIColor
    /// Table header-row background fill.
    public var tableHeaderBackground: UIColor
    /// Code-block background fill.
    public var codeBackground: UIColor
    /// List bullet/number marker color. Conceptually the list's text color. (Was hardcoded `.label`.)
    public var listMarker: UIColor
    /// Inline-code run background pill. (Was hardcoded `.systemGray5`.)
    public var inlineCodeBackground: UIColor
    /// IME marked-text (composing) underline. (Was hardcoded `.label`.)
    public var markedTextUnderline: UIColor
    /// Misspelling underline (the red spelling squiggle). Own-drawn; render-only. (Was hardcoded `.systemRed`.)
    public var misspellingUnderline: UIColor
    /// Grammar-error underline (native `.grammar` flags). Own-drawn; render-only.
    public var grammarUnderline: UIColor
    /// Autocorrect/correction underline (native `.correction` flags — carry alternatives). Own-drawn; render-only.
    public var correctionUnderline: UIColor
    /// Spoiler particle ("dust") color. (Was hardcoded `.secondaryLabel`.)
    public var spoilerDust: UIColor
    /// Quote AUTHOR (attribution) line text color — pull-quote and block-quote author runs. Render-only,
    /// like `primaryText`/`secondaryText` (see `QuoteAuthorSupport.swift`: injected as the runs' default
    /// foreground on render, stripped back to nil on read-back). Defaults to `secondaryText` until a host
    /// sets a distinct value, so there is no visual change out of the box.
    public var quoteAuthorText: UIColor
    /// Quote AUTHOR (attribution) line placeholder ("Add author") color. Defaults to `placeholder` until a
    /// host sets a distinct value.
    public var quoteAuthorPlaceholder: UIColor

    public init(
        primaryText: UIColor,
        secondaryText: UIColor,
        placeholder: UIColor,
        accent: UIColor,
        tableBorder: UIColor,
        tableHeaderBackground: UIColor,
        codeBackground: UIColor,
        listMarker: UIColor = .label,
        inlineCodeBackground: UIColor = .systemGray5,
        markedTextUnderline: UIColor = .label,
        spoilerDust: UIColor = .secondaryLabel,
        containerPlaceholder: UIColor = .placeholderText,
        shadowCursor: UIColor = UIColor(white: 0.7, alpha: 1.0),
        quoteAuthorText: UIColor? = nil,
        quoteAuthorPlaceholder: UIColor? = nil,
        misspellingUnderline: UIColor = .systemRed,
        grammarUnderline: UIColor = .systemGreen,
        correctionUnderline: UIColor = UIColor(red: 153.0/255.0, green: 172.0/255.0, blue: 235.0/255.0, alpha: 1.0)
    ) {
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.placeholder = placeholder
        self.accent = accent
        self.tableBorder = tableBorder
        self.tableHeaderBackground = tableHeaderBackground
        self.codeBackground = codeBackground
        self.listMarker = listMarker
        self.inlineCodeBackground = inlineCodeBackground
        self.markedTextUnderline = markedTextUnderline
        self.spoilerDust = spoilerDust
        self.containerPlaceholder = containerPlaceholder
        self.shadowCursor = shadowCursor
        self.quoteAuthorText = quoteAuthorText ?? secondaryText
        self.quoteAuthorPlaceholder = quoteAuthorPlaceholder ?? placeholder
        self.misspellingUnderline = misspellingUnderline
        self.grammarUnderline = grammarUnderline
        self.correctionUnderline = correctionUnderline
    }

    /// Reproduces the editor's prior hardcoded colors exactly (see the design doc's site inventory).
    public static let `default` = RichTextEditorTheme(
        primaryText: .black,
        secondaryText: .black,
        placeholder: .placeholderText,
        accent: .link,
        // Prior `TableBlockBox.gridColor` (dynamic light #E0E0E0 / dark white 0.27).
        tableBorder: UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor(white: 0.27, alpha: 1) : UIColor(white: 0.88, alpha: 1)
        },
        // Prior `TableBlockBox.headerRowBackground`.
        tableHeaderBackground: UIColor(white: 0.5, alpha: 0.1),
        codeBackground: UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor(white: 0.16, alpha: 1) : UIColor(white: 0.95, alpha: 1)
        },
        listMarker: .label,
        inlineCodeBackground: .systemGray5,
        markedTextUnderline: .label,
        spoilerDust: .secondaryLabel,
        containerPlaceholder: .placeholderText
    )
}
#endif
