import NextgramLyrics
import UIKit

/// Uses the same glyph layout for the dim text and the timed sweep, including wrapped words.
final class NextgramLyricTextLabel: UILabel {
    var lyricLine: NextgramLyricLine?
    var sweepEnabled = false
    var glowEnabled = false
    var wordFloatEnabled = false
    var isActiveLine = false
    var position = 0.0
    var lyricColor = UIColor.white

    private var layoutColor = UIColor.clear
    private var textLayout: (String, UIFont, CGFloat, NSTextStorage, NSLayoutManager, NSTextContainer)?

    override func drawText(in rect: CGRect) {
        guard self.sweepEnabled || self.wordFloatEnabled, let line = self.lyricLine, !line.words.isEmpty,
              let context = UIGraphicsGetCurrentContext() else {
            super.drawText(in: rect)
            return
        }
        let font = self.font ?? UIFont.systemFont(ofSize: 28.0)
        let width = self.bounds.width
        if self.textLayout?.0 != line.text || self.textLayout?.1 != font || self.textLayout?.2 != width || self.layoutColor != self.lyricColor {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.alignment = self.textAlignment
            let storage = NSTextStorage(string: line.text, attributes: [.font: font, .paragraphStyle: paragraph, .foregroundColor: self.lyricColor])
            self.layoutColor = self.lyricColor
            let manager = NSLayoutManager()
            let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0.0
            manager.addTextContainer(container)
            storage.addLayoutManager(manager)
            self.textLayout = (line.text, font, width, storage, manager, container)
        }
        guard let layout = self.textLayout else { return }
        let storage = layout.3
        let manager = layout.4
        let container = layout.5
        manager.ensureLayout(for: container)
        // Measure from the label bounds so wrapped glyph positions stay consistent with the native text.
        let origin = CGPoint(x: 0.0, y: max(0.0, (self.bounds.height - manager.usedRect(for: container).height) * 0.5))
        let words = line.words.filter { word in
            word.range.location != NSNotFound && word.range.length > 0 && word.range.location <= storage.length &&
                word.range.length <= storage.length - word.range.location
        }.sorted { $0.range.location < $1.range.location }
        if self.wordFloatEnabled {
            var cursor = 0
            for word in words where word.range.location >= cursor {
                if word.range.location > cursor {
                    let gap = manager.glyphRange(forCharacterRange: NSRange(location: cursor, length: word.range.location - cursor), actualCharacterRange: nil)
                    self.drawGlyphs(gap, manager: manager, origin: origin, alpha: self.sweepEnabled ? 0.38 : 1.0, context: context)
                }
                let glyphs = manager.glyphRange(forCharacterRange: word.range, actualCharacterRange: nil)
                var alpha: CGFloat = self.sweepEnabled ? 0.38 : 1.0
                if self.isActiveLine && !self.sweepEnabled {
                    let progress = min(1.0, max(0.0, (self.position - word.time) / max(0.001, word.end - word.time)))
                    alpha = self.position <= word.time ? 0.46 : 0.54 + CGFloat(Int(progress * 8.0)) * 0.0575
                }
                self.drawGlyphs(glyphs, manager: manager,
                    origin: CGPoint(x: origin.x, y: origin.y + self.wordLift(word, font: font)), alpha: alpha, context: context)
                cursor = NSMaxRange(word.range)
            }
            if cursor < storage.length {
                self.drawGlyphs(manager.glyphRange(forCharacterRange: NSRange(location: cursor, length: storage.length - cursor), actualCharacterRange: nil),
                    manager: manager, origin: origin, alpha: self.sweepEnabled ? 0.38 : 1.0, context: context)
            }
        } else {
            context.saveGState()
            context.setAlpha(0.38)
            super.drawText(in: rect)
            context.restoreGState()
        }

        guard self.sweepEnabled else { return }
        for word in words where self.position > word.time {
            let progress = min(1.0, max(0.0, (self.position - word.time) / max(0.001, word.end - word.time)))
            let glyphs = manager.glyphRange(forCharacterRange: word.range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { continue }
            var wordRects: [CGRect] = []
            manager.enumerateEnclosingRects(forGlyphRange: glyphs,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
                wordRects.append(rect.offsetBy(dx: origin.x, dy: origin.y))
            }
            let totalWidth = wordRects.reduce(CGFloat(0.0)) { $0 + $1.width }
            var remaining = totalWidth * progress
            for wordRect in wordRects {
                let fraction = min(1.0, max(0.0, remaining / max(1.0, wordRect.width)))
                remaining -= wordRect.width
                guard fraction > 0.0 else { continue }
                let text = (line.text as NSString).substring(with: word.range)
                let letter = text.unicodeScalars.first(where: { CharacterSet.letters.contains($0) })?.value ?? 0
                let reversed = (0x0590 ... 0x08ff).contains(letter) || (0xfb1d ... 0xfdff).contains(letter) ||
                    (0xfe70 ... 0xfeff).contains(letter) || (0x1ee00 ... 0x1eeff).contains(letter)
                if fraction >= 1.0 {
                    self.drawHighlight(in: wordRect, textRect: rect, alpha: 1.0, context: context, manager: manager, glyphs: glyphs, origin: origin, lift: self.wordLift(word, font: font))
                } else {
                    let feather = min(8.0, wordRect.width * 0.3)
                    let edge = (wordRect.width + feather) * fraction - feather
                    let brightWidth = min(wordRect.width, max(0.0, edge))
                    let bright = CGRect(x: reversed ? wordRect.maxX - brightWidth : wordRect.minX,
                        y: wordRect.minY, width: brightWidth, height: wordRect.height)
                    self.drawHighlight(in: bright, textRect: rect, alpha: 1.0, context: context, manager: manager, glyphs: glyphs, origin: origin, lift: self.wordLift(word, font: font))
                    for stripe in 0 ..< 8 {
                        let lower = max(0.0, edge + CGFloat(stripe) * feather / 8.0)
                        let upper = min(wordRect.width, edge + CGFloat(stripe + 1) * feather / 8.0)
                        guard upper > lower else { continue }
                        let band = CGRect(x: reversed ? wordRect.maxX - upper : wordRect.minX + lower,
                            y: wordRect.minY, width: upper - lower, height: wordRect.height)
                        self.drawHighlight(in: band, textRect: rect, alpha: 1.0 - (CGFloat(stripe) + 0.5) / 8.0, context: context, manager: manager, glyphs: glyphs, origin: origin, lift: self.wordLift(word, font: font))
                    }
                }
            }
        }
    }

    private func wordLift(_ word: NextgramLyricWord, font: UIFont) -> CGFloat {
        guard self.wordFloatEnabled else { return 0.0 }
        let progress = min(1.0, max(0.0, (self.position - word.time) / max(1.0, word.end - word.time)))
        let eased = 1.0 - pow(1.0 - progress, 3.0)
        return -min(3.0, max(1.5, font.pointSize * 0.072)) * CGFloat(eased)
    }

    private func drawGlyphs(_ glyphs: NSRange, manager: NSLayoutManager, origin: CGPoint, alpha: CGFloat, context: CGContext) {
        guard glyphs.length > 0 else { return }
        context.saveGState()
        context.setAlpha(alpha)
        manager.drawGlyphs(forGlyphRange: glyphs, at: origin)
        context.restoreGState()
    }

    private func drawHighlight(in clip: CGRect, textRect: CGRect, alpha: CGFloat, context: CGContext,
        manager: NSLayoutManager, glyphs: NSRange, origin: CGPoint, lift: CGFloat) {
        guard clip.width > 0.0, clip.height > 0.0 else { return }
        context.saveGState()
        context.clip(to: clip.offsetBy(dx: 0.0, dy: lift).insetBy(dx: 0.0, dy: -4.0))
        context.setAlpha(alpha)
        if self.glowEnabled {
            context.setShadow(offset: .zero, blur: 6.0, color: self.lyricColor.withAlphaComponent(0.7).cgColor)
        }
        if self.wordFloatEnabled {
            manager.drawGlyphs(forGlyphRange: glyphs, at: CGPoint(x: origin.x, y: origin.y + lift))
        } else {
            super.drawText(in: textRect)
        }
        context.restoreGState()
    }
}
