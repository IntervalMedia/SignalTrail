# Bluetooth SIG public data for Device Intelligence and GATT inspection

Research date: 2026-08-16
Last updated: 2026-08-28
Repository snapshot examined: Bluetooth SIG `public` commit [`1415ddd9db5770dd21ecbe53173fbfc09e2943b6`](https://bitbucket.org/bluetooth-SIG/public/commits/1415ddd9db5770dd21ecbe53173fbfc09e2943b6)

## Executive Summary & Status

The Bluetooth SIG public repository provides terminology and data-format authorities rather than a product-identification database. Its strongest uses are:

1. **Naming standard, member, and standards-organization UUIDs** without guessing;
2. **Explaining evidence origins** (advertised, solicited, overflow, service-data, or discovered after connection);
3. **Naming GATT services, characteristics, and descriptors** across the inspection tree;
4. **Decoding selected standard characteristic and descriptor values** (Device Information, Battery, Appearance, HID, Fitness/Cycling features, Presentation Format); and
5. **Deriving device categories** from self-declared GAP Appearance and GATT device identity.

It does **not** contain a registry that maps arbitrary advertisements, manufacturer payloads, or model strings to retail products. A company identifier denotes namespace allocation, not guaranteed manufacturer identity.

### Implementation Status Overview

| Capability | Status | Implementation Reference |
| --- | --- | --- |
| **Assigned UUID Lookups (Services, Characteristics, Descriptors, Units, SDOs, Members)** | **Completed** | `BluetoothAssignedUUIDLookup.swift`, `scripts/generate_bluetooth_sig_lookups.rb` |
| **UUID Canonicalization (16/32/128-bit Base UUID)** | **Completed** | `BluetoothAssignedUUIDLookup.canonical16BitValue(from:)` |
| **GAP Appearance Decoding (`0x2A01`)** | **Completed** | `GATTValueDecoder.decodeAppearance` & `BluetoothAppearanceLookup` |
| **Device Information Strings & EUI-64 System ID** | **Completed** | `GATTValueDecoder.swift` (`0x2A23`–`0x2A29`) |
| **PnP ID Decoding (`0x2A50`) with SIG Vendor join** | **Completed** | `GATTValueDecoder.decodePnPID` |
| **Standard Feature & Measurement Decoders** | **Completed** | Battery (`0x2A19`), Heart Rate (`0x2A37`), HID (`0x2A4A`/`0x2A4B`), RSC/CSC/Cycling/Fitness (`0x2A54`, `0x2A5C`, `0x2A65`, `0x2ACC`), Environment (`0x2A6E`, `0x2A6F`) |
| **Descriptor Decoding (Presentation Format `0x2904`)** | **Completed** | `GATTValueDecoder.decodePresentationFormatDescriptor` |
| **Provenance-Preserving Device Intelligence Engine** | **Completed** | `DeviceIntelligenceEngine` in `Formatting.swift` |
| **Per-Device Persistent JSON Storage & Cache** | **Completed** | `LocalStore.swift`, `ScanCoordinator.swift` |
| **Automatic Bounded GATT Inspection during Scan** | **Planned** | Detailed in `docs/automatic-gatt-device-intelligence.md` |
| **Permitted-Characteristic Service Grouping in UI** | **Completed** | `BluetoothPermittedCharacteristicsLookup`, `ServiceDetailViewModel`, and Service Detail sections |
| **High-Level Profile Summary Dashboards** | **Completed** | `ProfileDashboardBuilder` and Device Detail profile dashboard section |

## The iOS observation boundary

Apple gives a central app a normalized advertisement dictionary containing local name, manufacturer data, service data, advertised/overflow/solicited service UUIDs, transmit power, and connectability. It does not expose a generic raw Advertising Data element stream or keys for Appearance or Class of Device. This is the complete public key collection in [Apple's Advertisement Data Retrieval Keys](https://developer.apple.com/documentation/corebluetooth/advertisement-data-retrieval-keys).

After connection, `CBPeripheral` can discover services, characteristics, and descriptors and can read characteristics whose properties include `read`. Apple notes that discovering all characteristics by passing `nil` is slower than requesting selected UUIDs, and that not every characteristic is readable ([`CBPeripheral`](https://developer.apple.com/documentation/corebluetooth/cbperipheral), [`discoverCharacteristics(_:for:)`](https://developer.apple.com/documentation/corebluetooth/cbperipheral/discovercharacteristics%28_%3Afor%3A%29), [`readValue(for:)`](https://developer.apple.com/documentation/corebluetooth/cbperipheral/readvalue%28for%3A%29-6u2kr)).

| Evidence | Available during scan | Available after connection | Correct interpretation |
| --- | --- | --- | --- |
| Company identifier in manufacturer data | Yes, when manufacturer data is present | Not needed | Registered assignee of the numeric company identifier; useful attribution evidence, not guaranteed manufacturer identity |
| Standard service UUID | Yes, when present in advertised, solicited, overflow, or service-data UUIDs | Yes, when the service is discovered | Standard service/capability name; advertisement omission does not prove absence |
| Member UUID | Yes, in the same UUID-bearing fields | Yes, if used by a discovered GATT attribute | UUID assignee, not necessarily the device maker |
| Standards Development Organization UUID | Yes, in the same UUID-bearing fields | Potentially | Protocol/ecosystem attribution such as Matter, FIDO, or digital key; not a product identity |
| Service and characteristic tree | No | Yes | The GATT database exposed by the connected peripheral |
| Characteristic properties and values | No | Yes, subject to properties, security, and device behavior | Capability and device-supplied facts; retain raw bytes and label the source |
| GAP Appearance (`0x2A01`) | No public CoreBluetooth advertisement key | Yes, if exposed and readable | Device-declared category/subcategory |
| Device Information strings / PnP ID | No | Yes, if exposed and readable | Device-supplied manufacturer/model/revision data or a structured vendor/product tuple |
| Raw AD type, Appearance AD element, Class of Device AD element | No | No, unless the same concept is separately exposed through GATT | Outside the public CoreBluetooth scan result |
| BR/EDR Class of Device and SDP records | No | No through CoreBluetooth's BLE GATT APIs | Not applicable to SignalTrail's current BLE inspector |

CoreBluetooth supports 16-, 32-, and 128-bit UUID representations and expands assigned short UUIDs using the Bluetooth Base UUID. A lookup should therefore canonicalize all of those representations before matching ([Apple `CBUUID`](https://developer.apple.com/documentation/corebluetooth/cbuuid)).

## High-value repository data

### 1. Assigned GATT UUID names — highest priority

These files all use a top-level `uuids` array. Entries generally contain `uuid`, `name`, and `id`:

- [`assigned_numbers/uuids/service_uuids.yaml`](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/uuids/service_uuids.yaml) — standard GATT service UUIDs, such as Battery, Device Information, Heart Rate, Human Interface Device, and Environmental Sensing.
- [`assigned_numbers/uuids/characteristic_uuids.yaml`](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/uuids/characteristic_uuids.yaml) — standard characteristic UUIDs, including Device Name, Appearance, Battery Level, Device Information strings, and PnP ID.
- [`assigned_numbers/uuids/descriptors.yaml`](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/uuids/descriptors.yaml) — standard descriptor UUIDs, including User Description, Client Characteristic Configuration, Presentation Format, Valid Range, and Environmental Sensing descriptors.
- [`assigned_numbers/uuids/declarations.yaml`](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/uuids/declarations.yaml) — GATT attribute declarations for primary/secondary services, includes, and characteristics; useful vocabulary when explaining the hierarchy.
- [`assigned_numbers/uuids/units.yaml`](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/uuids/units.yaml) — assigned unit UUIDs for interpreting Characteristic Presentation Format and displaying units consistently.
- [`assigned_numbers/core/formattypes.yaml`](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/core/formattypes.yaml) — assigned presentation-format codes to combine with units when decoding the Characteristic Presentation Format descriptor.
- [`assigned_numbers/uuids/sdo_uuids.yaml`](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/uuids/sdo_uuids.yaml) — UUIDs allocated to standards organizations and ecosystems, including FIDO, Matter, digital-key, Wi-Fi, and Remote ID uses.

Recommended integration: generate one context-aware `BluetoothAssignedUUIDLookup` rather than separate untyped dictionaries. Its result should include at least `value`, `name`, `kind` (`service`, `characteristic`, `descriptor`, `unit`, `member`, or `sdo`), stable SIG `id` when present, and assignee when relevant. Context matters: UI code should ask for a service name when rendering a `CBService` and a characteristic name when rendering a `CBCharacteristic`, rather than treating every short UUID as the same namespace.

Immediate UI wins:

- `180F — Battery Service` instead of `180F` in advertisements and the connected service tree;
- `2A19 — Battery Level` instead of a raw characteristic UUID;
- a short factual explanation such as “Advertised standard service” versus “Discovered after connection”;
- member UUID wording such as “UUID assigned to Acme” instead of “Device made by Acme”; and
- SDO wording such as “Matter Profile ID” rather than treating the SDO name as the device manufacturer.

### 2. GATT Specification Supplement characteristic schemas — highest value after names

The [`gss/`](https://bitbucket.org/bluetooth-SIG/public/src/main/gss/) directory contains one YAML document per published characteristic definition. Each document has a top-level `characteristic` object with an `identifier`, `name`, description, ordered `structure` fields, and, where applicable, bit or enumeration definitions in `fields`.

For example:

- [Battery Level](https://bitbucket.org/bluetooth-SIG/public/src/main/gss/org.bluetooth.characteristic.battery_level.yaml) defines a one-byte `uint8`, percentage unit, and allowed range 0–100.
- [Heart Rate Measurement](https://bitbucket.org/bluetooth-SIG/public/src/main/gss/org.bluetooth.characteristic.heart_rate_measurement.yaml) defines flag-dependent 8/16-bit heart rate values, optional energy expended, and repeated RR intervals.
- [PnP ID](https://bitbucket.org/bluetooth-SIG/public/src/main/gss/org.bluetooth.characteristic.pnp_id.yaml) defines Vendor ID Source, Vendor ID, Product ID, and Product Version; source `1` means the Vendor ID uses the Bluetooth SIG Company Identifier namespace, while source `2` means the USB-IF namespace.
- [Manufacturer Name String](https://bitbucket.org/bluetooth-SIG/public/src/main/gss/org.bluetooth.characteristic.manufacturer_name_string.yaml) defines a variable-length UTF-8 value.

This is the fact base SignalTrail needs to replace generic hex with structured, attributed values. It also covers “Feature” characteristics: their schemas define named capability bits, allowing the app to show facts such as supported measurement features instead of an unexplained bitmask.

Do not attempt a universal runtime YAML interpreter first. At this snapshot, `gss` has 277 documents while the characteristic UUID catalog has 511 entries, so a known characteristic name does not guarantee that a field schema is present. The schemas also include conditional fields, arrays, bit ranges, prose references, typographic ranges, and sizes represented as both numbers and expressions. Generate or hand-write a decoder registry for a useful subset, validate length before every read, preserve raw hexadecimal data, and fall back to hex on any mismatch.

Recommended first decoder set:

1. Device Information: Manufacturer Name, Model Number, Serial Number, hardware/firmware/software revisions, System ID, and PnP ID.
2. GAP: Device Name and Appearance.
3. Battery: Battery Level.
4. Common category evidence: Heart Rate Measurement/Feature, Body Sensor Location, HID Information/Report Map, Environmental Sensing values, Cycling/Running features, and Fitness Machine Feature.
5. Characteristic Presentation Format and Unit lookup, once descriptor discovery is added.

Values read from a peripheral should be presented as device-reported evidence. PnP ID is particularly useful because a source-`1` Vendor ID can be joined to the existing company-identifier lookup without guessing; a source-`2` Vendor ID cannot be resolved from this SIG repository and should be labelled as USB-IF without inventing a company name.

### 3. Appearance — useful, but only after connection on iOS

[`assigned_numbers/core/appearance_values.yaml`](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/core/appearance_values.yaml) contains a top-level `appearance_values` list of category values/names and optional subcategory values/names. It includes useful, explicitly assigned types such as phone, computer subtypes, smartwatch, tag, thermometer, heart-rate belt, keyboard, mouse, cycling sensors, glucose meter, and many others.

Generate a `BluetoothAppearanceLookup` only when SignalTrail also implements a read of GAP Appearance characteristic `0x2A01`. It can provide strong category evidence because the value directly declares a category, but it remains self-reported and can be absent, generic, stale, or incorrect. CoreBluetooth does not provide an Appearance advertisement key, so the lookup cannot enrich the current advertisement-only parser.

This is materially different from [`assigned_numbers/core/class_of_device.yaml`](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/core/class_of_device.yaml). Class of Device is a BR/EDR classification (and an assigned AD element type), while the GAP Appearance characteristic is part of the BLE GATT model that CoreBluetooth can discover and read.

### 4. Permitted-characteristic tables — useful for navigation, not compliance claims

The repository provides permitted-characteristic lists for [Environmental Sensing](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/profiles_and_services/ess/ess_permitted_characteristics.yaml), [User Data](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/profiles_and_services/uds/uds_permitted_characteristics.yaml), [Industrial Measurement Device](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/profiles_and_services/imds/imds_permitted_characteristics.yaml), and [Cookware](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/profiles_and_services/cws/cws_permitted_characteristics.yaml). Each maps a stable service identifier to a list of characteristic identifiers.

These can organize a service screen into expected semantic groups and help select likely decoders. “Permitted” does not mean “required,” so SignalTrail should not label a device invalid merely because one of these characteristics is absent. Full profile conformance also cannot be inferred from a passive scan or a partial GATT tree.

### 5. Existing company and member UUID data — keep, but tighten claims

SignalTrail already uses the repository's [Company Identifiers](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/company_identifiers/company_identifiers.yaml) and [Member UUIDs](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/uuids/member_uuids.yaml). Keep both, but treat them as namespace ownership:

- the first two octets of Manufacturer Specific Data select a company identifier according to the Bluetooth data format, but downstream bytes are company-defined and require a separate, sourced decoder;
- a member UUID identifies the member to which that UUID was assigned, not necessarily the manufacturer of every product advertising it; and
- company identifier, member UUID, local name, and service evidence can corroborate each other, but disagreement should be shown rather than silently resolved to one company.

The Bluetooth SIG's [Assigned Numbers page](https://www.bluetooth.com/specifications/assigned-numbers/) identifies the Bitbucket YAML repository as the machine-readable publication and directs requests for company identifiers and 16-bit member UUIDs through Assigned Numbers support.

## Data that should not drive the current implementation

| Repository area | Why it should be deferred or excluded |
| --- | --- |
| [`assigned_numbers/core/ad_types.yaml`](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/core/ad_types.yaml) | Useful as protocol documentation, but CoreBluetooth does not expose the generic raw AD-element type stream. SignalTrail already receives Apple's normalized subset. |
| [`assigned_numbers/core/class_of_device.yaml`](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/core/class_of_device.yaml) | No Class of Device value is present in Apple's public scan dictionary or BLE GATT inspection API. Do not reinterpret manufacturer data as Class of Device. |
| [`assigned_numbers/uuids/service_class.yaml`](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/uuids/service_class.yaml) and `assigned_numbers/service_discovery/` | These primarily describe BR/EDR SDP service classes and attributes, not the GATT database exposed by CoreBluetooth. |
| `assigned_numbers/profiles_and_services/a2dp`, `avrcp`, `hfp`, `map`, and similar Classic-profile data | iOS handles these profiles outside a third-party app's CoreBluetooth GATT inspector. |
| [`assigned_numbers/mesh/`](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/mesh/) and [`dp/`](https://bitbucket.org/bluetooth-SIG/public/src/main/dp/) | Valuable only if SignalTrail deliberately implements Bluetooth Mesh protocol decoding. These tables are not generic device-category facts and should not be applied to arbitrary BLE data. |
| Arbitrary vendor-specific 128-bit UUIDs and manufacturer payload bytes | The SIG repository cannot name or decode them. They require a vendor-owned primary specification or an explicitly labelled heuristic. |

## A fact-based inspection model

The UI and intelligence engine should preserve provenance instead of collapsing evidence into a single unexplained label:

| Provenance | Suggested wording | Relative use in categorization |
| --- | --- | --- |
| SIG assigned number | “Standard Heart Rate service (`180D`) advertised” | Medium-to-high capability evidence; not exact identity |
| Connected GATT discovery | “Battery service discovered after connection” | Stronger evidence that the service is currently exposed |
| Device-reported GATT value | “Appearance: Smartwatch (device reported)” | High category evidence, still self-declared |
| Company identifier | “Company identifier assigned to Apple, Inc.” | Attribution evidence, not model proof |
| Member UUID | “Service UUID assigned to Example Corp.” | Namespace ownership evidence |
| Local/advertised name | “Advertised name: …” | Useful but unverified and mutable |
| Vendor-documented decoder | “Decoded as Vendor X format; source: …” | Strong when its version and source are recorded |
| Heuristic | “Possible … based on name pattern” | Low confidence and visibly labelled |

Absence should normally be “not observed,” not “not supported.” Advertisements are size-constrained, a service need not be advertised to exist, connection/security can hide readable values, and an interrupted discovery can leave a partial tree.

## Detailed Implementation Roadmap

### Phase 1 — Names and Provenance *(Status: COMPLETED)*

- [x] **1.1. Assigned Number Generators**: Ruby generator script `scripts/generate_bluetooth_sig_lookups.rb` parses YAML for adopted services, characteristics, descriptors, units, members, SDOs, and Appearance values.
- [x] **1.2. Unified Typed Lookup**: Implemented `BluetoothAssignedUUIDLookup.swift` with context-aware queries (`serviceMetadata`, `metadata(for:kind:)`).
- [x] **1.3. Canonical UUID Normalization**: Standardized 16-bit, 32-bit (`0000xxxx`), and 128-bit Bluetooth Base UUID (`-0000-1000-8000-00805F9B34FB`) expansion and parsing.
- [x] **1.4. Contextual UI Labels**: UI displays SIG names alongside hexadecimal values across advertisement cards, detail views, and characteristic rows.
- [x] **1.5. Attribution Language Refinement**: Phrasing reflects namespace allocation ("UUID assigned to X") rather than definitive manufacturing proof.
- [x] **1.6. Test Coverage**: Snapshot and unit tests in `BluetoothIntelligenceTests.swift` verify UUID lookups, collisions, and provenance descriptions.

### Phase 2 — Bounded Standard-Value Decoding & Intelligence *(Status: COMPLETED)*

- [x] **2.1. Decoder Registry**: Implemented `GATTValueDecoder.swift` for safe, length-checked value parsing.
- [x] **2.2. Core Characteristic Decoders**:
  - Device Information: Manufacturer Name (`0x2A29`), Model Number (`0x2A24`), Serial Number (`0x2A25`), Hardware/Firmware/Software Revisions (`0x2A26`–`0x2A28`), System ID EUI-64 (`0x2A23`).
  - PnP ID (`0x2A50`): Decodes Vendor ID Source (Bluetooth SIG vs USB-IF), joining SIG IDs directly to company lookup.
  - GAP Appearance (`0x2A01`): Decodes category and subcategory from `BluetoothAppearanceLookup`.
  - Battery Level (`0x2A19`): Percentage display with 0–100 range validation.
  - Health & Fitness: Heart Rate Measurement (`0x2A37`), Body Sensor Location (`0x2A38`), RSC Feature (`0x2A54`), CSC Feature (`0x2A5C`), Cycling Power (`0x2A65`), Fitness Machine (`0x2ACC`).
  - HID & Environmental: HID Information (`0x2A4A`), Report Map (`0x2A4B`), Temperature (`0x2A6E`), Humidity (`0x2A6F`).
- [x] **2.3. Presentation Format Descriptor**: Decodes format type, exponent, unit name lookup, namespace, and description for `0x2904`.
- [x] **2.4. Raw Hex Preservation & Warning Fallback**: Retains raw hexadecimal representations and attaches warnings whenever parsing encounters unexpected lengths or reserved bits.
- [x] **2.5. Intelligence Engine Integration**: `DeviceIntelligenceEngine` in `Formatting.swift` scores candidates using combined advertisement and GATT evidence.
- [x] **2.6. Persistent Per-Device Caching**: `LocalStore` and `ScanCoordinator` store individual device JSON snapshots and hydrate known attributes on discovery.

### Phase 3 — Remaining & Future Work *(Status: PLANNED / IN PROGRESS)*

#### 3.1. Automatic Bounded GATT Inspection during Scan *(Completed)*
- [x] **Sequential Background Queue**: Implemented automatic, read-only GATT probing for connectable peripherals during active Quick Scans (capped at 20 devices, 5s timeout, 1 concurrent connection), including synchronous cancellation reentrancy protection.
- [ ] **Read-Only Safety**: Probe discovers services and reads safe identification characteristics only (`0x180A`, `0x2A00`, `0x2A01`, `0x2A19`); never writes or enables notifications.
- [ ] **Live Intelligence Enrichment**: Merge discovered identity directly into live scan snapshots to classify devices (e.g. `AppleTV14,1` classifying immediately as `.television`).
- *Detailed specification:* See `docs/automatic-gatt-device-intelligence.md`.

#### 3.2. Permitted-Characteristic Semantic Service Grouping *(Completed)*
- [x] **Permitted-Characteristic Tables**: Added curated SIG mappings for Environmental Sensing (`ess`), User Data (`uds`), Industrial Measurement (`imds`), Cookware (`cws`), and core inspector services.
- [x] **Semantic Service Organization**: Grouped characteristics on `ServiceDetailViewController` into standard permitted and additional/custom sections.
- [x] **Graceful Handling**: Missing permitted characteristics remain neutral and produce no conformance warning.

#### 3.3. Profile-Oriented Summary Dashboards *(Completed)*
- [x] **Specialized Profile Cards**: Added summary widgets in `DeviceDetailViewController` when standard service clusters are detected:
  - *Fitness & Cycling*: Summary card displaying sensor location, battery, supported features (cadence, power balance, speed).
  - *Environmental Monitor*: Aggregated dashboard for Temperature, Humidity, and Pressure.
  - *HID Accessory*: Keyboard/Mouse capabilities, remote wake, battery level, country code.
  - *Hearing / Audio*: Standard audio control and volume offset capabilities.

#### 3.4. Curated External Model Datasets & Sourced Vendor Decoders *(Low / Future Priority)*
- [ ] **External Retail Model Lookups**: Maintain a distinct, locally-versioned dataset for commercial model strings (e.g. Apple Model Identifiers `AudioAccessory5,1` -> HomePod mini) separate from Bluetooth SIG lookups.
- [ ] **Documented Vendor Decoders**: Implement decoders for publicly specified vendor formats (e.g., RuuviTag, BTHome, Eddystone, Exposure Notification) accompanied by citations to primary specification documents.

## Update and licensing considerations

The snapshot examined contains machine-readable YAML but no repository-level `LICENSE`, formal schema, README, release manifest, semantic dataset version, or tags. Of 604 YAML files, 603 carry Bluetooth SIG proprietary notices that state furnishing the document does not grant an intellectual-property license, disclaim warranties, and say the content may change without notice; `company_identifiers.yaml` is the lone header exception. See, for example, the header of [`service_uuids.yaml`](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/uuids/service_uuids.yaml). The repository API describes the project as public YAML for Assigned Numbers, GATT Specification Supplement, and Device Properties ([Bitbucket repository API](https://api.bitbucket.org/2.0/repositories/bluetooth-sig/public))

For reproducible updates:

1. pin generation to an audited commit SHA rather than silently consuming `main`;
2. record the source path, commit SHA, retrieval date, and source hash in generated-file comments;
3. validate the expected top-level key and every required field before replacing checked-in output;
4. fail on duplicate UUIDs within a context, unknown field shapes, or malformed values;
5. generate deterministic sorted Swift and review the semantic diff;
6. run lookup and decoder fixtures before accepting an update; and
7. keep raw values usable when a newly changed schema cannot be decoded.

The repository's current head was an automated publication commit, which reinforces treating it as a changing upstream dataset rather than a stable SDK. A generator with checked-in output is appropriate for SignalTrail's offline/local-only design.
