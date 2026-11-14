import AccountContext
import Foundation
import NagramSettings
import NagramStrings
import NextgramTypography
import UIKit
import UniformTypeIdentifiers

public final class NextgramFontSettingsController: UITableViewController, UIDocumentPickerDelegate {
    private let context: AccountContext
    private var imported: [NextgramImportedFont] { NextgramTypography.shared.importedFonts }
    private var importing = false
    private var download: NextgramFontDownloadRequest?
    private var backgroundObserver: NSObjectProtocol?

    public init(context: AccountContext) {
        self.context = context
        super.init(style: .insetGrouped)
        self.title = self.string("Title")
        self.backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.cancelDownload() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { self.download?.cancel(); if let observer = self.backgroundObserver { NotificationCenter.default.removeObserver(observer) } }

    private func string(_ key: String) -> String {
        ngI18n("Nagram.Fonts." + key, self.context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.close))
        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.estimatedRowHeight = 56
    }
    @objc private func close() { self.cancelDownload(); self.dismiss(animated: true) }
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if self.isBeingDismissed || self.navigationController?.isBeingDismissed == true { self.cancelDownload() }
    }
    private func cancelDownload() {
        if self.download != nil { self.download?.cancel(); self.download = nil; self.importing = false; if self.isViewLoaded { self.tableView.reloadData() } }
    }
    public override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 4 : section == 1 ? 3 : self.imported.count }
    public override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? self.string("Footer") : section == 1 ? self.string("ImportHint") : nil
    }
    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 2 ? self.string("Imported") : nil
    }
    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.numberOfLines = 0
        if indexPath.section == 0 {
            let fields = ["InterfaceLatin", "InterfaceCJK", "MessageLatin", "MessageCJK"]
            let value = self.selection(indexPath.row)
            cell.textLabel?.text = self.string(fields[indexPath.row])
            cell.detailTextLabel?.text = self.name(value)
            cell.accessoryType = .disclosureIndicator
        } else if indexPath.section == 1 {
            cell.textLabel?.text = indexPath.row == 0 ? (self.download != nil ? self.context.sharedContext.currentPresentationData.with { $0 }.strings.Common_Cancel : self.string(self.importing ? "Importing" : "Import")) : NextgramFontDownload.allCases[indexPath.row - 1].name
            if indexPath.row > 0 { cell.detailTextLabel?.text = NextgramFontDownload.allCases[indexPath.row - 1].sizeDescription }
            cell.textLabel?.textColor = self.view.tintColor
        } else {
            let font = self.imported[indexPath.row]
            cell.textLabel?.text = font.name + "\nAa 你好 こんにちは 한글 0123"
            cell.textLabel?.font = NextgramTypography.shared.preview(id: font.id, size: 17)
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }
    private func selection(_ row: Int) -> String {
        let value = NextgramFontConfiguration.current
        return [value.interfaceLatin, value.interfaceCJK, value.messageLatin, value.messageCJK][row]
    }
    private func setSelection(_ id: String, row: Int) {
        var value = NextgramFontConfiguration.current
        switch row {
        case 0: value.interfaceLatin = id
        case 1: value.interfaceCJK = id
        case 2: value.messageLatin = id
        default: value.messageCJK = id
        }
        NextgramFontConfiguration.current = value
        self.tableView.reloadData()
    }
    private func name(_ id: String) -> String {
        ["system", "rounded", "serif", "monospace"].contains(id) ? self.string(id) : self.imported.first(where: { $0.id == id })?.name ?? self.string("system")
    }
    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let strings = self.context.sharedContext.currentPresentationData.with { $0 }.strings
        if indexPath.section == 0 {
            let controller = NextgramFontSelectionController(title: self.string("Select"),
                options: ["system", "rounded", "serif", "monospace"].map { ($0, self.name($0)) } + self.imported.map { ($0.id, $0.name) },
                selected: self.selection(indexPath.row)) { [weak self] id in self?.setSelection(id, row: indexPath.row) }
            self.navigationController?.pushViewController(controller, animated: true)
        } else if indexPath.section == 1 {
            if indexPath.row == 0, self.download != nil { self.cancelDownload(); return }
            guard !self.importing else { return }
            if indexPath.row > 0 { self.offerDownload(NextgramFontDownload.allCases[indexPath.row - 1]); return }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType(filenameExtension: "ttf"), UTType(filenameExtension: "otf"), UTType(filenameExtension: "ttc")].compactMap { $0 }, asCopy: true)
            picker.delegate = self
            self.present(picker, animated: true)
        } else {
            let font = self.imported[indexPath.row]
            let sheet = UIAlertController(title: font.name, message: nil, preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: self.string("Rename"), style: .default) { [weak self] _ in self?.rename(font) })
            sheet.addAction(UIAlertAction(title: strings.Common_Delete, style: .destructive) { [weak self] _ in
                do { try NextgramTypography.shared.remove(id: font.id); self?.tableView.reloadData() }
                catch { self?.showError() }
            })
            sheet.addAction(UIAlertAction(title: strings.Common_Cancel, style: .cancel))
            sheet.popoverPresentationController?.sourceView = tableView
            sheet.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath)
            self.present(sheet, animated: true)
        }
    }
    private func offerDownload(_ font: NextgramFontDownload) {
        let alert = UIAlertController(title: font.name, message: self.string("DownloadNotice") + "\n\n" + font.sizeDescription + "\n" + font.sourceURL.absoluteString, preferredStyle: .alert)
        let strings = self.context.sharedContext.currentPresentationData.with { $0 }.strings
        alert.addAction(UIAlertAction(title: strings.Common_Cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: "SIL Open Font License 1.1", style: .default) { [weak self] _ in
            self?.context.sharedContext.applicationBindings.openUrl(font.licenseURL.absoluteString)
        })
        alert.addAction(UIAlertAction(title: self.string("Download"), style: .default) { [weak self] _ in
            guard let self else { return }
            self.importing = true
            self.tableView.reloadData()
            self.download = font.download { [weak self] result in
                guard let self else { return }
                self.download = nil
                self.importing = false
                self.tableView.reloadData()
                if case .failure = result { self.showError() }
            }
        })
        self.present(alert, animated: true)
    }
    private func rename(_ font: NextgramImportedFont) {
        let alert = UIAlertController(title: self.string("Rename"), message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = font.name; $0.textAlignment = .right }
        let strings = self.context.sharedContext.currentPresentationData.with { $0 }.strings
        alert.addAction(UIAlertAction(title: strings.Common_Cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: strings.Common_OK, style: .default) { [weak self] _ in
            do { try NextgramTypography.shared.rename(id: font.id, name: alert.textFields?.first?.text ?? ""); self?.tableView.reloadData() }
            catch { self?.showError() }
        })
        self.present(alert, animated: true)
    }
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, !self.importing else { return }
        self.importing = true
        self.tableView.reloadData()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try NextgramTypography.shared.importFile(url) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.importing = false
                self.tableView.reloadData()
                if case .failure = result { self.showError() }
            }
        }
    }
    private func showError() {
        let alert = UIAlertController(title: self.title, message: self.string("Error"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: self.context.sharedContext.currentPresentationData.with { $0 }.strings.Common_OK, style: .default))
        self.present(alert, animated: true)
    }
}

private final class NextgramFontSelectionController: UITableViewController {
    private let options: [(String, String)]
    private var selected: String
    private let select: (String) -> Void
    init(title: String, options: [(String, String)], selected: String, select: @escaping (String) -> Void) {
        self.options = options; self.selected = selected; self.select = select
        super.init(style: .insetGrouped); self.title = title
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { self.options.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let (id, name) = self.options[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = name
        cell.detailTextLabel?.text = "Aa 你好 こんにちは 한글 0123"
        cell.detailTextLabel?.font = NextgramTypography.shared.preview(id: id, size: 17)
        cell.accessoryType = id == self.selected ? .checkmark : .none
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.selected = self.options[indexPath.row].0
        self.select(self.selected)
        self.navigationController?.popViewController(animated: true)
    }
}
