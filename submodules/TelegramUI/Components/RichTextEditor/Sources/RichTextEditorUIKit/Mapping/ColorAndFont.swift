#if canImport(UIKit)
import UIKit
import RichTextEditorCore

@available(iOS 13.0, *)
public extension RGBAColor {
    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

@available(iOS 13.0, *)
public extension UIColor {
    var rgba: RGBAColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBAColor(red: r, green: g, blue: b, alpha: a)
    }
}

@available(iOS 13.0, *)
public enum FontResolver {
    public static func font(family: String?, size: CGFloat, bold: Bool, italic: Bool, serif: Bool = false) -> UIFont {
        var descriptor: UIFontDescriptor
        if let family, let custom = UIFont(name: family, size: size) {
            descriptor = custom.fontDescriptor
        } else if serif, let serifDesc = UIFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif) {
            descriptor = serifDesc
        } else {
            descriptor = UIFont.systemFont(ofSize: size).fontDescriptor
        }
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if !traits.isEmpty,
           let d = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(traits)) {
            descriptor = d
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}
#endif
