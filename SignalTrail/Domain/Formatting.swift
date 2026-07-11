import Foundation

extension DateFormatter {
    static func wallClock(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter(); formatter.dateStyle = .none; formatter.timeStyle = .medium; formatter.timeZone = timeZone; return formatter
    }
    static let signalTrailList: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f }()
    static let signalTrailTime: DateFormatter = { let f = DateFormatter(); f.timeStyle = .medium; return f }()
}

extension TimeInterval {
    var clockString: String {
        let total = max(0, Int(self.rounded())); let hours = total / 3600; let minutes = (total % 3600) / 60; let seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds)
    }
}

extension Data {
    var hexadecimalString: String { map { String(format: "%02X", $0) }.joined() }
    init?(hexadecimalString: String) {
        let cleaned = hexadecimalString.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ":", with: "").uppercased()
        guard cleaned.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: cleaned.count / 2); var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte); index = next
        }
        self = data
    }
}

extension String {
    var normalizedHex: String { replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ":", with: "").uppercased() }
}

enum DeviceCategory: String, Codable, CaseIterable {
    case tracker, mobilePhone, smartWatch, computer, television, audio, smartHome, camera, printer, vehicle, healthFitness, peripheral, developmentTool, consumerElectronics, unknown
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

struct DeviceClassification {
    let category: DeviceCategory
    let probability: Int
    let evidence: [String]
    let manufacturer: String?
    var title: String { category.title }
    var confidence: String { category == .unknown ? "Unknown" : "Estimated \(probability)%" }
    var disclaimer: String { "Category is an inference from advertised BLE data and may be wrong." }
}

extension BLEAdvertisement {
    var classification: DeviceClassification { DeviceCategoryClassifier.classify(self) }
}

private enum DeviceCategoryClassifier {
    private struct Candidate { let category: DeviceCategory; let score: Int; let evidence: String }

    static func classify(_ advertisement: BLEAdvertisement) -> DeviceClassification {
        var candidates: [Candidate] = []
        let name = (advertisement.localName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let services = BLEAdvertisementDetector.serviceIdentifiers(in: advertisement)
        func add(_ category: DeviceCategory, _ score: Int, _ evidence: String) { candidates.append(Candidate(category: category, score: score, evidence: evidence)) }
        func nameContains(_ terms: [String]) -> Bool { terms.contains { name.contains($0) } }

        if BLEAdvertisementDetector.matches(profile: .appleFindMyOfflineFinding, advertisement: advertisement) { add(.tracker, 97, "Apple Find My Offline Finding payload") }
        if BLEAdvertisementDetector.matches(profile: .flipperZero, advertisement: advertisement) { add(.developmentTool, 98, "Flipper service UUID") }
        if BLEAdvertisementDetector.matches(profile: .metaSmartGlasses, advertisement: advertisement) { add(.smartWatch, 94, "Meta smart-glasses identifier") }
        if BLEAdvertisementDetector.matches(profile: .flockPenguinBattery, advertisement: advertisement) { add(.camera, 90, "Flock/Penguin battery signature") }
        if BLEAdvertisementDetector.matches(profile: .serialBluetoothModuleSkimmer, advertisement: advertisement) { add(.developmentTool, 66, "HC serial Bluetooth module name") }

        if nameContains(["iphone", "pixel", "galaxy s", "phone", "oneplus", "moto "]) { add(.mobilePhone, 88, "Advertised name resembles a phone") }
        if nameContains(["watch", "fitbit", "garmin", "wear", "band"]) { add(.smartWatch, 87, "Advertised name resembles a wearable") }
        if nameContains(["macbook", "laptop", "notebook", "surface", "thinkpad", "chromebook", "windows pc"]) { add(.computer, 86, "Advertised name resembles a computer") }
        if nameContains(["tv", "chromecast", "fire tv", "roku", "shield", "appletv", "apple tv"]) { add(.television, 89, "Advertised name resembles a TV/media device") }
        if nameContains(["airpods", "earbuds", "buds", "headphone", "speaker", "soundbar", "bose", "jbl"]) { add(.audio, 90, "Advertised name resembles an audio device") }
        if nameContains(["camera", "doorbell", "ring", "arlo", "nest cam", "wyze", "reolink"]) { add(.camera, 86, "Advertised name resembles a camera") }
        if nameContains(["printer", "epson", "brother", "laserjet", "deskjet", "canon "]) { add(.printer, 87, "Advertised name resembles a printer") }
        if nameContains(["tesla", "car", "vehicle", "bmw", "mercedes", "toyota", "ford "]) { add(.vehicle, 81, "Advertised name resembles an automotive device") }
        if nameContains(["bulb", "light", "plug", "switch", "thermostat", "sensor", "home", "tuya", "hue", "matter"]) { add(.smartHome, 77, "Advertised name resembles a smart-home device") }

        if !services.isDisjoint(with: [0x180D, 0x1814, 0x1816, 0x1822, 0x1826]) { add(.healthFitness, 84, "Fitness-related Bluetooth service") }
        if services.contains(0x1812) { add(.peripheral, 82, "Human Interface Device service") }
        if !services.isDisjoint(with: [0x181A, 0x181C, 0x181E, 0x1820]) { add(.smartHome, 75, "Environmental/user-data service") }
        if !services.isDisjoint(with: [0xFEAA, 0xFE2C]) { add(.tracker, 78, "Beacon/tracker service identifier") }
        if !services.isDisjoint(with: [0x184E, 0x1853]) { add(.audio, 78, "Bluetooth audio service") }

        let manufacturer = advertisement.companyIdentifier.map { BluetoothCompanyLookup.displayName(for: $0) }
        if candidates.isEmpty, manufacturer != nil { add(.consumerElectronics, 35, "Manufacturer identified, product type not identified") }

        guard let best = candidates.max(by: { $0.score < $1.score }) else {
            return DeviceClassification(category: .unknown, probability: 0, evidence: [], manufacturer: manufacturer)
        }
        let supporting = candidates.filter { $0.category == best.category }.sorted { $0.score > $1.score }.map(\.evidence)
        let corroborationBonus = min(8, max(0, supporting.count - 1) * 4)
        return DeviceClassification(category: best.category, probability: min(99, best.score + corroborationBonus), evidence: Array(supporting.prefix(3)), manufacturer: manufacturer)
    }
}

extension BLEDeviceSnapshot {
    var presentationName: String {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty && trimmedName != "Unnamed device" { return trimmedName }
        if let localName = advertisement.localName?.trimmingCharacters(in: .whitespacesAndNewlines), !localName.isEmpty { return localName }
        let classification = advertisement.classification
        if classification.category != .unknown { return classification.title }
        return "Unknown BLE device"
    }
    var signalDescription: String { "\(latestRSSI) dBm \(signalLevel.title.lowercased()) signal" }
}
