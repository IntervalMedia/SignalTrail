import CoreBluetooth
import UIKit

final class ScanViewController: UIViewController {
  private let environment: AppEnvironment
  private lazy var viewModel = ScanViewModel(
    coordinator: environment.scanCoordinator,
    store: environment.store,
    settingsStore: environment.settingsStore
  )

  private let statusCard = ScanStatusCard()
  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private let searchController = UISearchController(searchResultsController: nil)
  private let emptyState = EmptyStateView(
    symbol: "dot.radiowaves.left.and.right",
    title: "No devices yet",
    message:
      "Start an active scan or a recorded session to observe nearby Bluetooth Low Energy advertisements."
  )

  init(environment: AppEnvironment) {
    self.environment = environment
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "SignalTrail"
    view.backgroundColor = AppTheme.groupedBackground
    viewModel.delegate = self
    configureNavigation()
    configureTable()
    configureHeader()
    render()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    viewModel.refreshKnownDevices()
  }

  private func configureNavigation() {
    navigationItem.searchController = searchController
    navigationItem.hidesSearchBarWhenScrolling = true
    searchController.searchResultsUpdater = self
    searchController.obscuresBackgroundDuringPresentation = false

    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "Clear",
      style: .plain,
      target: self,
      action: #selector(clearTapped)
    )
  }

  private func configureTable() {
    tableView.backgroundColor = AppTheme.groupedBackground
    tableView.register(DeviceCell.self, forCellReuseIdentifier: DeviceCell.reuseIdentifier)
    tableView.dataSource = self
    tableView.delegate = self
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 90
    view.addSubview(tableView)
    tableView.pinEdges(to: view)
  }

  private func configureHeader() {
    statusCard.modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
    statusCard.actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)

    let container = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 300))
    container.addSubview(statusCard)
    statusCard.pinEdges(
      to: container, insets: UIEdgeInsets(top: 10, left: 16, bottom: 14, right: 16))
    tableView.tableHeaderView = container
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    guard let header = tableView.tableHeaderView else { return }
    let width = tableView.bounds.width
    let target = header.systemLayoutSizeFitting(
      CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    )
    if abs(header.frame.height - target.height) > 1 {
      header.frame.size = CGSize(width: width, height: target.height)
      tableView.tableHeaderView = header
    }
  }

  private func render() {
    statusCard.timerLabel.text = viewModel.timerText
    statusCard.updateMetrics(
      devices: viewModel.devices.count, observations: viewModel.observationCount)
    statusCard.setRunning(
      viewModel.isRunning,
      mode: viewModel.selectedMode,
      burstActive: viewModel.burstActive,
      statusText: viewModel.statusText
    )
    statusCard.modeControl.selectedSegmentIndex = viewModel.selectedMode == .active ? 0 : 1
    navigationItem.rightBarButtonItem?.isEnabled =
      !viewModel.isRunning && !viewModel.devices.isEmpty
    emptyState.removeFromSuperview()
    tableView.reloadData()

    if viewModel.devices.isEmpty {
      tableView.backgroundView = emptyState
    } else {
      tableView.backgroundView = nil
    }
  }

  @objc private func modeChanged() {
    viewModel.selectedMode = statusCard.modeControl.selectedSegmentIndex == 0 ? .active : .recording
    render()
  }

  @objc private func actionTapped() {
    viewModel.toggleScan()
  }

  @objc private func clearTapped() {
    viewModel.clear()
  }
}

extension ScanViewController: ScanViewModelDelegate {
  func scanViewModelDidUpdate(_ viewModel: ScanViewModel) {
    render()
  }

  func scanViewModelDidTick(_ viewModel: ScanViewModel) {
    statusCard.timerLabel.text = viewModel.timerText
    statusCard.setRunning(
      viewModel.isRunning,
      mode: viewModel.selectedMode,
      burstActive: viewModel.burstActive,
      statusText: viewModel.statusText
    )
  }

  func scanViewModel(_ viewModel: ScanViewModel, didEncounter message: String) {
    presentError(message)
  }
}

extension ScanViewController: UISearchResultsUpdating {
  func updateSearchResults(for searchController: UISearchController) {
    viewModel.searchText = searchController.searchBar.text ?? ""
  }
}

extension ScanViewController: UITableViewDataSource, UITableViewDelegate {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    viewModel.devices.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell =
      tableView.dequeueReusableCell(withIdentifier: DeviceCell.reuseIdentifier, for: indexPath)
      as! DeviceCell
    let device = viewModel.devices[indexPath.row]
    cell.configure(
      with: device, isKnown: viewModel.knownPeripheralIDs.contains(device.peripheralIdentifier))
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let device = viewModel.devices[indexPath.row]
    let controller = DeviceDetailViewController(device: device, environment: environment)
    navigationController?.pushViewController(controller, animated: true)
  }
}
