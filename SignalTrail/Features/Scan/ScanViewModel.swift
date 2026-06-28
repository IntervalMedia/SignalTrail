import Foundation

protocol ScanViewModelDelegate: AnyObject {
  func scanViewModelDidUpdate(_ viewModel: ScanViewModel)
  func scanViewModelDidTick(_ viewModel: ScanViewModel)
  func scanViewModel(_ viewModel: ScanViewModel, didEncounter message: String)
}

final class ScanViewModel {
  weak var delegate: ScanViewModelDelegate?

  private let coordinator: ScanCoordinator
  private let store: LocalStore
  private let settingsStore: SettingsStore
  private var timer: Timer?
  private var allDevices: [BLEDeviceSnapshot] = []
  private var knownIDs = Set<UUID>()

  var selectedMode: ScanMode = .active
  var searchText = "" {
    didSet { delegate?.scanViewModelDidUpdate(self) }
  }

  private(set) var state: ScanCoordinator.State = .idle

  var isRunning: Bool { state.isRunning }

  var devices: [BLEDeviceSnapshot] {
    guard !searchText.isEmpty else { return allDevices }
    return allDevices.filter {
      $0.displayName.localizedCaseInsensitiveContains(searchText)
        || $0.peripheralIdentifier.uuidString.localizedCaseInsensitiveContains(searchText)
        || ($0.advertisement.manufacturerDataHex?.localizedCaseInsensitiveContains(searchText)
          ?? false)
    }
  }

  var knownPeripheralIDs: Set<UUID> { knownIDs }

  func refreshKnownDevices() {
    knownIDs = Set(store.loadKnownDevices().map(\.peripheralIdentifier))
    delegate?.scanViewModelDidUpdate(self)
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
      return "—:—"
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
      return "Scanning continuously"
    case .recording(_, _, let active):
      return active ? "Recording • scan burst" : "Recording • battery pause"
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
