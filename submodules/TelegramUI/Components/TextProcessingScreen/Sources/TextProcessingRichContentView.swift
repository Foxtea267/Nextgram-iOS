import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramCore
import TelegramPresentationData
import AccountContext
import TelegramUIPreferences
import InstantPageUI

/// Renders a `.rich` `ComposedRichMessage`'s `InstantPage` inside the text-processing sheet.
/// Interactivity is self-contained only: spoiler reveal and details/blockquote collapse work,
/// while navigation-shaped actions (links, media gallery, audio) are inert no-ops — matching
/// the long-press-Send preview and the plain areas' behavior.
final class TextProcessingRichContentView: UIView {
    private let context: AccountContext
    private let instantPage: InstantPage
    private let webpage: TelegramMediaWebpage
    private let pageView: InstantPageV2View

    var requestUpdate: (() -> Void)?

    private var expandedDetails: [Int: Bool] = [:]
    private var cachedBoundingWidth: CGFloat?
    private var cachedThemeIdentity: ObjectIdentifier?
    private var cachedContentSize: CGSize = .zero
    private(set) var currentTextLineMetrics: InstantPageV2TextLineMetrics?

    init(context: AccountContext, instantPage: InstantPage) {
        self.context = context
        self.instantPage = instantPage

        let webpage = TelegramMediaWebpage(webpageId: EngineMedia.Id(namespace: 0, id: 0), content: .Loaded(TelegramMediaWebpageLoadedContent(
            url: "",
            displayUrl: "",
            hash: 0,
            type: nil,
            websiteName: nil,
            title: nil,
            text: nil,
            embedUrl: nil,
            embedType: nil,
            embedSize: nil,
            duration: nil,
            author: nil,
            isMediaLargeByDefault: nil,
            imageIsVideoCover: false,
            image: nil,
            file: nil,
            story: nil,
            attributes: [],
            instantPage: instantPage
        )))
        self.webpage = webpage

        let renderContext = InstantPageV2RenderContext(
            context: context,
            webpage: webpage,
            sourceLocation: InstantPageSourceLocation(userLocation: .other, peerType: .channel),
            imageReference: { image in
                return ImageMediaReference.standalone(media: image)
            },
            fileReference: { file in
                return FileMediaReference.standalone(media: file)
            },
            present: { _, _ in },
            push: { _ in },
            openUrl: { _ in },
            baseNavigationController: { return nil },
            message: nil
        )
        self.pageView = InstantPageV2View(renderContext: renderContext)

        super.init(frame: CGRect())

        self.addSubview(self.pageView)

        self.pageView.detailsTapped = { [weak self] index in
            guard let self else {
                return
            }
            self.expandedDetails[index] = !(self.expandedDetails[index] ?? false)
            self.cachedBoundingWidth = nil
            self.requestUpdate?()
        }

        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.handleTap(_:))))
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard case .ended = recognizer.state else {
            return
        }
        guard !self.pageView.displayContentsUnderSpoilers else {
            return
        }
        let local = recognizer.location(in: self.pageView)
        guard let hit = self.pageView.textItemAt(point: local) else {
            return
        }
        let itemLocal = CGPoint(x: local.x - hit.parentOffset.x, y: local.y - hit.parentOffset.y)
        guard let (_, attributes) = hit.item.attributesAtPoint(itemLocal, orNearest: false) else {
            return
        }
        if attributes[NSAttributedString.Key(rawValue: "TelegramSpoiler")] != nil || attributes[NSAttributedString.Key(rawValue: "Attribute__Spoiler")] != nil {
            self.pageView.setDisplayContentsUnderSpoilers(true, atLocation: local, animated: true)
        }
    }

    func update(boundingWidth: CGFloat, theme: PresentationTheme, strings: PresentationStrings, transition: ComponentTransition) -> CGSize {
        let themeIdentity = ObjectIdentifier(theme)
        if self.cachedBoundingWidth == boundingWidth, self.cachedThemeIdentity == themeIdentity {
            self.pageView.frame = CGRect(origin: CGPoint(), size: self.cachedContentSize)
            return self.cachedContentSize
        }

        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        let pageTheme = textProcessingInstantPageTheme(theme: theme)

        let layout = layoutInstantPageV2(
            webpage: self.webpage,
            instantPage: self.instantPage,
            userLocation: .other,
            boundingWidth: boundingWidth,
            horizontalInset: 0.0,
            theme: pageTheme,
            strings: strings,
            dateTimeFormat: presentationData.dateTimeFormat,
            cachedMessageSyntaxHighlight: nil,
            expandedDetails: self.expandedDetails,
            fitToWidth: true
        )
        self.pageView.update(layout: layout, theme: pageTheme, animation: .None)
        self.pageView.frame = CGRect(origin: CGPoint(), size: layout.contentSize)

        self.cachedBoundingWidth = boundingWidth
        self.cachedThemeIdentity = themeIdentity
        self.cachedContentSize = layout.contentSize
        self.currentTextLineMetrics = layout.textLineMetrics()
        return layout.contentSize
    }
}

/// The sheet's InstantPage palette: the list item colors the plain text areas already use,
/// in the structure `ChatSendMessageRichTextPreview` established for the outgoing-bubble palette.
private func textProcessingInstantPageTheme(theme: PresentationTheme) -> InstantPageTheme {
    let isDark = theme.overallDarkAppearance
    let primary = theme.list.itemPrimaryTextColor
    let secondary = theme.list.itemSecondaryTextColor
    let accent = theme.list.itemAccentColor

    let codeBlockBackgroundColor: UIColor
    if isDark {
        codeBlockBackgroundColor = UIColor(white: 0.0, alpha: 0.25)
    } else {
        codeBlockBackgroundColor = accent.withMultipliedAlpha(0.1)
    }

    let textCategories = InstantPageTextCategories(
        kicker: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 0.685), color: primary),
        header: InstantPageTextAttributes(font: InstantPageFont(style: .serif, size: 24.0, lineSpacingFactor: 0.685), color: primary),
        subheader: InstantPageTextAttributes(font: InstantPageFont(style: .serif, size: 19.0, lineSpacingFactor: 0.685), color: primary),
        paragraph: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 17.0, lineSpacingFactor: 1.0), color: primary),
        caption: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 1.0), color: secondary),
        credit: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 13.0, lineSpacingFactor: 1.0), color: secondary),
        table: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 15.0, lineSpacingFactor: 1.0), color: primary),
        article: InstantPageTextAttributes(font: InstantPageFont(style: .serif, size: 18.0, lineSpacingFactor: 1.0), color: primary),
        codeBlock: InstantPageTextAttributes(font: InstantPageFont(style: .monospace, size: 14.0, lineSpacingFactor: 1.0), color: primary)
    )
    return InstantPageTheme(
        type: isDark ? .dark : .light,
        pageBackgroundColor: .clear,
        textCategories: textCategories,
        serif: false,
        codeBlockBackgroundColor: codeBlockBackgroundColor,
        linkColor: accent,
        textHighlightColor: accent.withMultipliedAlpha(0.1),
        linkHighlightColor: accent.withMultipliedAlpha(0.1),
        markerColor: UIColor(rgb: 0xfef3bc),
        panelBackgroundColor: accent.withMultipliedAlpha(0.1),
        panelHighlightedBackgroundColor: accent.withMultipliedAlpha(0.25),
        panelPrimaryColor: primary,
        panelSecondaryColor: secondary,
        panelAccentColor: accent,
        tableBorderColor: primary.withMultipliedAlpha(0.1),
        tableHeaderColor: primary.withMultipliedAlpha(0.05),
        controlColor: accent,
        imageTintColor: nil,
        overlayPanelColor: accent.withMultipliedAlpha(0.25),
        separatorColor: accent.withMultipliedAlpha(0.25),
        secondaryControlColor: secondary,
        quoteAccentColor: accent
    )
}
