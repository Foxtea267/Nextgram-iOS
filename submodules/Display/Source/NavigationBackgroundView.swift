import Foundation
import UIKit
import AsyncDisplayKit

// MARK: NAGRAM
public struct GlassOverlayTransparencySettings: Equatable {
    public let followsSystemTransparency: Bool
    public let tintStrength: CGFloat

    public init(followsSystemTransparency: Bool, tintStrength: CGFloat) {
        self.followsSystemTransparency = followsSystemTransparency
        self.tintStrength = max(0.0, min(1.0, tintStrength))
    }
}

public var currentGlassOverlayTransparencySettings: () -> GlassOverlayTransparencySettings = {
    return GlassOverlayTransparencySettings(followsSystemTransparency: true, tintStrength: 1.0)
}

private func glassOverlayReduceTransparencyEnabled(settings: GlassOverlayTransparencySettings) -> Bool {
    return settings.followsSystemTransparency && UIAccessibility.isReduceTransparencyEnabled
}

private func adjustedGlassOverlayColor(_ color: UIColor, settings: GlassOverlayTransparencySettings) -> UIColor {
    if glassOverlayReduceTransparencyEnabled(settings: settings) {
        return color.withAlphaComponent(1.0)
    }
    return color
}

public final class NavigationBackgroundNode: ASDisplayNode {
    private var _color: UIColor
    private var appliedTransparencySettings = currentGlassOverlayTransparencySettings()
    private var appliedReduceTransparencyEnabled = glassOverlayReduceTransparencyEnabled(settings: currentGlassOverlayTransparencySettings())

    public var color: UIColor {
        return self._color
    }
    
    private var enableBlur: Bool
    private var enableSaturation: Bool
    private var customBlurRadius: CGFloat?

    public var effectView: UIVisualEffectView?
    private let backgroundNode: ASDisplayNode
    
    public var backgroundView: UIView {
        return self.backgroundNode.view
    }

    private var validLayout: (CGSize, CGFloat)?
    
    public var backgroundCornerRadius: CGFloat {
        if let (_, cornerRadius) = self.validLayout {
            return cornerRadius
        } else {
            return 0.0
        }
    }

    public init(color: UIColor, enableBlur: Bool = true, enableSaturation: Bool = true, customBlurRadius: CGFloat? = nil) {
        self._color = .clear
        self.enableBlur = enableBlur
        self.enableSaturation = enableSaturation
        self.customBlurRadius = customBlurRadius

        self.backgroundNode = ASDisplayNode()

        super.init()

        self.addSubnode(self.backgroundNode)

        self.updateColor(color: color, transition: .immediate)
    }

    
    public override func didLoad() {
        super.didLoad()
        
        if self.scheduledUpdate {
            self.scheduledUpdate = false
            self.updateBackgroundBlur(forceKeepBlur: false)
        }
    }
    
    private var scheduledUpdate = false
    
    private func updateBackgroundBlur(forceKeepBlur: Bool) {
        guard self.isNodeLoaded else {
            self.scheduledUpdate = true
            return
        }
        let transparencySettings = currentGlassOverlayTransparencySettings()
        if self.enableBlur && !glassOverlayReduceTransparencyEnabled(settings: transparencySettings) && ((self._color.alpha > .ulpOfOne && self._color.alpha < 0.95) || forceKeepBlur) {
            if self.effectView == nil {
                let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .light))

                for subview in effectView.subviews {
                    if subview.description.contains("VisualEffectSubview") {
                        subview.isHidden = true
                    }
                }

                if let sublayer = effectView.layer.sublayers?[0], let filters = sublayer.filters {
                    sublayer.backgroundColor = nil
                    sublayer.isOpaque = false
                    var allowedKeys: [String] = [
                        "gaussianBlur"
                    ]
                    if self.enableSaturation {
                        allowedKeys.append("colorSaturate")
                    }
                    sublayer.filters = filters.filter { filter in
                        guard let filter = filter as? NSObject else {
                            return true
                        }
                        let filterName = String(describing: filter)
                        if !allowedKeys.contains(filterName) {
                            return false
                        }
                        if let customBlurRadius = self.customBlurRadius, filterName == "gaussianBlur" {
                            filter.setValue(customBlurRadius as NSNumber, forKey: "inputRadius")
                        }
                        return true
                    }
                }

                if let (size, cornerRadius) = self.validLayout {
                    effectView.frame = CGRect(origin: CGPoint(), size: size)
                    ContainedViewLayoutTransition.immediate.updateCornerRadius(layer: effectView.layer, cornerRadius: cornerRadius)
                    effectView.clipsToBounds = !cornerRadius.isZero
                }
                self.effectView = effectView
                self.view.insertSubview(effectView, at: 0)
            }
            self.effectView?.alpha = 1.0
        } else if let effectView = self.effectView {
            self.effectView = nil
            effectView.removeFromSuperview()
        }
    }

    public func updateColor(color: UIColor, enableBlur: Bool? = nil, enableSaturation: Bool? = nil, forceKeepBlur: Bool = false, transition: ContainedViewLayoutTransition) {
        let effectiveEnableBlur = enableBlur ?? self.enableBlur
        let effectiveEnableSaturation = enableSaturation ?? self.enableSaturation
        let transparencySettings = currentGlassOverlayTransparencySettings()
        let reduceTransparencyEnabled = glassOverlayReduceTransparencyEnabled(settings: transparencySettings)
        
        if self._color.isEqual(color) && self.enableBlur == effectiveEnableBlur && self.enableSaturation == effectiveEnableSaturation && self.appliedTransparencySettings == transparencySettings && self.appliedReduceTransparencyEnabled == reduceTransparencyEnabled {
            return
        }
        self._color = color
        self.enableBlur = effectiveEnableBlur
        self.enableSaturation = effectiveEnableSaturation
        self.appliedTransparencySettings = transparencySettings
        self.appliedReduceTransparencyEnabled = reduceTransparencyEnabled

        transition.updateBackgroundColor(node: self.backgroundNode, color: adjustedGlassOverlayColor(self._color, settings: transparencySettings))

        self.updateBackgroundBlur(forceKeepBlur: forceKeepBlur)
    }

    public func update(size: CGSize, cornerRadius: CGFloat = 0.0, transition: ContainedViewLayoutTransition, beginWithCurrentState: Bool = true) {
        self.validLayout = (size, cornerRadius)

        let contentFrame = CGRect(origin: CGPoint(), size: size)
        transition.updateFrame(node: self.backgroundNode, frame: contentFrame, beginWithCurrentState: true)
        if let effectView = self.effectView, effectView.frame != contentFrame {
            transition.updateFrame(layer: effectView.layer, frame: contentFrame, beginWithCurrentState: true)
            if let sublayers = effectView.layer.sublayers {
                for sublayer in sublayers {
                    transition.updateFrame(layer: sublayer, frame: contentFrame, beginWithCurrentState: true)
                }
            }
        }

        transition.updateCornerRadius(node: self.backgroundNode, cornerRadius: cornerRadius)
        if let effectView = self.effectView {
            transition.updateCornerRadius(layer: effectView.layer, cornerRadius: cornerRadius)
            effectView.clipsToBounds = !cornerRadius.isZero
        }
    }
    
    public func update(size: CGSize, cornerRadius: CGFloat = 0.0, animator: ControlledTransitionAnimator) {
        self.validLayout = (size, cornerRadius)

        let contentFrame = CGRect(origin: CGPoint(), size: size)
        animator.updateFrame(layer: self.backgroundNode.layer, frame: contentFrame, completion: nil)
        if let effectView = self.effectView, effectView.frame != contentFrame {
            animator.updateFrame(layer: effectView.layer, frame: contentFrame, completion: nil)
            if let sublayers = effectView.layer.sublayers {
                for sublayer in sublayers {
                    animator.updateFrame(layer: sublayer, frame: contentFrame, completion: nil)
                }
            }
        }

        animator.updateCornerRadius(layer: self.backgroundNode.layer, cornerRadius: cornerRadius, completion: nil)
        if let effectView = self.effectView {
            animator.updateCornerRadius(layer: effectView.layer, cornerRadius: cornerRadius, completion: nil)
            effectView.clipsToBounds = !cornerRadius.isZero
        }
    }
}

open class BlurredBackgroundView: UIView {
    private var _color: UIColor?
    private var appliedTransparencySettings = currentGlassOverlayTransparencySettings()
    private var appliedReduceTransparencyEnabled = glassOverlayReduceTransparencyEnabled(settings: currentGlassOverlayTransparencySettings())

    private var enableBlur: Bool
    private var customBlurRadius: CGFloat?

    public private(set) var effectView: UIVisualEffectView?
    private let backgroundView: UIView

    private var validLayout: (CGSize, CGFloat)?
    
    public var backgroundCornerRadius: CGFloat {
        if let (_, cornerRadius) = self.validLayout {
            return cornerRadius
        } else {
            return 0.0
        }
    }

    public init(color: UIColor?, enableBlur: Bool = true, customBlurRadius: CGFloat? = nil) {
        self._color = nil
        self.enableBlur = enableBlur
        self.customBlurRadius = customBlurRadius

        self.backgroundView = UIView()

        super.init(frame: CGRect())

        self.addSubview(self.backgroundView)

        if let color = color {
            self.updateColor(color: color, transition: .immediate)
        }
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func updateBackgroundBlur(forceKeepBlur: Bool) {
        let transparencySettings = currentGlassOverlayTransparencySettings()
        if let color = self._color, self.enableBlur && !glassOverlayReduceTransparencyEnabled(settings: transparencySettings) && ((color.alpha > .ulpOfOne && color.alpha < 0.95) || forceKeepBlur) {
            if self.effectView == nil {
                let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .light))

                for subview in effectView.subviews {
                    if subview.description.contains("VisualEffectSubview") {
                        subview.isHidden = true
                    }
                }

                if let sublayer = effectView.layer.sublayers?[0], let filters = sublayer.filters {
                    sublayer.backgroundColor = nil
                    sublayer.isOpaque = false
                    //sublayer.setValue(true as NSNumber, forKey: "allowsInPlaceFiltering")
                    let allowedKeys: [String] = [
                        "colorSaturate",
                        "gaussianBlur"
                    ]
                    sublayer.filters = filters.filter { filter in
                        guard let filter = filter as? NSObject else {
                            return true
                        }
                        let filterName = String(describing: filter)
                        if !allowedKeys.contains(filterName) {
                            return false
                        }
                        if let customBlurRadius = self.customBlurRadius, filterName == "gaussianBlur" {
                            filter.setValue(customBlurRadius as NSNumber, forKey: "inputRadius")
                        }
                        return true
                    }
                }

                if let (size, cornerRadius) = self.validLayout {
                    effectView.frame = CGRect(origin: CGPoint(), size: size)
                    ContainedViewLayoutTransition.immediate.updateCornerRadius(layer: effectView.layer, cornerRadius: cornerRadius)
                    effectView.clipsToBounds = !cornerRadius.isZero
                }
                self.effectView = effectView
                self.insertSubview(effectView, at: 0)
            }
            self.effectView?.alpha = 1.0
        } else if let effectView = self.effectView {
            self.effectView = nil
            effectView.removeFromSuperview()
        }
    }

    public func updateColor(color: UIColor, enableBlur: Bool? = nil, forceKeepBlur: Bool = false, transition: ContainedViewLayoutTransition) {
        let effectiveEnableBlur = enableBlur ?? self.enableBlur
        let transparencySettings = currentGlassOverlayTransparencySettings()
        let reduceTransparencyEnabled = glassOverlayReduceTransparencyEnabled(settings: transparencySettings)

        if self._color == color && self.enableBlur == effectiveEnableBlur && self.appliedTransparencySettings == transparencySettings && self.appliedReduceTransparencyEnabled == reduceTransparencyEnabled {
            return
        }
        self._color = color
        self.enableBlur = effectiveEnableBlur
        self.appliedTransparencySettings = transparencySettings
        self.appliedReduceTransparencyEnabled = reduceTransparencyEnabled

        transition.updateBackgroundColor(layer: self.backgroundView.layer, color: adjustedGlassOverlayColor(color, settings: transparencySettings))

        self.updateBackgroundBlur(forceKeepBlur: forceKeepBlur)
    }

    public func update(size: CGSize, cornerRadius: CGFloat = 0.0, maskedCorners: CACornerMask = [.layerMaxXMaxYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMinXMinYCorner], transition: ContainedViewLayoutTransition) {
        self.validLayout = (size, cornerRadius)

        let contentFrame = CGRect(origin: CGPoint(), size: size)
        transition.updateFrame(view: self.backgroundView, frame: contentFrame, beginWithCurrentState: true)
        if let effectView = self.effectView, effectView.frame != contentFrame {
            transition.updateFrame(layer: effectView.layer, frame: contentFrame, beginWithCurrentState: true)
            if let sublayers = effectView.layer.sublayers {
                for sublayer in sublayers {
                    transition.updateFrame(layer: sublayer, frame: contentFrame, beginWithCurrentState: true)
                }
            }
        }
        
        if #available(iOS 11.0, *) {
            self.backgroundView.layer.maskedCorners = maskedCorners
        }

        transition.updateCornerRadius(layer: self.backgroundView.layer, cornerRadius: cornerRadius)
        if let effectView = self.effectView {
            transition.updateCornerRadius(layer: effectView.layer, cornerRadius: cornerRadius)
            effectView.clipsToBounds = !cornerRadius.isZero
            
            if #available(iOS 11.0, *) {
                effectView.layer.maskedCorners = maskedCorners
            }
        }
    }
    
    public func update(size: CGSize, cornerRadius: CGFloat = 0.0, animator: ControlledTransitionAnimator) {
        self.validLayout = (size, cornerRadius)

        let contentFrame = CGRect(origin: CGPoint(), size: size)
        animator.updateFrame(layer: self.backgroundView.layer, frame: contentFrame, completion: nil)
        if let effectView = self.effectView, effectView.frame != contentFrame {
            animator.updateFrame(layer: effectView.layer, frame: contentFrame, completion: nil)
            if let sublayers = effectView.layer.sublayers {
                for sublayer in sublayers {
                    animator.updateFrame(layer: sublayer, frame: contentFrame, completion: nil)
                }
            }
        }

        animator.updateCornerRadius(layer: self.backgroundView.layer, cornerRadius: cornerRadius, completion: nil)
        if let effectView = self.effectView {
            animator.updateCornerRadius(layer: effectView.layer, cornerRadius: cornerRadius, completion: nil)
            effectView.clipsToBounds = !cornerRadius.isZero
        }
    }
}
