import Foundation

final class LocalStore {
  private static let fractionalSecondsDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let legacyDateFormatter = ISO8601DateFormatter()

  private static let defaultAlertRuleID = UUID(uuidString: "1EBFD2F7-7C89-4635-B7C2-5337B859D6AB")!
  private static let findMyAlertRuleID =
    UUID(uuidString: "38DFF939-E02B-4BA1-94DE-D189CDDB1D84")!
  private static let flipperAlertRuleID =
    UUID(uuidString: "7664741B-4E95-46FC-B7B9-AAE739E2FA43")!
  private static let flockAlertRuleID =
    UUID(uuidString: "EA8BA90A-604F-4DB0-9764-38A69CA78605")!
  private static let skimmerAlertRuleID =
    UUID(uuidString: "5691C101-C485-4A97-9B80-2029C310E4CF")!
  private static let metaSmartGlassesAlertRuleID =
    UUID(uuidString: "09A4994E-6A31-4BDB-A06E-CA55AEA5A989")!
  private static let defaultAlertSeedVersion = "2026-09-07-oui-spy-detectors-v2"
  private static let defaultAlertRules = [
    AlertRule(
      id: defaultAlertRuleID,
      name: "Axon / TASER detected",
      matchType: .detectorProfile,
      matchValue: BLEDetectorProfile.axonTaser.rawValue,
      matchMode: .any,
      isEnabled: true,
      notifyOncePerSession: true,
      cooldownSeconds: 300
    ),
    AlertRule(
      id: findMyAlertRuleID,
      name: "Apple Find My-like broadcast detected",
      matchType: .detectorProfile,
      matchValue: BLEDetectorProfile.appleFindMyOfflineFinding.rawValue,
      isEnabled: true,
      notifyOncePerSession: true,
      cooldownSeconds: 300
    ),
    AlertRule(
      id: flipperAlertRuleID,
      name: "Flipper Zero-like broadcast detected",
      matchType: .detectorProfile,
      matchValue: BLEDetectorProfile.flipperZero.rawValue,
      isEnabled: true,
      notifyOncePerSession: true,
      cooldownSeconds: 300
    ),
    AlertRule(
      id: flockAlertRuleID,
      name: "Flock / Penguin-like broadcast detected",
      matchType: .detectorProfile,
      matchValue: BLEDetectorProfile.flockPenguinBattery.rawValue,
      isEnabled: true,
      notifyOncePerSession: true,
      cooldownSeconds: 300
    ),
    AlertRule(
      id: skimmerAlertRuleID,
      name: "HC serial-module name detected",
      matchType: .detectorProfile,
      matchValue: BLEDetectorProfile.serialBluetoothModuleSkimmer.rawValue,
      isEnabled: true,
      notifyOncePerSession: true,
      cooldownSeconds: 300
    ),
    AlertRule(
      id: metaSmartGlassesAlertRuleID,
      name: "Meta / Ray-Ban-like broadcast detected",
      matchType: .detectorProfile,
      matchValue: BLEDetectorProfile.metaSmartGlasses.rawValue,
      isEnabled: true,
      notifyOncePerSession: true,
      cooldownSeconds: 300
    )
  ]

  private struct AlertSeedMigration {
    let version: Int
    let rules: [AlertRule]
  }

  private struct AlertSeedState: Codable {
    var version: Int
    var offeredRuleIDs: Set<UUID>
  }

  // Seed migrations are append-only. Existing IDs must never be reused for a
  // changed default because any rule with an offered ID belongs to the user.
  private static let defaultAlertSeedMigrations = [
    AlertSeedMigration(version: 1, rules: Array(defaultAlertRules.prefix(5))),
    AlertSeedMigration(version: 2, rules: Array(defaultAlertRules.dropFirst(5)))
  ]

  enum StoreError: LocalizedError {
    case unableToCreateDirectory

    var errorDescription: String? {
      switch self {
      case .unableToCreateDirectory: return "Unable to create the application data directory."
      }
    }
  }

  private let fileManager: FileManager
  private let rootURL: URL
  private let sessionsURL: URL
  private let devicesURL: URL
  private let knownDevicesURL: URL
  private let alertRulesURL: URL
  private let alertRuleSeedVersionURL: URL
  private let alertRuleSeedStateURL: URL
  private let encoder: JSONEncoder
  private let lineEncoder: JSONEncoder
  private let decoder: JSONDecoder
  private let lock = NSRecursiveLock()
  private let deviceQueue = DispatchQueue(label: "com.signaltrail.deviceStore", qos: .utility)

  convenience init(fileManager: FileManager = .default) throws {
    let applicationSupport = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    try self.init(
      rootURL: applicationSupport.appendingPathComponent("SignalTrail", isDirectory: true),
      fileManager: fileManager
    )
  }

  init(rootURL: URL, fileManager: FileManager = .default) throws {
    self.fileManager = fileManager
    self.rootURL = rootURL
    sessionsURL = rootURL.appendingPathComponent("sessions", isDirectory: true)
    devicesURL = rootURL.appendingPathComponent("devices", isDirectory: true)
    knownDevicesURL = rootURL.appendingPathComponent("known-devices.json")
    alertRulesURL = rootURL.appendingPathComponent("alert-rules.json")
    alertRuleSeedVersionURL = rootURL.appendingPathComponent("alert-rules-seed-version.txt")
    alertRuleSeedStateURL = rootURL.appendingPathComponent("alert-rules-seed-state.json")

    encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = Self.dateEncodingStrategy
    lineEncoder = JSONEncoder()
    lineEncoder.outputFormatting = [.sortedKeys]
    lineEncoder.dateEncodingStrategy = Self.dateEncodingStrategy
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = Self.dateDecodingStrategy

    try createDirectories()
    recoverSessionMetadata()
    try applyDefaultAlertSeedIfNeeded()
    publishWidgetSummary()
  }

  // MARK: Sessions

  func createSession(_ session: ScanSession) throws {
    lock.lock()
    defer { lock.unlock() }
    try write(session, to: metadataURL(for: session.id))
    let detections = detectionsURL(for: session.id)
    if !fileManager.fileExists(atPath: detections.path) {
      _ = fileManager.createFile(atPath: detections.path, contents: nil)
    }
    publishWidgetSummary()
  }

  func appendDetection(_ detection: BLEDetection) throws {
    lock.lock()
    defer { lock.unlock() }
    let url = detectionsURL(for: detection.sessionID)
    if !fileManager.fileExists(atPath: url.path) {
      _ = fileManager.createFile(atPath: url.path, contents: nil)
    }
    var data = try lineEncoder.encode(detection)
    data.append(0x0A)
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
  }

  func updateSession(_ session: ScanSession) throws {
    lock.lock()
    defer { lock.unlock() }
    try write(session, to: metadataURL(for: session.id))
    publishWidgetSummary()
  }

  func loadSessions() throws -> [ScanSession] {
    lock.lock()
    defer { lock.unlock() }
    let urls = try fileManager.contentsOfDirectory(at: sessionsURL, includingPropertiesForKeys: nil)
    return
      urls
      .filter { $0.lastPathComponent.hasSuffix(".session.json") }
      .compactMap { try? read(ScanSession.self, from: $0) }
      .sorted { $0.startedAt > $1.startedAt }
  }

  func loadDetections(sessionID: UUID) throws -> [BLEDetection] {
    lock.lock()
    defer { lock.unlock() }
    let url = detectionsURL(for: sessionID)
    guard fileManager.fileExists(atPath: url.path) else { return [] }
    let data = try Data(contentsOf: url)
    guard let text = String(data: data, encoding: .utf8) else { return [] }
    return
      text
      .split(separator: "\n")
      .compactMap { Data($0.utf8) }
      .compactMap { try? decoder.decode(BLEDetection.self, from: $0) }
      .sorted { $0.timestamp < $1.timestamp }
  }

  private func recoverSessionMetadata() {
    lock.lock()
    defer { lock.unlock() }

    guard
      let urls = try? fileManager.contentsOfDirectory(
        at: sessionsURL,
        includingPropertiesForKeys: nil
      )
    else { return }

    for metadataURL in urls where metadataURL.lastPathComponent.hasSuffix(".session.json") {
      guard var session = try? read(ScanSession.self, from: metadataURL) else { continue }
      let detectionURL = detectionsURL(for: session.id)
      guard
        let data = try? Data(contentsOf: detectionURL),
        let text = String(data: data, encoding: .utf8)
      else { continue }

      let detections = text
        .split(separator: "\n")
        .compactMap { try? decoder.decode(BLEDetection.self, from: Data($0.utf8)) }
        .filter { $0.sessionID == session.id }

      guard !detections.isEmpty else { continue }

      let detectionCount = detections.count
      let uniqueDeviceCount = Set(detections.map(\.peripheralIdentifier)).count
      let inferredEnd = detections.map(\.timestamp).max()
      let recoveredEnd = session.endedAt ?? inferredEnd
      guard
        session.detectionCount != detectionCount
          || session.uniqueDeviceCount != uniqueDeviceCount
          || session.endedAt != recoveredEnd
      else { continue }

      session.detectionCount = detectionCount
      session.uniqueDeviceCount = uniqueDeviceCount
      session.endedAt = recoveredEnd
      try? write(session, to: metadataURL)
    }
  }

  func deleteSession(_ session: ScanSession) throws {
    lock.lock()
    defer { lock.unlock() }
    for url in [metadataURL(for: session.id), detectionsURL(for: session.id)]
    where fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
    publishWidgetSummary()
  }

  // MARK: Known devices

  func loadKnownDevices() -> [KnownDevice] {
    lock.lock()
    defer { lock.unlock() }
    return (try? read([KnownDevice].self, from: knownDevicesURL)) ?? []
  }

  func saveKnownDevices(_ devices: [KnownDevice]) throws {
    lock.lock()
    defer { lock.unlock() }
    try write(devices, to: knownDevicesURL)
  }

  func upsertKnownDevice(_ device: KnownDevice) throws {
    var devices = loadKnownDevices()
    if let index = devices.firstIndex(where: {
      $0.id == device.id || $0.peripheralIdentifier == device.peripheralIdentifier
    }) {
      devices[index] = device
    } else {
      devices.append(device)
    }
    try saveKnownDevices(devices)
  }

  func deleteKnownDevice(_ device: KnownDevice) throws {
    try saveKnownDevices(loadKnownDevices().filter { $0.id != device.id })
  }

  // MARK: Rules

  func loadAlertRules() -> [AlertRule] {
    lock.lock()
    defer { lock.unlock() }
    return (try? read([AlertRule].self, from: alertRulesURL)) ?? []
  }

  func saveAlertRules(_ rules: [AlertRule]) throws {
    lock.lock()
    defer { lock.unlock() }
    try write(rules, to: alertRulesURL)
  }

  func upsertAlertRule(_ rule: AlertRule) throws {
    var rules = loadAlertRules()
    if let index = rules.firstIndex(where: { $0.id == rule.id }) {
      rules[index] = rule
    } else {
      rules.append(rule)
    }
    try saveAlertRules(rules)
  }

  func deleteAlertRule(_ rule: AlertRule) throws {
    try saveAlertRules(loadAlertRules().filter { $0.id != rule.id })
  }

  // MARK: Devices

  var devicesDirectoryURL: URL { devicesURL }

  func deviceRecordFileURL(for id: UUID) -> URL {
    devicesURL.appendingPathComponent("\(id.uuidString).json")
  }

  func saveDeviceRecord(_ snapshot: BLEDeviceSnapshot) throws {
    lock.lock()
    defer { lock.unlock() }
    try write(snapshot, to: deviceRecordFileURL(for: snapshot.peripheralIdentifier))
  }

  func saveDeviceRecordAsync(
    _ snapshot: BLEDeviceSnapshot,
    completion: ((Result<Void, Error>) -> Void)? = nil
  ) {
    deviceQueue.async { [weak self] in
      guard let self = self else { return }
      let result: Result<Void, Error>
      do {
        try self.saveDeviceRecord(snapshot)
        result = .success(())
      } catch {
        result = .failure(error)
      }

      if let completion {
        DispatchQueue.main.async {
          completion(result)
        }
      }
    }
  }

  func loadDeviceRecord(for id: UUID) -> BLEDeviceSnapshot? {
    lock.lock()
    defer { lock.unlock() }
    let url = deviceRecordFileURL(for: id)
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    return try? read(BLEDeviceSnapshot.self, from: url)
  }

  func loadAllDeviceRecords() -> [UUID: BLEDeviceSnapshot] {
    lock.lock()
    defer { lock.unlock() }
    guard let urls = try? fileManager.contentsOfDirectory(at: devicesURL, includingPropertiesForKeys: nil) else {
      return [:]
    }
    var records: [UUID: BLEDeviceSnapshot] = [:]
    for url in urls where url.pathExtension == "json" {
      if let snapshot = try? read(BLEDeviceSnapshot.self, from: url) {
        records[snapshot.peripheralIdentifier] = snapshot
      }
    }
    return records
  }

  func purgeDeviceRecord(for id: UUID) throws {
    lock.lock()
    defer { lock.unlock() }
    let url = deviceRecordFileURL(for: id)
    if fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
  }

  func purgeAllDeviceRecords() throws {
    lock.lock()
    defer { lock.unlock() }
    guard let urls = try? fileManager.contentsOfDirectory(at: devicesURL, includingPropertiesForKeys: nil) else {
      return
    }
    for url in urls where url.pathExtension == "json" {
      try fileManager.removeItem(at: url)
    }
  }

  // MARK: All local data

  /// Removes every file managed by the local store, then restores the empty
  /// directory structure and bundled alert-rule defaults expected at runtime.
  /// Pending asynchronous device-record writes finish before the reset begins.
  func deleteAllLocalData() throws {
    try deviceQueue.sync {
      lock.lock()
      defer { lock.unlock() }

      if fileManager.fileExists(atPath: rootURL.path) {
        try fileManager.removeItem(at: rootURL)
      }

      try createDirectories()
      try applyDefaultAlertSeedIfNeeded()
      WidgetSummaryPublisher.publish(sessions: [])
    }
  }

  // MARK: Helpers

  private func publishWidgetSummary() {
    let sessions = (try? loadSessions()) ?? []
    WidgetSummaryPublisher.publish(sessions: sessions)
  }

  private func createDirectories() throws {
    do {
      try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
      try fileManager.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
      try fileManager.createDirectory(at: devicesURL, withIntermediateDirectories: true)
    } catch {
      throw StoreError.unableToCreateDirectory
    }
  }

  private func applyDefaultAlertSeedIfNeeded() throws {
    var rules = loadAlertRules()
    var state = loadAlertSeedState(existingRules: rules)

    for migration in Self.defaultAlertSeedMigrations where migration.version > state.version {
      var existingRuleIDs = Set(rules.map(\.id))
      for rule in migration.rules where !state.offeredRuleIDs.contains(rule.id) {
        if !existingRuleIDs.contains(rule.id) {
          rules.append(rule)
          existingRuleIDs.insert(rule.id)
        }
        state.offeredRuleIDs.insert(rule.id)
      }

      // Persist rules before advancing the ledger. If the second write fails,
      // retrying is idempotent because rule IDs are stable.
      try write(rules, to: alertRulesURL)
      state.version = migration.version
      try write(state, to: alertRuleSeedStateURL)
    }

    // Keep the legacy marker for compatibility with released builds that do
    // not understand the structured ledger.
    try Self.defaultAlertSeedVersion.write(to: alertRuleSeedVersionURL, atomically: true, encoding: .utf8)
  }

  private func loadAlertSeedState(existingRules: [AlertRule]) -> AlertSeedState {
    if let state = try? read(AlertSeedState.self, from: alertRuleSeedStateURL) {
      return state
    }

    if fileManager.fileExists(atPath: alertRuleSeedVersionURL.path) {
      let legacyVersion = try? String(contentsOf: alertRuleSeedVersionURL, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let appliedMigrations = legacyVersion == Self.defaultAlertSeedVersion
        ? Self.defaultAlertSeedMigrations
        : Self.defaultAlertSeedMigrations.filter { $0.version == 1 }
      return AlertSeedState(
        version: appliedMigrations.last?.version ?? 0,
        offeredRuleIDs: Set(appliedMigrations.flatMap(\.rules).map(\.id))
      )
    }

    // A rules file without seed metadata predates migration tracking. Treat
    // every bundled ID as already offered so deleted defaults stay deleted.
    if fileManager.fileExists(atPath: alertRulesURL.path) {
      let allSeedIDs = Set(Self.defaultAlertRules.map(\.id))
      return AlertSeedState(
        version: Self.defaultAlertSeedMigrations.last?.version ?? 0,
        offeredRuleIDs: allSeedIDs.union(existingRules.map(\.id))
      )
    }

    return AlertSeedState(version: 0, offeredRuleIDs: [])
  }

  private func metadataURL(for id: UUID) -> URL {
    sessionsURL.appendingPathComponent("\(id.uuidString).session.json")
  }

  private func detectionsURL(for id: UUID) -> URL {
    sessionsURL.appendingPathComponent("\(id.uuidString).detections.jsonl")
  }

  private func write<T: Encodable>(_ value: T, to url: URL) throws {
    let data = try encoder.encode(value)
    try data.write(to: url, options: .atomic)
  }

  private func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    try decoder.decode(type, from: Data(contentsOf: url))
  }

  private static var dateEncodingStrategy: JSONEncoder.DateEncodingStrategy {
    .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(fractionalSecondsDateFormatter.string(from: date))
    }
  }

  private static var dateDecodingStrategy: JSONDecoder.DateDecodingStrategy {
    .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)

      if let date = fractionalSecondsDateFormatter.date(from: value)
        ?? legacyDateFormatter.date(from: value)
      {
        return date
      }

      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid ISO-8601 date: \(value)"
      )
    }
  }
}
