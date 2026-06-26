import CoreBluetooth
import CoreLocation
import UIKit

final class SettingsViewController: UITableViewController {
  private let environment: AppEnvironment
  private var settings: AppSettings

  init(environment: AppEnvironment) {
    self.environment = environment
    self.settings = environment.settingsStore.settings
    super.init(style: .insetGrouped)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Settings"
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    settings = environment.settingsStore.settings
    tableView.reloadData()
  }

  override func numberOfSections(in tableView: UITableView) -> Int { 5 }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    [1, 3, 2, 2, 3][section]
  }

  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
  {
    ["Active Scan", "Recorded Sessions", "Filtering", "Permissions", "About"][section]
  }

  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String?
  {
    switch section {
    case 0:
      return "The active scan continuously listens for advertisements until this timer expires."
    case 1:
      return
        "Record mode alternates scan bursts and pauses. iOS controls the underlying BLE scan window."
    case 2: return "Weaker RSSI values are more negative. Filtering can reduce noisy observations."
    case 4:
      return
        "SignalTrail records the phone location where an advertisement was observed. It cannot determine the BLE device’s actual location or hardware MAC address."
    default: return nil
    }
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
    -> UITableViewCell
  {
    let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
    var content = cell.defaultContentConfiguration()
    cell.accessoryView = nil
    cell.accessoryType = .none
    cell.selectionStyle = .none

    switch indexPath.section {
    case 0:
      content.text = "Duration"
      content.secondaryText = settings.activeScanDuration.clockString
      cell.accessoryType = .disclosureIndicator
      cell.selectionStyle = .default

    case 1:
      if indexPath.row == 0 {
        content.text = "Scan burst"
        content.secondaryText = "\(Int(settings.recordingBurstDuration)) seconds"
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
      } else if indexPath.row == 1 {
        content.text = "Pause between bursts"
        content.secondaryText = "\(Int(settings.recordingPauseDuration)) seconds"
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
      } else {
        content.text = "Keep screen awake"
        let toggle = UISwitch()
        toggle.isOn = settings.keepScreenAwakeDuringRecording
        toggle.addTarget(self, action: #selector(keepAwakeChanged(_:)), for: .valueChanged)
        cell.accessoryView = toggle
      }

    case 2:
      if indexPath.row == 0 {
        content.text = "Minimum RSSI"
        content.secondaryText = "\(settings.minimumRSSI) dBm"
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
      } else {
        content.text = "Clear live scan results"
        content.textProperties.color = .systemRed
        cell.selectionStyle = .default
      }

    case 3:
      content.text = indexPath.row == 0 ? "Location permission" : "Notification permission"
      content.secondaryText = indexPath.row == 0 ? locationStatusText : "Tap to request or review"
      content.image = UIImage(systemName: indexPath.row == 0 ? "location" : "bell")
      content.imageProperties.tintColor = AppTheme.accent
      cell.accessoryType = .disclosureIndicator
      cell.selectionStyle = .default

    case 4:
      if indexPath.row == 0 {
        content.text = "SignalTrail"
        content.secondaryText =
          Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
      } else if indexPath.row == 1 {
        content.text = "Data storage"
        content.secondaryText = "Local to this device"
      } else {
        content.text = "Reset settings"
        content.textProperties.color = .systemRed
        cell.selectionStyle = .default
      }
    default:
      break
    }
    cell.contentConfiguration = content
    return cell
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    switch (indexPath.section, indexPath.row) {
    case (0, 0):
      showDurationPicker(
        title: "Active scan duration", current: settings.activeScanDuration,
        options: [30, 60, 120, 180, 300]
      ) { self.settings.activeScanDuration = $0 }
    case (1, 0):
      showDurationPicker(
        title: "Scan burst", current: settings.recordingBurstDuration,
        options: [3, 5, 8, 10, 15, 20]
      ) { self.settings.recordingBurstDuration = $0 }
    case (1, 1):
      showDurationPicker(
        title: "Pause", current: settings.recordingPauseDuration,
        options: [3, 5, 10, 12, 15, 30, 60]
      ) { self.settings.recordingPauseDuration = $0 }
    case (2, 0): showRSSIPicker()
    case (2, 1): environment.scanCoordinator.clearResults()
    case (3, 0): environment.locationProvider.requestWhenInUseAuthorization()
    case (3, 1):
      environment.notificationService.requestAuthorization { [weak self] granted in
        if !granted { self?.openSystemSettings() }
      }
    case (4, 2): resetSettings()
    default: break
    }
  }

  private var locationStatusText: String {
    switch environment.locationProvider.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse: return "Granted"
    case .denied: return "Denied"
    case .restricted: return "Restricted"
    case .notDetermined: return "Not requested"
    @unknown default: return "Unknown"
    }
  }

  private func showDurationPicker(
    title: String,
    current: TimeInterval,
    options: [TimeInterval],
    update: @escaping (TimeInterval) -> Void
  ) {
    let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
    options.forEach { value in
      let label = value >= 60 ? value.clockString : "\(Int(value)) seconds"
      alert.addAction(
        UIAlertAction(title: value == current ? "✓ \(label)" : label, style: .default) {
          [weak self] _ in
          guard let self = self else { return }
          update(value)
          self.environment.settingsStore.settings = self.settings
          self.tableView.reloadData()
        })
    }
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = view
      popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
    }
    present(alert, animated: true)
  }

  private func showRSSIPicker() {
    let alert = UIAlertController(title: "Minimum RSSI", message: nil, preferredStyle: .actionSheet)
    [-110, -100, -90, -80, -70].forEach { value in
      alert.addAction(
        UIAlertAction(
          title: value == settings.minimumRSSI ? "✓ \(value) dBm" : "\(value) dBm", style: .default
        ) { [weak self] _ in
          self?.settings.minimumRSSI = value
          if let self = self {
            self.environment.settingsStore.settings = self.settings
            self.tableView.reloadData()
          }
        })
    }
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = view
      popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
    }
    present(alert, animated: true)
  }

  private func openSystemSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }

  private func resetSettings() {
    let alert = UIAlertController(
      title: "Reset Settings?", message: "Recorded sessions and known devices will not be deleted.",
      preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(
      UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
        guard let self = self else { return }
        self.environment.settingsStore.reset()
        self.settings = .default
        self.tableView.reloadData()
      })
    present(alert, animated: true)
  }

  @objc private func keepAwakeChanged(_ sender: UISwitch) {
    settings.keepScreenAwakeDuringRecording = sender.isOn
    environment.settingsStore.settings = settings
  }
}
