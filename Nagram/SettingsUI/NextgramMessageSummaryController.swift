import AccountContext
import Foundation
import NagramSettings
import NagramStrings
import NagramTranslate
import SwiftSignalKit
import TelegramCore
import UIKit

private func summaryString(_ key: String, context: AccountContext) -> String {
    return ngI18n("Nagram.Summary." + key, context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode)
}

/// Separate configuration and device-only credential; never reuses the translation API key.
public final class NextgramSummarySettingsController: UITableViewController {
    private let context: AccountContext
    private var configuration = NextgramSummarySettings.configuration
    private let request = MetaDisposable()
    private var testing = false

    public init(context: AccountContext) {
        self.context = context
        super.init(style: .insetGrouped)
        self.title = summaryString("Settings", context: context)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { self.request.dispose() }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.close))
    }

    @objc private func close() {
        if let navigationController = self.navigationController, navigationController.viewControllers.first !== self {
            navigationController.popViewController(animated: true)
        } else { self.dismiss(animated: true) }
    }
    public override func numberOfSections(in tableView: UITableView) -> Int { return 2 }
    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return section == 0 ? 8 : 1 }
    public override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return section == 0 ? summaryString("Privacy", context: self.context) : nil
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        if indexPath.section == 1 {
            cell.textLabel?.text = summaryString(self.testing ? "Cancel" : "Test", context: self.context)
            cell.textLabel?.textColor = self.view.tintColor
            return cell
        }
        let keys = ["Enabled", "Format", "BaseURL", "Endpoint", "Model", "APIKey", "Prompt", "Temperature"]
        cell.textLabel?.text = summaryString(keys[indexPath.row], context: self.context)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = .disclosureIndicator
        switch indexPath.row {
        case 0:
            let toggle = UISwitch()
            toggle.isOn = self.configuration.enabled
            toggle.addTarget(self, action: #selector(self.toggleEnabled(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        case 1: cell.detailTextLabel?.text = self.configuration.format == "anthropic" ? "Anthropic" : "OpenAI"
        case 2: cell.detailTextLabel?.text = self.configuration.baseURL
        case 3: cell.detailTextLabel?.text = self.configuration.endpoint
        case 4: cell.detailTextLabel?.text = self.configuration.model
        case 5: cell.detailTextLabel?.text = ((try? NextgramSummarySettings.apiKey()) ?? "").isEmpty ? "—" : "••••••••"
        case 6: cell.detailTextLabel?.text = String(self.configuration.prompt.prefix(32))
        case 7: cell.detailTextLabel?.text = String(format: "%.1f", self.configuration.temperature)
        default: break
        }
        return cell
    }

    @objc private func toggleEnabled(_ toggle: UISwitch) {
        self.configuration.enabled = toggle.isOn
        NextgramSummarySettings.configuration = self.configuration
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 1 { self.test(); return }
        let row = indexPath.row
        if row == 0 { return }
        if row == 1 {
            self.configuration.format = self.configuration.format == "openai" ? "anthropic" : "openai"
            NextgramSummarySettings.configuration = self.configuration
            tableView.reloadData()
            return
        }
        let keys = [2: "BaseURL", 3: "Endpoint", 4: "Model", 5: "APIKey", 6: "Prompt", 7: "Temperature"]
        guard let key = keys[row] else { return }
        let alert = UIAlertController(title: summaryString(key, context: self.context), message: row == 6 ? "@toLang" : nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.textAlignment = .right
            switch row {
            case 2: field.text = self.configuration.baseURL; field.keyboardType = .URL
            case 3: field.text = self.configuration.endpoint
            case 4: field.text = self.configuration.model
            case 5: field.isSecureTextEntry = true; field.text = (try? NextgramSummarySettings.apiKey()) ?? ""
            case 6: field.text = self.configuration.prompt
            case 7: field.text = String(self.configuration.temperature); field.keyboardType = .decimalPad
            default: break
            }
        }
        let strings = self.context.sharedContext.currentPresentationData.with { $0 }.strings
        alert.addAction(UIAlertAction(title: strings.Common_Cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: strings.Common_OK, style: .default) { [weak self] _ in
            guard let self else { return }
            let text = alert.textFields?.first?.text ?? ""
            switch row {
            case 2: self.configuration.baseURL = text.trimmingCharacters(in: .whitespacesAndNewlines)
            case 3: self.configuration.endpoint = text
            case 4: self.configuration.model = text
            case 5:
                do { try NextgramSummarySettings.setAPIKey(text) }
                catch { self.showError(summaryString("CredentialError", context: self.context)); return }
            case 6: self.configuration.prompt = String(text.prefix(4096))
            case 7: self.configuration.temperature = min(1, max(0, Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0.2))
            default: break
            }
            NextgramSummarySettings.configuration = self.configuration
            tableView.reloadData()
        })
        self.present(alert, animated: true)
    }

    private func test() {
        if self.testing { self.request.set(nil); self.testing = false; self.tableView.reloadData(); return }
        do {
            let key = try NextgramSummarySettings.apiKey()
            self.testing = true
            self.tableView.reloadData()
            self.request.set((nextgramSummarizeMessages(text: "PONG", language: "en", configuration: self.configuration, apiKey: key, test: true) |> deliverOnMainQueue).start(next: { [weak self] _ in
                guard let self else { return }
                self.testing = false
                self.tableView.reloadData()
                self.showError(summaryString("TestOK", context: self.context))
            }, error: { [weak self] error in
                self?.testing = false
                self?.tableView.reloadData()
                self?.showError(error.message)
            }))
        } catch { self.showError(summaryString("CredentialError", context: self.context)) }
    }

    private func showError(_ text: String) {
        let alert = UIAlertController(title: self.title, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: self.context.sharedContext.currentPresentationData.with { $0 }.strings.Common_OK, style: .default))
        self.present(alert, animated: true)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.request.set(nil)
        self.testing = false
    }
}

/// Read-only preview first; a second, explicit confirmation is required before any third-party upload.
public final class NextgramMessageSummaryController: UITableViewController {
    private let context: AccountContext
    private let peerId: EnginePeer.Id
    private let threadId: Int64?
    private let selected: [EngineMessage]
    private var text = ""
    private var count = 0
    private var output = ""
    private var errorText = ""
    private var busy = false
    private var from = Date().addingTimeInterval(-3600)
    private var to = Date()
    private let request = MetaDisposable()
    private var generation = UUID()
    private var backgroundObserver: NSObjectProtocol?

    public init(context: AccountContext, peerId: EnginePeer.Id, threadId: Int64?, selected: [EngineMessage]) {
        self.context = context
        self.peerId = peerId
        self.threadId = threadId
        self.selected = selected
        super.init(style: .insetGrouped)
        self.title = summaryString("Title", context: context)
        self.backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.cancel() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { self.request.dispose(); if let observer = self.backgroundObserver { NotificationCenter.default.removeObserver(observer) } }
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.estimatedRowHeight = 50
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.close))
        if !self.selected.isEmpty { self.prepare(self.selected, limit: 100) }
    }

    @objc private func close() { self.cancel(); self.dismiss(animated: true) }
    private func cancel() { self.generation = UUID(); self.request.set(nil); self.busy = false; if self.isViewLoaded { self.tableView.reloadData() } }
    public override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); self.cancel() }
    public override func numberOfSections(in tableView: UITableView) -> Int { return 4 }
    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section { case 0: return 8; case 1: return self.text.isEmpty ? 0 : 2; case 2: return self.busy || !self.errorText.isEmpty ? 1 : 0; default: return self.output.isEmpty ? 0 : 2 }
    }
    public override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { return section == 1 ? summaryString("Privacy", context: self.context) : nil }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        switch indexPath.section {
        case 0:
            let keys = ["Settings", "Selected", "LastHour", "Today", "LastDay", "From", "To", "LoadRange"]
            cell.textLabel?.text = summaryString(keys[indexPath.row], context: self.context)
            if indexPath.row == 5 || indexPath.row == 6 {
                let picker = UIDatePicker()
                picker.datePickerMode = .dateAndTime
                picker.preferredDatePickerStyle = .compact
                picker.maximumDate = Date()
                picker.date = indexPath.row == 5 ? self.from : self.to
                picker.tag = indexPath.row
                picker.addTarget(self, action: #selector(self.dateChanged(_:)), for: .valueChanged)
                picker.isEnabled = !self.busy
                cell.accessoryView = picker
            }
            cell.selectionStyle = self.busy ? .none : .default
            if indexPath.row == 1 { cell.detailTextLabel?.text = String(self.selected.count) }
        case 1:
            if indexPath.row == 0 {
                cell.textLabel?.text = "\(self.count) · \(self.text.utf8.count) B\n\n" + self.text
                cell.textLabel?.font = .preferredFont(forTextStyle: .footnote)
                cell.selectionStyle = .none
            } else { cell.textLabel?.text = summaryString("Start", context: self.context); cell.textLabel?.textColor = self.view.tintColor }
        case 2:
            cell.textLabel?.text = self.busy ? summaryString("Cancel", context: self.context) : self.errorText
        default:
            cell.textLabel?.text = indexPath.row == 0 ? self.output : summaryString("Copy", context: self.context)
        }
        return cell
    }

    @objc private func dateChanged(_ picker: UIDatePicker) { if picker.tag == 5 { self.from = picker.date } else { self.to = picker.date } }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if self.busy { if indexPath.section == 2 { self.cancel() }; return }
        switch indexPath.section {
        case 0:
            let now = Date()
            switch indexPath.row {
            case 0: self.navigationController?.pushViewController(NextgramSummarySettingsController(context: self.context), animated: true)
            case 1: self.prepare(self.selected, limit: 100)
            case 2: self.load(from: now.addingTimeInterval(-3600), to: now)
            case 3: self.load(from: Calendar.current.startOfDay(for: now), to: now)
            case 4: self.load(from: now.addingTimeInterval(-86400), to: now)
            case 7: self.load(from: self.from, to: self.to)
            default: break
            }
        case 1: if indexPath.row == 1 { self.confirmUpload() }
        case 3: if indexPath.row == 1 { UIPasteboard.general.string = self.output }
        default: break
        }
    }

    private func content(_ message: EngineMessage) -> String? {
        guard message.id.peerId.namespace != Namespaces.Peer.SecretChat, !message.containsSecretMedia, !message._asMessage().isCopyProtected() else { return nil }
        let value: String
        if let rich = message.attributes.first(where: { $0 is RichTextMessageAttribute }) as? RichTextMessageAttribute {
            value = nextgramSummaryText(rich.fullInstantPage ?? rich.instantPage)
        } else { value = message.text }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    private func prepare(_ messages: [EngineMessage], limit: Int) {
        self.text = ""; self.count = 0; self.output = ""; self.errorText = ""
        guard messages.count <= limit else { self.errorText = summaryString("TooLarge", context: self.context); self.tableView.reloadData(); return }
        let values = messages.sorted { $0.index < $1.index }.compactMap(self.content)
        let text = values.joined(separator: "\n\n---\n\n")
        if text.utf8.count > 64000 { self.errorText = summaryString("TooLarge", context: self.context) }
        else if values.isEmpty { self.errorText = summaryString("Empty", context: self.context) }
        else { self.text = text; self.count = values.count }
        self.tableView.reloadData()
    }

    private func load(from: Date, to: Date) {
        self.cancel(); self.text = ""; self.output = ""; self.errorText = ""
        guard self.peerId.namespace != Namespaces.Peer.SecretChat, from < to, from.timeIntervalSince1970 > 0, to.timeIntervalSince1970 < Double(Int32.max) else { self.errorText = summaryString("InvalidRange", context: self.context); self.tableView.reloadData(); return }
        let lower = Int32(from.timeIntervalSince1970), upper = Int32(to.timeIntervalSince1970)
        let location = SearchMessagesLocation.peer(peerId: self.peerId, fromId: nil, tags: nil, reactions: nil, threadId: self.threadId, minDate: lower, maxDate: upper)
        self.busy = true
        let token = self.generation
        var pages = 0
        func page(_ cursor: SearchMessagesState?) {
            guard self.generation == token else { return }
            self.request.set((self.context.engine.messages.searchMessages(location: location, query: "", state: cursor, limit: 100) |> take(1) |> map(Optional.init) |> timeout(25, queue: .mainQueue(), alternate: .single(nil)) |> deliverOnMainQueue).start(next: { [weak self] result in
                guard let self, self.generation == token else { return }
                guard let (result, next) = result, !result.nextgramRequestFailed, result.completed || next != cursor else { self.busy = false; self.errorText = summaryString("LoadFailed", context: self.context); self.tableView.reloadData(); return }
                pages += 1
                let messages = result.messages.filter { $0.timestamp >= lower && $0.timestamp <= upper }.map(EngineMessage.init)
                let values = messages.compactMap(self.content)
                let size = values.reduce(0) { $0 + $1.utf8.count + 10 }
                guard size <= 64000, messages.count <= 5000, pages <= 100 else { self.busy = false; self.errorText = summaryString("TooLarge", context: self.context); self.tableView.reloadData(); return }
                if result.completed { self.busy = false; self.prepare(messages, limit: 5000) }
                else { DispatchQueue.main.async { page(next) } }
            }))
        }
        self.tableView.reloadData()
        page(nil)
    }

    private func confirmUpload() {
        let configuration = NextgramSummarySettings.configuration
        guard configuration.enabled, let url = NextgramSummarySettings.requestURL(configuration), !configuration.model.isEmpty else {
            self.navigationController?.pushViewController(NextgramSummarySettingsController(context: self.context), animated: true)
            return
        }
        let alert = UIAlertController(title: summaryString("Start", context: self.context), message: summaryString("Privacy", context: self.context) + "\n\n\(url.host ?? "") · \(configuration.model)\n\(self.count) · \(self.text.utf8.count) B", preferredStyle: .alert)
        let strings = self.context.sharedContext.currentPresentationData.with { $0 }.strings
        alert.addAction(UIAlertAction(title: strings.Common_Cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: summaryString("Upload", context: self.context), style: .default) { [weak self] _ in
            guard let self else { return }
            do {
                let key = try NextgramSummarySettings.apiKey()
                self.busy = true; self.errorText = ""; self.tableView.reloadData()
                let token = self.generation
                self.request.set((nextgramSummarizeMessages(text: self.text, language: strings.baseLanguageCode, configuration: configuration, apiKey: key) |> deliverOnMainQueue).start(next: { [weak self] result in
                    guard let self, self.generation == token else { return }
                    self.busy = false; self.output = result; self.tableView.reloadData()
                }, error: { [weak self] error in
                    guard let self, self.generation == token else { return }
                    self.busy = false; self.errorText = error.message; self.tableView.reloadData()
                }))
            } catch { self.errorText = summaryString("CredentialError", context: self.context); self.tableView.reloadData() }
        })
        self.present(alert, animated: true)
    }
}
