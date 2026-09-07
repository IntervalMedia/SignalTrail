import Foundation
import CoreLocation

// MARK: - Bluetooth evidence

enum BluetoothEvidenceProvenance: String, Codable, Hashable {
    case deviceReported
}

struct GATTDecodedField: Codable, Hashable {
    let name: String
    let value: String
}

struct GATTAppearance: Codable, Hashable {
    let rawValue: UInt16
    let categoryName: String
    let subcategoryName: String?

    var displayName: String {
        subcategoryName ?? categoryName
    }
}

struct GATTPnPIdentifier: Codable, Hashable {
    enum VendorIDSource: UInt8, Codable, Hashable {
        case bluetoothSIG = 1
        case usbImplementersForum = 2

        var displayName: String {
            switch self {
            case .bluetoothSIG: return "Bluetooth SIG Company Identifier"
            case .usbImplementersForum: return "USB Implementers Forum"
            }
        }
    }

    let vendorIDSource: VendorIDSource?
    let rawVendorIDSource: UInt8
    let vendorID: UInt16
    let productID: UInt16
    let productVersion: UInt16
}

struct GATTDecodedValue: Codable, Hashable {
    let displayText: String
    let rawHex: String
    let fields: [GATTDecodedField]
    let provenance: BluetoothEvidenceProvenance
    let warning: String?
    let appearance: GATTAppearance?
    let pnpIdentifier: GATTPnPIdentifier?

    init(
        displayText: String,
        rawHex: String,
        fields: [GATTDecodedField],
        provenance: BluetoothEvidenceProvenance = .deviceReported,
        warning: String? = nil,
        appearance: GATTAppearance? = nil,
        pnpIdentifier: GATTPnPIdentifier? = nil
    ) {
        self.displayText = displayText
        self.rawHex = rawHex
        self.fields = fields
        self.provenance = provenance
        self.warning = warning
        self.appearance = appearance
        self.pnpIdentifier = pnpIdentifier
    }
}

struct GATTDeviceIdentity: Codable, Hashable {
    var deviceName: String?
    var manufacturerName: String?
    var modelNumber: String?
    var serialNumber: String?
    var firmwareRevision: String?
    var hardwareRevision: String?
    var softwareRevision: String?
    var systemID: String?
    var pnpIdentifier: GATTPnPIdentifier?
    var appearance: GATTAppearance?

    var hasValues: Bool {
        deviceName != nil
            || manufacturerName != nil
            || modelNumber != nil
            || serialNumber != nil
            || firmwareRevision != nil
            || hardwareRevision != nil
            || softwareRevision != nil
            || systemID != nil
            || pnpIdentifier != nil
            || appearance != nil
    }
}

struct GATTDeviceEvidence: Codable, Hashable {
    var identity = GATTDeviceIdentity()
    var discoveredServiceUUIDs: [String] = []

    var hasValues: Bool {
        identity.hasValues || !discoveredServiceUUIDs.isEmpty
    }

    mutating func setDiscoveredServiceUUIDs(_ uuids: [String]) {
        discoveredServiceUUIDs = Array(Set(uuids.map { $0.uppercased() })).sorted()
    }
}

// MARK: - Scan domain

enum ScanMode: String, Codable, CaseIterable {
    case active
    case recording

    var title: String {
        switch self {
        case .active: return "Quick Scan"
        case .recording: return "Record Session"
        }
    }

    var description: String {
        switch self {
        case .active: return "Temporarily discover nearby BLE devices."
        case .recording: return "Save repeated observations with the phone's location."
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

    var metadataTag: String {
        let companyComponent = companyIdentifier.map { String(format: "%04X", $0) } ?? ""
        let serviceDataComponents = serviceData.keys.sorted().map { key in
            "\(key)=\(serviceData[key] ?? "")"
        }
        let components = [
            localName ?? "",
            manufacturerDataHex ?? "",
            companyComponent,
            memberServiceUUIDs.sorted().joined(separator: ","),
            serviceUUIDs.sorted().joined(separator: ","),
            solicitedServiceUUIDs.sorted().joined(separator: ","),
            serviceDataComponents.joined(separator: ","),
            overflowServiceUUIDs.sorted().joined(separator: ","),
            txPower.map { String($0) } ?? "",
            isConnectable ? "1" : "0",
        ]

        return components.joined(separator: "|")
    }
}

struct DeviceLocationMetadata: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double?
    let timestamp: Date

    init(latitude: Double, longitude: Double, horizontalAccuracy: Double? = nil, timestamp: Date = Date()) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }
}

struct DeviceRSSISample: Codable, Hashable {
    let timestamp: Date
    let rssi: Int

    init(timestamp: Date = Date(), rssi: Int) {
        self.timestamp = timestamp
        self.rssi = rssi
    }
}

struct BLEDeviceSnapshot: Codable, Hashable, Identifiable {
    var id: UUID { peripheralIdentifier }
    let peripheralIdentifier: UUID
    var displayName: String
    var customName: String?
    var latestRSSI: Int
    var strongestRSSI: Int
    var firstSeen: Date
    var lastSeen: Date
    var lastSeenMetadataTag: String = ""
    var sightingCount: Int
    var advertisement: BLEAdvertisement
    var gattEvidence: GATTDeviceEvidence? = nil
    var exploredServices: [GATTServiceSnapshot] = []
    var lastLocation: DeviceLocationMetadata? = nil
    var rssiHistory: [DeviceRSSISample] = []

    var signalLevel: SignalLevel { SignalLevel(rssi: latestRSSI) }

    init(
        peripheralIdentifier: UUID,
        displayName: String,
        customName: String? = nil,
        latestRSSI: Int,
        strongestRSSI: Int,
        firstSeen: Date,
        lastSeen: Date,
        lastSeenMetadataTag: String = "",
        sightingCount: Int,
        advertisement: BLEAdvertisement,
        gattEvidence: GATTDeviceEvidence? = nil,
        exploredServices: [GATTServiceSnapshot] = [],
        lastLocation: DeviceLocationMetadata? = nil,
        rssiHistory: [DeviceRSSISample] = []
    ) {
        self.peripheralIdentifier = peripheralIdentifier
        self.displayName = displayName
        self.customName = customName
        self.latestRSSI = latestRSSI
        self.strongestRSSI = strongestRSSI
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.lastSeenMetadataTag = lastSeenMetadataTag
        self.sightingCount = sightingCount
        self.advertisement = advertisement
        self.gattEvidence = gattEvidence
        self.exploredServices = exploredServices
        self.lastLocation = lastLocation
        self.rssiHistory = rssiHistory
    }

    private enum CodingKeys: String, CodingKey {
        case peripheralIdentifier
        case displayName
        case customName
        case latestRSSI
        case strongestRSSI
        case firstSeen
        case lastSeen
        case lastSeenMetadataTag
        case sightingCount
        case advertisement
        case gattEvidence
        case exploredServices
        case lastLocation
        case rssiHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        peripheralIdentifier = try container.decode(UUID.self, forKey: .peripheralIdentifier)
        displayName = try container.decode(String.self, forKey: .displayName)
        customName = try container.decodeIfPresent(String.self, forKey: .customName)
        latestRSSI = try container.decode(Int.self, forKey: .latestRSSI)
        strongestRSSI = try container.decode(Int.self, forKey: .strongestRSSI)
        firstSeen = try container.decode(Date.self, forKey: .firstSeen)
        lastSeen = try container.decode(Date.self, forKey: .lastSeen)
        lastSeenMetadataTag = try container.decodeIfPresent(String.self, forKey: .lastSeenMetadataTag) ?? ""
        sightingCount = try container.decode(Int.self, forKey: .sightingCount)
        advertisement = try container.decode(BLEAdvertisement.self, forKey: .advertisement)
        gattEvidence = try container.decodeIfPresent(GATTDeviceEvidence.self, forKey: .gattEvidence)
        exploredServices = try container.decodeIfPresent([GATTServiceSnapshot].self, forKey: .exploredServices) ?? []
        lastLocation = try container.decodeIfPresent(DeviceLocationMetadata.self, forKey: .lastLocation)
        rssiHistory = try container.decodeIfPresent([DeviceRSSISample].self, forKey: .rssiHistory) ?? []
    }
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

enum BLEDetectorProfile: String, Codable, CaseIterable {
    case axonTaser
    case appleFindMyOfflineFinding
    case flipperZero
    case flockPenguinBattery
    case serialBluetoothModuleSkimmer
    case metaSmartGlasses

    var title: String {
        switch self {
        case .axonTaser:
            return "Axon / TASER"
        case .appleFindMyOfflineFinding:
            return "Apple Find My Offline Finding"
        case .flipperZero:
            return "Flipper Zero"
        case .flockPenguinBattery:
            return "Flock / Penguin battery"
        case .serialBluetoothModuleSkimmer:
            return "HC serial-module / possible skimmer"
        case .metaSmartGlasses:
            return "Meta / Ray-Ban smart glasses"
        }
    }

    var guidance: String {
        switch self {
        case .axonTaser:
            return "Matches company ID 034D or advertised service FC81. This suggests an Axon/TASER device family, not a verified camera or weapon model."
        case .appleFindMyOfflineFinding:
            return "Matches Apple manufacturer data beginning 4C001219. This identifies Find My-shaped broadcasts, not authenticated AirTags."
        case .flipperZero:
            return "Matches advertised 16-bit service UUIDs 3081, 3082, or 3083."
        case .flockPenguinBattery:
            return "Matches XUNTONG manufacturer ID 09C8 with the Penguin battery naming patterns used by ESP32Marauder."
        case .serialBluetoothModuleSkimmer:
            return "Matches the exact advertised names HC-03, HC-05, or HC-06. These modules are common and are not proof of a payment-card skimmer."
        case .metaSmartGlasses:
            return "Matches Luxottica manufacturer data 530D together with advertised service FD5F, or a name containing Ray-Ban, Wayfarer, or Oakley Meta. These are unverified device claims."
        }
    }
}

enum AlertMatchType: String, Codable, CaseIterable {
    case peripheralIdentifier
    case companyIdentifier
    case companyName
    case localNameContains
    case manufacturerPrefix
    case memberServiceName
    case serviceUUID
    case detectorProfile

    var title: String {
        switch self {
        case .peripheralIdentifier: return "Device identifier"
        case .companyIdentifier: return "Company identifier"
        case .companyName: return "Company ID assignee"
        case .localNameContains: return "Name contains"
        case .manufacturerPrefix: return "Manufacturer prefix"
        case .memberServiceName: return "Member UUID assignee"
        case .serviceUUID: return "Service UUID"
        case .detectorProfile: return "Built-in BLE detector"
        }
    }

    var guidance: String {
        switch self {
        case .peripheralIdentifier:
            return "Use the app-scoped UUID shown by iOS. Hardware BLE MAC addresses are unavailable."
        case .companyIdentifier:
            return "Enter a Bluetooth SIG company identifier in hexadecimal, for example 004C for Apple. Manufacturer data must be advertised."
        case .companyName:
            return "Exact case-insensitive match against the Bluetooth SIG assignee of the company identifier in manufacturer data. This does not authenticate the device maker."
        case .localNameContains:
            return "Case-insensitive partial match against the advertised or peripheral name."
        case .manufacturerPrefix:
            return "Hexadecimal prefix match against manufacturer data, including the company identifier bytes."
        case .memberServiceName:
            return "Exact case-insensitive match against the assignee of a Bluetooth SIG 16-bit member UUID. Assignment does not authenticate the device maker."
        case .serviceUUID:
            return "Exact case-insensitive advertised service UUID match."
        case .detectorProfile:
            return "Enter a built-in detector identifier. Detector profiles support compound checks that cannot be represented by a single prefix or name."
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
        case .detectorProfile:
            return BLEDetectorProfile.appleFindMyOfflineFinding.rawValue
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
    var isAutomaticGATTEnrichmentEnabled: Bool = true
    var recordingBurstDuration: TimeInterval = 1
    var recordingPauseDuration: TimeInterval = 5
    var minimumRSSI: Int = -100
    var keepScreenAwakeDuringRecording = true
    var requestNotificationPermissionOnRuleCreation = true
    var isHunterSoundEnabled = true
    var hunterAlertTone: HunterAlertTone = .sonar
    var hunterHapticStyle: HunterHapticStyle = .medium

    static let `default` = AppSettings()

    init(
        activeScanDuration: TimeInterval = 120,
        isAutomaticGATTEnrichmentEnabled: Bool = true,
        recordingBurstDuration: TimeInterval = 1,
        recordingPauseDuration: TimeInterval = 5,
        minimumRSSI: Int = -100,
        keepScreenAwakeDuringRecording: Bool = true,
        requestNotificationPermissionOnRuleCreation: Bool = true,
        isHunterSoundEnabled: Bool = true,
        hunterAlertTone: HunterAlertTone = .sonar,
        hunterHapticStyle: HunterHapticStyle = .medium
    ) {
        self.activeScanDuration = activeScanDuration
        self.isAutomaticGATTEnrichmentEnabled = isAutomaticGATTEnrichmentEnabled
        self.recordingBurstDuration = recordingBurstDuration
        self.recordingPauseDuration = recordingPauseDuration
        self.minimumRSSI = minimumRSSI
        self.keepScreenAwakeDuringRecording = keepScreenAwakeDuringRecording
        self.requestNotificationPermissionOnRuleCreation = requestNotificationPermissionOnRuleCreation
        self.isHunterSoundEnabled = isHunterSoundEnabled
        self.hunterAlertTone = hunterAlertTone
        self.hunterHapticStyle = hunterHapticStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeScanDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .activeScanDuration) ?? 120
        isAutomaticGATTEnrichmentEnabled = try container.decodeIfPresent(Bool.self, forKey: .isAutomaticGATTEnrichmentEnabled) ?? true
        recordingBurstDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .recordingBurstDuration) ?? 1
        recordingPauseDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .recordingPauseDuration) ?? 5
        minimumRSSI = try container.decodeIfPresent(Int.self, forKey: .minimumRSSI) ?? -100
        keepScreenAwakeDuringRecording = try container.decodeIfPresent(Bool.self, forKey: .keepScreenAwakeDuringRecording) ?? true
        requestNotificationPermissionOnRuleCreation = try container.decodeIfPresent(Bool.self, forKey: .requestNotificationPermissionOnRuleCreation) ?? true
        isHunterSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .isHunterSoundEnabled) ?? true
        hunterAlertTone = try container.decodeIfPresent(HunterAlertTone.self, forKey: .hunterAlertTone) ?? .sonar
        hunterHapticStyle = try container.decodeIfPresent(HunterHapticStyle.self, forKey: .hunterHapticStyle) ?? .medium
    }
}

enum HunterAlertTone: String, Codable, CaseIterable {
    case sonar
    case deepPing
    case brightPing

    var title: String {
        switch self {
        case .sonar: return "Sonar"
        case .deepPing: return "Deep ping"
        case .brightPing: return "Bright ping"
        }
    }
}

enum HunterHapticStyle: String, Codable, CaseIterable {
    case off
    case light
    case medium
    case heavy

    var title: String { rawValue.capitalized }
}

// MARK: - GATT

struct GATTCharacteristicSnapshot: Codable, Hashable {
    let uuid: String
    let properties: [String]
    var valueHex: String?
    var decodedValue: GATTDecodedValue? = nil
    var descriptors: [GATTDescriptorSnapshot] = []
    var isNotifying: Bool
}

struct GATTDescriptorSnapshot: Codable, Hashable {
    let uuid: String
    var displayValue: String?
    var rawHex: String?
}

struct GATTServiceSnapshot: Codable, Hashable {
    let uuid: String
    var characteristics: [GATTCharacteristicSnapshot]
}
