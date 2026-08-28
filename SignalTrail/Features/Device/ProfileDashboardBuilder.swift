import UIKit

enum ProfileDashboardCluster: Hashable {
    case fitnessCycling
    case environmentalSensing
    case hidAccessory
    case hearingAudio
}

struct ProfileDashboardMetric: Hashable {
    let title: String
    let value: String
    let unit: String?
    let rawHex: String?
    let iconName: String?
}

struct ProfileDashboardCard: Hashable {
    let profile: ProfileDashboardCluster
    let title: String
    let iconName: String
    let accentColor: UIColor
    let metrics: [ProfileDashboardMetric]
}

enum ProfileDashboardBuilder {
    static func buildCards(for snapshot: BLEDeviceSnapshot) -> [ProfileDashboardCard] {
        let services = Set(snapshot.exploredServices.map { canonical($0.uuid) })
        let characteristics = snapshot.exploredServices.flatMap(\.characteristics)
        var cards: [ProfileDashboardCard] = []

        if services.contains("1818") || services.contains("1816") || services.contains("180D") || services.contains("1814") {
            let metrics = metricValues(for: characteristics, ids: ["2A5D", "2A38"], title: "Sensor Location")
                + metricValues(for: characteristics, ids: ["2A65", "2A5C", "2A54"], title: "Supported Features")
                + metricValues(for: characteristics, ids: ["2A19"], title: "Battery Level", unit: "%")
            if !metrics.isEmpty { cards.append(card(.fitnessCycling, "Fitness & Cycling Dashboard", "figure.outdoor.cycle", .systemGreen, metrics)) }
        }

        if services.contains("181A") || services.contains("1809") || characteristics.contains(where: { ["2A6D", "2A6E", "2A6F"].contains(canonical($0.uuid)) }) {
            let metrics = metricValues(for: characteristics, ids: ["2A6E"], title: "Temperature", unit: "°C")
                + metricValues(for: characteristics, ids: ["2A6F"], title: "Humidity", unit: "%")
                + metricValues(for: characteristics, ids: ["2A6D"], title: "Pressure", unit: "hPa")
                + metricValues(for: characteristics, ids: ["2A6C"], title: "Elevation", unit: "m")
                + metricValues(for: characteristics, ids: ["2A19"], title: "Battery Level", unit: "%")
            if !metrics.isEmpty { cards.append(card(.environmentalSensing, "Environmental Sensing Dashboard", "thermometer.medium", .systemOrange, metrics)) }
        }

        if services.contains("1812") || snapshot.gattEvidence?.identity.appearance?.categoryName.lowercased().contains("human interface device") == true {
            var metrics: [ProfileDashboardMetric] = []
            if let appearance = snapshot.gattEvidence?.identity.appearance {
                metrics.append(ProfileDashboardMetric(title: "Input Device Type", value: appearance.displayName, unit: nil, rawHex: String(format: "%04X", appearance.rawValue), iconName: "keyboard"))
            }
            metrics += metricValues(for: characteristics, ids: ["2A4A"], title: "Capabilities")
            metrics += metricValues(for: characteristics, ids: ["2A19"], title: "Battery Level", unit: "%")
            if !metrics.isEmpty { cards.append(card(.hidAccessory, "HID Accessory Dashboard", "keyboard", .systemBlue, metrics)) }
        }

        if services.intersection(["1854", "1844", "1848"]).isEmpty == false || snapshot.gattEvidence?.identity.appearance?.categoryName.lowercased().contains("hearing aid") == true {
            let metrics = metricValues(for: characteristics, ids: ["2BDA"], title: "Hearing Aid Features")
                + metricValues(for: characteristics, ids: ["2BDC"], title: "Active Preset")
                + metricValues(for: characteristics, ids: ["2B7D"], title: "Volume Control")
                + metricValues(for: characteristics, ids: ["2BA4"], title: "Media State")
                + metricValues(for: characteristics, ids: ["2A19"], title: "Battery Level", unit: "%")
            if !metrics.isEmpty { cards.append(card(.hearingAudio, "Audio & Hearing Dashboard", "ear", .systemPurple, metrics)) }
        }
        return cards
    }

    private static func metricValues(for characteristics: [GATTCharacteristicSnapshot], ids: [String], title: String, unit: String? = nil) -> [ProfileDashboardMetric] {
        guard let characteristic = characteristics.first(where: { ids.contains(canonical($0.uuid)) }) else { return [] }
        let value = characteristic.decodedValue?.displayText ?? characteristic.valueHex ?? "N/A"
        return [ProfileDashboardMetric(title: title, value: value, unit: unit, rawHex: characteristic.valueHex ?? characteristic.decodedValue?.rawHex, iconName: nil)]
    }

    private static func card(_ profile: ProfileDashboardCluster, _ title: String, _ iconName: String, _ color: UIColor, _ metrics: [ProfileDashboardMetric]) -> ProfileDashboardCard {
        ProfileDashboardCard(profile: profile, title: title, iconName: iconName, accentColor: color, metrics: metrics)
    }

    private static func canonical(_ uuid: String) -> String {
        guard let value = BluetoothAssignedUUIDLookup.canonical16BitValue(from: uuid) else { return uuid.uppercased() }
        return String(format: "%04X", value)
    }
}
