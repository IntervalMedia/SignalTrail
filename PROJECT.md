# Project: SignalTrail Bluetooth SIG Device Intelligence Capabilities

## Architecture
SignalTrail is a UIKit-first iOS application for Bluetooth Low Energy (BLE) scanning, inspection, logging, and device intelligence.
The codebase is structured into clear layers:
- `App/`: Application delegate, scene wiring, coordinator bootstrapping.
- `Domain/`: Shared models (`Models.swift`), data formatting, and heuristic categorization (`Formatting.swift`, `DeviceIntelligenceEngine`).
- `Services/`:
  - `Bluetooth/`: `BluetoothScanner`, `BluetoothService`, `PeripheralInspector`, `BackgroundGATTProbe`, `ScanCoordinator`, `GATTValueDecoder`, `BluetoothAssignedUUIDLookup`, `BluetoothPermittedCharacteristicsLookup`.
  - `Persistence/`: `LocalStore`, JSON disk caching for device snapshots and sessions.
  - `Settings/`: `SettingsStore`, user preferences.
- `Features/`:
  - `Scan/`: `ScanViewController`, `ScanCoordinator`.
  - `Device/`: `DeviceDetailViewController`, `ServiceDetailViewController`, `CharacteristicViewController`, `ProfileDashboardBuilder`.
  - `Settings/`: `SettingsViewController`.
- `SignalTrailTests/`: XCTest unit testing suite covering scan coordination, intelligence classification, persistence, alert matching, and dashboard building.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | F1-SettingsToggle | `isAutomaticGATTEnrichmentEnabled` setting in `AppSettings` + UI toggle in `SettingsViewController` Section 0 | M1 | Survey R1 |
| 2 | F2-BackgroundGATTProbe | Dedicated read-only `BackgroundGATTProbe` service reading 0x180A, 0x2A00, 0x2A01, 0x2A19 with 0 writes/notifications | M1 | Survey R1 |
| 3 | F3-AutoProbeQueue | Sequential queue in `ScanCoordinator` (1 concurrent connection, 20 device cap, 5s timeout, deduplication, scan stop cancel) | M2 | Survey R1 |
| 4 | F4-LiveIntelligenceEnrichment | Dynamic snapshot, disk cache, presentation name, and classification enrichment (e.g. AppleTV14,1 -> .television) | M2 | Survey R1 |
| 5 | F5-PermittedCharacteristicsLookup | `BluetoothPermittedCharacteristicsLookup` with SIG definitions for ESS, UDS, IMDS, CWS, etc. | M3 | Survey R2 |
| 6 | F6-SemanticServiceGrouping | `ServiceDetailViewController` semantic grouping ("Standard Permitted" vs "Additional / Custom") + neutral absent handling | M3 | Survey R2 |
| 7 | F7-GATTValueDecoders | Decoders for Pressure (0x2A6D), Sensor Location (0x2A5D), and Audio/Hearing characteristics | M4 | Survey R3 |
| 8 | F8-ProfileDashboards | Summary cards in `DeviceDetailViewController` for Fitness/Cycling, Environmental, HID, Audio/Hearing + raw hex | M4 | Survey R3 |
| 9 | F9-FullVerification | Comprehensive unit tests in `SignalTrailTests/`, 100% test pass via `xcodebuild`, `plutil` validation | M5 | Survey R4 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | M1-GATTProbeInfra | AppSettings toggle, SettingsViewController toggle, BackgroundGATTProbe service | none | DONE |
| 2 | M2-AutoProbeQueue | ScanCoordinator queue mechanics, live snapshot merge, persistent cache, dynamic classification | M1 | DONE |
| 3 | M3-PermittedCharacteristics | BluetoothPermittedCharacteristicsLookup, ServiceDetailViewModel, ServiceDetailViewController semantic grouping | none | DONE |
| 4 | M4-ProfileDashboards | Extended GATT decoders, ProfileDashboardBuilder, DeviceDetailViewController dashboard UI + raw hex | none | DONE |
| 5 | M5-FinalAcceptance | End-to-end integration, full test suite pass, plutil verification, coverage hardening | M1, M2, M3, M4 | IN_PROGRESS |

## Interface Contracts
### AppSettings ↔ SettingsStore & SettingsViewController
- `AppSettings.isAutomaticGATTEnrichmentEnabled: Bool` (default: `true`, Codable)
- `SettingsViewController`: Section 0 toggle updates `settingsStore.settings.isAutomaticGATTEnrichmentEnabled`

### BackgroundGATTProbe ↔ ScanCoordinator
- `BackgroundGATTProbe(peripheral: CBPeripheral, scanner: BluetoothScanning, timeout: TimeInterval = 5.0, completion: @escaping (Result<GATTDeviceEvidence, Error>) -> Void)`
- Strictly read-only: discovers services, reads 0x1800 (0x2A00, 0x2A01), 0x180A (0x2A23..0x2A29, 0x2A50), 0x180F (0x2A19).
- Cancels connection immediately upon timeout or when `cancel()` is called.

### ScanCoordinator ↔ Device Store & Intelligence
- `ScanCoordinator.enrichDevice(_:with:exploredServices:)`
- Updates `snapshots`, `deviceCache`, `visibleSnapshots`, persists to disk via `LocalStore`, calls `reconcileGATTDuplicates`, triggers delegate update.

### BluetoothPermittedCharacteristicsLookup ↔ ServiceDetailViewModel
- `BluetoothPermittedCharacteristicsLookup.permittedCharacteristicUUIDs(forServiceUUIDString serviceUUID: String) -> Set<UInt16>?`
- `ServiceDetailViewModel.Section`: `.standardPermitted(characteristics: [GATTCharacteristicSnapshot])`, `.additionalCustom(characteristics: [GATTCharacteristicSnapshot])`, `.allDiscovered(characteristics: [GATTCharacteristicSnapshot])`

### ProfileDashboardBuilder ↔ DeviceDetailViewController
- `ProfileDashboardBuilder.buildCards(for snapshot: BLEDeviceSnapshot) -> [ProfileDashboardCard]`
- `ProfileDashboardCard`: `title: String`, `iconName: String`, `accentColor: UIColor`, `metrics: [ProfileDashboardMetric]`
- `ProfileDashboardMetric`: `title: String`, `value: String`, `unit: String?`, `rawHex: String?`, `iconName: String?`

## Code Layout
- `SignalTrail/Domain/Models.swift`: `AppSettings`, `GATTDeviceIdentity`, `GATTDecodedValue`, `ProfileDashboardCard`, `ProfileDashboardMetric`
- `SignalTrail/Domain/Formatting.swift`: `DeviceIntelligenceEngine` classification rules
- `SignalTrail/Services/Bluetooth/BackgroundGATTProbe.swift`: Background probing service
- `SignalTrail/Services/Bluetooth/ScanCoordinator.swift`: Auto-probe queue & snapshot enrichment
- `SignalTrail/Services/Bluetooth/BluetoothPermittedCharacteristicsLookup.swift`: SIG permitted-characteristic registry
- `SignalTrail/Services/Bluetooth/GATTValueDecoder.swift`: Extended decoders (Pressure, Sensor Location, Audio/Hearing)
- `SignalTrail/Features/Device/ProfileDashboardBuilder.swift`: Profile dashboard aggregator
- `SignalTrail/Features/Device/DeviceDetailViewController.swift`: Profile dashboard UI section
- `SignalTrail/Features/Device/ServiceDetailViewController.swift`: Semantic table sections
- `SignalTrail/Features/Settings/SettingsViewController.swift`: Auto-probe settings switch
- `SignalTrailTests/`: Comprehensive test suites
