import TelegramCore
import UIKit

/// A bounded, searchable list rather than one UIAlertAction for every common group.
final class NextgramCommonGroupPicker: UITableViewController, UISearchResultsUpdating {
    private let groups: [EnginePeer]
    private var filtered: [EnginePeer]
    private let selectedId: EnginePeer.Id?
    private let allTitle: String
    private let choose: (EnginePeer.Id?) -> Void
    private let search = UISearchController(searchResultsController: nil)

    init(groups: [EnginePeer], selectedId: EnginePeer.Id?, title: String, allTitle: String, cancelTitle: String,
         choose: @escaping (EnginePeer.Id?) -> Void) {
        let sorted = groups.sorted { $0.compactDisplayTitle.localizedStandardCompare($1.compactDisplayTitle) == .orderedAscending }
        self.groups = sorted
        self.filtered = sorted
        self.selectedId = selectedId
        self.allTitle = allTitle
        self.choose = choose
        super.init(style: .insetGrouped)
        self.title = title
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: cancelTitle, style: .plain, target: self, action: #selector(self.cancel))
        self.search.searchResultsUpdater = self
        self.search.obscuresBackgroundDuringPresentation = false
        self.search.searchBar.placeholder = title
        self.navigationItem.searchController = self.search
        self.navigationItem.hidesSearchBarWhenScrolling = false
        self.definesPresentationContext = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "group")
        self.tableView.keyboardDismissMode = .onDrag
    }

    func updateSearchResults(for searchController: UISearchController) {
        let query = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.filtered = query.isEmpty ? self.groups : self.groups.filter {
            $0.compactDisplayTitle.localizedStandardContains(query) || String($0.id.toInt64()).contains(query)
        }
        self.tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? 1 : self.filtered.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "group", for: indexPath)
        let peer = indexPath.section == 0 ? nil : self.filtered[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = peer?.compactDisplayTitle ?? self.allTitle
        content.textProperties.numberOfLines = 2
        content.image = UIImage(systemName: indexPath.section == 0 ? "square.stack.3d.up" : "person.2")
        cell.contentConfiguration = content
        cell.accessoryType = peer?.id == self.selectedId ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let id = indexPath.section == 0 ? nil : self.filtered[indexPath.row].id
        self.view.endEditing(true)
        self.search.isActive = false
        self.dismiss(animated: true) { [choose] in choose(id) }
    }

    @objc private func cancel() { self.dismiss(animated: true) }
}
