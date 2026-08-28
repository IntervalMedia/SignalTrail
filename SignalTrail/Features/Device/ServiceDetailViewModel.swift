import Foundation

struct ServiceDetailSection {
    let title: String
    let characteristics: [GATTCharacteristicSnapshot]
    let warning: String?

    init(title: String, characteristics: [GATTCharacteristicSnapshot], warning: String? = nil) {
        self.title = title
        self.characteristics = characteristics
        self.warning = warning
    }
}

enum ServiceDetailViewModel {
    static func buildSections(
        serviceUUID: String,
        characteristics: [GATTCharacteristicSnapshot]
    ) -> [ServiceDetailSection] {
        guard !characteristics.isEmpty else { return [] }
        guard let permitted = BluetoothPermittedCharacteristicsLookup
            .permittedCharacteristicUUIDs(forServiceUUIDString: serviceUUID) else {
            return [ServiceDetailSection(title: "Discovered Characteristics", characteristics: characteristics)]
        }

        let standard = characteristics.filter {
            guard let value = BluetoothAssignedUUIDLookup.canonical16BitValue(from: $0.uuid) else {
                return false
            }
            return permitted.contains(value)
        }
        let custom = characteristics.filter { !standard.contains($0) }
        var sections: [ServiceDetailSection] = []
        if !standard.isEmpty {
            sections.append(ServiceDetailSection(title: "Standard Permitted Characteristics", characteristics: standard))
        }
        if !custom.isEmpty {
            sections.append(ServiceDetailSection(title: "Additional / Custom Characteristics", characteristics: custom))
        }
        return sections
    }
}
