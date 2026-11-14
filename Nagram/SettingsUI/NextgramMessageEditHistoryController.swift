import AccountContext
import Display
import Foundation
import ImageIO
import NagramMessageHistory
import NagramStrings
import TelegramCore
import TextFormat
import UIKit

/// A local, read-only version list. Opening media never replaces the live message.
public final class NextgramMessageEditHistoryController: UITableViewController {
    private let context: AccountContext
    private let versions: [NagramMessageEditVersion]
    private let copyProtected: Bool
    private let openMedia: (NagramMessageEditVersion) -> Void

    public init(context: AccountContext, versions: [NagramMessageEditVersion], copyProtected: Bool, openMedia: @escaping (NagramMessageEditVersion) -> Void) {
        self.context = context
        self.versions = versions
        self.copyProtected = copyProtected
        self.openMedia = openMedia
        super.init(style: .insetGrouped)
        self.title = ngI18n("Nagram.MessageEditHistory.Title", context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.close))
        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.estimatedRowHeight = 140.0
        self.tableView.allowsSelection = false
    }

    @objc private func close() {
        self.dismiss(animated: true)
    }

    public override func numberOfSections(in tableView: UITableView) -> Int {
        return self.versions.count
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let language = self.context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        let title = section == 0 ? ngI18n("Nagram.MessageEditHistory.Current", language) : "\(self.versions.count - section)."
        return title + " · " + formatter.string(from: Date(timeIntervalSince1970: TimeInterval(self.versions[section].timestamp)))
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let version = self.versions[indexPath.section]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let text = UITextView()
        text.isEditable = false
        text.isSelectable = !self.copyProtected
        text.isScrollEnabled = false
        text.backgroundColor = .clear
        text.textContainerInset = .zero
        text.textContainer.lineFragmentPadding = 0.0
        text.adjustsFontForContentSizeCategory = true
        let font = UIFont.preferredFont(forTextStyle: .body)
        let entities = (version.attributes.first(where: { $0 is TextEntitiesMessageAttribute }) as? TextEntitiesMessageAttribute)?.entities ?? []
        let richText = version.attributes.first(where: { $0 is RichTextMessageAttribute }) as? RichTextMessageAttribute
        text.attributedText = stringWithAppliedEntities(
            version.text.isEmpty ? (richText == nil ? "∅" : ngI18n("Nagram.MessageEditHistory.OpenRichText", self.context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode)) : version.text, entities: entities,
            baseColor: .label, linkColor: .link,
            baseFont: font, linkFont: font,
            boldFont: UIFont.systemFont(ofSize: font.pointSize, weight: .bold),
            italicFont: UIFont.italicSystemFont(ofSize: font.pointSize),
            boldItalicFont: Font.semiboldItalic(font.pointSize),
            fixedFont: UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular),
            blockQuoteFont: font, external: true, message: nil
        )
        let stack = UIStackView(arrangedSubviews: [text])
        stack.axis = .vertical
        stack.spacing = 12.0
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let imageData = version.imageData, let image = nextgramHistoryThumbnail(imageData) {
            let preview = UIImageView(image: image)
            preview.contentMode = .scaleAspectFit
            preview.clipsToBounds = true
            let previewHeight = preview.heightAnchor.constraint(equalToConstant: 220)
            previewHeight.priority = .defaultHigh
            previewHeight.isActive = true
            let spoiler = version.attributes.contains { $0 is MediaSpoilerMessageAttribute }
            if spoiler {
                preview.isHidden = true
                let reveal = UIButton(type: .system)
                reveal.setTitle("•••", for: .normal)
                reveal.accessibilityLabel = ngI18n("Nagram.MessageEditHistory.OpenImage", self.context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode)
                reveal.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
                reveal.addAction(UIAction { [weak tableView, weak preview, weak reveal] _ in
                    preview?.isHidden = false
                    reveal?.isHidden = true
                    tableView?.beginUpdates(); tableView?.endUpdates()
                }, for: .touchUpInside)
                stack.addArrangedSubview(reveal)
            }
            stack.addArrangedSubview(preview)
            let zoom = UIButton(type: .system)
            zoom.setTitle(ngI18n("Nagram.MessageEditHistory.OpenImage", self.context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode), for: .normal)
            zoom.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            zoom.addAction(UIAction { [weak self] _ in self?.present(NextgramHistoryImageController(image: image), animated: true) }, for: .touchUpInside)
            stack.addArrangedSubview(zoom)
        }
        if !version.media.isEmpty || richText != nil {
            let language = self.context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
            let button = UIButton(type: .system)
            button.setTitle(ngI18n(richText == nil ? "Nagram.MessageEditHistory.OpenMedia" : "Nagram.MessageEditHistory.OpenRichText", language), for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .body)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.contentHorizontalAlignment = .leading
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44.0).isActive = true
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                // Close the sheet before opening Telegram's standalone gallery.
                self.dismiss(animated: true) { self.openMedia(version) }
            }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        cell.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 16.0),
            stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -16.0)
        ])
        return cell
    }
}

private func nextgramHistoryThumbnail(_ data: Data) -> UIImage? {
    // A small compressed image can have enormous decoded dimensions. Never decode an unbounded original here.
    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048,
            kCGImageSourceShouldCacheImmediately: true
          ] as CFDictionary) else { return nil }
    return UIImage(cgImage: image)
}

private final class NextgramHistoryImageController: UIViewController, UIScrollViewDelegate {
    private let image: UIImage
    private let imageView = UIImageView()
    private let scrollView = UIScrollView()

    init(image: UIImage) { self.image = image; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .black
        self.scrollView.delegate = self
        self.scrollView.maximumZoomScale = 5
        self.imageView.image = self.image
        self.imageView.contentMode = .scaleAspectFit
        self.scrollView.addSubview(self.imageView)
        self.view.addSubview(self.scrollView)
        let done = UIButton(type: .system)
        done.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        done.tintColor = .white
        done.translatesAutoresizingMaskIntoConstraints = false
        done.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        self.view.addSubview(done)
        NSLayoutConstraint.activate([done.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -16), done.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 8), done.widthAnchor.constraint(equalToConstant: 44), done.heightAnchor.constraint(equalToConstant: 44)])
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.scrollView.frame = self.view.bounds
        if self.scrollView.zoomScale == 1 { self.imageView.frame = self.scrollView.bounds; self.scrollView.contentSize = self.scrollView.bounds.size }
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { return self.imageView }
}
