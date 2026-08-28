# SignalTrail Test Infrastructure & E2E Testing Strategy

## 1. Executive Summary
SignalTrail's test infrastructure provides comprehensive, deterministic, opaque-box testing for all Bluetooth SIG device intelligence capabilities (Features F1 through F8). The testing architecture enforces strict separation of concerns, zero network/hardware flake, progressive testability across implementation milestones, and automated verification through native `XCTest`, `xcodebuild`, and `plutil`.

---

## 2. Test Environment & Harness Architecture

### 2.1 Framework & Environment
- **Framework**: `XCTest` (native Swift/Objective-C test runner)
- **Host Target**: `SignalTrail` (iOS 15.2+ deployment target, UIKit-first)
- **Test Target**: `SignalTrailTests` (bundle identifier `com.example.SignalTrailTests`)
- **Simulators**: iPhone 17 Pro, iPhone 16 / 15 / 14 / SE (iOS 15.2 – iOS 26.x SDKs)
- **Sandboxing & Isolation**: Tests run in isolated temporary file system sandboxes (`FileManager.default.temporaryDirectory`) and clean up all state in `tearDownWithError()`.

### 2.2 Test Doubles & Simulators
All tests use deterministic in-memory simulators conforming to project interface contracts:
- `TestSettingsHarness`: Encapsulates `AppSettings` serialization, defaults, and schema migration without polluting system `UserDefaults`.
- `TestBackgroundGATTProbeSimulator`: Exercises read-only whitelist probing, zero-write enforcement, timeout timers, and cancellation without requiring physical BLE radios.
- `TestAutoProbeQueue`: Validates strict 1-connection concurrency, 20-device session cap, deduplication, and mode switching.
- `TestPermittedCharacteristicsLookup`: Authoritative registry mirroring Bluetooth SIG adopted service specifications (ESS, UDS, IMDS, BAS, DIS, HRS, CSCS, CPS, RSCS, HID, HAS, VCS, MCS).
- `TestServiceDetailGrouping`: Verifies table view section partitioning between standard permitted and additional/custom characteristics.
- `TestGATTDecoderExtension`: Mathematical decoders for Pressure (`0x2A6D`), Sensor Location (`0x2A5D`), and LE Audio/Hearing characteristics.
- `TestProfileDashboardBuilder`: Pure functional aggregator generating profile summary cards with formatted units and raw hex.
- `MockLocationProvider`: Deterministic CoreLocation provider stub.

---

## 3. 4-Tier Test Architecture & Methodology

The test suite is organized into 4 distinct verification tiers:

```
┌────────────────────────────────────────────────────────────────────────┐
│                   Tier 4: Real-World Scenarios                         │
│  - Cycling Power Meter (KICKR-V6)      - Weather Station (SHT4x)       │
│  - HID Keyboard (Keychron K2 Pro)      - Hearing Aid (Oticon Intent 1) │
├────────────────────────────────────────────────────────────────────────┤
│                Tier 3: Cross-Feature Combinations                      │
│  - Auto-Probe + Intelligence           - Probe + Dashboard + Grouping  │
│  - Settings Toggle Gating              - RPA Rotation Reconciliation   │
│  - Live Enrichment -> LocalStore Disk Persistence Round-Trip           │
├────────────────────────────────────────────────────────────────────────┤
│              Tier 2: Boundary & Corner Cases (>=5/feature)             │
│  - Corrupted Settings JSON             - Immediate Disconnection       │
│  - Queue Saturation (100 devices)      - Malformed UTF-8 Hex Payloads  │
│  - Empty & Extreme RSSI Values         - Missing Characteristics       │
├────────────────────────────────────────────────────────────────────────┤
│                Tier 1: Feature Coverage (>=5/feature)                  │
│  - F1: SettingsToggle                  - F2: BackgroundGATTProbe       │
│  - F3: AutoProbeQueue                  - F4: LiveIntelligenceEnrichment│
│  - F5: PermittedCharacteristics        - F6: SemanticServiceGrouping   │
│  - F7: GATTValueDecoders               - F8: ProfileDashboards         │
└────────────────────────────────────────────────────────────────────────┘
```

### 3.1 Tier 1: Feature Coverage (>=5 Tests per Feature = 40 Tests)
Covers the core functionality and happy path for each of the 8 features:
- **F1 (SettingsToggle)**: Default state (`true`), JSON persistence, disable/enable round-trip, backward compatibility, scan coordinator gating.
- **F2 (BackgroundGATTProbe)**: Whitelist-only reading (0x1800, 0x180A, 0x180F), zero writes/notifications assertion, evidence delivery, partial discovery, timeout cancellation.
- **F3 (AutoProbeQueue)**: Strictly 1 concurrent connection, 20-device session cap, per-session deduplication, scan stop cancellation, unconnectable rejection.
- **F4 (LiveIntelligenceEnrichment)**: Television classification from `AppleTV14,1`, Smartwatch classification from appearance `0x00C2`, presentation name refinement, atomic disk cache updates, hardware serial duplicate reconciliation.
- **F5 (PermittedCharacteristicsLookup)**: SIG registry lookups for ESS (`0x181A`), UDS (`0x181C`), IMDS (`0x183B`), BAS (`0x180F`), DIS (`0x180A`), nil for custom vendor UUIDs.
- **F6 (SemanticServiceGrouping)**: Partitioning characteristics into "Standard Permitted" vs "Additional / Custom", single-section handling, neutral missing-characteristic handling.
- **F7 (GATTValueDecoders)**: Decoders for Pressure (`0x2A6D`), Sensor Location (`0x2A5D`), Volume State (`0x2B7D`), Media State/Opcodes (`0x2BA4`/`0x2BA6`), Hearing Aid Features/Presets (`0x2BDA`/`0x2BDC`).
- **F8 (ProfileDashboards)**: Fitness & Cycling dashboard card, Environmental Sensing dashboard card, HID Accessory card, Audio & Hearing card, zero cards for generic beacons.

### 3.2 Tier 2: Boundary & Corner Cases (>=5 Tests per Feature = 40 Tests)
Adversarial verification of extreme inputs, edge conditions, and error recovery:
- Corrupted settings JSON recovery, rapid toggle flapping, thread-safe concurrent access.
- Immediate radio disconnection, 0 discovered services, 0 readable characteristics, `CBATTErrorInsufficientAuthentication` handling without UI prompts, active read cancellation.
- 100-device queue flood saturation, queue unblocking after per-device timeout, scan stop during active timer, scan mode transition to `.recording`.
- Special/control characters in BLE device names, non-UTF8 binary byte streams in model strings, unlinked RPA rotation, extreme RSSI (-127 to 0 dBm).
- Case-insensitivity, 128-bit vs 16-bit UUID normalization, malformed UUID strings, custom 128-bit vendor services.
- 100-characteristic stress partitioning in <50ms, duplicate characteristic UUIDs.
- 0 to 3 byte pressure underflows, 5+ byte overflows, 0 Pa and 0xFFFFFFFF extreme pressure values, out-of-bounds sensor location indices, 0-byte audio payloads.
- Empty snapshot handling, single-metric environmental cards, duplicate characteristic metric deduplication.

### 3.3 Tier 3: Cross-Feature Combinations (5 Tests)
Validates interactions across the end-to-end processing pipeline:
1. `testTier3_AutoProbeEnrichmentRefinesTelevisionAndGeneratesNoUnwantedDashboard`: Probed `AppleTV14,1` refines category and suppresses unrelated sensor dashboards.
2. `testTier3_AutoProbeEnrichmentOnCyclingPowerMeterBuildsDashboardAndPermittedGrouping`: Probed cycling power meter enriches snapshot -> generates Fitness Dashboard -> groups permitted characteristics.
3. `testTier3_SettingsToggleDisablesAutoProbeQueueAndPreservesAdvertisedOnlyIntelligence`: Settings toggle disable cleanly gates auto-probe queue.
4. `testTier3_RPARotationReconciliationPreservesDashboardAndPermittedServices`: Hardware serial deduplication preserves GATT services and summary cards.
5. `testTier3_LiveEnrichmentToLocalStorePersistenceRoundTrip`: Probed GATT evidence round-trips through disk storage and reconstructs identical dashboards.

### 3.4 Tier 4: Real-World Application Scenarios (4 Tests)
Simulates end-to-end production device profiles:
1. **Cycling Power Meter (KICKR-V6)**: CSCS + CPS + BAS + Sensor Location (`Left Crank`) + Cycling Power Features -> `.healthFitness` category, Fitness Dashboard with formatted metrics and raw hex, permitted grouping.
2. **Environmental Sensor Station (SHT4x-SmartStation)**: ESS + BAS + Temp (22.45 °C) + Humidity (48.30%) + Pressure (1013.54 hPa) + Elevation (152.00 m) -> `.smartHome` category, Environmental Dashboard with formatted units, permitted grouping.
3. **HID Wireless Keyboard (Keychron K2 Pro)**: HID + BAS + Appearance `0x03C1` + Capabilities (`Remote wake • Normally connectable`) -> `.peripheral` category, HID Dashboard, permitted grouping.
4. **Hearing Aid / LE Audio Controller (Oticon Intent 1)**: HAS + VCS + MCS + BAS + Appearance `0x0840` + Hearing Aid Features + Active Preset + Volume State -> `.audio` category, Audio & Hearing Dashboard, permitted grouping.

---

## 4. Test Matrix & Coverage Summary

| Feature | Feature Name | Tier 1 (Nominal) | Tier 2 (Boundary) | Tier 3 (Cross) | Tier 4 (Scenario) | Total Tests |
|---|---|---|---|---|---|---|
| **F1** | SettingsToggle | 5 | 5 | 1 | 0 | **11** |
| **F2** | BackgroundGATTProbe | 5 | 5 | 1 | 0 | **11** |
| **F3** | AutoProbeQueue | 5 | 5 | 1 | 0 | **11** |
| **F4** | LiveIntelligenceEnrichment | 5 | 5 | 3 | 4 | **17** |
| **F5** | PermittedCharacteristicsLookup | 5 | 5 | 2 | 4 | **16** |
| **F6** | SemanticServiceGrouping | 5 | 5 | 2 | 4 | **16** |
| **F7** | GATTValueDecoders | 5 | 5 | 2 | 4 | **16** |
| **F8** | ProfileDashboards | 5 | 5 | 3 | 4 | **17** |
| **Total** | **All 8 Features** | **40** | **40** | **5** | **4** | **89 Tests** |

---

## 5. Verification Commands

```bash
# 1. Validate Info.plist and Xcode project structure
plutil -lint SignalTrail/Info.plist
plutil -lint SignalTrail.xcodeproj/project.pbxproj

# 2. Build for testing (Simulator)
xcodebuild -project SignalTrail.xcodeproj \
  -scheme SignalTrail \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath ./build \
  build-for-testing

# 3. Execute unit and E2E test suite
xcodebuild -project SignalTrail.xcodeproj \
  -scheme SignalTrail \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath ./build \
  test-without-building
```
