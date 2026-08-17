import CoreBluetooth
import CoreLocation
import UIKit
import UserNotifications

final class ScanViewController: UIViewController {
  private static let onboardingShownKey = "SignalTrail.ScanOnboardingShown"

  private let environment: AppEnvironment
  private lazy var viewModel = ScanViewModel(
    coordinator: environment.scanCoordinator,
    store: environment.store,
    settingsStore: environment.settingsStore
  )

  private let statusCard = ScanStatusCard()
  private let controlsCard = CardView()
  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private let searchController = UISearchController(searchResultsController: nil)
  private let filterStack = UIStackView()
  private var filterButtons: [LiveResultFilter: UIButton] = [:]
  private let sortControl = UISegmentedControl(items: LiveResultSort.allCases.map(\.title))
  private let rssiSlider = UISlider()
  private let rssiValueLabel = UILabel()
  private let emptyState = EmptyStateView(
    symbol: "dot.radiowaves.left.and.right",
    title: "No devices yet",
    message:
      "Start a Quick Scan for nearby devices or Record Session to save repeated observations with the phone's route."
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

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    presentFirstRunOnboardingIfNeeded()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    viewModel.refreshKnownDevices()
    updateReadiness()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    if searchController.isActive {
      searchController.isActive = false
    }
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
    tableView.estimatedRowHeight = 112
    view.addSubview(tableView)
    tableView.pinEdges(to: view)
  }

  private func configureHeader() {
    statusCard.modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
    statusCard.actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
    configureResultControls()

    let initialWidth = max(view.bounds.width, UIScreen.main.bounds.width, 320)
    let container = UIView(frame: CGRect(x: 0, y: 0, width: initialWidth, height: 420))

    let stack = UIStackView(arrangedSubviews: [statusCard, controlsCard])
    stack.axis = .vertical
    stack.spacing = 12
    container.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
      stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
    ])
    tableView.tableHeaderView = container
  }

  private func configureResultControls() {
    let titleLabel = UILabel()
    titleLabel.text = "Live results"
    titleLabel.font = .preferredFont(forTextStyle: .headline)

    filterStack.axis = .horizontal
    filterStack.spacing = 8
    filterStack.alignment = .center

    for filter in LiveResultFilter.allCases {
      let button = UIButton(type: .system)
      var configuration = UIButton.Configuration.tinted()
      configuration.cornerStyle = .capsule
      configuration.title = filter.title
      configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
      button.configuration = configuration
      button.addAction(UIAction { [weak self] _ in
        self?.toggleFilter(filter)
      }, for: .touchUpInside)
      filterButtons[filter] = button
      filterStack.addArrangedSubview(button)
    }

    let filterScroll = UIScrollView()
    filterScroll.showsHorizontalScrollIndicator = false
    filterScroll.addSubview(filterStack)
    filterStack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      filterStack.leadingAnchor.constraint(equalTo: filterScroll.contentLayoutGuide.leadingAnchor),
      filterStack.trailingAnchor.constraint(equalTo: filterScroll.contentLayoutGuide.trailingAnchor),
      filterStack.topAnchor.constraint(equalTo: filterScroll.contentLayoutGuide.topAnchor),
      filterStack.bottomAnchor.constraint(equalTo: filterScroll.contentLayoutGuide.bottomAnchor),
      filterStack.heightAnchor.constraint(equalTo: filterScroll.frameLayoutGuide.heightAnchor),
    ])
    filterScroll.heightAnchor.constraint(equalToConstant: 36).isActive = true

    sortControl.selectedSegmentIndex = viewModel.sort.rawValue
    sortControl.addTarget(self, action: #selector(sortChanged), for: .valueChanged)

    let rssiTitle = UILabel()
    rssiTitle.text = "Minimum RSSI"
    rssiTitle.font = .preferredFont(forTextStyle: .subheadline)

    rssiValueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    rssiValueLabel.textColor = .secondaryLabel
    rssiValueLabel.textAlignment = .right

    let rssiHeader = UIStackView(arrangedSubviews: [rssiTitle, UIView(), rssiValueLabel])
    rssiHeader.axis = .horizontal
    rssiHeader.alignment = .center

    rssiSlider.minimumValue = -100
    rssiSlider.maximumValue = -40
    rssiSlider.value = Float(viewModel.minimumRSSI)
    rssiSlider.addTarget(self, action: #selector(rssiChanged), for: .valueChanged)

    let stack = UIStackView(arrangedSubviews: [titleLabel, filterScroll, sortControl, rssiHeader, rssiSlider])
    stack.axis = .vertical
    stack.spacing = 10
    controlsCard.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: controlsCard.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: controlsCard.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: controlsCard.topAnchor, constant: 14),
      stack.bottomAnchor.constraint(equalTo: controlsCard.bottomAnchor, constant: -14),
    ])
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
    sortControl.selectedSegmentIndex = viewModel.sort.rawValue
    rssiSlider.value = Float(viewModel.minimumRSSI)
    rssiValueLabel.text = "\(viewModel.minimumRSSI) dBm"
    renderFilterButtons()
    updateReadiness()

    navigationItem.rightBarButtonItem?.isEnabled =
      !viewModel.isRunning && !viewModel.devices.isEmpty
    emptyState.removeFromSuperview()
    tableView.reloadData()

    tableView.backgroundView = viewModel.devices.isEmpty ? emptyState : nil
  }

  private func renderFilterButtons() {
    for (filter, button) in filterButtons {
      var configuration = button.configuration
      let selected = viewModel.activeFilters.contains(filter)
      configuration?.baseForegroundColor = selected ? .white : AppTheme.accent
      configuration?.baseBackgroundColor = selected ? AppTheme.accent : AppTheme.accent.withAlphaComponent(0.14)
      button.configuration = configuration
    }
  }

  private func updateReadiness() {
    statusCard.configureReadiness(
      bluetooth: bluetoothReadinessText,
      location: locationReadinessText,
      notifications: "Checking"
    )
    environment.notificationService.authorizationStatus { [weak self] status in
      guard let self else { return }
      self.statusCard.configureReadiness(
        bluetooth: self.bluetoothReadinessText,
        location: self.locationReadinessText,
        notifications: self.notificationReadinessText(for: status)
      )
    }
  }

  private var bluetoothReadinessText: String {
    switch environment.bluetoothScanner.state {
    case .poweredOn: return "Ready"
    case .unknown, .resetting: return "Checking"
    default: return "Unavailable"
    }
  }

  private var locationReadinessText: String {
    switch environment.locationProvider.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse: return "Granted"
    case .notDetermined: return "Required for recording"
    case .denied, .restricted: return "Required for recording"
    @unknown default: return "Required for recording"
    }
  }

  private func notificationReadinessText(for status: UNAuthorizationStatus) -> String {
    switch status {
    case .authorized, .provisional, .ephemeral: return "Enabled"
    default: return "Disabled"
    }
  }

  private func presentFirstRunOnboardingIfNeeded() {
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: Self.onboardingShownKey), presentedViewController == nil else { return }
    defaults.set(true, forKey: Self.onboardingShownKey)

    let alert = UIAlertController(
      title: "Welcome to SignalTrail",
      message: """
      Quick Scan temporarily discovers nearby BLE devices.

      Record Session saves repeated signal observations with the phone's location.

      Observation points show where this phone heard a signal, not a verified device location.
      """,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Continue", style: .default))
    present(alert, animated: true)
  }

  private func toggleFilter(_ filter: LiveResultFilter) {
    if viewModel.activeFilters.contains(filter) {
      viewModel.activeFilters.remove(filter)
      return
    }

    if filter == .strongest {
      viewModel.activeFilters.remove(.recentlySeen)
    } else if filter == .recentlySeen {
      viewModel.activeFilters.remove(.strongest)
    }
    viewModel.activeFilters.insert(filter)
  }

  private func showRecordingPermissionContext() {
    let alert = UIAlertController(
      title: "Allow location for recording?",
      message:
        "Record Session saves where this phone observed each signal so you can replay your route. It does not prove where the broadcasting device was located.",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self] _ in
      self?.viewModel.toggleScan()
    })
    present(alert, animated: true)
  }

  @objc private func modeChanged() {
    viewModel.selectedMode = statusCard.modeControl.selectedSegmentIndex == 0 ? .active : .recording
    render()
  }

  @objc private func sortChanged() {
    viewModel.activeFilters.remove(.strongest)
    viewModel.activeFilters.remove(.recentlySeen)
    viewModel.sort = LiveResultSort(rawValue: sortControl.selectedSegmentIndex) ?? .signal
  }

  @objc private func rssiChanged() {
    let value = Int((rssiSlider.value / 5).rounded() * 5)
    viewModel.minimumRSSI = value
  }

  @objc private func actionTapped() {
    guard !viewModel.isRunning,
          viewModel.selectedMode == .recording,
          environment.locationProvider.authorizationStatus == .notDetermined else {
      viewModel.toggleScan()
      return
    }
    showRecordingPermissionContext()
  }

  @objc private func clearTapped() {
    viewModel.clear()
  }

  private func showAlertTemplates(for device: BLEDeviceSnapshot) {
    let alert = UIAlertController(title: "Create Alert", message: nil, preferredStyle: .actionSheet)
    let templates = alertTemplates(for: device)
    for template in templates {
      alert.addAction(UIAlertAction(title: template.title, style: .default) { [weak self] _ in
        self?.openAlertEditor(rule: template.rule)
      })
    }
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = view
      popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
    }
    present(alert, animated: true)
  }

  private func openAlertEditor(rule: AlertRule) {
    let controller = AlertRuleEditorViewController(rule: rule, environment: environment, isNewRule: true)
    controller.onSave = { [weak self] _ in self?.viewModel.refreshKnownDevices() }
    navigationController?.pushViewController(controller, animated: true)
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
      with: device,
      isKnown: viewModel.knownPeripheralIDs.contains(device.peripheralIdentifier),
      alertMatched: viewModel.matchesAlert(device)
    )
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let device = viewModel.devices[indexPath.row]
    let controller = DeviceDetailViewController(device: device, environment: environment)
    navigationController?.pushViewController(controller, animated: true)
  }

  func tableView(
    _ tableView: UITableView,
    trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
  ) -> UISwipeActionsConfiguration? {
    let device = viewModel.devices[indexPath.row]
    let alert = UIContextualAction(style: .normal, title: "Alert") { [weak self] _, _, completion in
      self?.showAlertTemplates(for: device)
      completion(true)
    }
    alert.backgroundColor = .systemOrange
    return UISwipeActionsConfiguration(actions: [alert])
  }
}

struct AlertTemplate {
  let title: String
  let rule: AlertRule
}

func alertTemplates(for device: BLEDeviceSnapshot) -> [AlertTemplate] {
  var templates: [AlertTemplate] = []
  templates.append(
    AlertTemplate(
      title: "This exact device",
      rule: AlertRule(
        id: UUID(),
        name: "\(device.presentationName) appears",
        matchType: .peripheralIdentifier,
        matchValue: device.peripheralIdentifier.uuidString,
        isEnabled: true,
        notifyOncePerSession: true,
        cooldownSeconds: 300
      )
    )
  )

  if let companyIdentifier = device.advertisement.companyIdentifier {
    let company = BluetoothCompanyLookup.displayName(for: companyIdentifier)
    templates.append(
      AlertTemplate(
        title: "This company ID assignee",
        rule: AlertRule(
          id: UUID(),
          name: "\(company) broadcast detected",
          matchType: .companyIdentifier,
          matchValue: String(format: "%04X", companyIdentifier),
          isEnabled: true,
          notifyOncePerSession: true,
          cooldownSeconds: 300
        )
      )
    )
  }

  if let manufacturerData = device.advertisement.manufacturerDataHex, !manufacturerData.isEmpty {
    templates.append(
      AlertTemplate(
        title: "Similar advertisement data",
        rule: AlertRule(
          id: UUID(),
          name: "Similar \(device.presentationName) advertisement",
          matchType: .manufacturerPrefix,
          matchValue: String(manufacturerData.prefix(8)),
          isEnabled: true,
          notifyOncePerSession: true,
          cooldownSeconds: 300
        )
      )
    )
  }

  templates.append(
    AlertTemplate(
      title: "Custom multi-condition rule",
      rule: AlertRule(
        id: UUID(),
        name: "",
        matchType: .localNameContains,
        matchValue: device.advertisement.localName ?? device.presentationName,
        isEnabled: true,
        notifyOncePerSession: true,
        cooldownSeconds: 300
      )
    )
  )
  return templates
}
