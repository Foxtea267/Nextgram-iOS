import NextgramLyrics
import UIKit

private final class NextgramLyricCell: UITableViewCell {
    private let lyricLabel = UILabel()
    private var timed = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        self.backgroundColor = .clear
        self.contentView.backgroundColor = .clear
        self.selectionStyle = .none
        self.isAccessibilityElement = true
        self.lyricLabel.translatesAutoresizingMaskIntoConstraints = false
        self.lyricLabel.numberOfLines = 0
        self.lyricLabel.lineBreakMode = .byWordWrapping
        self.lyricLabel.textColor = .white
        self.lyricLabel.isAccessibilityElement = false
        self.contentView.addSubview(self.lyricLabel)
        NSLayoutConstraint.activate([
            self.lyricLabel.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 24.0),
            self.lyricLabel.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -24.0),
            self.lyricLabel.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 14.0),
            self.lyricLabel.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -14.0)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(line: NextgramLyricLine, font: UIFont, active: Bool) {
        self.timed = line.time != nil
        let text = line.text.isEmpty ? (self.timed ? "•••" : " ") : line.text
        self.lyricLabel.text = text
        self.lyricLabel.font = font
        self.accessibilityLabel = text
        if let timestamp = line.time, timestamp.isFinite {
            let seconds = Int(max(0.0, min(359999.0, timestamp)))
            self.accessibilityValue = String(format: "%d:%02d", seconds / 60, seconds % 60)
        } else {
            self.accessibilityValue = nil
        }
        self.setActive(active, animated: false)
    }

    func setActive(_ active: Bool, animated: Bool) {
        let alpha: CGFloat = self.timed ? (active ? 1.0 : 0.4) : 0.85
        var traits: UIAccessibilityTraits = self.timed ? .button : .staticText
        if active {
            traits.insert(.selected)
        }
        self.accessibilityTraits = traits
        if animated && !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.2, delay: 0.0, options: [.beginFromCurrentState, .allowUserInteraction], animations: {
                self.lyricLabel.alpha = alpha
            })
        } else {
            self.lyricLabel.layer.removeAllAnimations()
            self.lyricLabel.alpha = alpha
        }
    }
}

final class NextgramLyricsView: UIView, UITableViewDataSource, UITableViewDelegate {
    var seek: ((Double) -> Void)?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let placeholderLabel = UILabel()
    private var lyrics: NextgramLyrics?
    private var lyricFont = NextgramLyricsView.font(size: 28.0)
    private var fontSize: CGFloat = 28.0
    private var position = 0.0
    private var activeIndex: Int?
    private var needsCentering = true
    private var manualScrollUntil = 0.0
    private var resumeAfterInteraction = false

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)

        self.backgroundColor = .clear
        self.tableView.backgroundColor = .clear
        self.tableView.separatorStyle = .none
        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.estimatedRowHeight = 96.0
        self.tableView.showsVerticalScrollIndicator = false
        self.tableView.contentInsetAdjustmentBehavior = .never
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.register(NextgramLyricCell.self, forCellReuseIdentifier: "Lyric")
        self.addSubview(self.tableView)

        self.placeholderLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        self.placeholderLabel.font = Self.font(size: 20.0)
        self.placeholderLabel.numberOfLines = 0
        self.placeholderLabel.textAlignment = .center
        self.addSubview(self.placeholderLabel)
        self.tableView.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func font(size: CGFloat) -> UIFont {
        let font = UIFont.systemFont(ofSize: size, weight: .bold)
        return font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? font
    }

    func update(lyrics: NextgramLyrics?, placeholder: String, fontSize: CGFloat) {
        let fontSize = fontSize.isFinite ? min(64.0, max(12.0, fontSize)) : 28.0
        let lyricsChanged = self.lyrics != lyrics
        let fontChanged = self.fontSize != fontSize
        self.placeholderLabel.text = placeholder
        let hasLines = lyrics?.lines.isEmpty == false
        self.tableView.isHidden = !hasLines
        self.placeholderLabel.isHidden = hasLines
        guard lyricsChanged || fontChanged else {
            return
        }

        self.lyrics = lyrics
        self.fontSize = fontSize
        self.lyricFont = Self.font(size: fontSize)
        self.tableView.estimatedRowHeight = fontSize * 2.0 + 28.0
        self.activeIndex = lyrics?.currentLineIndex(at: self.position)
        self.needsCentering = true
        if lyricsChanged {
            self.manualScrollUntil = 0.0
            self.resumeAfterInteraction = false
        }
        self.tableView.reloadData()
        self.setNeedsLayout()
        self.layoutIfNeeded()
        if self.activeIndex == nil && lyricsChanged {
            self.tableView.setContentOffset(CGPoint(x: 0.0, y: -self.tableView.contentInset.top), animated: false)
        }
        self.centerActiveLineIfNeeded(animated: false)
    }

    func updatePosition(_ timestamp: Double, force: Bool = false) {
        guard timestamp.isFinite else {
            return
        }
        self.position = max(0.0, timestamp)
        if force {
            self.manualScrollUntil = 0.0
            self.resumeAfterInteraction = self.tableView.isDragging || self.tableView.isDecelerating
            self.needsCentering = true
        }
        let index = self.lyrics?.currentLineIndex(at: self.position)
        if self.activeIndex != index {
            let previousIndex = self.activeIndex
            self.activeIndex = index
            self.needsCentering = true
            if let previousIndex,
               let cell = self.tableView.cellForRow(at: IndexPath(row: previousIndex, section: 0)) as? NextgramLyricCell {
                cell.setActive(false, animated: true)
            }
            if let index, let cell = self.tableView.cellForRow(at: IndexPath(row: index, section: 0)) as? NextgramLyricCell {
                cell.setActive(true, animated: true)
            }
        }
        self.centerActiveLineIfNeeded(animated: !force)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let sizeChanged = self.tableView.frame.size != self.bounds.size
        self.tableView.frame = self.bounds
        self.placeholderLabel.frame = self.bounds.insetBy(dx: 24.0, dy: 24.0)
        let inset = self.lyrics?.isSynced == true
            ? max(24.0, self.bounds.height * 0.5 - self.fontSize * 0.75 - 14.0) : 24.0
        let contentInset = UIEdgeInsets(top: inset, left: 0.0, bottom: inset, right: 0.0)
        if self.tableView.contentInset != contentInset {
            self.tableView.contentInset = contentInset
        }
        if sizeChanged {
            self.needsCentering = true
        }
        self.centerActiveLineIfNeeded(animated: false)
    }

    private func centerActiveLineIfNeeded(animated: Bool) {
        let targetIndex = self.activeIndex ?? (self.lyrics?.isSynced == true ? 0 : nil)
        guard self.needsCentering, !self.tableView.isHidden, self.bounds.height > 0.0,
              !self.tableView.isDragging, !self.tableView.isDecelerating,
              ProcessInfo.processInfo.systemUptime >= self.manualScrollUntil,
              let targetIndex, self.lyrics?.lines.indices.contains(targetIndex) == true else {
            return
        }
        self.needsCentering = false
        self.tableView.scrollToRow(at: IndexPath(row: targetIndex, section: 0), at: .middle,
            animated: animated && !UIAccessibility.isReduceMotionEnabled)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.lyrics?.lines.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Lyric", for: indexPath)
        if let cell = cell as? NextgramLyricCell, let lyrics = self.lyrics, lyrics.lines.indices.contains(indexPath.row) {
            cell.configure(line: lyrics.lines[indexPath.row], font: self.lyricFont, active: self.activeIndex == indexPath.row)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard let lyrics = self.lyrics, lyrics.isSynced, lyrics.lines.indices.contains(indexPath.row),
              let timestamp = lyrics.lines[indexPath.row].time, timestamp.isFinite else {
            return
        }
        self.updatePosition(timestamp, force: true)
        self.seek?(timestamp)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        self.resumeAfterInteraction = false
        self.needsCentering = true
        self.manualScrollUntil = ProcessInfo.processInfo.systemUptime + 5.0
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.isDragging || scrollView.isDecelerating {
            self.manualScrollUntil = ProcessInfo.processInfo.systemUptime + 5.0
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            self.finishManualScrolling()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        self.finishManualScrolling()
    }

    private func finishManualScrolling() {
        self.manualScrollUntil = self.resumeAfterInteraction ? 0.0 : ProcessInfo.processInfo.systemUptime + 5.0
        self.resumeAfterInteraction = false
    }
}
