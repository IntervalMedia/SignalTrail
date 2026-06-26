import CoreBluetooth
import CoreLocation
import Foundation
import UIKit

protocol ScanCoordinatorDelegate: AnyObject {
  func scanCoordinatorDidChangeState(_ coordinator: ScanCoordinator)
  func scanCoordinator(_ coordinator: ScanCoordinator, didUpdate devices: [BLEDeviceSnapshot])
  func scanCoordinator(_ coordinator: ScanCoordinator, didEncounter message: String)
}

final class ScanCoordinator {
  private static let liveDeviceMaximumAge: TimeInterval = 90
  private static let liveDeviceMaximumCount = 400

  enum State: Equatable {
    case idle
    case waitingForBluetooth(ScanMode)
    case waitingForLocation
    case active(startedAt: Date, endsAt: Date)
    case recording(startedAt: Date, sessionID: UUID, isBurstActive: Bool)

    var mode: ScanMode? {
      switch self {
      case .idle: return nil
      case .waitingForBluetooth(let mode): return mode
      case .waitingForLocation: return .recording
      case .active: return .active
      case .recording: return .recording
      }
    }

    var isRunning: Bool {
      switch self {
      case .idle: return false
      default: return true
      }
    }
  }

  weak var delegate: ScanCoordinatorDelegate?

  private let scanner: BluetoothScanner
  private let locationProvider: LocationProviding
  private let store: LocalStore
  private let settingsStore: SettingsStore
  private let notificationService: NotificationService

  private var stateTimer: Timer?
  private var burstTimer: Timer?
  private var snapshots: [UUID: BLEDeviceSnapshot] = [:]
  private var activeSession: ScanSession?
  private var sessionUniqueIDs = Set<UUID>()
  private var notificationHistory: [UUID: Date] = [:]
  private var notifiedRulesForSession = Set<UUID>()
  private var alertRules: [AlertRule] = []

  private(set) var state: State = .idle {
    didSet { delegate?.scanCoordinatorDidChangeState(self) }
  }

  var devices: [BLEDeviceSnapshot] {
    snapshots.values.sorted {
      if $0.latestRSSI == $1.latestRSSI {
        return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
      }
      return $0.latestRSSI > $1.latestRSSI
    }
  }

  init(
    scanner: BluetoothScanner,
    locationProvider: LocationProviding,
    store: LocalStore,
    settingsStore: SettingsStore,
    notificationService: NotificationService
  ) {
    self.scanner = scanner
    self.locationProvider = locationProvider
    self.store = store
    self.settingsStore = settingsStore
    self.notificationService = notificationService
    scanner.delegate = self
    locationProvider.onAuthorizationChanged = { [weak self] status in
      guard let self = self else { return }
      if self.state == .waitingForLocation {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
          self.startRecordingWithAuthorization()
        } else if status == .denied || status == .restricted {
          self.state = .idle
          self.delegate?.scanCoordinator(
            self,
            didEncounter: "Location access was not granted, so the recording was not started."
          )
        }
        return
      }

      guard self.state.mode == .recording else { return }
      if status == .denied || status == .restricted {
        self.stop(reason: .user)
        self.delegate?.scanCoordinator(
          self,
          didEncounter: "Location access was removed, so the recording was stopped."
        )
      }
    }
  }

  func startActive() {
    guard !state.isRunning else { return }
    resetTransientState()
    let duration = settingsStore.settings.activeScanDuration
    let start = Date()
    if scanner.isReady {
      state = .active(startedAt: start, endsAt: start.addingTimeInterval(duration))
      scanner.startScanning()
      scheduleStateTimer(after: duration) { [weak self] in self?.stop(reason: .timerCompleted) }
    } else {
      state = .waitingForBluetooth(.active)
    }
  }

  func startRecording() {
    guard !state.isRunning else { return }

    switch locationProvider.authorizationStatus {
    case .notDetermined:
      state = .waitingForLocation
      locationProvider.requestWhenInUseAuthorization()
    case .authorizedWhenInUse, .authorizedAlways:
      startRecordingWithAuthorization()
    case .denied, .restricted:
      delegate?.scanCoordinator(
        self,
        didEncounter:
          "Location access is required to record observation locations. Enable it in Settings."
      )
    @unknown default:
      delegate?.scanCoordinator(self, didEncounter: "Location access is not currently available.")
    }
  }

  private func startRecordingWithAuthorization() {
    guard state == .idle || state == .waitingForLocation else { return }
    resetTransientState()
    let start = Date()
    let session = ScanSession(
      id: UUID(),
      startedAt: start,
      endedAt: nil,
      mode: .recording,
      name: "Recording \(DateFormatter.signalTrailList.string(from: start))",
      detectionCount: 0,
      uniqueDeviceCount: 0,
      timeZoneIdentifier: TimeZone.current.identifier
    )
    do {
      try store.createSession(session)
      activeSession = session
    } catch {
      state = .idle
      delegate?.scanCoordinator(
        self, didEncounter: "Unable to create the recording: \(error.localizedDescription)")
      return
    }

    locationProvider.startUpdating()
    UIApplication.shared.isIdleTimerDisabled = settingsStore.settings.keepScreenAwakeDuringRecording
    state =
      scanner.isReady
      ? .recording(startedAt: start, sessionID: session.id, isBurstActive: true)
      : .waitingForBluetooth(.recording)
    beginRecordingBurst()
  }

  func stop(reason: ScanStopReason = .user) {
    guard state.isRunning else { return }
    scanner.stopScanning()
    stateTimer?.invalidate()
    burstTimer?.invalidate()
    stateTimer = nil
    burstTimer = nil
    locationProvider.stopUpdating()
    UIApplication.shared.isIdleTimerDisabled = false

    if var session = activeSession {
      session.endedAt = Date()
      session.uniqueDeviceCount = sessionUniqueIDs.count
      do { try store.updateSession(session) } catch {
        delegate?.scanCoordinator(
          self, didEncounter: "The session ended, but its summary could not be saved.")
      }
    }

    activeSession = nil
    state = .idle
  }

  func clearResults() {
    guard !state.isRunning else { return }
    snapshots.removeAll()
    scanner.clearCachedPeripherals()
    delegate?.scanCoordinator(self, didUpdate: [])
  }

  func peripheral(for identifier: UUID) -> CBPeripheral? {
    scanner.peripheral(for: identifier)
  }

  private func beginRecordingBurst() {
    guard case .recording(let startedAt, let sessionID, _) = state else {
      if case .waitingForBluetooth(.recording) = state { return }
      return
    }

    state = .recording(startedAt: startedAt, sessionID: sessionID, isBurstActive: true)
    scanner.startScanning()
    burstTimer?.invalidate()
    burstTimer = Timer.scheduledTimer(
      withTimeInterval: settingsStore.settings.recordingBurstDuration, repeats: false
    ) { [weak self] _ in
      self?.endRecordingBurst()
    }
  }

  private func endRecordingBurst() {
    guard case .recording(let startedAt, let sessionID, _) = state else { return }
    scanner.stopScanning()
    state = .recording(startedAt: startedAt, sessionID: sessionID, isBurstActive: false)
    burstTimer?.invalidate()
    burstTimer = Timer.scheduledTimer(
      withTimeInterval: settingsStore.settings.recordingPauseDuration, repeats: false
    ) { [weak self] _ in
      self?.beginRecordingBurst()
    }
  }

  private func scheduleStateTimer(after interval: TimeInterval, action: @escaping () -> Void) {
    stateTimer?.invalidate()
    stateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in action() }
  }

  private func resetTransientState() {
    snapshots.removeAll()
    sessionUniqueIDs.removeAll()
    notificationHistory.removeAll()
    notifiedRulesForSession.removeAll()
    alertRules = store.loadAlertRules()
    scanner.clearCachedPeripherals()
    delegate?.scanCoordinator(self, didUpdate: [])
  }

  static func pruneSnapshots(
    _ snapshots: [UUID: BLEDeviceSnapshot],
    now: Date,
    maximumAge: TimeInterval = liveDeviceMaximumAge,
    maximumCount: Int = liveDeviceMaximumCount
  ) -> [UUID: BLEDeviceSnapshot] {
    guard maximumAge >= 0, maximumCount > 0 else { return [:] }

    let cutoff = now.addingTimeInterval(-maximumAge)
    var retained = snapshots.values.filter { $0.lastSeen >= cutoff }

    retained.sort {
      if $0.lastSeen == $1.lastSeen {
        if $0.latestRSSI == $1.latestRSSI {
          return $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            == .orderedAscending
        }
        return $0.latestRSSI > $1.latestRSSI
      }
      return $0.lastSeen > $1.lastSeen
    }

    if retained.count > maximumCount {
      retained.removeSubrange(maximumCount...)
    }

    return Dictionary(uniqueKeysWithValues: retained.map { ($0.peripheralIdentifier, $0) })
  }

  private func processAlerts(for device: BLEDeviceSnapshot) {
    let now = Date()
    for rule in alertRules where AlertMatcher.matches(rule: rule, device: device) {
      if rule.notifyOncePerSession && notifiedRulesForSession.contains(rule.id) { continue }
      if let last = notificationHistory[rule.id], now.timeIntervalSince(last) < rule.cooldownSeconds
      {
        continue
      }

      notificationHistory[rule.id] = now
      notifiedRulesForSession.insert(rule.id)
      notificationService.notify(rule: rule, device: device)
    }
  }
}

extension ScanCoordinator: BluetoothScannerDelegate {
  func bluetoothScannerDidChangeState(_ scanner: BluetoothScanner) {
    guard state.isRunning else {
      delegate?.scanCoordinatorDidChangeState(self)
      return
    }

    if scanner.state == .poweredOn {
      switch state {
      case .waitingForBluetooth(.active):
        let duration = settingsStore.settings.activeScanDuration
        let start = Date()
        state = .active(startedAt: start, endsAt: start.addingTimeInterval(duration))
        scanner.startScanning()
        scheduleStateTimer(after: duration) { [weak self] in self?.stop(reason: .timerCompleted) }

      case .waitingForBluetooth(.recording):
        guard let session = activeSession else { return }
        state = .recording(startedAt: session.startedAt, sessionID: session.id, isBurstActive: true)
        beginRecordingBurst()

      default:
        break
      }
    } else if scanner.state == .poweredOff || scanner.state == .unauthorized
      || scanner.state == .unsupported
    {
      delegate?.scanCoordinator(self, didEncounter: bluetoothMessage(for: scanner.state))
      stop(reason: .bluetoothUnavailable)
    }
  }

  func bluetoothScanner(
    _ scanner: BluetoothScanner,
    didDiscover peripheral: CBPeripheral,
    advertisement: BLEAdvertisement,
    rssi: Int,
    timestamp: Date
  ) {
    guard rssi >= settingsStore.settings.minimumRSSI else { return }

    let name = peripheral.name ?? advertisement.localName ?? "Unnamed device"
    var snapshot =
      snapshots[peripheral.identifier]
      ?? BLEDeviceSnapshot(
        peripheralIdentifier: peripheral.identifier,
        displayName: name,
        latestRSSI: rssi,
        strongestRSSI: rssi,
        firstSeen: timestamp,
        lastSeen: timestamp,
        sightingCount: 0,
        advertisement: advertisement
      )
    snapshot.displayName = name
    snapshot.latestRSSI = rssi
    snapshot.strongestRSSI = max(snapshot.strongestRSSI, rssi)
    snapshot.lastSeen = timestamp
    snapshot.sightingCount += 1
    snapshot.advertisement = advertisement
    snapshots[peripheral.identifier] = snapshot
    snapshots = Self.pruneSnapshots(snapshots, now: timestamp)
    scanner.trimCachedPeripherals(to: Set(snapshots.keys))
    delegate?.scanCoordinator(self, didUpdate: devices)
    processAlerts(for: snapshot)

    guard case .recording = state, var session = activeSession else { return }
    let location = locationProvider.currentLocation
    let detection = BLEDetection(
      id: UUID(),
      sessionID: session.id,
      peripheralIdentifier: peripheral.identifier,
      displayName: name,
      rssi: rssi,
      timestamp: timestamp,
      latitude: location?.coordinate.latitude,
      longitude: location?.coordinate.longitude,
      horizontalAccuracy: location?.horizontalAccuracy,
      advertisement: advertisement
    )

    do {
      try store.appendDetection(detection)
      session.detectionCount += 1
      sessionUniqueIDs.insert(peripheral.identifier)
      session.uniqueDeviceCount = sessionUniqueIDs.count
      activeSession = session
      if session.detectionCount.isMultiple(of: 25) {
        try store.updateSession(session)
      }
    } catch {
      delegate?.scanCoordinator(self, didEncounter: "A detection could not be written to storage.")
    }
  }

  private func bluetoothMessage(for state: CBManagerState) -> String {
    switch state {
    case .poweredOff: return "Bluetooth is turned off."
    case .unauthorized: return "Bluetooth access is not authorised. Enable it in Settings."
    case .unsupported: return "Bluetooth Low Energy is not supported on this device."
    case .resetting: return "Bluetooth is resetting."
    default: return "Bluetooth is not currently available."
    }
  }
}
