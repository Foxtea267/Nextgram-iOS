import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AppBundle

// MARK: NAGRAM — 搜索结果顶部的「打开链接」入口行，版式沿用 ContactsAddItem（左侧图标 + 强调色标题）。

private let titleFont = Font.regular(17.0)
private let subtitleFont = Font.regular(14.0)
private let separatorHeight = 1.0 / UIScreen.main.scale

public extension ListViewItemHeaderFamily {
    static let nagramSearchLink = ListViewItemHeaderFamily("nagramSearchLink")
}

public final class NagramSearchLinkItem: ListViewItem {
    let theme: PresentationTheme
    let title: String
    let subtitle: String
    let action: () -> Void

    public let header: ListViewItemHeader?

    public var neighborDescriptor: AnyEquatable {
        return AnyEquatable(HeaderNeighborDescriptor(headerId: self.header?.id, headerFamily: .nagramSearchLink))
    }

    public init(theme: PresentationTheme, title: String, subtitle: String, header: ListViewItemHeader?, action: @escaping () -> Void) {
        self.theme = theme
        self.title = title
        self.subtitle = subtitle
        self.header = header
        self.action = action
    }

    public func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = NagramSearchLinkItemNode()
            let makeLayout = node.asyncLayout()
            let (first, last, firstWithHeader) = NagramSearchLinkItem.mergeType(item: self, neighbors: neighbors)
            let (nodeLayout, nodeApply) = makeLayout(self, params, first, last, firstWithHeader)
            node.contentSize = nodeLayout.contentSize
            node.insets = nodeLayout.insets

            completion(node, {
                return (nil, { _ in nodeApply(false) })
            })
        }
    }

    public func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? NagramSearchLinkItemNode {
                let layout = nodeValue.asyncLayout()
                async {
                    let (first, last, firstWithHeader) = NagramSearchLinkItem.mergeType(item: self, neighbors: neighbors)
                    let (nodeLayout, apply) = layout(self, params, first, last, firstWithHeader)
                    Queue.mainQueue().async {
                        completion(nodeLayout, { _ in
                            apply(animation.isAnimated)
                        })
                    }
                }
            }
        }
    }

    public var selectable: Bool {
        return true
    }

    public func selected(listView: ListView) {
        self.action()
    }

    static func mergeType(item: NagramSearchLinkItem, neighbors: ListViewItemNeighbors) -> (first: Bool, last: Bool, firstWithHeader: Bool) {
        var first = false
        var last = false
        var firstWithHeader = false
        if neighbors.previous != nil {
            if let header = item.header {
                if let previousItem = neighbors.previous?.base(HeaderNeighborFacet.self), previousItem.headerFamily == .nagramSearchLink {
                    firstWithHeader = header.id != previousItem.headerId
                } else {
                    firstWithHeader = true
                }
            }
        } else {
            first = true
            firstWithHeader = item.header != nil
        }
        if neighbors.next != nil {
            if let header = item.header {
                if let nextItem = neighbors.next?.base(HeaderNeighborFacet.self), nextItem.headerFamily == .nagramSearchLink {
                    last = header.id != nextItem.headerId
                } else {
                    last = true
                }
            }
        } else {
            last = true
        }
        return (first, last, firstWithHeader)
    }
}

final class NagramSearchLinkItemNode: ListViewItemNode {
    private let backgroundNode: ASDisplayNode
    private let separatorNode: ASDisplayNode
    private let highlightedBackgroundNode: ASDisplayNode

    private let iconNode: ASImageNode
    private let titleNode: TextNode
    private let subtitleNode: TextNode

    private var layoutParams: (NagramSearchLinkItem, ListViewItemLayoutParams, Bool, Bool, Bool)?

    required init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true

        self.separatorNode = ASDisplayNode()
        self.separatorNode.isLayerBacked = true

        self.highlightedBackgroundNode = ASDisplayNode()
        self.highlightedBackgroundNode.isLayerBacked = true

        self.iconNode = ASImageNode()
        self.iconNode.displaysAsynchronously = false
        self.titleNode = TextNode()
        self.subtitleNode = TextNode()

        super.init(layerBacked: false, rotated: false, seeThrough: false)

        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.separatorNode)
        self.addSubnode(self.iconNode)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.subtitleNode)
    }

    override func layoutForParams(_ params: ListViewItemLayoutParams, item: ListViewItem, neighbors: ListViewItemNeighbors) {
        if let (item, _, _, _, _) = self.layoutParams {
            let (first, last, firstWithHeader) = NagramSearchLinkItem.mergeType(item: item, neighbors: neighbors)
            self.layoutParams = (item, params, first, last, firstWithHeader)
            let makeLayout = self.asyncLayout()
            let (nodeLayout, nodeApply) = makeLayout(item, params, first, last, firstWithHeader)
            self.contentSize = nodeLayout.contentSize
            self.insets = nodeLayout.insets
            let _ = nodeApply(false)
        }
    }

    override func setHighlighted(_ highlighted: Bool, at point: CGPoint, animated: Bool) {
        super.setHighlighted(highlighted, at: point, animated: animated)

        if highlighted {
            self.highlightedBackgroundNode.alpha = 1.0
            if self.highlightedBackgroundNode.supernode == nil {
                self.insertSubnode(self.highlightedBackgroundNode, aboveSubnode: self.separatorNode)
            }
        } else if self.highlightedBackgroundNode.supernode != nil {
            if animated {
                self.highlightedBackgroundNode.layer.animateAlpha(from: self.highlightedBackgroundNode.alpha, to: 0.0, duration: 0.4, completion: { [weak self] completed in
                    if let self, completed {
                        self.highlightedBackgroundNode.removeFromSupernode()
                    }
                })
                self.highlightedBackgroundNode.alpha = 0.0
            } else {
                self.highlightedBackgroundNode.removeFromSupernode()
            }
        }
    }

    func asyncLayout() -> (_ item: NagramSearchLinkItem, _ params: ListViewItemLayoutParams, _ first: Bool, _ last: Bool, _ firstWithHeader: Bool) -> (ListViewItemNodeLayout, (Bool) -> Void) {
        let makeTitleLayout = TextNode.asyncLayout(self.titleNode)
        let makeSubtitleLayout = TextNode.asyncLayout(self.subtitleNode)

        let currentItem = self.layoutParams?.0

        return { [weak self] item, params, first, last, firstWithHeader in
            var updatedTheme: PresentationTheme?
            var updatedIcon: UIImage?
            if currentItem?.theme !== item.theme {
                updatedTheme = item.theme
                updatedIcon = generateTintedImage(image: UIImage(bundleImageName: "Contact List/LinkActionIcon"), color: item.theme.list.itemAccentColor)
            }
            let leftInset: CGFloat = 65.0 + params.leftInset
            let rightInset: CGFloat = 10.0 + params.rightInset
            let textWidth = max(0.0, params.width - leftInset - rightInset)

            let (titleLayout, titleApply) = makeTitleLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: item.title, font: titleFont, textColor: item.theme.list.itemAccentColor), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: textWidth, height: CGFloat.infinity), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
            let (subtitleLayout, subtitleApply) = makeSubtitleLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: item.subtitle, font: subtitleFont, textColor: item.theme.list.itemSecondaryTextColor), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .middle, constrainedSize: CGSize(width: textWidth, height: CGFloat.infinity), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))

            let height: CGFloat = 56.0
            let nodeLayout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: height), insets: UIEdgeInsets(top: firstWithHeader ? 29.0 : 0.0, left: 0.0, bottom: 0.0, right: 0.0))

            let spacing: CGFloat = 1.0
            let textHeight = titleLayout.size.height + spacing + subtitleLayout.size.height
            let titleFrame = CGRect(origin: CGPoint(x: leftInset, y: floor((height - textHeight) / 2.0)), size: titleLayout.size)
            let subtitleFrame = CGRect(origin: CGPoint(x: leftInset, y: titleFrame.maxY + spacing), size: subtitleLayout.size)

            return (nodeLayout, { [weak self] animated in
                guard let self else {
                    return
                }
                self.layoutParams = (item, params, first, last, firstWithHeader)

                let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.4, curve: .spring) : .immediate

                if updatedTheme != nil {
                    self.separatorNode.backgroundColor = item.theme.list.itemPlainSeparatorColor
                    self.backgroundNode.backgroundColor = item.theme.list.plainBackgroundColor
                    self.highlightedBackgroundNode.backgroundColor = item.theme.list.itemHighlightedBackgroundColor
                }

                let _ = titleApply()
                let _ = subtitleApply()
                transition.updateFrame(node: self.titleNode, frame: titleFrame)
                transition.updateFrame(node: self.subtitleNode, frame: subtitleFrame)

                if let updatedIcon {
                    self.iconNode.image = updatedIcon
                }
                transition.updateFrame(node: self.iconNode, frame: CGRect(x: params.leftInset + 14.0, y: floor((height - 40.0) / 2.0), width: 40.0, height: 40.0))

                let topHighlightInset: CGFloat = (first || !nodeLayout.insets.top.isZero) ? 0.0 : separatorHeight
                self.backgroundNode.frame = CGRect(origin: CGPoint(), size: nodeLayout.contentSize)
                self.highlightedBackgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -nodeLayout.insets.top - topHighlightInset), size: CGSize(width: nodeLayout.size.width, height: nodeLayout.size.height + topHighlightInset))
                self.separatorNode.frame = CGRect(origin: CGPoint(x: leftInset, y: nodeLayout.contentSize.height - separatorHeight), size: CGSize(width: max(0.0, nodeLayout.size.width - leftInset), height: separatorHeight))
                self.separatorNode.isHidden = last
            })
        }
    }

    override func layoutHeaderAccessoryItemNode(_ accessoryItemNode: ListViewAccessoryItemNode) {
        accessoryItemNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -29.0), size: CGSize(width: self.bounds.size.width, height: 29.0))
    }

    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration * 0.5)
    }

    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration * 0.5, removeOnCompletion: false)
    }

    override public func headers() -> [ListViewItemHeader]? {
        return self.layoutParams?.0.header.flatMap { [$0] }
    }
}
