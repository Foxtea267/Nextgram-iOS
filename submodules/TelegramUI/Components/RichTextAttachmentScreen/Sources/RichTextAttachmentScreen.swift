import Foundation
import UIKit
import Display
import ComponentFlow
import AccountContext
import AttachmentUI
import ViewControllerComponent
import TelegramPresentationData
import PresentationDataUtils
import GlassBarButtonComponent
import GlassBackgroundComponent
import BundleIconComponent
import MultilineTextComponent
import EdgeEffect
import RichTextEditorCore
import RichTextEditorUIKit
import RichTextEditorMediaView
import InstantPageUI
import ContextUI
import Postbox
import TelegramCore
import CheckNode
import GlassControls
import ChatRichTextEditorComposer
import ChatTextLinkEditUI
import TextFormat
import UndoUI

/// `RichTextChecklistMarkerView` host wrapper backing a checklist item's checkbox with a `CheckNode`
/// (an `ASDisplayNode`, so we host its `.view` — this is a `UIView`, not a node). The editor frames this
/// view in the marker gutter and calls `setChecked(_:animated:)` when the item toggles. A private copy
/// lives in each editor host (cross-module; duplication is expected).
private final class HostChecklistCheckboxView: UIView, RichTextChecklistMarkerView {
    private let checkNode: CheckNode
    init(theme: CheckNodeTheme, checked: Bool) {
        self.checkNode = CheckNode(theme: theme, content: .check(isRectangle: true))
        super.init(frame: .zero)
        self.checkNode.isUserInteractionEnabled = false
        self.addSubview(self.checkNode.view)
        self.checkNode.setSelected(checked, animated: false)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        self.checkNode.frame = self.bounds
    }
    func setChecked(_ checked: Bool, animated: Bool) {
        self.checkNode.setSelected(checked, animated: animated)
    }
}

private final class RichTextSendButtonComponent: Component {
    let theme: PresentationTheme
    let isEnabled: Bool
    let isLocked: Bool
    let action: () -> Void

    init(theme: PresentationTheme, isEnabled: Bool, isLocked: Bool, action: @escaping () -> Void) {
        self.theme = theme
        self.isEnabled = isEnabled
        self.isLocked = isLocked
        self.action = action
    }

    static func ==(lhs: RichTextSendButtonComponent, rhs: RichTextSendButtonComponent) -> Bool {
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.isEnabled != rhs.isEnabled {
            return false
        }
        if lhs.isLocked != rhs.isLocked {
            return false
        }
        return true
    }

    final class View: UIView {
        private let button = ComponentView<Empty>()
        private let buttonMaskView = UIView()
        private let buttonCutoutMaskView = UIImageView()
        private let lockBackgroundView = GlassBackgroundView()
        private let lockIconView = UIImageView()

        private var component: RichTextSendButtonComponent?

        override init(frame: CGRect) {
            self.buttonMaskView.backgroundColor = .white
            if let filter = CALayer.luminanceToAlpha() {
                self.buttonMaskView.layer.filters = [filter]
            }

            self.lockBackgroundView.isUserInteractionEnabled = false
            self.lockIconView.isUserInteractionEnabled = false

            super.init(frame: frame)

            self.clipsToBounds = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(component: RichTextSendButtonComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            self.component = component

            let buttonSize = self.button.update(
                transition: transition,
                component: AnyComponent(GlassControlGroupComponent(
                    theme: component.theme,
                    preferClearGlass: false,
                    background: component.isEnabled ? .activeTint(inset: false) : .color(component.theme.chat.inputPanel.panelControlDisabledColor),
                    items: [
                        GlassControlGroupComponent.Item(id: 0, content: .icon("Chat/Input/Text/SendIcon"), action: component.isEnabled ? component.action : nil)
                    ],
                    minWidth: 44.0
                )),
                environment: {},
                containerSize: availableSize
            )

            if let buttonView = self.button.view {
                if buttonView.superview == nil {
                    self.addSubview(buttonView)
                }
                transition.setFrame(view: buttonView, frame: CGRect(origin: .zero, size: buttonSize))

                if component.isLocked {
                    var animateIn = false
                    if buttonView.mask !== self.buttonMaskView {
                        buttonView.mask = self.buttonMaskView

                        if !transition.animation.isImmediate {
                            animateIn = true
                        }
                    }
                    let maskOverflow: CGFloat = 36.0
                    self.buttonMaskView.frame = CGRect(origin: CGPoint(x: -maskOverflow, y: -maskOverflow), size: CGSize(width: buttonSize.width + maskOverflow * 2.0, height: buttonSize.height + maskOverflow * 2.0))

                    let lockDiameter: CGFloat = 24.0
                    let lockOffset: CGFloat = -7.0
                    let cutoutInset: CGFloat = 2.0 - UIScreenPixel
                    let cutoutDiameter = lockDiameter + cutoutInset * 2.0
                    let lockFrame = CGRect(x: lockOffset, y: lockOffset, width: lockDiameter, height: lockDiameter)
                    let cutoutFrame = lockFrame.insetBy(dx: -cutoutInset, dy: -cutoutInset)

                    if self.buttonCutoutMaskView.image?.size.height != cutoutDiameter {
                        self.buttonCutoutMaskView.image = generateStretchableFilledCircleImage(diameter: cutoutDiameter, color: .black)
                    }
                    if self.buttonCutoutMaskView.superview == nil {
                        self.buttonMaskView.addSubview(self.buttonCutoutMaskView)
                    }
                    self.buttonCutoutMaskView.frame = cutoutFrame.offsetBy(dx: maskOverflow, dy: maskOverflow)

                    if self.lockBackgroundView.superview == nil {
                        self.addSubview(self.lockBackgroundView)
                    }
                    self.bringSubviewToFront(self.lockBackgroundView)
                    self.lockBackgroundView.update(size: lockFrame.size, cornerRadius: lockDiameter * 0.5, isDark: component.theme.overallDarkAppearance, tintColor: .init(kind: .custom(style: .default, color: component.theme.list.itemCheckColors.fillColor)), isInteractive: false, transition: transition)
                    transition.setFrame(view: self.lockBackgroundView, frame: lockFrame)
                    transition.setAlpha(view: self.lockBackgroundView, alpha: 1.0)

                    if self.lockIconView.image == nil {
                        self.lockIconView.image = generateTintedImage(image: UIImage(bundleImageName: "Chat/Stickers/SmallLock"), color: .white)
                    }
                    if self.lockIconView.superview == nil {
                        self.lockBackgroundView.contentView.addSubview(self.lockIconView)
                    }
                    if let image = self.lockIconView.image {
                        let iconFrame = CGRect(
                            origin: CGPoint(
                                x: floorToScreenPixels((lockDiameter - image.size.width) * 0.5),
                                y: floorToScreenPixels((lockDiameter - image.size.height) * 0.5)
                            ),
                            size: image.size
                        )
                        transition.setFrame(view: self.lockIconView, frame: iconFrame)
                    }

                    if animateIn {
                        self.lockBackgroundView.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                        self.lockBackgroundView.layer.animateScale(from: 0.01, to: 1.0, duration: 0.2)
                        self.buttonCutoutMaskView.layer.animateScale(from: 0.001, to: 1.0, duration: 0.2)
                    }
                } else {
                    if transition.animation.isImmediate {
                        if buttonView.mask === self.buttonMaskView {
                            buttonView.mask = nil
                        }
                        self.buttonCutoutMaskView.removeFromSuperview()
                        self.lockBackgroundView.removeFromSuperview()
                    } else {
                        self.lockBackgroundView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2)
                        self.lockBackgroundView.layer.animateScale(from: 1.0, to: 0.01, duration: 0.2, removeOnCompletion: false, completion: { _ in
                            if buttonView.mask === self.buttonMaskView {
                                buttonView.mask = nil
                            }
                            self.buttonCutoutMaskView.removeFromSuperview()
                            self.lockBackgroundView.removeFromSuperview()
                            self.lockBackgroundView.layer.removeAllAnimations()
                            self.buttonCutoutMaskView.layer.removeAllAnimations()
                        })
                        self.buttonCutoutMaskView.layer.animateScale(from: 1.0, to: 0.001, duration: 0.2, removeOnCompletion: false)
                    }
                }
            }

            return buttonSize
        }
    }

    func makeView() -> View {
        return View(frame: .zero)
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

public class RichTextAttachmentScreen: ViewControllerComponentContainer, AttachmentContainable {
    public typealias Document = RichTextEditorCoreDocument
    
    public enum Mode {
        case standalone(savedDraft: Document?, media: [String: Media], emojiFiles: [Int64: TelegramMediaFile])
        case edit(initialDocument: Document?, media: [String: Media], emojiFiles: [Int64: TelegramMediaFile])
    }
    
    public enum RichTextAttachment {
        case image(ImageMediaReference)
        case file(FileMediaReference)
        case location(TelegramMediaMap)
    }
    
    public var requestAttachmentMenuExpansion: () -> Void = {}
    public var updateNavigationStack: (@escaping ([AttachmentContainable]) -> ([AttachmentContainable], AttachmentMediaPickerContext?)) -> Void = { _ in }
    public var parentController: () -> ViewController? = { return nil }
    public var updateTabBarAlpha: (CGFloat, ContainedViewLayoutTransition) -> Void = { _, _ in }
    public var updateTabBarVisibility: (Bool, ContainedViewLayoutTransition) -> Void = { _, _ in }
    public var cancelPanGesture: () -> Void = { }
    public var isContainerPanning: () -> Bool = { return false }
    public var isContainerExpanded: () -> Bool = { return false }
    public var isMinimized: Bool = false

    public var mediaPickerContext: AttachmentMediaPickerContext?

    public var isPanGestureEnabled: (() -> Bool)? {
        return { [weak self] in
            guard let self, let componentView = self.node.hostView.componentView as? RichTextAttachmentScreenComponent.View else {
                return true
            }
            return componentView.isPanGestureEnabled()
        }
    }

    private let context: AccountContext
    private let sendMessage: (Document, [String: Media], [Int64: TelegramMediaFile], Bool) -> Void
    private let syncContent: ((Document, [String: Media], [Int64: TelegramMediaFile]) -> Void)?

    public convenience init(
        context: AccountContext,
        mode: Mode,
        sendMessage: @escaping (Document, [String: Media], [Int64: TelegramMediaFile]) -> Void,
        syncContent: ((Document, [String: Media], [Int64: TelegramMediaFile]) -> Void)? = nil,
        presentAttachmentMenu: ((_ photoVideoOnly: Bool, @escaping (RichTextAttachmentScreen.RichTextAttachment) -> Void) -> Void)?,
        presentFormulaEditor: ((_ initialValue: String?, _ completion: @escaping (String) -> Void) -> Void)?
    ) {
        self.init(
            context: context,
            mode: mode,
            sendMessage: { document, media, emojiFiles, _ in
                sendMessage(document, media, emojiFiles)
            },
            syncContent: syncContent,
            presentAttachmentMenu: presentAttachmentMenu,
            presentFormulaEditor: presentFormulaEditor
        )
    }

    public init(
        context: AccountContext,
        mode: Mode,
        sendMessage: @escaping (Document, [String: Media], [Int64: TelegramMediaFile], Bool) -> Void,
        syncContent: ((Document, [String: Media], [Int64: TelegramMediaFile]) -> Void)? = nil,
        presentAttachmentMenu: ((_ photoVideoOnly: Bool, @escaping (RichTextAttachmentScreen.RichTextAttachment) -> Void) -> Void)?,
        presentFormulaEditor: ((_ initialValue: String?, _ completion: @escaping (String) -> Void) -> Void)?
    ) {
        self.context = context
        self.sendMessage = sendMessage
        self.syncContent = syncContent

        let overNavigationContainer = SparseContainerView()

        super.init(context: context, component: RichTextAttachmentScreenComponent(
            context: context,
            mode: mode,
            overNavigationContainer: overNavigationContainer,
            presentAttachmentMenu: presentAttachmentMenu,
            presentFormulaEditor: presentFormulaEditor
        ), navigationBarAppearance: .transparent, theme: .default)

        self._hasGlassStyle = true

        // Glass style: the Cancel/Done buttons are rendered by the View into
        // overNavigationContainer, so the nav item only needs an empty placeholder.
        self.navigationItem.setLeftBarButton(UIBarButtonItem(customView: UIView()), animated: false)

        if let navigationBar = self.navigationBar {
            navigationBar.customOverBackgroundContentView.insertSubview(overNavigationContainer, at: 0)
        }
        
        self.attemptNavigation = { [weak self] _ in
            guard let self, let syncContent = self.syncContent, let componentView = self.node.hostView.componentView as? RichTextAttachmentScreenComponent.View else {
                return true
            }
            syncContent(componentView.currentDocument, componentView.currentMedia, componentView.currentEmojiFiles)
            return true
        }
    }

    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func resetForReuse() {
        guard let syncContent = self.syncContent, let componentView = self.node.hostView.componentView as? RichTextAttachmentScreenComponent.View else {
            return
        }
        syncContent(componentView.currentDocument, componentView.currentMedia, componentView.currentEmojiFiles)
    }
    
    fileprivate func donePressed() {
        guard let componentView = self.node.hostView.componentView as? RichTextAttachmentScreenComponent.View else {
            return
        }
        if !componentView.isSendRichFormattingLocked {
            self.complete(withoutFormatting: false)
            return
        }

        let strings = self.context.sharedContext.currentPresentationData.with { $0 }.strings
        let controller = textAlertController(context: self.context, title: strings.RichText_RemoveFormattingTitle, text: strings.RichText_RemoveFormattingText, actions: [
            TextAlertAction(type: .defaultAction, title: strings.RichText_SubscribeToPremium, action: { [weak self] in
                guard let self else {
                    return
                }
                let premiumController = self.context.sharedContext.makePremiumIntroController(context: self.context, source: .richText, forceDark: false, dismissed: nil)
                if let parentController = self.parentController() {
                    parentController.push(premiumController)
                } else {
                    self.push(premiumController)
                }
            }),
            TextAlertAction(type: .genericAction, title: strings.RichText_SendWithoutFormatting, action: { [weak self] in
                self?.complete(withoutFormatting: true)
            }),
            TextAlertAction(type: .genericAction, title: strings.Common_Cancel, action: {
            })
        ], actionLayout: .vertical)
        self.present(controller, in: .window(.root))
    }

    fileprivate func complete(withoutFormatting: Bool) {
        guard let componentView = self.node.hostView.componentView as? RichTextAttachmentScreenComponent.View else {
            self.dismiss()
            return
        }
        self.sendMessage(componentView.currentDocument, componentView.currentMedia, componentView.currentEmojiFiles, withoutFormatting)
        self.dismiss()
    }

    fileprivate func close() {
        guard let syncContent = self.syncContent, let componentView = self.node.hostView.componentView as? RichTextAttachmentScreenComponent.View else {
            self.dismiss()
            return
        }
        syncContent(componentView.currentDocument, componentView.currentMedia, componentView.currentEmojiFiles)
        self.dismiss()
    }
}

final class RichTextAttachmentScreenComponent: Component {
    typealias EnvironmentType = ViewControllerComponentContainer.Environment

    // Held for the next step: the RichTextEditor demo will read context and add
    // its editor view into the View's content container.
    let context: AccountContext
    let mode: RichTextAttachmentScreen.Mode
    let overNavigationContainer: UIView
    let presentAttachmentMenu: ((_ photoVideoOnly: Bool, @escaping (RichTextAttachmentScreen.RichTextAttachment) -> Void) -> Void)?
    let presentFormulaEditor: ((_ initialValue: String?, _ completion: @escaping (String) -> Void) -> Void)?

    init(context: AccountContext, mode: RichTextAttachmentScreen.Mode, overNavigationContainer: UIView, presentAttachmentMenu: ((_ photoVideoOnly: Bool, @escaping (RichTextAttachmentScreen.RichTextAttachment) -> Void) -> Void)?, presentFormulaEditor: ((_ initialValue: String?, _ completion: @escaping (String) -> Void) -> Void)?) {
        self.context = context
        self.mode = mode
        self.overNavigationContainer = overNavigationContainer
        self.presentAttachmentMenu = presentAttachmentMenu
        self.presentFormulaEditor = presentFormulaEditor
    }

    static func ==(lhs: RichTextAttachmentScreenComponent, rhs: RichTextAttachmentScreenComponent) -> Bool {
        return true
    }

    final class View: UIView {
        private let navigationTapView: UIView
        private let title = ComponentView<Empty>()
        private let leftNavActionsBar = ComponentView<Empty>()
        private let rightNavActionsBar = ComponentView<Empty>()
        
        private let editor = RichTextEditorView()
        // Frosted fade at the screen top (mirrors ComposePollScreen) — scrolling content dissolves into the
        // nav region. Overlaid above the editor; the nav buttons live in the separate over-nav container.
        private let topEdgeEffectView = EdgeEffectView()

        /// The current editor document, read by the controller's `donePressed`.
        var currentDocument: Document {
            return self.editor.document
        }

        /// Picked media keyed by the opaque `mediaID` handed to the editor. Read by `donePressed`.
        private var attachedMedia: [String: Media] = [:]

        /// The picked media map, keyed by the editor's `mediaID`. Read by the controller's `donePressed`.
        var currentMedia: [String: Media] {
            return self.attachedMedia
        }

        /// The custom-emoji file store (seeded + user-inserted), keyed by fileId. Read by the controller's
        /// `donePressed` so each emoji run's `TelegramMediaFile` is re-attached when converting back.
        var currentEmojiFiles: [Int64: TelegramMediaFile] {
            return self.emojiKeyboard?.currentEmojiFiles ?? [:]
        }

        var isSendRichFormattingLocked: Bool {
            guard let component = self.component, !component.context.isPremium else {
                return false
            }
            let content = chatInputContent(fromDocument: self.currentDocument, media: self.currentMedia, emojiFiles: self.currentEmojiFiles)
            return !content.isEmpty && !content.isEntityExpressible(options: [.quotesRequireRichContent])
        }

        private var component: RichTextAttachmentScreenComponent?
        private var environment: EnvironmentType?
        
        private let actionBar = ComponentView<Empty>()
        private let aiButton = ComponentView<Empty>()
        private let sendButton = ComponentView<Empty>()

        private var emojiKeyboard: RichTextEmojiKeyboardController?
        private var componentState: EmptyComponentState?
        private var isUpdating = false
        private var lastTabBarVisible: Bool?
        private var didShowPremiumToast = false
        /// The `PresentationTheme` last mapped into the editor. `PresentationTheme` is a shared `final
        /// class`, so reference inequality is the cheap change-signal — guarding the editor `theme` setter
        /// (which does an unconditional reload+redraw) against firing on every keystroke (`onChange` →
        /// `componentState.updated` → `update`).
        private var appliedTheme: PresentationTheme?

        override init(frame: CGRect) {
            self.navigationTapView = UIView()
            
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func isPanGestureEnabled() -> Bool {
            return !viewTreeContainsFirstResponder(view: self.editor)
        }
        
        private func textCell(_ id: String, _ lines: [String]) -> Cell {
            Cell(id: BlockID(id), blocks: lines.enumerated().map { i, t in
                .paragraph(ParagraphBlock(id: BlockID("\(id)p\(i)"), runs: [TextRun(text: t)]))
            })
        }

        // MARK: Phase 5b — image picker + link prompt

        /// Picks one medium via the host attachment menu, registers its raw `Media` in `attachedMedia` (so the
        /// media-view provider can resolve it), and hands back the editor-facing `(mediaID, naturalSize, kind,
        /// caption)`. Callers decide what to do with it (insert a new block, or append to an existing one).
        private func pickMedia(photoVideoOnly: Bool, completion: @escaping (_ mediaID: String, _ naturalSize: CGSize, _ kind: MediaKind, _ caption: [TextRun]) -> Void) {
            guard let component = self.component else {
                return
            }
            component.presentAttachmentMenu?(photoVideoOnly, { [weak self] attachment in
                guard let self else {
                    return
                }
                let media: Media
                let kind: MediaKind
                let naturalSize: CGSize
                switch attachment {
                case let .image(imageReference):
                    let image = imageReference.media
                    media = image
                    kind = .image
                    naturalSize = image.representations.last?.dimensions.cgSize ?? CGSize(width: 1, height: 1)
                case let .file(fileReference):
                    let file = fileReference.media
                    if file.isVideo {
                        media = file
                        kind = .video
                        naturalSize = file.dimensions?.cgSize ?? CGSize(width: 1, height: 1)
                    } else if file.isMusic || file.isVoice {
                        // Audio (music from the Audio picker; voice only via edit round-trips). The block is a
                        // fixed-height row, so naturalSize is ignored by MediaBlockBox — pass a 1x1 placeholder.
                        media = file
                        kind = .audio
                        naturalSize = CGSize(width: 1.0, height: 1.0)
                    } else {
                        return   // unsupported document type
                    }
                case let .location(map):
                    // A map is id-less, so mint a deterministic key from its coordinates; the venue title (if any)
                    // seeds the caption (a raw dropped pin has no venue -> empty caption). Self-contained insert,
                    // since the shared `media.id` path below can't key an id-less medium.
                    let mediaID = "map:\(map.latitude):\(map.longitude)"
                    self.attachedMedia[mediaID] = map
                    let caption: [TextRun] = map.venue?.title.isEmpty == false ? [TextRun(text: map.venue!.title)] : []
                    completion(mediaID, CGSize(width: 600.0, height: 300.0), .location, caption)
                    return
                }
                guard let mediaId = media.id else { return }
                let mediaID = "\(mediaId.namespace):\(mediaId.id)"
                self.attachedMedia[mediaID] = media
                completion(mediaID, naturalSize, kind, [])
            })
        }

        private func presentImagePicker() {
            self.pickMedia(photoVideoOnly: false) { [weak self] mediaID, naturalSize, kind, caption in
                self?.editor.insertMedia(mediaID: mediaID, naturalSize: naturalSize, kind: kind, caption: caption)
            }
        }

        private func presentLinkPrompt() {
            guard let component = self.component, let environment = self.environment,
                  let controller = environment.controller() as? RichTextAttachmentScreen else {
                return
            }

            // Reuse the shared chat link-editing UI (title/selected-text label/URL field + webpage preview),
            // reading the current selection + existing link from the editor's native API and applying the
            // result back through it — mirrors the chat composer's `openLinkEditing` rich-text branch.
            let selectedText = self.editor.selectedText()
            let existingLink = self.editor.currentLink()

            let linkController = chatTextLinkEditController(
                context: component.context,
                text: environment.strings.TextFormat_AddLinkText(selectedText).string,
                link: existingLink,
                apply: { [weak self] link, _ in
                    guard let self, let link else { return }
                    self.editor.becomeFirstResponder()
                    if link.isEmpty {
                        self.editor.removeLink()
                    } else {
                        self.editor.setLink(link)
                    }
                }
            )
            controller.present(linkController, in: .window(.root))
        }

        /// Presents the list-marker picker (None / Bullet / Numbered / Checklist), applying the choice to
        /// the paragraphs the current caret or selection touches. Shared by the caret-case "add block"
        /// bar and the text-only selection bar.
        private func presentListMenu(from sourceView: UIView) {
            guard let component = self.component, let environment = self.environment else {
                return
            }
            guard let controller = environment.controller() as? RichTextAttachmentScreen else {
                return
            }

            let current = self.editor.currentState().listMarker

            var items: [ContextMenuItem] = []

            items.append(.action(ContextMenuActionItem(text: environment.strings.RichText_Menu_List_None, icon: { theme in
                UIImage()
            }, additionalLeftIcon: { theme in
                return current == nil ? generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Check"), color: theme.contextMenu.primaryColor) : UIImage()
            }, action: { [weak self] _, f in
                f(.default)
                guard let self else {
                    return
                }
                self.editor.setList(nil)
            })))

            items.append(.action(ContextMenuActionItem(text: environment.strings.RichText_Menu_List_Bullet, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/FormatBulletList"), color: theme.contextMenu.primaryColor)
            }, additionalLeftIcon: { theme in
                return current == .bullet ? generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Check"), color: theme.contextMenu.primaryColor) : UIImage()
            }, iconPosition: .left, action: { [weak self] _, f in
                f(.default)
                guard let self else {
                    return
                }
                self.editor.setList(.bullet)
            })))

            items.append(.action(ContextMenuActionItem(text: environment.strings.RichText_Menu_List_Numbered, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/FormatNumberList"), color: theme.contextMenu.primaryColor)
            }, additionalLeftIcon: { theme in
                return current == .ordered ? generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Check"), color: theme.contextMenu.primaryColor) : UIImage()
            }, iconPosition: .left, action: { [weak self] _, f in
                f(.default)
                guard let self else {
                    return
                }
                self.editor.setList(.ordered)
            })))

            items.append(.action(ContextMenuActionItem(text: environment.strings.RichText_Menu_List_Checklist, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/FormatChecklist"), color: theme.contextMenu.primaryColor)
            }, additionalLeftIcon: { theme in
                return current == .checklist ? generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Check"), color: theme.contextMenu.primaryColor) : UIImage()
            }, iconPosition: .left, action: { [weak self] _, f in
                f(.default)
                guard let self else {
                    return
                }
                self.editor.setList(.checklist)
            })))

            let presentationData = component.context.sharedContext.currentPresentationData.with { $0 }
            let contextController = makeContextController(
                presentationData: presentationData,
                source: .reference(RichTextActionContextReferenceSource(sourceView: sourceView)),
                items: .single(ContextController.Items(content: .list(items))),
                gesture: nil
            )
            (controller.parentController() ?? controller).presentInGlobalOverlay(contextController)
        }
        
        /// Normalizes the caret's / selection's paragraph(s) to plain body text, stripping any block
        /// container they sit in: a code block or pull quote is toggled back to body paragraphs; a list
        /// marker and every enclosing block-quote level are removed; a heading (or any other non-body
        /// style) is down-converted. Backs the "Text" item in `presentAddMenu`.
        private func convertToBodyText() {
            let live = self.editor.currentState()
            // Code blocks and pull quotes are standalone box types, each with its own toggle-off that
            // splits back into body paragraphs — so they replace, rather than compose with, the steps below.
            if live.isCodeBlock {
                self.editor.makeCodeBlock()
                return
            }
            if live.isPullQuote {
                self.editor.makePullQuote()
                return
            }
            // Unwrap every enclosing block-quote level FIRST: `setList` only mutates top-level boxes, so a
            // quoted list item must be promoted to a top-level paragraph before its list marker can be cleared.
            var guardCount = 0
            while self.editor.currentState().blockQuoteDepth > 0 && guardCount < 32 {
                self.editor.unwrapBlockQuoteLevel()
                guardCount += 1
            }
            if self.editor.currentState().listMarker != nil {
                self.editor.setList(nil)
            }
            self.editor.setParagraphStyle(.body)
        }

        /// When the editor is unfocused (no caret), an Add-menu format/insert action should target the END of
        /// the document, not the default offset-0 start (which touches no paragraph, so the command no-ops).
        /// Focuses the editor and drops the caret at the end so the following command applies there. No-op when
        /// a caret already exists — the user's position is preserved.
        private func focusEditorAtDocumentEndIfNeeded(hasCursor: Bool) {
            guard !hasCursor else { return }
            self.editor.becomeFirstResponder()
            self.editor.moveCaretToDocumentEnd()
        }

        private func presentAddMenu(from sourceView: UIView) {
            guard let component = self.component, let environment = self.environment, let controller = environment.controller() as? RichTextAttachmentScreen else {
                return
            }

            let editorState = self.editor.currentState()
            // Captured at menu-open time (before presenting can change first-responder state): whether the user
            // has a live caret. When false, the Add-menu actions target the document end instead of offset 0.
            let hasCursor = viewTreeContainsFirstResponder(view: self.editor)

            var items: [ContextMenuItem] = []
            
            if !editorState.hasSelection {
                items.append(.action(ContextMenuActionItem(text: environment.strings.RichText_MenuHeading, icon: { theme in
                    return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/FormatHeading"), color: theme.contextMenu.primaryColor)
                }, additionalLeftIcon: component.context.isPremium ? nil : { _ in
                    return UIImage(bundleImageName: "Premium/ContextStar")
                }, action: { [weak self] c, _ in
                    guard let self, let environment = self.environment else {
                        c?.dismiss(completion: nil)
                        return
                    }
                    
                    let live = self.editor.currentState()
                    
                    var subItems: [ContextMenuItem] = []
                    subItems.append(.action(ContextMenuActionItem(text: environment.strings.ChatList_Context_Back, icon: { theme in
                        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Back"), color: theme.contextMenu.primaryColor)
                    }, iconPosition: .left, action: { c, _ in
                        c?.popItems()
                    })))
                    subItems.append(.separator)
                    for level in 0 ..< 6 {
                        let fontSize: CGFloat
                        switch level {
                        case 0:
                            fontSize = 24
                        case 1:
                            fontSize = 21
                        case 2:
                            fontSize = 19
                        case 3:
                            fontSize = 18
                        case 4:
                            fontSize = 17
                        case 5:
                            fontSize = 16
                        default:
                            fontSize = 24
                        }
                        
                        let mappedStyle: ParagraphStyleName
                        switch level {
                        case 0:
                            mappedStyle = .heading1
                        case 1:
                            mappedStyle = .heading2
                        case 2:
                            mappedStyle = .heading3
                        case 3:
                            mappedStyle = .heading4
                        case 4:
                            mappedStyle = .heading5
                        case 5:
                            mappedStyle = .heading6
                        default:
                            mappedStyle = .heading1
                        }
                        
                        subItems.append(.action(ContextMenuActionItem(text: environment.strings.RichText_MenuHeadingItem("\(level + 1)").string, textFont: .custom(font: Font.with(size: fontSize, design: .serif, weight: .semibold), height: nil, verticalOffset: nil), icon: { theme in
                            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/FormatHeading\(level + 1)"), color: theme.contextMenu.primaryColor)
                        }, additionalLeftIcon: { theme in
                            return live.paragraphStyle == mappedStyle ? generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Check"), color: theme.contextMenu.primaryColor) : UIImage()
                        }, iconPosition: .left, action: { [weak self] _, f in
                            guard let self else {
                                f(.default)
                                return
                            }

                            if hasCursor {
                                self.editor.setParagraphStyle(mappedStyle)
                            } else {
                                // No caret: append a NEW empty paragraph with this heading style at the end and
                                // focus it, rather than converting an existing paragraph (a no-op at offset 0).
                                self.focusEditorAtDocumentEndIfNeeded(hasCursor: hasCursor)
                                self.editor.insertDocument(Document(blocks: [.paragraph(ParagraphBlock(id: BlockID.generate(), style: mappedStyle))]))
                            }

                            f(.default)
                        })))
                    }
                    c?.pushItems(items: .single(ContextController.Items(content: .list(subItems))))
                })))
            }
            
            // "Text" normalizes to a plain body paragraph. Offer it whenever there is no selection (so the
            // caret's paragraph can always be reset — e.g. a heading down-converted), or when the selection
            // is not already plain body text: it sits in a block container (quote / code / list / pull quote)
            // or carries a non-body paragraph style (a heading). Tapping it strips that container/style.
            let isPlainBody = !editorState.isCodeBlock
                && !editorState.isPullQuote
                && editorState.listMarker == nil
                && editorState.blockQuoteDepth == 0
                && (editorState.paragraphStyle == nil || editorState.paragraphStyle == .body)
            if !editorState.hasSelection || !isPlainBody {
                items.append(.action(ContextMenuActionItem(text: environment.strings.RichText_MenuText, icon: { theme in
                    return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/FormatText"), color: theme.contextMenu.primaryColor)
                }, action: { [weak self] c, _ in
                    guard let self else {
                        c?.dismiss(completion: nil)
                        return
                    }

                    self.focusEditorAtDocumentEndIfNeeded(hasCursor: hasCursor)
                    self.convertToBodyText()
                    c?.dismiss(completion: nil)
                })))
            }
            
            items.append(.action(ContextMenuActionItem(text: environment.strings.RichText_MenuQuote, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/FormatQuote"), color: theme.contextMenu.primaryColor)
            }, action: { [weak self] c, _ in
                guard let self else {
                    c?.dismiss(completion: nil)
                    return
                }

                self.focusEditorAtDocumentEndIfNeeded(hasCursor: hasCursor)
                let live = self.editor.currentState()
                if live.blockQuoteDepth > 0 {
                    self.editor.unwrapBlockQuoteLevel()
                } else {
                    self.editor.wrapInBlockQuote()
                }
                c?.dismiss(completion: nil)
            })))
            
            items.append(.action(ContextMenuActionItem(text: environment.strings.RichText_MenuPullquote, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/FormatPullquote"), color: theme.contextMenu.primaryColor)
            }, additionalLeftIcon: component.context.isPremium ? nil : { _ in
                return UIImage(bundleImageName: "Premium/ContextStar")
            }, action: { [weak self] c, _ in
                guard let self else {
                    c?.dismiss(completion: nil)
                    return
                }
                
                self.focusEditorAtDocumentEndIfNeeded(hasCursor: hasCursor)
                let live = self.editor.currentState()
                if live.blockQuoteDepth > 0 {
                    self.editor.unwrapBlockQuoteLevel()
                }
                if live.isPullQuote {
                } else {
                    self.editor.makePullQuote()
                }
                c?.dismiss(completion: nil)
            })))
            
            items.append(.action(ContextMenuActionItem(text: environment.strings.RichText_MenuCode, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/FormatCode"), color: theme.contextMenu.primaryColor)
            }, additionalLeftIcon: component.context.isPremium ? nil : { _ in
                return UIImage(bundleImageName: "Premium/ContextStar")
            }, action: { [weak self] c, _ in
                guard let self else {
                    c?.dismiss(completion: nil)
                    return
                }
                
                self.focusEditorAtDocumentEndIfNeeded(hasCursor: hasCursor)
                let live = self.editor.currentState()
                if live.blockQuoteDepth > 0 {
                    self.editor.unwrapBlockQuoteLevel()
                }
                if live.isCodeBlock {
                } else {
                    self.editor.makeCodeBlock()
                }
                c?.dismiss(completion: nil)
            })))
            
            items.append(.action(ContextMenuActionItem(text: environment.strings.RichText_MenuFormula, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/FormatFormula"), color: theme.contextMenu.primaryColor)
            }, additionalLeftIcon: component.context.isPremium ? nil : { _ in
                return UIImage(bundleImageName: "Premium/ContextStar")
            }, action: { [weak self] c, _ in
                guard let self else {
                    c?.dismiss(completion: nil)
                    return
                }

                self.focusEditorAtDocumentEndIfNeeded(hasCursor: hasCursor)
                self.component?.presentFormulaEditor?(nil, { [weak self] latex in
                    guard let self else {
                        return
                    }
                    self.editor.insertFormula(latex: latex)
                    DispatchQueue.main.async { [weak self] in
                        self?.editor.becomeFirstResponder()
                    }
                })
                
                c?.dismiss(completion: nil)
            })))
            
            let presentationData = component.context.sharedContext.currentPresentationData.with { $0 }
            let contextController = makeContextController(
                presentationData: presentationData,
                source: .reference(RichTextActionContextReferenceSource(sourceView: sourceView)),
                items: .single(ContextController.Items(content: .list(items))),
                gesture: nil
            )
            (controller.parentController() ?? controller).presentInGlobalOverlay(contextController)
        }

        private func presentActionMenu(from sourceView: UIView, items: [ContextMenuItem]) {
            guard let component = self.component else { return }
            let presentationData = component.context.sharedContext.currentPresentationData.with { $0 }
            let controller = makeContextController(
                presentationData: presentationData,
                source: .reference(RichTextActionContextReferenceSource(sourceView: sourceView)),
                items: .single(ContextController.Items(content: .list(items))),
                gesture: nil
            )
            self.environment?.controller()?.presentInGlobalOverlay(controller)
        }

        /// Maps the app theme to the editor's render colors. Every value is `PresentationTheme`-derived —
        /// no OS-semantic `UIColor` survives on this path. accent/table derivations mirror the chat
        /// composer (`ChatTextInputPanelNode.makeRichTextThemeColors`); text uses `list.item*` because the
        /// screen's surface is `list.plainBackgroundColor`.
        private static func mapEditorTheme(_ theme: PresentationTheme) -> RichTextEditorTheme {
            let codeFill = theme.list.itemAccentColor.withMultipliedAlpha(0.1)
            
            let shadowCursorColor: UIColor
            if theme.overallDarkAppearance {
                shadowCursorColor = UIColor(white: 1.0, alpha: 0.4)
            } else {
                shadowCursorColor = UIColor(white: 0.0, alpha: 0.3)
            }
            
            return RichTextEditorTheme(
                primaryText: theme.list.itemPrimaryTextColor,
                secondaryText: theme.list.itemSecondaryTextColor,
                placeholder: theme.list.itemPlaceholderTextColor,
                accent: theme.list.itemAccentColor,
                tableBorder: theme.list.itemPrimaryTextColor.withMultipliedAlpha(0.1),
                tableHeaderBackground: theme.list.itemPrimaryTextColor.withMultipliedAlpha(0.05),
                codeBackground: codeFill,
                listMarker: theme.list.itemPrimaryTextColor,
                inlineCodeBackground: codeFill,
                markedTextUnderline: theme.list.itemPrimaryTextColor,
                spoilerDust: theme.list.itemSecondaryTextColor,
                containerPlaceholder: theme.list.itemPlaceholderTextColor.mixedWith(theme.list.itemAccentColor, alpha: 0.15).withMultipliedBrightnessBy(theme.overallDarkAppearance ? 1.1 : 0.9),
                shadowCursor: shadowCursorColor,
                quoteAuthorText: theme.list.itemAccentColor,
                quoteAuthorPlaceholder: theme.list.itemPlaceholderTextColor.mixedWith(theme.list.itemAccentColor, alpha: 0.15).withMultipliedBrightnessBy(theme.overallDarkAppearance ? 1.1 : 0.9)
            )
        }

        func presentPremiumToast() {
            guard let component = self.component, let controller = self.environment?.controller() as? RichTextAttachmentScreen else {
                return
            }
            let presentationData = component.context.sharedContext.currentPresentationData.with { $0 }

            let overlayController = UndoOverlayController(
                presentationData: presentationData,
                content: .premiumPaywall(title: nil, text: presentationData.strings.RichText_PremiumToastText, customUndoText: nil, timeout: nil, linkAction: nil),
                elevatedLayout: true,
                action: { action in
                    if case .info = action {

                    }
                    return true
                }
            )
            (controller.parentController() ?? controller).presentInGlobalOverlay(overlayController)
        }

        func update(component: RichTextAttachmentScreenComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<EnvironmentType>, transition: ComponentTransition) -> CGSize {
            let environment = environment[EnvironmentType.self].value
            self.componentState = state
            self.environment = environment

            self.isUpdating = true
            defer { self.isUpdating = false }

            if self.component == nil {
                editor.placeholders = RichTextEditorPlaceholders(body: environment.strings.RichText_PlaceholderBody, listEnd: "", listOutdent: "", pullQuote: environment.strings.RichText_PlaceholderQuote, blockQuote: environment.strings.RichText_PlaceholderQuote, codeBlock: environment.strings.RichText_PlaceholderCode)
                
                // The screen paints `list.plainBackgroundColor` (below); clear the editor's opaque default
                // `.systemBackground` so that themed surface shows through.
                editor.canvasBackgroundColor = .clear
                // Theme the editor's mapper BEFORE seeding the document: the document setter builds each
                // block's attributed string with the mapper's current theme (baking in the foreground
                // color), and the `editor.theme` setter only re-maps existing boxes when `bounds.width > 0`
                // — which is false here (the editor frame is set later this pass). So seeding pre-existing
                // text before theming left it the `.default` black foreground. (The guarded re-apply below
                // is a no-op on this first pass since `appliedTheme` is now set, and handles later theme
                // changes when the frame — and a working reload width — exists.)
                editor.theme = Self.mapEditorTheme(environment.theme)
                self.appliedTheme = environment.theme
                // Quote geometry for the full-page article editor. Defaults == the editor's built-in look;
                // tune here to diverge from the chat composer.
                editor.quoteStyle = QuoteStyle(leadingInset: 9.0, topInset: 4.0, bottomInset: 4.0)
                editor.pullQuoteStyle = PullQuoteStyle()
                // Quote collapse/expand affordance icons (same assets as the chat composer / legacy input).
                if let collapse = UIImage(bundleImageName: "Media Gallery/Minimize")?.precomposed().withRenderingMode(.alwaysTemplate),
                   let expand = UIImage(bundleImageName: "Media Gallery/Fullscreen")?.precomposed().withRenderingMode(.alwaysTemplate) {
                    editor.quoteCollapseIcons = RichTextEditorQuoteCollapseIcons(collapse: collapse, expand: expand)
                }
                // A selection-handle ("knob") drag must NOT be hijacked by the interactive keyboard-/modal-
                // dismiss gestures. These Display flags can only be set host-side (the editor package can't
                // import Display) and are applied to the hit-testable handle views, so the effect is scoped to
                // knob interaction — not the whole editor surface.
                editor.configureSelectionHandleView = { handle in
                    handle.disablesInteractiveTransitionGestureRecognizer = true   // navigation back-swipe (triggered by a horizontal knob drag)
                    handle.disablesInteractiveModalDismiss = true
                    handle.disablesInteractiveKeyboardGestureRecognizer = true
                }
                // Table row/column structural menu: the editor hands us a framework-agnostic descriptor; we
                // present it as a ContextController anchored to the tapped handle (in the editor's canvas).
                editor.onRequestTableStructuralMenu = { [weak self] request in
                    guard let self, let component = self.component else { return }
                    let presentationData = component.context.sharedContext.currentPresentationData.with { $0 }
                    presentTableStructuralMenu(request, presentationData: presentationData) { [weak self] controller in
                        self?.environment?.controller()?.presentInGlobalOverlay(controller)
                    }
                }
                // Media control (more button) menu: the editor hands us an account-free request; we present
                // our own menu anchored to the tapped control. `delete` is bound to the exact occurrence.
                editor.onRequestMediaControl = { [weak self] request in
                    guard let self, let component = self.component, let anchor = request.view else { return }
                    let presentationData = component.context.sharedContext.currentPresentationData.with { $0 }
                    switch request.control {
                    case .more:
                        var items: [ContextMenuItem] = []
                        items.append(.action(ContextMenuActionItem(
                            text: request.isSpoiler ? presentationData.strings.Attachment_DisableSpoiler : presentationData.strings.Attachment_EnableSpoiler,
                            icon: { _ in nil },
                            iconAnimation: ContextMenuActionItem.IconAnimation(name: "anim_spoiler", loop: true),
                            action: { _, f in f(.default); request.toggleSpoiler() }
                        )))
                        items.append(.action(ContextMenuActionItem(
                            text: presentationData.strings.Common_Delete,
                            textColor: .destructive,
                            icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.contextMenu.destructiveColor) },
                            action: { _, f in f(.default); request.delete() }
                        )))
                        presentMediaControlMenu(anchorView: anchor, items: items,
                                                presentationData: presentationData) { [weak self] controller in
                            self?.environment?.controller()?.presentInGlobalOverlay(controller)
                        }
                    case .add:
                        guard let addMore = request.addMore else { break }
                        self.pickMedia(photoVideoOnly: true) { mediaID, naturalSize, kind, _ in
                            guard kind == .image || kind == .video else { return }   // mosaic is photo/video only
                            addMore(mediaID, naturalSize, kind)
                        }
                    case .delete:
                        request.delete()
                    case .toggleLayout:
                        request.toggleLayout?()
                    }
                }
                editor.disablesInteractiveTransitionGestureRecognizer = true   // navigation back-swipe (triggered by a horizontal knob drag)
                editor.disablesInteractiveModalDismiss = true
                editor.disablesInteractiveKeyboardGestureRecognizer = true
                // Seed the editor with the caller-supplied initial content (e.g. the chat composer's
                // current document when expanding); an empty document when none is provided.
                
                var initialContents: Document?
                var initialMedia: [String: Media] = [:]
                var initialEmojiFiles: [Int64: TelegramMediaFile] = [:]
                switch component.mode {
                case let .edit(documentValue, mediaValue, emojiFilesValue):
                    initialContents = documentValue
                    initialMedia = mediaValue
                    initialEmojiFiles = emojiFilesValue
                case let .standalone(documentValue, mediaValue, emojiFilesValue):
                    initialContents = documentValue
                    initialMedia = mediaValue
                    initialEmojiFiles = emojiFilesValue
                }
                
                editor.document = initialContents ?? Document()
                // Seed the picked-media store alongside the document (before the media-view provider runs)
                // so any media referenced by the initial document resolves on first layout.
                self.attachedMedia = initialMedia

                let emojiKeyboard = RichTextEmojiKeyboardController(context: component.context, editor: editor, requestLayout: { [weak self] in
                    guard let self, !self.isUpdating else { return }
                    self.componentState?.updated(transition: .spring(duration: 0.4))
                })
                self.emojiKeyboard = emojiKeyboard
                // Seed the keyboard's file store with the files of any custom emoji the initial document
                // references (the `Document` carries only fileIds) — before the editor's first layout, so a
                // custom emoji carried in from the chat composer renders, and its file survives back out.
                emojiKeyboard.seedEmojiFiles(initialEmojiFiles)

                editor.registerEmojiViewProvider { [weak self] id, size in
                    return self?.emojiKeyboard?.customEmojiView(forId: id, size: size)
                }

                editor.registerFormulaRenderer { context in
                    guard let attachment = instantPageMathAttachment(
                        latex: context.latex,
                        fontSize: context.fontSize,
                        textColor: context.textColor,
                        mode: .inline
                    ) else {
                        return nil
                    }
                    return RichTextFormulaRenderResult(
                        image: attachment.rendered.image,
                        size: attachment.rendered.size,
                        ascent: attachment.rendered.ascent,
                        descent: attachment.rendered.descent
                    )
                }

                editor.onEditFormulaRequested = { [weak self] latex, completion in
                    guard let self, let component = self.component else {
                        return
                    }
                    component.presentFormulaEditor?(latex, { [weak self] updatedLatex in
                        completion(updatedLatex)
                        DispatchQueue.main.async { [weak self] in
                            self?.editor.becomeFirstResponder()
                        }
                    })
                }

                editor.registerMediaViewProvider { [weak self] items, _, displayMode, existing in
                    guard let self, let component = self.component else { return nil }
                    // Theme an audio row to the editor's accent/text scheme (same `list.item*` sources as
                    // `mapEditorTheme` / the table); ignored for image/map media.
                    let theme = component.context.sharedContext.currentPresentationData.with { $0 }.theme
                    let audioColors = InstantPageAudioColorOverride(
                        control: theme.list.itemAccentColor,
                        controlForeground: theme.list.itemCheckColors.foregroundColor,
                        title: theme.list.itemPrimaryTextColor,
                        description: theme.list.itemSecondaryTextColor
                    )
                    let resolved: [(media: EngineMedia, naturalSize: CGSize, isSpoiler: Bool)] = items.compactMap { item in
                        guard let media = self.attachedMedia[item.mediaID] else { return nil }
                        return (EngineMedia(media), item.naturalSize, item.isSpoiler)
                    }
                    guard !resolved.isEmpty else { return nil }
                    // In-place update: reuse the existing container (surviving photo/video cells keep their bound
                    // fetch, no re-flash) across add-more / delete-one; else build a fresh one.
                    if let view = existing as? MediaItemNodeView {
                        view.updateResolvedItems(resolved, displayMode: displayMode)
                        return view
                    }
                    return MediaItemNodeView(context: component.context, items: resolved, audioColorOverride: audioColors, displayMode: displayMode)
                }

                // Host the checklist checkbox with a `CheckNode` themed from the standard app checkbox palette
                // (`list.itemCheckColors`), mirroring `instantPageChecklistMarkerTheme`. Reads `appliedTheme`
                // (the live `PresentationTheme`) lazily; nil before the first theme apply (harmless — the editor
                // falls back to its glyph marker until a checkbox is provided).
                editor.registerChecklistMarkerViewProvider { [weak self] checked, _ in
                    guard let self, let theme = self.appliedTheme else { return nil }
                    let c = theme.list.itemCheckColors
                    let nodeTheme = CheckNodeTheme(backgroundColor: c.fillColor, strokeColor: c.foregroundColor, borderColor: c.strokeColor, overlayBorder: false, hasInset: false, hasShadow: false)
                    return HostChecklistCheckboxView(theme: nodeTheme, checked: checked)
                }

                editor.onBecameFirstResponder = { [weak self] in
                    guard let self else {
                        return
                    }
                    if let controller = self.environment?.controller() as? RichTextAttachmentScreen {
                        controller.requestAttachmentMenuExpansion()
                    }
                }

                // The editor no longer drives its own layout/keyboard insets; it just tells us when anything
                // changes so we re-run this update (which calls editor.update(size:insets:)). The isUpdating
                // guard only defends the SYNCHRONOUS loop (update → editor.update → onChange → update);
                // editor.update/performLayout don't fire onChange synchronously, so it can't loop. Async
                // onChange (user edits/caret moves) skips the guard and correctly schedules a re-layout.
                editor.onChange = { [weak self] in
                    guard let self, !self.isUpdating else { return }
                    self.componentState?.updated(transition: .spring(duration: 0.4))
                }

                self.addSubview(editor)
                self.topEdgeEffectView.isUserInteractionEnabled = false
                self.addSubview(self.topEdgeEffectView)
            }
            self.component = component

            let isSendRichFormattingLocked = self.isSendRichFormattingLocked
            if !self.didShowPremiumToast && isSendRichFormattingLocked {
                self.didShowPremiumToast = true
                DispatchQueue.main.async { [weak self] in
                    self?.presentPremiumToast()
                }
            }

            if self.appliedTheme !== environment.theme {
                self.appliedTheme = environment.theme
                self.editor.theme = Self.mapEditorTheme(environment.theme)
            }

            let barButtonSize = CGSize(width: 44.0, height: 44.0)
            
            let editorState = self.editor.currentState()
            
            if self.navigationTapView.superview == nil {
                component.overNavigationContainer.addSubview(self.navigationTapView)
            }
            transition.setFrame(view: self.navigationTapView, frame: CGRect(origin: CGPoint(), size: CGSize(width: availableSize.width, height: environment.navigationHeight)))
            
            let leftNavActionsBarSize = self.leftNavActionsBar.update(
                transition: transition,
                component: AnyComponent(GlassControlGroupComponent(
                    theme: environment.theme,
                    preferClearGlass: false,
                    background: .panel,
                    items: [
                        GlassControlGroupComponent.Item(id: 0, content: .icon("Navigation/Close"), action: { [weak self] in
                            guard let self, let controller = self.environment?.controller() as? RichTextAttachmentScreen else {
                                return
                            }
                            controller.close()
                        })
                    ], minWidth: 44.0)
                ),
                environment: {},
                containerSize: CGSize(width: availableSize.width, height: barButtonSize.height)
            )
            let leftNavActionsBarFrame = CGRect(origin: CGPoint(x: environment.safeInsets.left + 16.0, y: 16.0), size: leftNavActionsBarSize)
            if let leftNavActionsBarView = self.leftNavActionsBar.view {
                if leftNavActionsBarView.superview == nil {
                    component.overNavigationContainer.addSubview(leftNavActionsBarView)
                }
                transition.setFrame(view: leftNavActionsBarView, frame: leftNavActionsBarFrame)
            }
            
            let rightNavActionsBarSize = self.rightNavActionsBar.update(
                transition: transition,
                component: AnyComponent(GlassControlGroupComponent(
                    theme: environment.theme,
                    preferClearGlass: false,
                    background: .panel,
                    items: [
                        GlassControlGroupComponent.Item(id: 0, content: .icon("Media Editor/Undo"), action: editorState.canUndo ? { [weak self] in
                            self?.editor.undo()
                        } : nil),
                        GlassControlGroupComponent.Item(id: 1, content: .icon("Media Editor/Redo"), action: editorState.canRedo ? { [weak self] in
                            self?.editor.redo()
                        } : nil)
                    ], minWidth: 44.0)
                ),
                environment: {},
                containerSize: CGSize(width: availableSize.width, height: barButtonSize.height)
            )
            let rightNavActionsBarFrame = CGRect(origin: CGPoint(x: availableSize.width - (environment.safeInsets.left + 16.0) - rightNavActionsBarSize.width, y: 16.0), size: rightNavActionsBarSize)
            if let rightNavActionsBarView = self.rightNavActionsBar.view {
                if rightNavActionsBarView.superview == nil {
                    component.overNavigationContainer.addSubview(rightNavActionsBarView)
                }
                transition.setFrame(view: rightNavActionsBarView, frame: rightNavActionsBarFrame)
            }

            if case .standalone = component.mode {
                let titleSize = self.title.update(
                    transition: .immediate,
                    component: AnyComponent(
                        MultilineTextComponent(
                            text: .plain(NSAttributedString(
                                string: environment.strings.RichText_TitleArticle,
                                font: Font.semibold(17.0),
                                textColor: environment.theme.rootController.navigationBar.primaryTextColor
                            ))
                        )
                    ),
                    environment: {},
                    containerSize: CGSize(width: 200.0, height: 40.0)
                )
                // The title is centered, but must clear both the left button cluster (Close + undo + redo) and the
                // Done button. When the natural center would overlap either side, re-center it in the gap between
                // the cluster's trailing edge and Done (needed on narrow screens where the centered title would
                // otherwise sit under the redo pill).
                let leftClusterMaxX = leftNavActionsBarFrame.maxX
                var titleFrame = CGRect(origin: CGPoint(x: floorToScreenPixels((availableSize.width - titleSize.width) / 2.0), y: floorToScreenPixels((environment.navigationHeight - titleSize.height) / 2.0) + 3.0), size: titleSize)
                if titleFrame.minX < leftClusterMaxX + 16.0 || titleFrame.maxX > rightNavActionsBarFrame.minX - 16.0 {
                    titleFrame.origin.x = leftClusterMaxX + floorToScreenPixels((rightNavActionsBarFrame.minX - leftClusterMaxX) - titleSize.width) / 2.0
                }
                if let titleView = self.title.view {
                    if titleView.superview == nil {
                        component.overNavigationContainer.addSubview(titleView)
                    }
                    transition.setFrame(view: titleView, frame: titleFrame)
                }
            }
            
            self.backgroundColor = environment.theme.actionSheet.opaqueItemBackgroundColor

            let emojiPanelHeight = self.emojiKeyboard?.updatePanel(container: self, availableSize: availableSize, environment: environment, transition: transition) ?? 0.0
            let editorTop = environment.navigationHeight
            let editorFrame = CGRect(x: environment.safeInsets.left, y: 0.0,
                                     width: availableSize.width - environment.safeInsets.left - environment.safeInsets.right,
                                     height: availableSize.height)
            self.editor.frame = editorFrame
            
            var barActions: [RichTextActionBarComponent.Action] = []
            let barActionsId: AnyHashable
            
            if editorState.hasSelection {
                barActionsId = 1
                
                barActions.append(RichTextActionBarComponent.Action(
                    id: AnyHashable("bold"), icon: "RichText/ToolBold",
                    action: { [weak self] _ in self?.editor.toggleBold() },
                    isSelected: editorState.bold
                ))
                barActions.append(RichTextActionBarComponent.Action(
                    id: AnyHashable("italic"), icon: "RichText/ToolItalic",
                    action: { [weak self] _ in self?.editor.toggleItalic() },
                    isSelected: editorState.italic
                ))
                barActions.append(RichTextActionBarComponent.Action(
                    id: AnyHashable("strike"), icon: "RichText/ToolStrike",
                    action: { [weak self] _ in self?.editor.toggleStrikethrough() },
                    isSelected: editorState.strikethrough
                ))
                barActions.append(RichTextActionBarComponent.Action(
                    id: AnyHashable("underline"), icon: "RichText/ToolUnderline",
                    action: { [weak self] _ in self?.editor.toggleUnderline() },
                    isSelected: editorState.underline
                ))
                barActions.append(RichTextActionBarComponent.Action(
                    id: AnyHashable("spoiler"), icon: "RichText/ToolSpoiler",
                    action: { [weak self] _ in self?.editor.toggleSpoiler() },
                    isSelected: editorState.spoiler
                ))
                barActions.append(RichTextActionBarComponent.Action(
                    id: AnyHashable("link"), icon: "RichText/ToolLink",
                    action: editorState.hasSelection ? { [weak self] _ in self?.presentLinkPrompt() } : nil,
                    isSelected: editorState.link != nil
                ))
                // A list/quote/etc. marker can only apply to paragraph text, so offer it only when the selection
                // covers no media or table block (see `EditorState.selectionIsTextOnly`).
                if editorState.selectionIsTextOnly {
                    barActions.append(RichTextActionBarComponent.Action(
                        id: AnyHashable("list"), icon: "RichText/ToolList",
                        action: { [weak self] sourceView in self?.presentListMenu(from: sourceView) },
                        isSelected: editorState.listMarker != nil,
                        showsPremiumBadge: !component.context.isPremium
                    ))
                    
                    barActions.append(RichTextActionBarComponent.Action(
                        id: AnyHashable("quote"), icon: "RichText/ToolQuote",
                        action: { [weak self] sourceView in self?.presentAddMenu(from: sourceView) },
                        isSelected: editorState.listMarker != nil,
                        showsPremiumBadge: !component.context.isPremium
                    ))
                }
            } else {
                barActionsId = 0
                
                barActions.append(RichTextActionBarComponent.Action(
                    id: AnyHashable("add"), icon: "Chat/Context Menu/Add",
                    action: editorState.isInTable ? nil : { [weak self] sourceView in
                        self?.presentAddMenu(from: sourceView)
                    },
                    isSelected: false
                ))
                barActions.append(RichTextActionBarComponent.Action(
                    id: AnyHashable("list"), icon: "RichText/ToolList",
                    action: editorState.isInTable ? nil : { [weak self] sourceView in
                        self?.presentListMenu(from: sourceView)
                    },
                    isSelected: false,
                    showsPremiumBadge: !component.context.isPremium
                ))
                barActions.append(RichTextActionBarComponent.Action(
                    id: AnyHashable("table"), icon: "RichText/ToolTable",
                    action: { [weak self] sourceView in
                        guard let self, let environment = self.environment else { return }
                        var items: [ContextMenuItem] = []
                        if self.editor.currentState().isInTable {
                            items.append(.action(ContextMenuActionItem(text: environment.strings.RichText_Menu_Table_Copy, icon: { _ in nil }, action: { [weak self] _, f in
                                f(.default)
                                self?.editor.copyCurrentTable()
                            })))
                            items.append(.action(ContextMenuActionItem(text: environment.strings.RichText_Menu_Table_ConvertToText, icon: { _ in nil }, action: { [weak self] _, f in
                                f(.default)
                                self?.editor.convertCurrentTableToText()
                            })))
                            items.append(.action(ContextMenuActionItem(text: environment.strings.RichText_Menu_Table_Delete, textColor: .destructive, icon: { _ in nil }, action: { [weak self] _, f in
                                f(.default); self?.editor.deleteTable()
                            })))
                        } else {
                            // No caret: drop the table at the document end (become FR + caret to end), not at
                            // the default offset-0 start. With a caret it inserts at the caret as before.
                            self.focusEditorAtDocumentEndIfNeeded(hasCursor: viewTreeContainsFirstResponder(view: self.editor))
                            self.editor.insertTable(rows: 2, cols: 2)
                        }
                        self.presentActionMenu(from: sourceView, items: items)
                    },
                    isSelected: false,
                    showsPremiumBadge: !component.context.isPremium
                ))
                if component.presentAttachmentMenu != nil {
                    barActions.append(RichTextActionBarComponent.Action(
                        id: AnyHashable("attach"), icon: "RichText/ToolAttach",
                        action: editorState.isInTable ? nil : { [weak self] _ in self?.presentImagePicker() },
                        isSelected: false
                    ))
                }
                barActions.append(RichTextActionBarComponent.Action(
                    id: AnyHashable("emoji"), icon: "RichText/ToolEmoji",
                    action: { [weak self] _ in self?.emojiKeyboard?.toggle() },
                    isSelected: self.emojiKeyboard?.isEmojiMode ?? false
                ))
            }
            
            let tabBarBottomInset = max(environment.inputHeight, emojiPanelHeight, environment.additionalInsets.bottom)
            
            var sideInset: CGFloat = 12.0
            if tabBarBottomInset <= 28.0 {
                sideInset = 20.0
            }
            
            let actionBarSpacing: CGFloat = 6.0
            
            let aiButtonSize = self.aiButton.update(
                transition: transition,
                component: AnyComponent(GlassControlGroupComponent(
                    theme: environment.theme,
                    preferClearGlass: false,
                    background: .panel,
                    items: [
                        GlassControlGroupComponent.Item(id: 0, content: .icon("Chat/Input/Text/InputAIIcon"), action: { [weak self] in
                            Task { @MainActor in
                                guard let self, let component = self.component, let environment = self.environment else {
                                    return
                                }
                                guard let controller = environment.controller() as? RichTextAttachmentScreen else {
                                    return
                                }
                                
                                // AI edit on the current selection: seed the edit screen with only the
                                // selected sub-document (partial table/image coverage expanded to the whole
                                // block, both directions) and replace that same range with the result. The
                                // gate is CONTENT-based (`ChatInputContent.isEmpty`), not text-based, so a
                                // selection covering only an image / empty-caption still enters here.
                                if let sel = self.editor.selectedGlobalRange() {
                                    let doc = self.editor.document
                                    let (lo, hi) = doc.expandingRangeOverNonTextBlocks(globalFrom: sel.from, globalTo: sel.to)
                                    let subDoc = doc.extractFragment(globalFrom: lo, globalTo: hi, carryingNonTextBlocks: true)
                                    let subContent = chatInputContent(fromDocument: subDoc, media: self.currentMedia, emojiFiles: self.currentEmojiFiles)
                                    if !subContent.isEmpty {
                                        let initialText = ComposedRichMessage.rich(instantPage: instantPage(from: subContent))
                                        let textProcessingScreen = await component.context.sharedContext.makeTextProcessingScreen(
                                            context: component.context,
                                            theme: environment.theme,
                                            mode: .edit(
                                                saveRestoreStateId: nil,
                                                completion: { [weak self] result in
                                                    guard let self else {
                                                        return
                                                    }
                                                    let content: ChatInputContent
                                                    switch result {
                                                    case let .rich(instantPage):
                                                        content = chatInputContent(fromInstantPage: instantPage)
                                                    case let .plain(text, entities):
                                                        content = chatInputContent(from: chatInputStateStringWithAppliedEntities(text, entities: entities))
                                                    case .empty:
                                                        // An empty result deletes the (expanded) selection.
                                                        self.editor.replaceRange(from: lo, to: hi, with: Document(blocks: []))
                                                        return
                                                    }
                                                    let (document, media, emojiFiles) = documentMediaAndEmoji(fromChatInputContent: content)
                                                    self.emojiKeyboard?.seedEmojiFiles(emojiFiles)
                                                    self.attachedMedia.merge(media) { _, new in new }
                                                    self.editor.replaceRange(from: lo, to: hi, with: document)
                                                },
                                                send: nil,
                                                sendContextActions: nil
                                            ),
                                            inputText: initialText,
                                            copyResult: nil,
                                            translateChat: nil
                                        )
                                        if let parentController = controller.parentController() {
                                            parentController.push(textProcessingScreen)
                                        } else {
                                            controller.push(textProcessingScreen)
                                        }
                                        return
                                    }
                                }

                                // No usable selection → generate content and insert it at the caret.
                                do {
                                    let textProcessingScreen = await component.context.sharedContext.makeTextProcessingScreen(
                                        context: component.context,
                                        theme: environment.theme,
                                        mode: .generate(
                                            completion: { [weak self] result in
                                                guard let self else {
                                                    return
                                                }
                                                let content: ChatInputContent
                                                switch result {
                                                case let .rich(instantPage):
                                                    content = chatInputContent(fromInstantPage: instantPage)
                                                case let .plain(text, entities):
                                                    content = chatInputContent(from: chatInputStateStringWithAppliedEntities(text, entities: entities))
                                                case .empty:
                                                    return
                                                }
                                                let (document, media, emojiFiles) = documentMediaAndEmoji(fromChatInputContent: content)
                                                self.emojiKeyboard?.seedEmojiFiles(emojiFiles)
                                                self.attachedMedia.merge(media) { _, new in new }
                                                self.editor.insertDocument(document)
                                            }
                                        ),
                                        inputText: .plain(text: "", entities: []),
                                        copyResult: nil,
                                        translateChat: nil
                                    )
                                    if let parentController = controller.parentController() {
                                        parentController.push(textProcessingScreen)
                                    } else {
                                        controller.push(textProcessingScreen)
                                    }
                                }
                            }
                        })
                    ], minWidth: 44.0)
                ),
                environment: {},
                containerSize: CGSize(width: 44.0, height: 44.0)
            )
            
            var isSendEnabled = true
            let content = chatInputContent(fromDocument: self.currentDocument, media: self.currentMedia, emojiFiles: self.currentEmojiFiles)
            if content.isEmptyWhitespaceTrimmed {
                isSendEnabled = false
            }
            
            let sendButtonSize = self.sendButton.update(
                transition: transition,
                component: AnyComponent(RichTextSendButtonComponent(
                    theme: environment.theme,
                    isEnabled: isSendEnabled,
                    isLocked: isSendRichFormattingLocked,
                    action: { [weak self] in
                        guard let self, let controller = self.environment?.controller() as? RichTextAttachmentScreen else {
                            return
                        }
                        controller.donePressed()
                    }
                )),
                environment: {},
                containerSize: CGSize(width: 44.0, height: 44.0)
            )
            
            let actionBarSize = self.actionBar.update(
                transition: transition,
                component: AnyComponent(RichTextActionBarComponent(
                    theme: environment.theme,
                    actionsId: barActionsId,
                    actions: barActions
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width - (sideInset + environment.safeInsets.left) * 2.0 - actionBarSpacing * 2.0 - aiButtonSize.width - sendButtonSize.width, height: 44.0)
            )
            
            var bottomInset = max(environment.inputHeight, emojiPanelHeight, environment.safeInsets.bottom)
            
            let aiButtonFrame = CGRect(origin: CGPoint(x: sideInset + environment.safeInsets.left, y: availableSize.height - bottomInset - 6.0 - aiButtonSize.height), size: aiButtonSize)
            if let aiButtonView = self.aiButton.view {
                if aiButtonView.superview == nil {
                    self.addSubview(aiButtonView)
                }
                transition.setFrame(view: aiButtonView, frame: aiButtonFrame)
            }
            
            let sendButtonFrame = CGRect(origin: CGPoint(x: availableSize.width - (sideInset + environment.safeInsets.left) - sendButtonSize.width, y: availableSize.height - bottomInset - 6.0 - sendButtonSize.height), size: sendButtonSize)
            if let sendButtonView = self.sendButton.view {
                if sendButtonView.superview == nil {
                    self.addSubview(sendButtonView)
                }
                transition.setFrame(view: sendButtonView, frame: sendButtonFrame)
            }
            
            let actionBarFrame = CGRect(origin: CGPoint(x: sideInset + environment.safeInsets.left + aiButtonSize.width + actionBarSpacing, y: availableSize.height - bottomInset - 6.0 - actionBarSize.height), size: actionBarSize)
            if let actionBarView = self.actionBar.view {
                if actionBarView.superview == nil {
                    self.addSubview(actionBarView)
                }
                transition.setFrame(view: actionBarView, frame: actionBarFrame)
            }
            bottomInset += 6.0 + actionBarSize.height + 6.0
            
            // The editor no longer tracks the keyboard; supply the bottom obstruction as a scroll inset.
            // Only one of (system keyboard / emoji panel) is up at a time (the emoji panel uses an
            // EmptyInputView, so inputHeight ≈ 0 while it shows); the home-indicator safe area is the floor.
            _ = self.editor.update(size: editorFrame.size,
                                   insets: UIEdgeInsets(top: editorTop, left: 0.0, bottom: bottomInset + 16.0, right: 0.0),
                                   contentMargins: UIEdgeInsets(top: 12.0, left: 0.0, bottom: 12.0, right: 0.0))

            // Top edge effect (mirrors ComposePollScreen): a blurred gradient at the screen top that content
            // fades under. Content color = the screen background (themed list.plainBackgroundColor).
            let edgeEffectHeight: CGFloat = 88.0
            let topEdgeEffectFrame = CGRect(origin: .zero, size: CGSize(width: availableSize.width, height: edgeEffectHeight))
            transition.setFrame(view: self.topEdgeEffectView, frame: topEdgeEffectFrame)
            self.topEdgeEffectView.update(content: environment.theme.actionSheet.opaqueItemBackgroundColor, blur: true, alpha: 1.0, rect: topEdgeEffectFrame, edge: .top, edgeSize: topEdgeEffectFrame.height, transition: transition)

            // While the emoji panel is up, hide the AttachmentController's bottom menu/tab bar so the
            // container collapses that panel and re-lays out this screen at full height — otherwise the
            // emoji panel renders behind the attachment menu (mirrors ComposePollScreen).
            let isTabBarVisible = !(self.emojiKeyboard?.isEmojiMode ?? false)
            if self.lastTabBarVisible != isTabBarVisible {
                self.lastTabBarVisible = isTabBarVisible
                if let controller = environment.controller() as? RichTextAttachmentScreen {
                    let tabBarTransition = transition.containedViewLayoutTransition
                    DispatchQueue.main.async { [weak controller] in
                        controller?.updateTabBarVisibility(isTabBarVisible, tabBarTransition)
                    }
                }
            }

            return availableSize
        }
    }

    func makeView() -> View {
        return View()
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<EnvironmentType>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

@available(iOS 13.0, *)
private final class RichTextActionContextReferenceSource: ContextReferenceContentSource {
    private let sourceView: UIView
    init(sourceView: UIView) { self.sourceView = sourceView }
    func transitionInfo() -> ContextControllerReferenceViewInfo? {
        return ContextControllerReferenceViewInfo(referenceView: self.sourceView,
            contentAreaInScreenSpace: UIScreen.main.bounds,
            insets: UIEdgeInsets(top: -4.0, left: 0.0, bottom: -4.0, right: 0.0), actionsPosition: .top)
    }
}
