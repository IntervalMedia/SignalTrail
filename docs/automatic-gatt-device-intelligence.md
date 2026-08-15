# Automatic GATT device intelligence

## Goal

Improve identification of connectable BLE peripherals by automatically performing a bounded, read-only GATT inspection, decoding human-readable characteristic values, and feeding reliable identification data back into SignalTrail's device intelligence/category result.

## User-visible behaviour

1. During a Quick Scan, a peripheral whose advertisement reports `isConnectable == true` becomes eligible for background GATT enrichment.
2. SignalTrail probes eligible peripherals sequentially rather than opening many connections at once.
3. The probe discovers services/characteristics and automatically reads **readable** characteristics only. It never writes and never enables notifications.
4. Characteristic values that are valid printable UTF-8 are displayed as decoded text first, with the original hexadecimal value retained as a secondary/copyable raw value.
5. Bluetooth SIG Device Information Service (`0x180A`) values are recognised, including at minimum:
   - `0x2A24` Model Number String
   - `0x2A25` Serial Number String
   - `0x2A26` Firmware Revision String
   - `0x2A27` Hardware Revision String
   - `0x2A28` Software Revision String
   - `0x2A29` Manufacturer Name String
   - `0x2A50` PnP ID (structured decode where possible)
6. The device intelligence engine incorporates GATT identification evidence in addition to advertisement evidence. Model/manufacturer evidence may raise or correct the category when it is more specific than advertisement-only inference.
7. Example: `0x2A29 = Apple Inc.` plus `0x2A24 = AppleTV14,1` should classify the device as a TV/media device and show the decoded strings rather than `4170706C65...`.

## Safety and resource constraints

Automatic inspection must be deliberately bounded. Connecting to every peripheral at once would be unreliable and power-expensive on iOS.

- Quick Scan only for the initial implementation; do not automatically probe during recording bursts.
- Maximum one background GATT connection at a time.
- Queue each peripheral identifier at most once per scan.
- Cap automatic probes per scan (recommended: 20) so a dense RF environment cannot create an unbounded connection queue.
- Per-peripheral timeout (recommended: 4–6 seconds), then disconnect and continue.
- Disconnect immediately after service/characteristic discovery and pending identification reads complete.
- Cancel queued/in-flight probes when the scan stops or Bluetooth becomes unavailable.
- Do not write characteristic values and do not subscribe to notifications from the automatic probe.
- Manual device inspection remains available and may expose the full GATT tree.

## Proposed design

### 1. GATT value decoding

Add a focused decoder in `Services/Bluetooth` (or alongside `PeripheralInspector` if avoiding a new project-file entry):

```swift
struct GATTDecodedValue: Hashable {
    enum Format: Hashable {
        case utf8
        case hex
        case structured(String)  // e.g. "PnP ID"
    }

    let displayText: String
    let rawHex: String
    let format: Format
}
```

Decode order:

1. Known Bluetooth SIG characteristic-specific format.
2. Printable UTF-8 / ASCII.
3. Raw hexadecimal fallback.

Never treat arbitrary binary payloads as text simply because UTF-8 decoding technically succeeds; require printable scalar content and reject control-heavy strings.

### 2. Device identity snapshot

Introduce a value type independent from CoreBluetooth objects so it can be safely merged into live scan state:

```swift
struct GATTDeviceIdentity: Hashable {
    var manufacturerName: String?
    var modelNumber: String?
    var serialNumber: String?
    var firmwareRevision: String?
    var hardwareRevision: String?
    var softwareRevision: String?
    var pnpIdentifier: String?
}
```

Attach the identity to `BLEDeviceSnapshot` (not persisted initially unless there is a clear session-storage requirement). Preserve it when advertisements for the same peripheral are merged.

### 3. Automatic probe coordinator

Keep scanning ownership in `ScanCoordinator`; do not turn `BluetoothScanner` into a second domain coordinator.

Recommended state:

```swift
private var autoProbeQueue: [UUID] = []
private var attemptedAutoProbeIDs = Set<UUID>()
private var activeAutoProbe: PeripheralInspector?
private var autoProbeTimeout: Timer?
private let maxAutoProbesPerScan = 20
```

When a new connectable device is discovered during `.active` scan:

- enqueue if not attempted;
- retain the `CBPeripheral` through the scanner cache;
- start the next probe only when there is no active probe.

When identity information changes:

- merge it into `snapshots[identifier]`;
- force a visible snapshot refresh;
- allow `presentationName`, search, filtering, and device cells to use the enriched intelligence result.

### 4. PeripheralInspector changes

Support a read-only automatic mode:

```swift
enum InspectionMode {
    case manual
    case automaticIdentification
}
```

`automaticIdentification` should:

- discover all services (because useful vendor services may expose identity),
- discover characteristics,
- automatically read characteristics that are readable,
- prioritise Device Information Service characteristics,
- track pending discovery/read operations,
- notify its delegate when identification inspection has completed,
- tolerate individual read failures without failing the whole probe.

Manual mode retains explicit read/write/notify controls.

### 5. Intelligence engine integration

Extend evidence kinds with GATT-derived evidence, e.g.:

```swift
case gattManufacturer
case gattModel
case gattService
```

`DeviceIntelligenceEngine` should accept both advertisement data and optional `GATTDeviceIdentity`.

High-confidence model-family patterns should beat generic manufacturer-only inference. Initial deterministic patterns can include:

- `AppleTV*` -> `.television`
- `iPhone*` -> `.mobilePhone`
- `Watch*` / `AppleWatch*` -> `.smartWatch`
- `Mac*` / `MacBook*` / `iMac*` -> `.computer`
- `AirPods*` / obvious headset model strings -> `.audio`
- generic model text terms already used by the advertisement-name classifier

Do not infer an exact retail model unless SignalTrail has a maintained mapping source. Preserve the raw model identifier (`AppleTV14,1`) even when a friendly family name is available.

### 6. UI presentation

For GATT characteristic rows:

- title: SIG characteristic name when known, UUID retained in the subtitle/detail;
- primary value: decoded English/text representation;
- secondary/raw value: hexadecimal, still copyable;
- binary-only characteristics continue to show hex.

Device summary should show GATT-derived manufacturer/model when present and identify that the evidence came from a connected GATT read rather than advertisement data.

## Tests

Unit tests should cover at minimum:

- printable ASCII/UTF-8 decoding (`4170706C6520496E632E` -> `Apple Inc.`);
- `4170706C65545631342C31` -> `AppleTV14,1`;
- binary/control-heavy data remains hexadecimal;
- Device Information characteristic UUID -> semantic field mapping;
- snapshot merge preserves previously discovered GATT identity;
- GATT model evidence can change an advertisement-only `.unknown` / generic result to the expected category;
- lower-confidence manufacturer-only GATT evidence does not override stronger detector-profile evidence;
- automatic probe queue is bounded, sequential, deduplicated, and reset between scans;
- timeout/failure advances to the next queued peripheral.

## On-device validation

BLE connection behaviour must be validated on physical hardware. Test at least:

1. Apple TV exposing `0x180A`/`0x2A29`/`0x2A24`.
2. A connectable peripheral with readable binary characteristics to verify no bogus text conversion.
3. Several connectable peripherals in range to verify the probe queue remains sequential and scanning continues.
4. A peripheral that refuses connection/read requests to verify timeout/failure recovery.
5. Start/stop Quick Scan repeatedly to verify no stale inspector/delegate/connection state leaks between scans.

## Acceptance criteria

- Connectable peripherals discovered in Quick Scan can be enriched automatically without user tapping Connect.
- Automatic probing never writes or enables notifications.
- Only one automatic connection is active at a time and the queue is capped/deduplicated.
- Human-readable characteristic values display decoded text while raw hex remains available.
- `180A` manufacturer/model data is extracted into structured identity fields.
- GATT identity contributes deterministic evidence to device category inference.
- Apple TV example is categorised as TV/media from `AppleTV14,1`.
- Existing manual GATT inspection continues to work.
- Unit tests pass, and PR notes include physical-device validation requirements.