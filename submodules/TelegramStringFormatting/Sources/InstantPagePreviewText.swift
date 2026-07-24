import Foundation
import UIKit
import CoreText
import Postbox
import TelegramCore
import TelegramPresentationData
import AppBundle

private enum InstantPagePreviewIcon: Int32 {
    case formula
    case table
}

private let iconAttribute = NSAttributedString.Key("TelegramInstantPagePreviewIcon")

public func renderInstantPagePreviewIcons(_ text: NSAttributedString, font: UIFont, textColor: UIColor) -> NSAttributedString {
    let result = NSMutableAttributedString(attributedString: text)
    var replacements: [(range: NSRange, image: UIImage, font: UIFont, textColor: UIColor)] = []
    result.enumerateAttribute(iconAttribute, in: NSRange(location: 0, length: result.length)) { value, range, _ in
        guard let rawValue = (value as? NSNumber)?.int32Value, let icon = InstantPagePreviewIcon(rawValue: rawValue) else {
            return
        }

        let imageName: String
        switch icon {
        case .formula:
            imageName = "Chat List/FormulaIcon"
        case .table:
            imageName = "Chat List/TableIcon"
        }
        if let image = UIImage(bundleImageName: imageName)?.withRenderingMode(.alwaysTemplate) {
            let rangeFont = result.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont ?? font
            let rangeTextColor = result.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor ?? textColor
            replacements.append((range, image, rangeFont, rangeTextColor))
        }
    }
    
    final class RunDelegateData {
        let ascent: CGFloat
        let descent: CGFloat
        let width: CGFloat

        init(ascent: CGFloat, descent: CGFloat, width: CGFloat) {
            self.ascent = ascent
            self.descent = descent
            self.width = width
        }
    }

    for replacement in replacements.reversed() {
        let runDelegateData = RunDelegateData(
            ascent: replacement.font.ascender,
            descent: abs(replacement.font.descender),
            width: replacement.image.size.width
        )
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateCurrentVersion,
            dealloc: { dataRef in
                Unmanaged<RunDelegateData>.fromOpaque(dataRef).release()
            },
            getAscent: { dataRef in
                return Unmanaged<RunDelegateData>.fromOpaque(dataRef).takeUnretainedValue().ascent
            },
            getDescent: { dataRef in
                return Unmanaged<RunDelegateData>.fromOpaque(dataRef).takeUnretainedValue().descent
            },
            getWidth: { dataRef in
                return Unmanaged<RunDelegateData>.fromOpaque(dataRef).takeUnretainedValue().width
            }
        )

        var attributes: [NSAttributedString.Key: Any] = [
            .font: replacement.font,
            .foregroundColor: replacement.textColor,
            .attachment: replacement.image
        ]
        if let runDelegate = CTRunDelegateCreate(&callbacks, Unmanaged.passRetained(runDelegateData).toOpaque()) {
            attributes[NSAttributedString.Key(kCTRunDelegateAttributeName as String)] = runDelegate
        }
        result.replaceCharacters(in: replacement.range, with: NSAttributedString(string: "\u{fffc}", attributes: attributes))
    }

    return result
}

extension RichText {
    public func previewAttributedText(strings: PresentationStrings) -> NSAttributedString {
        switch self {
        case .empty:
            return NSAttributedString()
        case let .plain(value):
            return NSAttributedString(string: value)
        case let .bold(value):
            return value.previewAttributedText(strings: strings)
        case let .italic(value):
            return value.previewAttributedText(strings: strings)
        case let .underline(value):
            return value.previewAttributedText(strings: strings)
        case let .strikethrough(value):
            let result = NSMutableAttributedString(attributedString: value.previewAttributedText(strings: strings))
            if result.length != 0 {
                result.addAttribute(
                    .strikethroughStyle,
                    value: NSNumber(value: NSUnderlineStyle.single.rawValue),
                    range: NSRange(location: 0, length: result.length)
                )
            }
            return result
        case let .fixed(value):
            return value.previewAttributedText(strings: strings)
        case let .url(value, _, _):
            return value.previewAttributedText(strings: strings)
        case let .email(value, _):
            return value.previewAttributedText(strings: strings)
        case let .concat(values):
            let result = NSMutableAttributedString()
            for value in values {
                result.append(value.previewAttributedText(strings: strings))
            }
            return result
        case let .`subscript`(value):
            return value.previewAttributedText(strings: strings)
        case let .superscript(value):
            return value.previewAttributedText(strings: strings)
        case let .marked(value):
            return value.previewAttributedText(strings: strings)
        case let .phone(value, _):
            return value.previewAttributedText(strings: strings)
        case .image:
            return NSAttributedString(string: strings.Message_Photo)
        case let .anchor(value, _):
            return value.previewAttributedText(strings: strings)
        case .formula:
            return NSAttributedString(
                string: strings.RichTextPreview_Formula,
                attributes: [ iconAttribute: NSNumber(value: InstantPagePreviewIcon.formula.rawValue) ]
            )
        case let .textCustomEmoji(_, alt):
            return NSAttributedString(string: alt)
        case let .textAutoEmail(value), let .textAutoPhone(value), let .textAutoUrl(value), let .textBankCard(value), let .textBotCommand(value), let .textCashtag(value), let .textHashtag(value), let .textMention(value), let .textMentionName(value, _), let .textSpoiler(value), let .textDate(value, _, _):
            return value.previewAttributedText(strings: strings)
        }
    }

    public func previewText(strings: PresentationStrings) -> String {
        return self.previewAttributedText(strings: strings).string
    }
}

extension InstantPageListItem {
    public func previewAttributedText(strings: PresentationStrings, media: [MediaId: Media]) -> NSAttributedString {
        switch self {
        case .unknown:
            return NSAttributedString()
        case let .text(text, num, checked):
            let result = NSMutableAttributedString()
            if let checked {
                result.append(NSAttributedString(string: "\(checked ? "☑︎" : "☐") "))
            } else if let num, !num.isEmpty {
                result.append(NSAttributedString(string: "\(num). "))
            }
            result.append(text.previewAttributedText(strings: strings))
            return result
        case let .blocks(blocks, num, checked):
            let blocksText = NSMutableAttributedString()
            for block in blocks {
                if blocksText.length != 0 {
                    blocksText.append(NSAttributedString(string: "\n"))
                }
                blocksText.append(block.previewAttributedText(strings: strings, media: media))
            }
            let result = NSMutableAttributedString()
            if let checked {
                result.append(NSAttributedString(string: "\(checked ? "☑︎" : "☐") "))
            } else if let num {
                result.append(NSAttributedString(string: "\(num). "))
            }
            result.append(blocksText)
            return result
        }
    }

    public func previewText(strings: PresentationStrings, media: [MediaId: Media]) -> String {
        return self.previewAttributedText(strings: strings, media: media).string
    }
}

extension InstantPageBlock {
    public func previewAttributedText(strings: PresentationStrings, media: [MediaId: Media]) -> NSAttributedString {
        switch self {
        case .unsupported:
            return NSAttributedString()
        case let .title(text), let .subtitle(text), let .header(text), let .subheader(text), let .paragraph(text), let .footer(text):
            return text.previewAttributedText(strings: strings)
        case let .authorDate(author, _):
            return author.previewAttributedText(strings: strings)
        case let .heading(text, _), let .preformatted(text, _):
            return text.previewAttributedText(strings: strings)
        case .formula:
            return NSAttributedString(
                string: strings.RichTextPreview_Formula,
                attributes: [ iconAttribute: NSNumber(value: InstantPagePreviewIcon.formula.rawValue) ]
            )
        case .divider:
            return NSAttributedString(string: "\n")
        case .anchor:
            return NSAttributedString()
        case let .list(items, _):
            let result = NSMutableAttributedString()
            for item in items {
                if result.length != 0 {
                    result.append(NSAttributedString(string: "\n"))
                }
                result.append(item.previewAttributedText(strings: strings, media: media))
            }
            return result
        case let .blockQuote(blocks, caption, _):
            let result = NSMutableAttributedString()
            for block in blocks {
                if result.length != 0 {
                    result.append(NSAttributedString(string: " "))
                }
                result.append(block.previewAttributedText(strings: strings, media: media))
            }
            result.append(caption.previewAttributedText(strings: strings))
            return result
        case let .pullQuote(text, caption):
            let result = NSMutableAttributedString(attributedString: text.previewAttributedText(strings: strings))
            result.append(caption.previewAttributedText(strings: strings))
            return result
        case .image(_, _, _, _, _):
            return NSAttributedString(string: strings.Message_Photo)
        case .video(_, _, _, _, _):
            return NSAttributedString(string: strings.Message_Video)
        case let .audio(id, _):
            if let file = media[id] as? TelegramMediaFile, file.isVoice {
                return NSAttributedString(string: strings.Message_Audio)
            } else {
                return NSAttributedString(string: strings.RichTextPreview_Music)
            }
        case .cover, .webEmbed, .postEmbed, .collage, .slideshow, .channelBanner, .kicker, .thinking, .details, .relatedArticles:
            return NSAttributedString()
        case .table:
            return NSAttributedString(
                string: strings.RichTextPreview_Formula,
                attributes: [ iconAttribute: NSNumber(value: InstantPagePreviewIcon.table.rawValue) ]
            )
        case .map:
            return NSAttributedString(string: strings.Message_Location)
        }
    }

    public func previewText(strings: PresentationStrings, media: [MediaId: Media]) -> String {
        return self.previewAttributedText(strings: strings, media: media).string
    }
}

extension InstantPage {
    public func previewAttributedText(strings: PresentationStrings) -> NSAttributedString {
        let maxLength: Int = 200
        let result = NSMutableAttributedString()
        for block in self.blocks {
            if result.length != 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            result.append(block.previewAttributedText(strings: strings, media: self.media))
            if result.string.count > maxLength {
                break
            }
        }
        return result
    }

    public func previewText(strings: PresentationStrings) -> String {
        return self.previewAttributedText(strings: strings).string
    }
}
