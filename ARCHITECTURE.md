# SignalTrail architecture

## Design

SignalTrail uses a small service-oriented MVVM/coordinator structure:

```text
SceneDelegate / MainTabBarController
        │
        ▼
SwiftUI hosting controllers / UIKit detail flows
        │
        ├── ScanViewModel
        └── AppEnvironment
               │
               ├── ScanCoordinator
               ├── BluetoothScanner ── CoreBluetooth
               ├── HunterController ── RSSI proximity feedback
               ├── PeripheralInspector ── CoreBluetooth GATT
               ├── CoreLocationProvider ── Core Location
               ├── NotificationService ── UserNotifications
               ├── LocalStore ── JSON + JSONL files
               ├── SettingsStore ── versioned UserDefaults payload
               └── WidgetSummaryPublisher ── App Group / WidgetKit
```

The five tab roots are SwiftUI views hosted in the existing UIKit navigation stacks. `ScanScreenModel` adapts `ScanViewModel` delegate updates, `HunterScreenModel` observes the shared Hunter controller, and `TrailSettingsModel` persists edits against the latest settings snapshot. Keeping the navigation stacks preserves device inspection, alert editors, session replay, and the existing Hunter tab handoff. Native iOS 26 Liquid Glass is restricted to fixed action controls; scrolling cards use solid adaptive system colors and older systems use standard button styles.

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

Manages one connected peripheral and converts GATT services, characteristics, descriptors, and decoded values into UI-safe snapshots. Weak multicast observers allow the device, service, and characteristic screens to receive the same connection updates without replacing one another. After connection, it automatically reads a bounded allowlist of readable GAP, Device Information, Battery, HID metadata, and selected capability characteristics. Those reads enrich the live device with device-reported Appearance, identity, and feature evidence; they never write or enable notifications. Manual read, write, and notification operations remain separate from discovery state. Characteristic writes are surfaced by the UI as Advanced tools and require confirmation before dispatch.

### `HunterController`

Tracks one selected CoreBluetooth peripheral using duplicate advertisement RSSI
updates. It maps RSSI to the OUI-SPY Foxhunter pulse intervals, stops feedback
after five seconds without a matching advertisement, and drives generated audio
and haptic feedback from `AppSettings`. Hunter and normal scan sessions are
mutually exclusive because they share one `CBCentralManager` scan.

### `LocalStore`

Provides repository-like methods for sessions, detections, cached device records, known devices, and alert rules. Detection files use JSONL append writes. Launch-time recovery derives interrupted-session counts, unique devices, and end times from valid detection records. Alert defaults use append-only migrations and an offered-rule ledger so user-modified or deleted rules remain user-owned. A future `GRDBStore` should sit behind a repository protocol before replacing these operations.

### `SettingsStore`

Persists `AppSettings` in a versioned Codable envelope in `UserDefaults`. It migrates the legacy raw settings payload, preserves fallback defaults for corrupt data, and refuses to overwrite an unknown future schema until the app understands it.

### `WidgetSummaryPublisher`

Projects recent session metadata into a compact App Group payload and asks WidgetKit to reload the summary widget. The extension reads only this projection; it does not access the main JSONL store or initiate Bluetooth work.

### Feature modules

- `Scan`: first-run onboarding, readiness checks, Quick Scan, Record Session, live filters, sorting, minimum RSSI, and device search
- `Hunter`: single-device RSSI direction finding with configurable pulse feedback
- `Device`: summary-first advertisement and GATT inspection with collapsed technical sections
- `Sessions`: map/timeline replay and export
- `KnownDevices`: Library tab, saved devices, alert templates, rule preview/testing, and rule editing
- `Settings`: scan timing, permissions, and defaults
- `SignalTrailWidget`: small through extra-large summaries of recent sessions and counts from the shared App Group snapshot

### Assigned-number lookups

- `BluetoothCompanyLookup` loads the bundled Bluetooth SIG `company_identifiers.yaml` file once and caches it in memory.
- `BluetoothAssignedUUIDLookup` is the generated, typed source for adopted services, characteristics, descriptors, units, member assignments, standards-organization UUIDs, and GAP Appearance values. It canonicalizes short and Bluetooth-Base-UUID forms before matching.
- `BluetoothMemberUUIDLookup` is a compatibility facade over that typed source for existing alert matching.
- `GATTValueDecoder` contains a curated, length-checked subset of Bluetooth SIG GSS decoders and always retains raw bytes alongside decoded fields.
- Lookup presentation distinguishes an assigned namespace from a device-reported claim and from an inference. Company/member allocation is not presented as authenticated manufacturer identity.
- Class of Device, Classic SDP/service-class tables, and generic Mesh Device Properties are deliberately excluded from the BLE inspection path.

## Improvement backlog

- [ ] TODO: Introduce repository, notification, location, and scanner protocols at `AppEnvironment` boundaries and inject deterministic test doubles.
- [ ] TODO: Move `LocalStore` reads, JSONL recovery, and exports behind a serial worker or actor; retain atomic replacement for metadata files.
- [ ] TODO: Replace JSONL indexing with SQLite/GRDB when sessions require pagination, cross-session queries, or measured data volumes make launch recovery expensive.
- [ ] TODO: Add structured persistence diagnostics and surface recoverable corruption to the user instead of relying exclusively on best-effort fallbacks.
- [ ] TODO: Expand curated GSS decoders only where length, flags, units, and optional fields can be validated deterministically.
- [ ] TODO: Add separately sourced vendor decoders for documented formats without presenting vendor UUIDs as Bluetooth SIG assignments.
- [ ] TODO: Evaluate CoreBluetooth state restoration only for explicitly supported service UUIDs; unrestricted background discovery remains constrained by iOS.
- [ ] TODO: Add session rename, tags, notes, retention controls, and bulk deletion.
- [ ] TODO: Add deterministic UI tests using fixture advertisements, including active-scan rule refresh and replay rediscovery.
- [ ] TODO: Add physical-device integration checks for multicast GATT observers, disconnect/error paths, characteristic subscriptions, and replay reconnection.
- [ ] TODO: Add widget deep links, stale-snapshot messaging, and tests for unavailable App Group storage.
- [ ] TODO: Localize user-facing strings and complete VoiceOver, Dynamic Type, and contrast audits across SwiftUI and UIKit flows.

## Concurrency

CoreBluetooth, `ScanCoordinator`, and UIKit updates run on the main queue. `LocalStore` uses an `NSRecursiveLock` for coordinated file access and a utility serial queue for cached-device writes, while session JSONL and metadata operations remain synchronous. This is adequate for the current single-process app flow, but high-volume work should move the full persistence boundary behind a serial worker or actor.

## MVP trade-off remediation

- `PeripheralInspector` uses weak multicast observers so device, service, and characteristic screens can receive simultaneous inspection updates without replacing one another.
- Settings are stored in a versioned Codable envelope. Legacy unversioned settings migrate on read, while unknown future schema versions are preserved rather than overwritten.
- `LocalStore` performs an idempotent launch-time recovery pass over session JSONL. Valid detections repair stale counts and close interrupted sessions at their latest detection timestamp; malformed or truncated records are ignored.
- Successful alert creation, editing, enable/disable, and deletion refresh the coordinator's in-memory rules immediately. Cooldown and once-per-session histories remain intact during the refresh.
- Bundled alert defaults use ordered, append-only seed migrations and a ledger of previously offered rule identifiers. New defaults can be added without restoring deleted defaults or replacing user-modified rules.
- Replayed device details require a fresh matching realtime observation before exposing connection actions. The screen adopts the newly observed peripheral and live snapshot when it reappears.
- Notification permission remains contextual after alert creation. Presentation is deferred until the navigation transition completes and is anchored to a stable visible controller.

The Bluetooth observer and replay-reconnection flows still require physical-device verification because CoreBluetooth discovery and GATT behavior are not represented by the Simulator.
