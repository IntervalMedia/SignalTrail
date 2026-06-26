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
    /// 16-bit Bluetooth SIG member UUIDs detected in advertised service UUIDs (for example, FC81).
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
    case localNameContains
    case manufacturerPrefix
    case serviceUUID

    var title: String {
        switch self {
        case .peripheralIdentifier: return "Device identifier"
        case .companyIdentifier: return "Company identifier"
        case .localNameContains: return "Name contains"
        case .manufacturerPrefix: return "Manufacturer prefix"
        case .serviceUUID: return "Service UUID"
        }
    }
}

struct AlertRule: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var matchType: AlertMatchType
    var matchValue: String
    var isEnabled: Bool
    var notifyOncePerSession: Bool
    var cooldownSeconds: TimeInterval
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
