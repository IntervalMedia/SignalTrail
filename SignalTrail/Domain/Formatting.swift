import Foundation

extension DateFormatter {
    static func wallClock(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        formatter.timeZone = timeZone
        return formatter
    }

    static let signalTrailList: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let signalTrailTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()
}

extension TimeInterval {
    var clockString: String {
        let total = max(0, Int(self.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension Data {
    var hexadecimalString: String {
        map { String(format: "%02X", $0) }.joined()
    }

    init?(hexadecimalString: String) {
        let cleaned = hexadecimalString
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ":", with: "")
            .uppercased()
        guard cleaned.count.isMultiple(of: 2) else { return nil }

        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}

extension String {
    var normalizedHex: String {
        replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ":", with: "")
            .uppercased()
    }
}

// MARK: - Device intelligence

enum DeviceCategory: String, Codable, CaseIterable {
    case tracker
    case mobilePhone
    case smartWatch
    case computer
    case television
    case audio
    case smartHome
    case camera
    case printer
    case vehicle
    case healthFitness
    case peripheral
    case developmentTool
    case consumerElectronics
    case unknown

    var title: String {
        switch self {
        case .tracker: return "Tracker / beacon"
        case .mobilePhone: return "Mobile phone"
        case .smartWatch: return "Smart watch / wearable"
        case .computer: return "Laptop / computer"
        case .television: return "Smart TV / media device"
        case .audio: return "Headphones / audio"
        case .smartHome: return "IoT / smart home"
        case .camera: return "Camera / security device"
        case .printer: return "Printer"
        case .vehicle: return "Vehicle / automotive"
        case .healthFitness: return "Health / fitness device"
        case .peripheral: return "Computer accessory"
        case .developmentTool: return "Developer / security tool"
        case .consumerElectronics: return "Consumer electronics"
        case .unknown: return "Unknown device type"
        }
    }
}

enum IntelligenceEvidenceKind: String, Codable {
    case detectorProfile
    case advertisedName
    case serviceUUID
    case manufacturer
}

struct IntelligenceEvidence: Codable, Hashable {
    let kind: IntelligenceEvidenceKind
    let description: String
    let weight: Int
}

struct DeviceIntelligence: Codable, Hashable {
    let category: DeviceCategory
    let probability: Int
    let manufacturer: String?
    let modelFamily: String?
    let detectorMatches: [BLEDetectorProfile]
    let evidence: [IntelligenceEvidence]

    var categoryTitle: String { category.title }
    var confidenceLabel: String {
        category == .unknown ? "Unknown" : "Estimated \(probability)%"
    }
    var disclaimer: String {
        "This category is inferred from advertised BLE data and may be wrong."
    }
}

struct DeviceIntelligenceEngine {
    private struct Candidate {
        let category: DeviceCategory
        let score: Int
        let evidence: IntelligenceEvidence
        let modelFamily: String?
    }

    func analyze(_ advertisement: BLEAdvertisement) -> DeviceIntelligence {
        let detectorMatches = BLEDetectorProfile.allCases.filter {
            BLEAdvertisementDetector.matches(profile: $0, advertisement: advertisement)
        }
        let manufacturer = advertisement.companyIdentifier.map {
            BluetoothCompanyLookup.displayName(for: $0)
        }
        let services = BLEAdvertisementDetector.serviceIdentifiers(in: advertisement)
        let normalizedName = (advertisement.localName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        var candidates: [Candidate] = []
        func add(
            _ category: DeviceCategory,
            score: Int,
            kind: IntelligenceEvidenceKind,
            description: String,
            modelFamily: String? = nil
        ) {
            candidates.append(Candidate(
                category: category,
                score: score,
                evidence: IntelligenceEvidence(kind: kind, description: description, weight: score),
                modelFamily: modelFamily
            ))
        }
        func nameContains(_ terms: [String]) -> Bool {
            terms.contains { normalizedName.contains($0) }
        }

        for profile in detectorMatches {
            switch profile {
            case .appleFindMyOfflineFinding:
                add(.tracker, score: 97, kind: .detectorProfile,
                    description: "Apple Find My Offline Finding payload", modelFamily: "Find My accessory")
            case .flipperZero:
                add(.developmentTool, score: 98, kind: .detectorProfile,
                    description: "Flipper Zero service UUID", modelFamily: "Flipper Zero")
            case .flockPenguinBattery:
                add(.camera, score: 90, kind: .detectorProfile,
                    description: "Flock/Penguin battery signature", modelFamily: "Flock camera accessory")
            case .serialBluetoothModuleSkimmer:
                add(.developmentTool, score: 66, kind: .detectorProfile,
                    description: "HC serial Bluetooth module name", modelFamily: "HC serial module")
            case .metaSmartGlasses:
                add(.smartWatch, score: 94, kind: .detectorProfile,
                    description: "Meta smart-glasses identifier", modelFamily: "Meta / Ray-Ban smart glasses")
            }
        }

        let nameRules: [(DeviceCategory, Int, [String], String)] = [
            (.mobilePhone, 88, ["iphone", "pixel", "galaxy s", "phone", "oneplus", "moto "], "Phone-like advertised name"),
            (.smartWatch, 87, ["watch", "fitbit", "garmin", "wear", "band"], "Wearable-like advertised name"),
            (.computer, 86, ["macbook", "laptop", "notebook", "surface", "thinkpad", "chromebook", "windows pc"], "Computer-like advertised name"),
            (.television, 89, ["tv", "chromecast", "fire tv", "roku", "shield", "appletv", "apple tv"], "TV/media-like advertised name"),
            (.audio, 90, ["airpods", "earbuds", "buds", "headphone", "speaker", "soundbar", "bose", "jbl"], "Audio-like advertised name"),
            (.camera, 86, ["camera", "doorbell", "ring", "arlo", "nest cam", "wyze", "reolink"], "Camera-like advertised name"),
            (.printer, 87, ["printer", "epson", "brother", "laserjet", "deskjet", "canon "], "Printer-like advertised name"),
            (.vehicle, 81, ["tesla", "car", "vehicle", "bmw", "mercedes", "toyota", "ford "], "Automotive-like advertised name"),
            (.smartHome, 77, ["bulb", "light", "plug", "switch", "thermostat", "sensor", "home", "tuya", "hue", "matter"], "Smart-home-like advertised name")
        ]
        for rule in nameRules where nameContains(rule.2) {
            add(rule.0, score: rule.1, kind: .advertisedName, description: rule.3)
        }

        let serviceRules: [(DeviceCategory, Int, Set<UInt16>, String)] = [
            (.healthFitness, 84, [0x180D, 0x1814, 0x1816, 0x1822, 0x1826], "Fitness-related Bluetooth service"),
            (.peripheral, 82, [0x1812], "Human Interface Device service"),
            (.smartHome, 75, [0x181A, 0x181C, 0x181E, 0x1820], "Environmental or user-data service"),
            (.tracker, 78, [0xFEAA, 0xFE2C], "Beacon or tracker service identifier"),
            (.audio, 78, [0x184E, 0x1853], "Bluetooth audio service")
        ]
        for rule in serviceRules where !services.isDisjoint(with: rule.2) {
            add(rule.0, score: rule.1, kind: .serviceUUID, description: rule.3)
        }

        if candidates.isEmpty, manufacturer != nil {
            add(.consumerElectronics, score: 35, kind: .manufacturer,
                description: "Manufacturer identified, product type not identified")
        }

        guard let best = candidates.max(by: { $0.score < $1.score }) else {
            return DeviceIntelligence(
                category: .unknown,
                probability: 0,
                manufacturer: manufacturer,
                modelFamily: nil,
                detectorMatches: detectorMatches,
                evidence: []
            )
        }

        let supporting = candidates
            .filter { $0.category == best.category }
            .sorted { $0.score > $1.score }
        let corroborationBonus = min(8, max(0, supporting.count - 1) * 4)

        return DeviceIntelligence(
            category: best.category,
            probability: min(99, best.score + corroborationBonus),
            manufacturer: manufacturer,
            modelFamily: supporting.compactMap(\.modelFamily).first,
            detectorMatches: detectorMatches,
            evidence: Array(supporting.map(\.evidence).prefix(3))
        )
    }
}

extension BLEAdvertisement {
    var intelligence: DeviceIntelligence {
        DeviceIntelligenceEngine().analyze(self)
    }
}

extension BLEDeviceSnapshot {
    var intelligence: DeviceIntelligence { advertisement.intelligence }

    var presentationName: String {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty && trimmedName != "Unnamed device" { return trimmedName }

        if let localName = advertisement.localName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !localName.isEmpty {
            return localName
        }

        if let modelFamily = intelligence.modelFamily { return modelFamily }
        if intelligence.category != .unknown { return intelligence.categoryTitle }
        return "Unknown BLE device"
    }

    var signalDescription: String {
        "\(latestRSSI) dBm \(signalLevel.title.lowercased()) signal"
    }
}
