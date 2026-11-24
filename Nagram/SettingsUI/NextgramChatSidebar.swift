import TelegramPresentationData
import UIKit

public final class NextgramChatSidebar: UIView {
    public enum Style: Equatable {
        case drawer
        case panel
    }

    private let backdrop = UIButton(type: .custom)
    private let transitionView = UIView()
    private let panel = UIView()
    private let panelContent = UIStackView()
    private let contentShade = UIView()
    private var contentPreview: UIView?
    private var closing = false
    private let style: Style

    public init(theme: PresentationTheme, title: String, closeTitle: String, actions: [(title: String, icon: String, action: () -> Void)], style: Style = .panel, search: (title: String, action: () -> Void)? = nil) {
        self.style = style
        super.init(frame: .zero)
        self.accessibilityViewIsModal = true
        self.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.clipsToBounds = true
        self.transitionView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.transitionView)
        NSLayoutConstraint.activate([
            self.transitionView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.transitionView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.transitionView.topAnchor.constraint(equalTo: self.topAnchor),
            self.transitionView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])

        self.backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.36)
        self.backdrop.accessibilityLabel = closeTitle
        self.backdrop.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
        self.backdrop.translatesAutoresizingMaskIntoConstraints = false
        self.transitionView.addSubview(self.backdrop)
        NSLayoutConstraint.activate([
            self.backdrop.leadingAnchor.constraint(equalTo: self.transitionView.leadingAnchor),
            self.backdrop.trailingAnchor.constraint(equalTo: self.transitionView.trailingAnchor),
            self.backdrop.topAnchor.constraint(equalTo: self.transitionView.topAnchor),
            self.backdrop.bottomAnchor.constraint(equalTo: self.transitionView.bottomAnchor)
        ])

        let isDrawer = style == .drawer
        self.panel.backgroundColor = isDrawer ? theme.list.plainBackgroundColor : theme.list.modalBlocksBackgroundColor
        self.panel.layer.cornerRadius = isDrawer ? 0.0 : 24.0
        self.panel.layer.cornerCurve = .continuous
        self.panel.clipsToBounds = true
        self.panel.translatesAutoresizingMaskIntoConstraints = false
        self.transitionView.addSubview(self.panel)

        let heading = UILabel()
        heading.text = title
        heading.font = UIFont.systemFont(ofSize: 22.0, weight: isDrawer ? .semibold : .bold)
        heading.textColor = theme.list.itemPrimaryTextColor
        heading.accessibilityTraits = .header

        let header: UIView
        if isDrawer, let search {
            let button = self.makeGlassSearchButton(theme: theme, title: search.title, action: search.action)
            let row = UIStackView(arrangedSubviews: [heading, button])
            row.alignment = .center
            row.spacing = 12.0
            heading.setContentHuggingPriority(.defaultLow, for: .horizontal)
            header = row
        } else {
            header = heading
        }
        let stack = self.panelContent
        stack.addArrangedSubview(header)
        stack.axis = .vertical
        stack.spacing = isDrawer ? 0.0 : 4.0
        stack.setCustomSpacing(isDrawer ? 7.0 : 16.0, after: header)
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.panel.addSubview(stack)

        for entry in actions {
            var configuration = UIButton.Configuration.plain()
            configuration.title = entry.title
            configuration.image = UIImage(systemName: entry.icon)
            configuration.imagePadding = 14.0
            if isDrawer {
                configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .medium)
            }
            configuration.baseForegroundColor = theme.list.itemPrimaryTextColor
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 12.0, leading: 0.0, bottom: 12.0, trailing: 0.0)
            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                self?.close(completion: entry.action)
            })
            button.contentHorizontalAlignment = .leading
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48.0).isActive = true
            stack.addArrangedSubview(button)
        }

        let preferredWidth = isDrawer ? self.panel.widthAnchor.constraint(equalTo: self.transitionView.widthAnchor, multiplier: 0.77) : self.panel.widthAnchor.constraint(equalToConstant: 300.0)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            self.panel.leadingAnchor.constraint(equalTo: isDrawer ? self.transitionView.leadingAnchor : self.safeAreaLayoutGuide.leadingAnchor, constant: isDrawer ? 0.0 : 10.0),
            self.panel.trailingAnchor.constraint(lessThanOrEqualTo: self.safeAreaLayoutGuide.trailingAnchor, constant: isDrawer ? -48.0 : -36.0),
            self.panel.topAnchor.constraint(equalTo: isDrawer ? self.transitionView.topAnchor : self.safeAreaLayoutGuide.topAnchor, constant: isDrawer ? 0.0 : 8.0),
            self.panel.bottomAnchor.constraint(equalTo: isDrawer ? self.transitionView.bottomAnchor : self.safeAreaLayoutGuide.bottomAnchor, constant: isDrawer ? 0.0 : -8.0),
            preferredWidth,
            stack.leadingAnchor.constraint(equalTo: self.panel.safeAreaLayoutGuide.leadingAnchor, constant: isDrawer ? 32.0 : 22.0),
            stack.trailingAnchor.constraint(equalTo: self.panel.safeAreaLayoutGuide.trailingAnchor, constant: isDrawer ? -24.0 : -22.0),
            stack.topAnchor.constraint(equalTo: self.panel.safeAreaLayoutGuide.topAnchor, constant: isDrawer ? 8.0 : 20.0),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: self.panel.bottomAnchor, constant: -24.0)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeGlassSearchButton(theme: PresentationTheme, title: String, action: @escaping () -> Void) -> UIView {
        let container: UIView
        if #available(iOS 26.0, *) {
            let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            glass.layer.cornerRadius = 22.0
            glass.layer.cornerCurve = .continuous
            glass.clipsToBounds = true
            container = glass
        } else {
            let fallback = UIView()
            fallback.backgroundColor = theme.list.itemPrimaryTextColor.withAlphaComponent(0.10)
            fallback.layer.cornerRadius = 22.0
            fallback.layer.cornerCurve = .continuous
            container = fallback
        }
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20.0, weight: .medium)), for: .normal)
        button.tintColor = theme.list.itemPrimaryTextColor
        button.accessibilityLabel = title
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 44.0),
            container.heightAnchor.constraint(equalToConstant: 44.0),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    public func open(in view: UIView) {
        self.frame = view.bounds
        self.prepareContentPreview(in: view)
        view.addSubview(self)
        self.layoutIfNeeded()
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        if self.contentPreview != nil {
            self.panel.alpha = reduceMotion ? 0.0 : 1.0
        } else {
            self.backdrop.alpha = 0.0
        }
        if !reduceMotion {
            self.setClosedPosition()
        }
        let animations = {
            self.backdrop.alpha = 1.0
            self.transitionView.transform = .identity
            self.panel.transform = .identity
            self.panelContent.transform = .identity
            self.panel.alpha = 1.0
            self.contentPreview?.layer.cornerRadius = 48.0
            self.contentShade.alpha = 1.0
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            if let self, !self.closing {
                UIAccessibility.post(notification: .screenChanged, argument: self.panel)
            }
        }
        if reduceMotion {
            UIView.animate(withDuration: 0.15, delay: 0.0, options: [.beginFromCurrentState], animations: animations, completion: completion)
        } else {
            // Fast start and a soft settle, like the reference recording. // MARK: NEXTGRAM
            UIView.animate(withDuration: self.contentPreview == nil ? 0.28 : 0.46, delay: 0.0, usingSpringWithDamping: 0.93, initialSpringVelocity: 0.0, options: [.beginFromCurrentState, .allowUserInteraction], animations: animations, completion: completion)
        }
    }

    public func close(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard !self.closing else { return }
        self.closing = true
        self.isUserInteractionEnabled = false
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        UIView.animate(withDuration: animated ? 0.34 : 0.0, delay: 0.0, options: [.beginFromCurrentState, .curveEaseOut], animations: {
            if self.contentPreview == nil || reduceMotion {
                self.backdrop.alpha = 0.0
            }
            if reduceMotion {
                self.panel.alpha = 0.0
            } else {
                self.setClosedPosition()
                self.contentPreview?.layer.cornerRadius = 0.0
                self.contentShade.alpha = 0.0
            }
        }, completion: { _ in
            self.removeFromSuperview()
            UIAccessibility.post(notification: .screenChanged, argument: nil)
            completion?()
        })
    }

    public override func accessibilityPerformEscape() -> Bool {
        self.close()
        return true
    }

    private func prepareContentPreview(in view: UIView) {
        guard self.style == .drawer, let snapshot = view.snapshotView(afterScreenUpdates: false) else { return }
        self.backgroundColor = self.panel.backgroundColor
        self.backdrop.backgroundColor = .clear
        let preview = UIButton(type: .custom)
        preview.frame = self.bounds
        preview.accessibilityLabel = self.backdrop.accessibilityLabel
        preview.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
        snapshot.isUserInteractionEnabled = false
        preview.clipsToBounds = true
        preview.layer.cornerCurve = .continuous
        preview.layer.cornerRadius = 0.0
        let rtl = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
        preview.layer.maskedCorners = rtl ? [.layerMaxXMinYCorner, .layerMaxXMaxYCorner] : [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        snapshot.frame = preview.bounds
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        preview.addSubview(snapshot)
        self.contentShade.frame = preview.bounds
        self.contentShade.isUserInteractionEnabled = false
        self.contentShade.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.contentShade.backgroundColor = UIColor.black.withAlphaComponent(0.24)
        self.contentShade.alpha = 0.0
        preview.addSubview(self.contentShade)
        self.backdrop.isHidden = true
        preview.translatesAutoresizingMaskIntoConstraints = false
        self.transitionView.addSubview(preview)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: self.panel.trailingAnchor),
            preview.topAnchor.constraint(equalTo: self.transitionView.topAnchor),
            preview.widthAnchor.constraint(equalTo: self.transitionView.widthAnchor),
            preview.heightAnchor.constraint(equalTo: self.transitionView.heightAnchor)
        ])
        self.contentPreview = preview
    }

    private var drawerOffset: CGFloat {
        self.panel.bounds.width * (self.effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1.0 : 1.0)
    }

    private func setClosedPosition() {
        if self.contentPreview != nil {
            self.transitionView.transform = CGAffineTransform(translationX: -self.drawerOffset, y: 0.0)
            self.panelContent.transform = CGAffineTransform(translationX: self.drawerOffset * 0.80, y: 0.0).scaledBy(x: 0.94, y: 0.94)
        } else {
            let rtl = self.effectiveUserInterfaceLayoutDirection == .rightToLeft
            let distance = self.panel.bounds.width + max(self.safeAreaInsets.left, self.safeAreaInsets.right) + 12.0
            self.panel.transform = CGAffineTransform(translationX: rtl ? distance : -distance, y: 0.0)
        }
    }
}
