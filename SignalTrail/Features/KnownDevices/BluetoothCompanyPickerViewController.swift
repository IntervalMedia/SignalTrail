import UIKit

final class BluetoothCompanyPickerViewController: UITableViewController, UISearchResultsUpdating {
  var onSelect: ((UInt16, String) -> Void)?

  private let companies = BluetoothCompanyLookup.commonCompanies
  private var filteredCompanies: [(UInt16, String)] = []
  private let searchController = UISearchController(searchResultsController: nil)

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Company Identifier"
    navigationItem.largeTitleDisplayMode = .never
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")

    searchController.obscuresBackgroundDuringPresentation = false
    searchController.searchBar.placeholder = "Search companies"
    searchController.searchResultsUpdater = self
    navigationItem.searchController = searchController
    definesPresentationContext = true

    filteredCompanies = companies
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    filteredCompanies.count
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
    -> UITableViewCell
  {
    let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
    let (identifier, name) = filteredCompanies[indexPath.row]
    let value = String(format: "%04X", identifier)

    var content = cell.defaultContentConfiguration()
    content.text = name
    content.secondaryText = "0x\(value)"
    content.secondaryTextProperties.color = .secondaryLabel

    cell.contentConfiguration = content
    cell.accessoryType = .disclosureIndicator
    return cell
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let company = filteredCompanies[indexPath.row]
    onSelect?(company.0, company.1)
    navigationController?.popViewController(animated: true)
  }

  func updateSearchResults(for searchController: UISearchController) {
    let query = searchController.searchBar.text?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    guard !query.isEmpty else {
      filteredCompanies = companies
      tableView.reloadData()
      return
    }

    let normalizedQuery = query.localizedLowercase
    filteredCompanies = companies.filter { identifier, name in
      let hex = String(format: "%04X", identifier)
      return name.localizedLowercase.contains(normalizedQuery)
        || hex.localizedLowercase.contains(normalizedQuery)
        || "0x\(hex)".localizedLowercase.contains(normalizedQuery)
    }
    tableView.reloadData()
  }
}
