import Foundation
import CoreLocation

// MARK: - Scan domain

enum ScanMode: String, Codable, CaseIterable {
    case active
    case recording

    var title: String {
        switch self {
        case .active: return "Active"
        case .recording: return "Record"
        }
    }
}

enum ScanStopReason: String {
    case user
    case timerCompleted
    case enteredBackground
    case bluetoothUnavailable
}

struct BLEAdvertisement: Codable, Hashable {
    var localName: String?
    var manufacturerDataHex: String?
    var companyIdentifier: UInt16?
    var memberServiceUUIDs: [String] = []
    var serviceUUIDs: [String]
    var solicitedServiceUUIDs: [String]
    var serviceData: [String: String]
    var overflowServiceUUIDs: [String]
    var txPower: Int?
    var isConnectable: Bool

    static let empty = BLEAdvertisement(
        localName: nil,
        manufacturerDataHex: nil,
        companyIdentifier: nil,
        memberServiceUUIDs: [],
        serviceUUIDs: [],
        solicitedServiceUUIDs: [],
        serviceData: [:],
        overflowServiceUUIDs: [],
        txPower: nil,
        isConnectable: false
    )
}

struct BLEDeviceSnapshot: Hashable {
    let peripheralIdentifier: UUID
    var displayName: String
    var latestRSSI: Int
    var strongestRSSI: Int
    var firstSeen: Date
    var lastSeen: Date
    var sightingCount: Int
    var advertisement: BLEAdvertisement

    var signalLevel: SignalLevel { SignalLevel(rssi: latestRSSI) }
}

enum SignalLevel: String, Codable {
    case excellent
    case good
    case fair
    case weak
    case unknown

    init(rssi: Int) {
        switch rssi {
        case -55...0: self = .excellent
        case -67 ... -56: self = .good
        case -79 ... -68: self = .fair
        case -100 ... -80: self = .weak
        default: self = .unknown
        }
    }

    var title: String { rawValue.capitalized }
}

struct BLEDetection: Codable, Hashable, Identifiable {
    let id: UUID
    let sessionID: UUID
    let peripheralIdentifier: UUID
    let displayName: String
    let rssi: Int
    let timestamp: Date
    let latitude: Double?
    let longitude: Double?
    let horizontalAccuracy: Double?
    let advertisement: BLEAdvertisement

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude = latitude, let longitude = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ScanSession: Codable, Hashable, Identifiable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var mode: ScanMode
    var name: String
    var detectionCount: Int
    var uniqueDeviceCount: Int
    /// IANA time-zone identifier recorded at the moment the session started.
    /// Older sessions decoded without this key return `nil`; callers fall back to the device's current zone.
    var timeZoneIdentifier: String?

    var duration: TimeInterval {
        max(0, (endedAt ?? Date()).timeIntervalSince(startedAt))
    }

    /// The time zone in which this session was recorded, falling back to the device's current zone.
    var timeZone: TimeZone {
        timeZoneIdentifier.flatMap { TimeZone(identifier: $0) } ?? .current
    }
}

// MARK: - Saved devices and matching

struct KnownDevice: Codable, Hashable, Identifiable {
    let id: UUID
    var peripheralIdentifier: UUID
    var nickname: String
    var lastKnownName: String
    var companyIdentifier: UInt16?
    var manufacturerPrefixHex: String?
    var notes: String
    var createdAt: Date
    var lastSeenAt: Date?
}

enum AlertMatchType: String, Codable, CaseIterable {
    case peripheralIdentifier
    case companyIdentifier
    case companyName
    case localNameContains
    case manufacturerPrefix
    case memberServiceName
    case serviceUUID

    var title: String {
        switch self {
        case .peripheralIdentifier: return "Device identifier"
        case .companyIdentifier: return "Company identifier"
        case .companyName: return "Company name"
        case .localNameContains: return "Name contains"
        case .manufacturerPrefix: return "Manufacturer prefix"
        case .memberServiceName: return "Member UUID name"
        case .serviceUUID: return "Service UUID"
        }
    }

    var guidance: String {
        switch self {
        case .peripheralIdentifier:
            return "Use the app-scoped UUID shown by iOS. Hardware BLE MAC addresses are unavailable."
        case .companyIdentifier:
            return "Enter a Bluetooth SIG company identifier in hexadecimal, for example 004C for Apple. Manufacturer data must be advertised."
        case .companyName:
            return "Exact case-insensitive match against the Bluetooth SIG company name derived from manufacturer data."
        case .localNameContains:
            return "Case-insensitive partial match against the advertised or peripheral name."
        case .manufacturerPrefix:
            return "Hexadecimal prefix match against manufacturer data, including the company identifier bytes."
        case .memberServiceName:
            return "Exact case-insensitive match against derived Bluetooth SIG 16-bit member UUID names in the advertisement."
        case .serviceUUID:
            return "Exact case-insensitive advertised service UUID match."
        }
    }

    var exampleValue: String {
        switch self {
        case .peripheralIdentifier:
            return "11111111-2222-3333-4444-555555555555"
        case .companyIdentifier:
            return "004C"
        case .companyName:
            return "Apple, Inc."
        case .localNameContains:
            return "apple"
        case .manufacturerPrefix:
            return "4C000215"
        case .memberServiceName:
            return "Apple, Inc."
        case .serviceUUID:
            return "180F"
        }
    }

    var usesCompanyPicker: Bool {
        self == .companyIdentifier || self == .companyName
    }
}

struct AlertRuleMatch: Codable, Hashable {
    var matchType: AlertMatchType
    var matchValue: String

    var summary: String {
        let value = matchValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "\(matchType.title): No value" }
        return "\(matchType.title): \(value)"
    }
}

enum AlertRuleMatchMode: String, Codable, CaseIterable {
    case any
    case all

    var title: String {
        switch self {
        case .any: return "Match Any"
        case .all: return "Match All"
        }
    }

    var shortTitle: String {
        switch self {
        case .any: return "Any"
        case .all: return "All"
        }
    }
}

struct AlertRule: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var matchType: AlertMatchType
    var matchValue: String
    var additionalMatches: [AlertRuleMatch] = []
    var matchMode: AlertRuleMatchMode = .any
    var isEnabled: Bool
    var notifyOncePerSession: Bool
    var cooldownSeconds: TimeInterval

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case matchType
        case matchValue
        case additionalMatches
        case matchMode
        case isEnabled
        case notifyOncePerSession
        case cooldownSeconds
    }

    init(
        id: UUID,
        name: String,
        matchType: AlertMatchType,
        matchValue: String,
        additionalMatches: [AlertRuleMatch] = [],
        matchMode: AlertRuleMatchMode = .any,
        isEnabled: Bool,
        notifyOncePerSession: Bool,
        cooldownSeconds: TimeInterval
    ) {
        self.id = id
        self.name = name
        self.matchType = matchType
        self.matchValue = matchValue
        self.additionalMatches = additionalMatches
        self.matchMode = matchMode
        self.isEnabled = isEnabled
        self.notifyOncePerSession = notifyOncePerSession
        self.cooldownSeconds = cooldownSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        matchType = try container.decode(AlertMatchType.self, forKey: .matchType)
        matchValue = try container.decode(String.self, forKey: .matchValue)
        additionalMatches = try container.decodeIfPresent([AlertRuleMatch].self, forKey: .additionalMatches) ?? []
        matchMode = try container.decodeIfPresent(AlertRuleMatchMode.self, forKey: .matchMode) ?? .any
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        notifyOncePerSession = try container.decode(Bool.self, forKey: .notifyOncePerSession)
        cooldownSeconds = try container.decode(TimeInterval.self, forKey: .cooldownSeconds)
    }

    var criteria: [AlertRuleMatch] {
        [AlertRuleMatch(matchType: matchType, matchValue: matchValue)] + additionalMatches
    }

    mutating func replaceCriteria(with criteria: [AlertRuleMatch]) {
        guard let first = criteria.first else { return }
        matchType = first.matchType
        matchValue = first.matchValue
        additionalMatches = Array(criteria.dropFirst())
    }

    var matchSummary: String {
        let criteria = self.criteria
        guard let primary = criteria.first else { return "No criteria" }
        guard criteria.count > 1 else { return primary.summary }
        let noun = criteria.count == 2 ? "criterion" : "criteria"
        return "\(matchMode.shortTitle) of \(criteria.count) \(noun): \(primary.summary)"
    }
}

struct AppSettings: Codable, Equatable {
    var activeScanDuration: TimeInterval = 120
    var recordingBurstDuration: TimeInterval = 8
    var recordingPauseDuration: TimeInterval = 12
    var minimumRSSI: Int = -100
    var keepScreenAwakeDuringRecording = true
    var requestNotificationPermissionOnRuleCreation = true

    static let `default` = AppSettings()
}

// MARK: - GATT

struct GATTCharacteristicSnapshot: Hashable {
    let uuid: String
    let properties: [String]
    var valueHex: String?
    var isNotifying: Bool
}

struct GATTServiceSnapshot: Hashable {
    let uuid: String
    var characteristics: [GATTCharacteristicSnapshot]
}
