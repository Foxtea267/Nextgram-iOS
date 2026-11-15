import AccountContext
import AsyncDisplayKit
import AvatarNode
import Display
import PhotoResources
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import UIKit

struct NextgramFeedPost: Equatable {
    let peer: EnginePeer
    let message: EngineMessage
    let showsMedia: Bool
    let day: String?
    let time: String
    let unread: Bool
}

final class NextgramFeedBubbleItem: ListViewItem {
    let context: AccountContext
    let presentation: ChatPresentationData
    let text: String
    let post: NextgramFeedPost?
    private let action: (() -> Void)?

    init(context: AccountContext, presentation: ChatPresentationData, text: String, post: NextgramFeedPost? = nil, action: (() -> Void)? = nil) {
        self.context = context
        self.presentation = presentation
        self.text = text
        self.post = post
        self.action = action
    }

    var selectable: Bool { self.action != nil }

    func selected(listView: ListView) {
        listView.clearHighlightAnimated(true)
        self.action?()
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = NextgramFeedBubbleNode()
            let (layout, apply) = node.asyncLayout()(self, params)
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, { (nil, { _ in apply() }) })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            guard let node = node() as? NextgramFeedBubbleNode else { return }
            let makeLayout = node.asyncLayout()
            async {
                let (layout, apply) = makeLayout(self, params)
                Queue.mainQueue().async { completion(layout, { _ in apply() }) }
            }
        }
    }
}

private enum FeedThumbnail {
    case photo(TelegramMediaImage, CGSize)
    case video(TelegramMediaFile, CGSize)

    init?(post: NextgramFeedPost) {
        guard post.showsMedia else { return nil }
        for media in post.message.media {
            if let photo = media as? TelegramMediaImage, let size = photo.representations.last?.dimensions.cgSize {
                self = .photo(photo, size)
                return
            }
            if let video = media as? TelegramMediaFile, video.isVideo && !video.isVideoSticker,
               let size = video.dimensions?.cgSize {
                self = .video(video, size)
                return
            }
        }
        return nil
    }

    var size: CGSize {
        switch self {
        case let .photo(_, size), let .video(_, size): return size
        }
    }

    func signal(context: AccountContext, message: EngineMessage) -> Signal<(TransformImageArguments) -> DrawingContext?, NoError> {
        let reference = MessageReference(message._asMessage())
        switch self {
        case let .photo(photo, _):
            return chatMessagePhotoThumbnail(account: context.account, userLocation: .peer(message.id.peerId),
                                             photoReference: .message(message: reference, media: photo))
        case let .video(video, _):
            return chatMessageVideoThumbnail(account: context.account, userLocation: .peer(message.id.peerId),
                                             fileReference: .message(message: reference, media: video))
        }
    }
}

private final class NextgramFeedBubbleNode: ListViewItemNode {
    private let plate = ASDisplayNode()
    private let dayPlate = ASDisplayNode()
    private let avatar = AvatarNode(font: avatarPlaceholderFont(size: 14.0))
    private let day = TextNode()
    private let title = TextNode()
    private let body = TextNode()
    private let time = TextNode()
    private let unreadDot = ASDisplayNode()
    private let videoBadge = ASImageNode()
    private var image: TransformImageNode?
    private var imageMessage: EngineMessage?

    init() {
        super.init(layerBacked: false, rotated: false, seeThrough: true)
        self.dayPlate.cornerRadius = 12.0
        self.unreadDot.cornerRadius = 3.0
        self.videoBadge.image = UIImage(systemName: "play.circle.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
        self.videoBadge.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        self.videoBadge.cornerRadius = 16.0
        self.videoBadge.contentMode = .center
        self.videoBadge.isUserInteractionEnabled = false
        for node in [self.plate, self.dayPlate, self.avatar, self.day, self.title, self.body, self.time, self.unreadDot] as [ASDisplayNode] {
            node.isUserInteractionEnabled = false
            self.addSubnode(node)
        }
        self.isAccessibilityElement = true
    }

    override func setHighlighted(_ highlighted: Bool, at point: CGPoint, animated: Bool) {
        super.setHighlighted(highlighted, at: point, animated: animated)
        self.alpha = highlighted ? 0.72 : 1.0
    }

    func asyncLayout() -> (NextgramFeedBubbleItem, ListViewItemLayoutParams) -> (ListViewItemNodeLayout, () -> Void) {
        let layoutDay = TextNode.asyncLayout(self.day)
        let layoutTitle = TextNode.asyncLayout(self.title)
        let layoutBody = TextNode.asyncLayout(self.body)
        let layoutTime = TextNode.asyncLayout(self.time)
        return { [weak self] item, params in
            let post = item.post
            let thumbnail = post.flatMap(FeedThumbnail.init(post:))
            let theme = item.presentation.theme.theme
            let incoming = theme.chat.message.incoming
            let background = incoming.bubble.withWallpaper.fill.first ?? theme.list.itemBlocksBackgroundColor
            let availableWidth = max(1.0, params.width - params.leftInset - params.rightInset)
            let avatarSpace: CGFloat = post == nil ? 0.0 : 44.0
            let maxTextWidth = max(1.0, min(440.0, availableWidth - avatarSpace - 52.0))
            let pad: CGFloat = post == nil ? 12.0 : 11.0

            func textArgs(_ text: String, font: UIFont, color: UIColor, lines: Int, width: CGFloat) -> TextNodeLayoutArguments {
                return TextNodeLayoutArguments(attributedString: NSAttributedString(string: text, font: font, textColor: color), backgroundColor: nil,
                    maximumNumberOfLines: lines, truncationType: .end, constrainedSize: CGSize(width: width, height: .greatestFiniteMagnitude),
                    alignment: .natural, cutout: nil, insets: .zero)
            }

            let (dayLayout, applyDay) = layoutDay(textArgs(post?.day ?? "", font: Font.semibold(12.0), color: .white, lines: 1, width: maxTextWidth))
            let (titleLayout, applyTitle) = layoutTitle(textArgs(post?.peer.compactDisplayTitle ?? "", font: Font.semibold(14.0), color: incoming.accentTextColor, lines: 1, width: maxTextWidth))
            let bodyColor = post == nil && item.selectable ? incoming.accentTextColor : incoming.primaryTextColor
            let (bodyLayout, applyBody) = layoutBody(textArgs(item.text, font: post == nil ? Font.semibold(13.0) : item.presentation.messageFont, color: bodyColor, lines: 0, width: maxTextWidth))
            let (timeLayout, applyTime) = layoutTime(textArgs(post?.time ?? "", font: Font.regular(11.0), color: incoming.secondaryTextColor, lines: 1, width: maxTextWidth))

            let mediaWidth = thumbnail == nil ? 0.0 : min(300.0, maxTextWidth)
            let mediaHeight = thumbnail.map { min(320.0, max(70.0, floor(mediaWidth * $0.size.height / max(1.0, $0.size.width)))) } ?? 0.0
            let dotSpace: CGFloat = post?.unread == true ? 12.0 : 0.0
            let contentWidth = max(max(titleLayout.size.width, bodyLayout.size.width), max(mediaWidth, timeLayout.size.width + dotSpace))
            let bubbleWidth = contentWidth + 2.0 * pad
            let bubbleX = post == nil ? params.leftInset + floor((availableWidth - bubbleWidth) / 2.0)
                : params.leftInset + avatarSpace + max(6.0, floor((availableWidth - 540.0) / 2.0))
            let bubbleY: CGFloat = post?.day == nil ? 4.0 : 42.0
            let contentX = bubbleX + pad
            let titleY = bubbleY + (post == nil ? 0.0 : 8.0)
            let mediaY = titleY + (post == nil ? 0.0 : titleLayout.size.height + 5.0)
            let bodyY = mediaY + (thumbnail == nil ? 0.0 : mediaHeight + 6.0) + (post == nil ? 7.0 : 0.0)
            let timeY = bodyY + bodyLayout.size.height + 4.0
            let bubbleBottom = post == nil ? timeY + 3.0 : timeY + timeLayout.size.height + 7.0
            let bubble = CGRect(x: bubbleX, y: bubbleY, width: bubbleWidth, height: bubbleBottom - bubbleY)
            let dayX = params.leftInset + floor((availableWidth - dayLayout.size.width) / 2.0)
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: bubbleBottom + 4.0), insets: .zero)

            return (layout, { [weak self] in
                guard let self else { return }
                _ = applyDay()
                _ = applyTitle()
                _ = applyBody()
                _ = applyTime()
                self.plate.backgroundColor = background
                self.plate.cornerRadius = post == nil ? 15.0 : min(24.0, max(8.0, item.presentation.chatBubbleCorners.mainRadius))
                self.plate.frame = bubble
                self.dayPlate.isHidden = post?.day == nil
                self.dayPlate.backgroundColor = UIColor.black.withAlphaComponent(0.45)
                self.dayPlate.frame = CGRect(x: dayX - 10.0, y: 8.0, width: dayLayout.size.width + 20.0, height: 24.0)
                self.day.isHidden = post?.day == nil
                self.day.frame = CGRect(x: dayX, y: 8.0 + floor((24.0 - dayLayout.size.height) / 2.0), width: dayLayout.size.width, height: dayLayout.size.height)
                self.title.frame = CGRect(origin: CGPoint(x: contentX, y: titleY), size: titleLayout.size)
                self.body.frame = CGRect(origin: CGPoint(x: contentX, y: bodyY), size: bodyLayout.size)
                let timeX = contentX + contentWidth - timeLayout.size.width
                self.time.frame = CGRect(origin: CGPoint(x: timeX, y: timeY), size: timeLayout.size)
                self.unreadDot.isHidden = post?.unread != true
                self.unreadDot.backgroundColor = incoming.accentTextColor
                self.unreadDot.frame = CGRect(x: timeX - 10.0, y: self.time.frame.midY - 3.0, width: 6.0, height: 6.0)
                self.avatar.isHidden = post == nil
                if let post {
                    let avatarSize = CGSize(width: 34.0, height: 34.0)
                    self.avatar.setPeer(context: item.context, theme: theme, peer: post.peer, displayDimensions: avatarSize)
                    self.avatar.frame = CGRect(origin: CGPoint(x: bubbleX - 40.0, y: bubbleBottom - avatarSize.height), size: avatarSize)
                }
                self.videoBadge.removeFromSupernode()
                if let thumbnail, let post {
                    if self.imageMessage != post.message {
                        self.image?.removeFromSupernode()
                        let node = TransformImageNode()
                        node.isUserInteractionEnabled = false
                        node.backgroundColor = incoming.mediaPlaceholderColor
                        node.cornerRadius = 8.0
                        node.clipsToBounds = true
                        self.addSubnode(node)
                        node.setSignal(thumbnail.signal(context: item.context, message: post.message))
                        self.image = node
                        self.imageMessage = post.message
                    }
                    let size = CGSize(width: mediaWidth, height: mediaHeight)
                    self.image?.frame = CGRect(origin: CGPoint(x: contentX, y: mediaY), size: size)
                    self.image?.asyncLayout()(TransformImageArguments(corners: ImageCorners(radius: 8.0), imageSize: thumbnail.size.aspectFilled(size),
                        boundingSize: size, intrinsicInsets: .zero, resizeMode: .aspectFill))()
                    if case .video = thumbnail {
                        self.videoBadge.frame = CGRect(x: contentX + floor((mediaWidth - 32.0) / 2.0), y: mediaY + floor((mediaHeight - 32.0) / 2.0), width: 32.0, height: 32.0)
                        self.addSubnode(self.videoBadge)
                    }
                } else {
                    self.image?.removeFromSupernode()
                    self.image = nil
                    self.imageMessage = nil
                }
                self.accessibilityLabel = [post?.day, post?.peer.compactDisplayTitle, item.text, post?.time].compactMap { $0 }.joined(separator: ", ")
                self.accessibilityTraits = item.selectable ? .button : .staticText
            })
        }
    }
}
