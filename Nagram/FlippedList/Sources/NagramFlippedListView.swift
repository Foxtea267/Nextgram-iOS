import Foundation
import UIKit
import AsyncDisplayKit
import Display

// MARK: NAGRAM — 上下镜像的列表，用于「从下往上显示」。
// 列表本身和其中每一行、每个分组标题各翻转一次，内容仍正向显示，而列表的「顶部」落在屏幕底部。
// 于是 ListView 现有的从顶部排列、滑到底部加载更多、回到开头，在屏幕上分别成为贴底排列、
// 往上滑加载更多、回到底部；分组标题也随之到了组的下方，各行组件不用为此改动。
// 只做上下镜像而不旋转：左右不变，滚动条仍在右侧，左滑操作的方向也不变。
// 不能改用 ListViewImpl.rotated：它要求各行自己处理翻转，并据此改变分组标题的计算。
//
// 创建者负责交换上下边距：列表的 top inset 是屏幕底部的留白，bottom inset 是屏幕顶部的留白。
// 列表占用了 visibleContentOffsetChanged，外部改用 flippedVisibleContentOffsetChanged。
open class NagramFlippedListView: ListViewImpl {
    private static let flipTransform = CATransform3DMakeScale(1.0, -1.0, 1.0)

    public var flippedVisibleContentOffsetChanged: (ListViewVisibleContentOffset, ContainedViewLayoutTransition) -> Void = { _, _ in }

    override public init() {
        super.init()

        self.transform = NagramFlippedListView.flipTransform

        // 每次排版和每帧动画结束时 ListView 都会调用它，此时各行的留白已是最新。
        self.visibleContentOffsetChanged = { [weak self] offset, transition in
            guard let self else {
                return
            }
            self.updateItemTransforms()
            self.flippedVisibleContentOffsetChanged(offset, transition)
        }
    }

    // ListView 通过这几个方法把行和分组标题加进来，借此把它们翻回正向。
    override open func addSubnode(_ subnode: ASDisplayNode) {
        self.flipBackIfNeeded(subnode)
        super.addSubnode(subnode)
    }

    override open func insertSubnode(_ subnode: ASDisplayNode, belowSubnode below: ASDisplayNode) {
        self.flipBackIfNeeded(subnode)
        super.insertSubnode(subnode, belowSubnode: below)
    }

    override open func insertSubnode(_ subnode: ASDisplayNode, aboveSubnode above: ASDisplayNode) {
        self.flipBackIfNeeded(subnode)
        super.insertSubnode(subnode, aboveSubnode: above)
    }

    override open func insertSubnode(_ subnode: ASDisplayNode, at idx: Int) {
        self.flipBackIfNeeded(subnode)
        super.insertSubnode(subnode, at: idx)
    }

    private func flipBackIfNeeded(_ subnode: ASDisplayNode) {
        if let itemNode = subnode as? ListViewItemNode {
            itemNode.transform = NagramFlippedListView.itemTransform(insets: itemNode.insets)
        } else if subnode is ListViewItemHeaderNode {
            subnode.transform = NagramFlippedListView.flipTransform
        }
    }

    private func updateItemTransforms() {
        for subnode in self.subnodes ?? [] {
            guard let itemNode = subnode as? ListViewItemNode else {
                continue
            }
            let transform = NagramFlippedListView.itemTransform(insets: itemNode.insets)
            if !CATransform3DEqualToTransform(itemNode.transform, transform) {
                itemNode.transform = transform
            }
        }
    }

    // 行的外框包含留白（分组标题的位置就是顶部留白），而内容只占留白之间的部分。
    // 围绕外框中心翻转会把留白换到内容的另一侧，所以翻转后再平移 top - bottom，
    // 让内容回到原来的位置，留白仍留给分组标题。
    private static func itemTransform(insets: UIEdgeInsets) -> CATransform3D {
        return CATransform3DConcat(NagramFlippedListView.flipTransform, CATransform3DMakeTranslation(0.0, insets.top - insets.bottom, 0.0))
    }
}
