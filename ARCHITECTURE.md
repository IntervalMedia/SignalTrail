# SignalTrail architecture

## Design

SignalTrail uses a small service-oriented MVVM/coordinator structure:

```text
SceneDelegate / MainTabBarController
        │
        ▼
UIKit feature controllers
        │
        ├── ScanViewModel
        └── AppEnvironment
               │
               ├── ScanCoordinator
               ├── BluetoothScanner ── CoreBluetooth
               ├── PeripheralInspector ── CoreBluetooth GATT
               ├── CoreLocationProvider ── Core Location
               ├── NotificationService ── UserNotifications
               ├── LocalStore ── JSON + JSONL files
               └── SettingsStore ── UserDefaults
```

The UI never writes files or talks directly to `CBCentralManager`. `AppEnvironment` owns the shared services for the app lifetime, and the scene delegate stops any running scan when the app scene enters the background. Domain models remain independent of controllers and persistence details.

## Responsibilities

### `BluetoothScanner`

Owns `CBCentralManager`, discovers advertisements, retains current `CBPeripheral` references, and routes connection events. It does not decide scan timing or persistence policy.

### `ScanCoordinator`

Owns the scan state machine:

- active scan timer
- recording burst/pause timer
- live-device aggregation
- location attachment
- session persistence
- rule matching and notification cooldowns
- screen-idle policy
- Bluetooth power-state gating before scans can begin

This is the main seam for adding background restoration, service-filtered scans, or alternative scanning strategies.

### `AdvertisementParser`

Normalizes CoreBluetooth advertisement dictionaries into `BLEAdvertisement` values:

- company identifier extraction from manufacturer data
- canonicalized advertised, solicited, and overflow service UUIDs
- service-data hex encoding
- TX power parsing
- derived 16-bit Bluetooth SIG member UUID detection for supported assigned numbers

### `PeripheralInspector`

Manages one connected peripheral and converts GATT services and characteristics into UI-safe snapshots. Read, write, and notification operations remain separate from discovery state.

### `LocalStore`

Provides repository-like methods for sessions, detections, known devices, and rules. Detection files use JSONL append writes. A future `GRDBStore` can implement the same public operations without changing view controllers.

### Feature modules

- `Scan`: live active/recorded scanning
- `Device`: advertisement and GATT inspection
- `Sessions`: map/timeline replay and export
- `KnownDevices`: saved devices and rule editing
- `Settings`: timing, filtering, permissions, and defaults

### Assigned-number lookups

- `BluetoothCompanyLookup` loads the bundled Bluetooth SIG `company_identifiers.yaml` file once and caches it in memory.
- `BluetoothMemberUUIDLookup` is a generated Swift lookup table derived from Bluetooth SIG `member_uuids.yaml`.
- These lookups are presentation helpers; matching still uses the raw advertised values.

## Extension points

Recommended next steps:

1. Introduce repository protocols and inject mock implementations for view-model tests.
2. Replace JSONL indexing with GRDB when sessions become large or require cross-session queries.
3. Automate regeneration of both Bluetooth SIG assigned-number lookups from the bundled YAML sources.
4. Add service decoders for Battery, Device Information, Heart Rate, Environmental Sensing, and Nordic UART.
5. Add CoreBluetooth state restoration only for explicitly supported service UUIDs; unrestricted background discovery remains constrained by iOS.
6. Add session naming, tags, notes, data-retention controls, and a bulk-delete workflow.
7. Add deterministic UI tests with an injected Bluetooth scanner protocol and fixture advertisements.

## Concurrency

CoreBluetooth, `ScanCoordinator`, and UIKit updates run on the main queue. `LocalStore` uses an `NSRecursiveLock` around file access and appends JSONL detections directly to disk. This is adequate for the current single-process app flow, but high-volume development should move persistence behind a serial worker queue or actor.

## Known MVP trade-offs

- A single `PeripheralInspectorDelegate` is sufficient for the pushed navigation flow, but a multicast observer or publisher would better support multiple simultaneous inspectors.
- Settings are stored as one Codable object in `UserDefaults`; schema migration should be introduced before settings become complex.
- Session metadata updates every 25 detections and at normal stop. An abrupt process termination can leave a session open or its count slightly stale; a recovery pass should infer final metadata from JSONL on the next launch.
- Alerts are loaded at scan start for efficiency. Changes made while a scan is already running apply to the next scan.
- Device-detail inspection depends on the peripheral still being retained by the live scanner; replayed sessions cannot reconnect unless the device is observed again in realtime.
