import Foundation

final class LocalStore {
  private static let fractionalSecondsDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let legacyDateFormatter = ISO8601DateFormatter()

  private static let defaultAlertRuleID = UUID(uuidString: "1EBFD2F7-7C89-4635-B7C2-5337B859D6AB")!
  private static let defaultAlertSeedVersion = "2026-06-26-axon-taser"
  private static let defaultAlertRules = [
    AlertRule(
      id: defaultAlertRuleID,
      name: "Axon / TASER detected",
      matchType: .manufacturerPrefix,
      matchValue: "0025DF",
      additionalMatches: [
        AlertRuleMatch(
          matchType: .companyName,
          matchValue: "TASER International, Inc."
        ),
        AlertRuleMatch(
          matchType: .memberServiceName,
          matchValue: "TASER International, Inc."
        ),
        AlertRuleMatch(
          matchType: .memberServiceName,
          matchValue: "Axon Enterprise, Inc."
        ),
      ],
      matchMode: .any,
      isEnabled: true,
      notifyOncePerSession: true,
      cooldownSeconds: 300
    )
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
  private let knownDevicesURL: URL
  private let alertRulesURL: URL
  private let alertRuleSeedVersionURL: URL
  private let encoder: JSONEncoder
  private let lineEncoder: JSONEncoder
  private let decoder: JSONDecoder
  private let lock = NSRecursiveLock()

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
    knownDevicesURL = rootURL.appendingPathComponent("known-devices.json")
    alertRulesURL = rootURL.appendingPathComponent("alert-rules.json")
    alertRuleSeedVersionURL = rootURL.appendingPathComponent("alert-rules-seed-version.txt")

    encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = Self.dateEncodingStrategy
    lineEncoder = JSONEncoder()
    lineEncoder.outputFormatting = [.sortedKeys]
    lineEncoder.dateEncodingStrategy = Self.dateEncodingStrategy
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = Self.dateDecodingStrategy

    try createDirectories()
    try applyDefaultAlertSeedIfNeeded()
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

  func deleteSession(_ session: ScanSession) throws {
    lock.lock()
    defer { lock.unlock() }
    for url in [metadataURL(for: session.id), detectionsURL(for: session.id)]
    where fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
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

  // MARK: Helpers

  private func createDirectories() throws {
    do {
      try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
      try fileManager.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
    } catch {
      throw StoreError.unableToCreateDirectory
    }
  }

  private func applyDefaultAlertSeedIfNeeded() throws {
    let currentSeedVersion = try? String(contentsOf: alertRuleSeedVersionURL, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard currentSeedVersion != Self.defaultAlertSeedVersion else { return }

    var rules = loadAlertRules()
    let existingRuleIDs = Set(rules.map(\.id))
    rules.append(contentsOf: Self.defaultAlertRules.filter { !existingRuleIDs.contains($0.id) })

    try write(rules, to: alertRulesURL)
    try Self.defaultAlertSeedVersion.write(to: alertRuleSeedVersionURL, atomically: true, encoding: .utf8)
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
