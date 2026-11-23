import UIKit

final class NextgramLyricsDiagnosticsController: UIViewController {
    private let reportView = UITextView()
    var lyricsSections: [Int: String] = [:]
    private var expandedLyrics = Set<Int>()
    private let viewLyricsTitle: String
    private let hideLyricsTitle: String
    var report = "" {
        didSet { self.updateReport() }
    }

    init(title: String, done: String, refresh: String, viewLyrics: String, hideLyrics: String, onRefresh: @escaping () -> Void) {
        self.viewLyricsTitle = viewLyrics
        self.hideLyricsTitle = hideLyrics
        super.init(nibName: nil, bundle: nil)
        self.title = title
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: done, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: refresh, primaryAction: UIAction { _ in onRefresh() })
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground
        self.reportView.backgroundColor = .clear
        self.reportView.adjustsFontForContentSizeCategory = true
        self.reportView.isEditable = false
        self.reportView.isSelectable = true
        self.reportView.delegate = self
        self.reportView.linkTextAttributes = [
            .foregroundColor: UIColor.link,
            .underlineStyle: 0
        ]
        self.reportView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        self.reportView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.reportView)
        NSLayoutConstraint.activate([
            self.reportView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.reportView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.reportView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.reportView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor)
        ])
        self.updateReport()
    }

    private func updateReport() {
        guard self.isViewLoaded else { return }
        let offset = self.reportView.contentOffset
        let result = NSMutableAttributedString()
        let lines = self.report.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("__NEXTGRAM_LYRICS__:") {
                let idText = String(line.dropFirst("__NEXTGRAM_LYRICS__:".count))
                if let id = Int(idText), let lyrics = self.lyricsSections[id] {
                    let expanded = self.expandedLyrics.contains(id)
                    let title = expanded ? "△ \(self.hideLyricsTitle)" : "▽ \(self.viewLyricsTitle)"
                    let link = NSMutableAttributedString(string: title, attributes: [
                        .link: URL(string: "nextgram-lyrics://section/\(id)")!
                    ])
                    result.append(link)
                    if expanded {
                        result.append(NSAttributedString(string: "\n" + lyrics))
                    }
                }
            } else {
                result.append(NSAttributedString(string: line))
            }
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        result.addAttributes([
            .font: UIFont.preferredFont(forTextStyle: .body, compatibleWith: self.traitCollection),
            .foregroundColor: UIColor.label
        ], range: NSRange(location: 0, length: result.length))
        self.reportView.attributedText = result
        self.reportView.setContentOffset(offset, animated: false)
    }
}

extension NextgramLyricsDiagnosticsController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange,
                  interaction: UITextItemInteraction) -> Bool {
        guard URL.scheme == "nextgram-lyrics", let id = Int(URL.lastPathComponent) else { return true }
        guard interaction == .invokeDefaultAction else { return false }
        if self.expandedLyrics.contains(id) {
            self.expandedLyrics.remove(id)
        } else if self.lyricsSections[id] != nil {
            self.expandedLyrics.insert(id)
        }
        self.updateReport()
        return false
    }
}
