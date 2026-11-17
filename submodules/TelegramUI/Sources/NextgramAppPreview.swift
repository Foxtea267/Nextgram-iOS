#if DEBUG && targetEnvironment(simulator)
import NagramSettings
import UIKit

// MARK: NEXTGRAM — An interactive Canvas entry for the real iPhone app, including Telegram's pages.
@available(iOS 17.0, *)
#Preview("Nextgram · iPhone App") {
    NextgramAppPreviewController()
}

private final class NextgramAppPreviewController: UIViewController {
    private var content: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard self.content == nil else {
            return
        }
        guard NagramDemoMode.isCanvasPreview,
              let appDelegate = UIApplication.shared.delegate as? AppDelegate,
              let root = appDelegate.takeCanvasRootController() else {
            self.showUnavailable()
            return
        }
        if let previousHost = root.parent as? NextgramAppPreviewController {
            previousHost.detachContent()
        }
        self.addChild(root)
        root.view.frame = self.view.bounds
        root.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(root.view)
        root.didMove(toParent: self)
        self.content = root
        appDelegate.mainWindow?.updateDeviceMetrics()
    }

    private func detachContent() {
        guard let content = self.content else {
            return
        }
        content.willMove(toParent: nil)
        content.view.removeFromSuperview()
        content.removeFromParent()
        self.content = nil
    }

    private func showUnavailable() {
        let label = UILabel()
        label.text = "Select the Telegram scheme and an iPhone simulator, then restart the preview."
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
            label.widthAnchor.constraint(equalTo: self.view.widthAnchor, multiplier: 0.8),
        ])
    }
}
#endif
