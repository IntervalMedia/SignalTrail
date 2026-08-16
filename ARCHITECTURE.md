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

- Quick Scan timer
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

Manages one connected peripheral and converts GATT services, characteristics, descriptors, and decoded values into UI-safe snapshots. After an explicit user connection, it automatically reads a bounded allowlist of readable GAP, Device Information, Battery, HID metadata, and selected capability characteristics. Those reads enrich the live device with device-reported Appearance, identity, and feature evidence; they never write or enable notifications. Manual read, write, and notification operations remain separate from discovery state. Characteristic writes are surfaced by the UI as Advanced tools and require confirmation before dispatch.

### `LocalStore`

Provides repository-like methods for sessions, detections, known devices, and rules. Detection files use JSONL append writes, and alert-rule storage also handles one-time seed migrations such as the default Axon/TASER rule. A future `GRDBStore` can implement the same public operations without changing view controllers.

### Feature modules

- `Scan`: first-run onboarding, readiness checks, Quick Scan, Record Session, live filters, sorting, minimum RSSI, and device search
- `Device`: summary-first advertisement and GATT inspection with collapsed technical sections
- `Sessions`: map/timeline replay and export
- `KnownDevices`: Library tab, saved devices, alert templates, rule preview/testing, and rule editing
- `Settings`: scan timing, permissions, and defaults

### Assigned-number lookups

- `BluetoothCompanyLookup` loads the bundled Bluetooth SIG `company_identifiers.yaml` file once and caches it in memory.
- `BluetoothAssignedUUIDLookup` is the generated, typed source for adopted services, characteristics, descriptors, units, member assignments, standards-organization UUIDs, and GAP Appearance values. It canonicalizes short and Bluetooth-Base-UUID forms before matching.
- `BluetoothMemberUUIDLookup` is a compatibility facade over that typed source for existing alert matching.
- `GATTValueDecoder` contains a curated, length-checked subset of Bluetooth SIG GSS decoders and always retains raw bytes alongside decoded fields.
- Lookup presentation distinguishes an assigned namespace from a device-reported claim and from an inference. Company/member allocation is not presented as authenticated manufacturer identity.
- Class of Device, Classic SDP/service-class tables, and generic Mesh Device Properties are deliberately excluded from the BLE inspection path.

## Extension points

Recommended next steps:

1. Introduce repository protocols and inject mock implementations for view-model tests.
2. Replace JSONL indexing with GRDB when sessions become large or require cross-session queries.
3. Expand curated GSS decoders only where length, flags, units, and optional fields can be validated deterministically.
4. Add separately sourced vendor decoders for documented formats such as Nordic UART without treating arbitrary vendor UUIDs as Bluetooth SIG data.
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
- Default alert seeds are migration-driven. Changes to bundled defaults should advance the seed version rather than rewriting user-managed rules in place.
- Device-detail inspection depends on the peripheral still being retained by the live scanner; replayed sessions cannot reconnect unless the device is observed again in realtime.
- Notification permission prompts are requested contextually after alert creation and must be presented from a stable visible controller, not from a disappearing editor during a navigation transition.
