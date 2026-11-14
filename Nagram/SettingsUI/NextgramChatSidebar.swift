import TelegramPresentationData
import UIKit

public final class NextgramChatSidebar: UIView {
    private let backdrop = UIButton(type: .custom)
    private let panel = UIView()
    private var closing = false

    public init(theme: PresentationTheme, title: String, closeTitle: String, actions: [(title: String, icon: String, action: () -> Void)]) {
        super.init(frame: .zero)
        self.accessibilityViewIsModal = true
        self.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        self.backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.36)
        self.backdrop.accessibilityLabel = closeTitle
        self.backdrop.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
        self.addSubview(self.backdrop)

        self.panel.backgroundColor = theme.list.modalBlocksBackgroundColor
        self.panel.layer.cornerRadius = 24.0
        self.panel.layer.cornerCurve = .continuous
        self.panel.clipsToBounds = true
        self.panel.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.panel)

        let heading = UILabel()
        heading.text = title
        heading.font = UIFont.systemFont(ofSize: 22.0, weight: .bold)
        heading.textColor = theme.list.itemPrimaryTextColor
        heading.accessibilityTraits = .header

        let stack = UIStackView(arrangedSubviews: [heading])
        stack.axis = .vertical
        stack.spacing = 4.0
        stack.setCustomSpacing(16.0, after: heading)
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.panel.addSubview(stack)

        for entry in actions {
            var configuration = UIButton.Configuration.plain()
            configuration.title = entry.title
            configuration.image = UIImage(systemName: entry.icon)
            configuration.imagePadding = 14.0
            configuration.baseForegroundColor = theme.list.itemPrimaryTextColor
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 12.0, leading: 0.0, bottom: 12.0, trailing: 0.0)
            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                self?.close(completion: entry.action)
            })
            button.contentHorizontalAlignment = .leading
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48.0).isActive = true
            stack.addArrangedSubview(button)
        }

        let preferredWidth = self.panel.widthAnchor.constraint(equalToConstant: 300.0)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            self.panel.leadingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.leadingAnchor, constant: 10.0),
            self.panel.trailingAnchor.constraint(lessThanOrEqualTo: self.safeAreaLayoutGuide.trailingAnchor, constant: -36.0),
            self.panel.topAnchor.constraint(equalTo: self.safeAreaLayoutGuide.topAnchor, constant: 8.0),
            self.panel.bottomAnchor.constraint(equalTo: self.safeAreaLayoutGuide.bottomAnchor, constant: -8.0),
            preferredWidth,
            stack.leadingAnchor.constraint(equalTo: self.panel.leadingAnchor, constant: 22.0),
            stack.trailingAnchor.constraint(equalTo: self.panel.trailingAnchor, constant: -22.0),
            stack.topAnchor.constraint(equalTo: self.panel.topAnchor, constant: 20.0)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        self.backdrop.frame = self.bounds
    }

    public func open(in view: UIView) {
        self.frame = view.bounds
        view.addSubview(self)
        self.layoutIfNeeded()
        self.backdrop.alpha = 0.0
        if !UIAccessibility.isReduceMotionEnabled {
            self.panel.transform = self.offscreenTransform
        }
        UIView.animate(withDuration: 0.24, animations: {
            self.backdrop.alpha = 1.0
            self.panel.transform = .identity
        }, completion: { [weak self] _ in
            if let self, !self.closing {
                UIAccessibility.post(notification: .screenChanged, argument: self.panel)
            }
        })
    }

    public func close(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard !self.closing else { return }
        self.closing = true
        self.isUserInteractionEnabled = false
        UIView.animate(withDuration: animated ? 0.20 : 0.0, animations: {
            self.backdrop.alpha = 0.0
            if !UIAccessibility.isReduceMotionEnabled {
                self.panel.transform = self.offscreenTransform
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

    private var offscreenTransform: CGAffineTransform {
        let rtl = self.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let distance = self.panel.bounds.width + max(self.safeAreaInsets.left, self.safeAreaInsets.right) + 12.0
        return CGAffineTransform(translationX: rtl ? distance : -distance, y: 0.0)
    }
}
