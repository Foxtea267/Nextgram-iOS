import Foundation
import UIKit

public protocol NavigationBarTitleView: UIView {
    var requestUpdate: ((ContainedViewLayoutTransition) -> Void)? { get set }
    var prefersCenteredNavigationTitle: Bool { get } // MARK: NEXTGRAM
    
    func animateLayoutTransition()
    
    func updateLayout(availableSize: CGSize, transition: ContainedViewLayoutTransition) -> CGSize
}

// MARK: NEXTGRAM
public extension NavigationBarTitleView {
    var prefersCenteredNavigationTitle: Bool { return false }
}
