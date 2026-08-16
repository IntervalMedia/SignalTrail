import Foundation

protocol ScanViewModelDelegate: AnyObject {
  func scanViewModelDidUpdate(_ viewModel: ScanViewModel)
  func scanViewModelDidTick(_ viewModel: ScanViewModel)
  func scanViewModel(_ viewModel: ScanViewModel, didEncounter message: String)
}

enum LiveResultFilter: CaseIterable {
  case strongest
  case recentlySeen
  case known
  case alertMatched
  case connectable
  case unknown

  var title: String {
    switch self {
    case .strongest: return "Strongest"
    case .recentlySeen: return "Recently seen"
    case .known: return "Known"
    case .alertMatched: return "Alert matched"
    case .connectable: return "Connectable"
    case .unknown: return "Unknown devices"
    }
  }
}

enum LiveResultSort: Int, CaseIterable {
  case signal
  case newest
  case name
  case observations

  var title: String {
    switch self {
    case .signal: return "Signal"
    case .newest: return "Newest"
    case .name: return "Name"
    case .observations: return "Count"
    }
  }
}

final class ScanViewModel {
  weak var delegate: ScanViewModelDelegate?

  private let coordinator: ScanCoordinator
  private let store: LocalStore
  private let settingsStore: SettingsStore
  private var timer: Timer?
  private var allDevices: [BLEDeviceSnapshot] = []
  private var knownIDs = Set<UUID>()
  private var alertRules: [AlertRule] = []

  var selectedMode: ScanMode = .active
  var searchText = "" {
    didSet { delegate?.scanViewModelDidUpdate(self) }
  }
  var activeFilters = Set<LiveResultFilter>() {
    didSet { delegate?.scanViewModelDidUpdate(self) }
  }
  var sort: LiveResultSort = .signal {
    didSet { delegate?.scanViewModelDidUpdate(self) }
  }

  var minimumRSSI: Int {
    get { settingsStore.settings.minimumRSSI }
    set {
      var settings = settingsStore.settings
      settings.minimumRSSI = newValue
      settingsStore.settings = settings
      delegate?.scanViewModelDidUpdate(self)
    }
  }

  private(set) var state: ScanCoordinator.State = .idle

  var isRunning: Bool { state.isRunning }

  var devices: [BLEDeviceSnapshot] {
    sortedDevices(
      allDevices.filter { device in
        device.latestRSSI >= minimumRSSI
          && matchesSearch(device)
          && matchesFilters(device)
      }
    )
  }

  var knownPeripheralIDs: Set<UUID> { knownIDs }

  var alertMatchedPeripheralIDs: Set<UUID> {
    Set(allDevices.filter(matchesAlert).map(\.peripheralIdentifier))
  }

  func refreshKnownDevices() {
    knownIDs = Set(store.loadKnownDevices().map(\.peripheralIdentifier))
    alertRules = store.loadAlertRules()
    delegate?.scanViewModelDidUpdate(self)
  }

  func matchesAlert(_ device: BLEDeviceSnapshot) -> Bool {
    alertRules.contains { AlertMatcher.matches(rule: $0, device: device) }
  }

  var observationCount: Int {
    allDevices.reduce(0) { $0 + $1.sightingCount }
  }

  var timerText: String {
    switch state {
    case .idle:
      return selectedMode == .active
        ? settingsStore.settings.activeScanDuration.clockString : "00:00"
    case .waitingForBluetooth, .waitingForLocation:
      return "--:--"
    case .active(_, let endsAt):
      return max(0, endsAt.timeIntervalSinceNow).clockString
    case .recording(let startedAt, _, _):
      return Date().timeIntervalSince(startedAt).clockString
    }
  }

  var statusText: String {
    switch state {
    case .idle:
      return "Ready"
    case .waitingForBluetooth:
      return "Waiting for Bluetooth"
    case .waitingForLocation:
      return "Waiting for location permission"
    case .active:
      return "Scanning"
    case .recording(_, _, let active):
      return active ? "Recording scan burst" : "Recording battery pause"
    }
  }

  var burstActive: Bool {
    if case .recording(_, _, let active) = state { return active }
    return true
  }

  init(coordinator: ScanCoordinator, store: LocalStore, settingsStore: SettingsStore) {
    self.coordinator = coordinator
    self.store = store
    self.settingsStore = settingsStore
    coordinator.delegate = self
    knownIDs = Set(store.loadKnownDevices().map(\.peripheralIdentifier))
    alertRules = store.loadAlertRules()
  }

  func toggleScan() {
    if isRunning {
      coordinator.stop()
    } else {
      selectedMode == .active ? coordinator.startActive() : coordinator.startRecording()
    }
  }

  func clear() {
    coordinator.clearResults()
  }

  private func matchesSearch(_ device: BLEDeviceSnapshot) -> Bool {
    guard !searchText.isEmpty else { return true }
    let advertisedServiceUUIDs = device.advertisement.serviceUUIDs
      + device.advertisement.solicitedServiceUUIDs
      + device.advertisement.overflowServiceUUIDs
      + Array(device.advertisement.serviceData.keys)
    let assignedServiceNames = advertisedServiceUUIDs.compactMap {
      BluetoothAssignedUUIDLookup.serviceMetadata(for: $0)?.name
    }
    let reportedIdentityValues = [
      device.gattEvidence?.identity.manufacturerName,
      device.gattEvidence?.identity.modelNumber,
      device.gattEvidence?.identity.appearance?.displayName,
    ].compactMap { $0 }
    return device.presentationName.localizedCaseInsensitiveContains(searchText)
      || device.displayName.localizedCaseInsensitiveContains(searchText)
      || device.peripheralIdentifier.uuidString.localizedCaseInsensitiveContains(searchText)
      || device.intelligence.categoryTitle.localizedCaseInsensitiveContains(searchText)
      || assignedServiceNames.contains { $0.localizedCaseInsensitiveContains(searchText) }
      || reportedIdentityValues.contains { $0.localizedCaseInsensitiveContains(searchText) }
      || (device.advertisement.manufacturerDataHex?.localizedCaseInsensitiveContains(searchText)
        ?? false)
  }

  private func matchesFilters(_ device: BLEDeviceSnapshot) -> Bool {
    for filter in activeFilters {
      switch filter {
      case .strongest, .recentlySeen:
        continue
      case .known:
        guard knownIDs.contains(device.peripheralIdentifier) else { return false }
      case .alertMatched:
        guard matchesAlert(device) else { return false }
      case .connectable:
        guard device.advertisement.isConnectable else { return false }
      case .unknown:
        guard !knownIDs.contains(device.peripheralIdentifier),
              device.intelligence.confidenceLabel == "Unknown" else { return false }
      }
    }
    return true
  }

  private func sortedDevices(_ devices: [BLEDeviceSnapshot]) -> [BLEDeviceSnapshot] {
    let resolvedSort: LiveResultSort
    if activeFilters.contains(.strongest) {
      resolvedSort = .signal
    } else if activeFilters.contains(.recentlySeen) {
      resolvedSort = .newest
    } else {
      resolvedSort = sort
    }

    return devices.sorted { left, right in
      switch resolvedSort {
      case .signal:
        if left.latestRSSI == right.latestRSSI { return compareNames(left, right) }
        return left.latestRSSI > right.latestRSSI
      case .newest:
        if left.lastSeen == right.lastSeen { return compareNames(left, right) }
        return left.lastSeen > right.lastSeen
      case .name:
        if left.presentationName == right.presentationName { return left.lastSeen > right.lastSeen }
        return compareNames(left, right)
      case .observations:
        if left.sightingCount == right.sightingCount { return compareNames(left, right) }
        return left.sightingCount > right.sightingCount
      }
    }
  }

  private func compareNames(_ left: BLEDeviceSnapshot, _ right: BLEDeviceSnapshot) -> Bool {
    left.presentationName.localizedCaseInsensitiveCompare(right.presentationName) == .orderedAscending
  }

  private func updateTimerLifecycle() {
    timer?.invalidate()
    guard state.isRunning else {
      timer = nil
      return
    }
    timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      guard let self = self else { return }
      self.delegate?.scanViewModelDidTick(self)
    }
  }
}

extension ScanViewModel: ScanCoordinatorDelegate {
  func scanCoordinatorDidChangeState(_ coordinator: ScanCoordinator) {
    state = coordinator.state
    updateTimerLifecycle()
    delegate?.scanViewModelDidUpdate(self)
  }

  func scanCoordinator(_ coordinator: ScanCoordinator, didUpdate devices: [BLEDeviceSnapshot]) {
    allDevices = devices
    delegate?.scanViewModelDidUpdate(self)
  }

  func scanCoordinator(_ coordinator: ScanCoordinator, didEncounter message: String) {
    delegate?.scanViewModel(self, didEncounter: message)
  }
}
