# SignalTrail project status

SignalTrail is a local-first iOS/iPadOS Bluetooth Low Energy scanner, observation logger, GATT inspector, heuristic device-intelligence tool, and RSSI hunter. The deployment target is iOS/iPadOS 15.2. Xcode 26 or newer is required because the app conditionally adopts native Liquid Glass APIs on iOS 26.

For user-facing setup and capabilities, see [README.md](README.md). For service boundaries and design decisions, see [ARCHITECTURE.md](ARCHITECTURE.md). For current verification guidance, see [VALIDATION.md](VALIDATION.md).

## Current architecture

- `App/` owns application and scene wiring, the shared `AppEnvironment`, and five-tab navigation.
- `Domain/` contains Codable models, formatting, Bluetooth evidence, and device-intelligence classification.
- `Features/` contains SwiftUI tab roots for Scan, Hunter, Sessions, Library, and Settings, hosted in UIKit navigation stacks. Device inspection, GATT navigation, editors, and session-map detail remain UIKit.
- `Services/Bluetooth/` owns scanning, advertisement parsing, scan coordination, bounded automatic GATT probes, manual peripheral inspection, assigned-number lookup, and value decoding.
- `Services/Persistence/` owns versioned settings, JSON/JSONL application data, session recovery, device snapshots, alert seed migrations, and the widget summary projection.
- `Services/Location/`, `Notifications/`, and `Export/` isolate their platform responsibilities.
- `SignalTrailWidget/` displays recent session summaries from an App Group snapshot and performs no Bluetooth work.
- `SignalTrailTests/` contains XCTest coverage for persistence, alerts, scan coordination, automatic probing, assigned-number intelligence, and decoder behavior.

## Capability inventory

| Area | Current capability |
|---|---|
| Scanning | Timed Quick Scan, burst/pause recording, Bluetooth readiness, live search/filter/sort, minimum RSSI, and bounded result retention |
| Recording | Timestamped JSONL detections with advertisement data, RSSI, phone location, metadata summaries, crash recovery, replay, map timeline, and JSON/CSV export |
| Device intelligence | Bluetooth SIG company/member/adopted-number lookup, heuristic profiles, device-reported GATT identity, structured PnP ID, selected standard decoders, and profile dashboards |
| Automatic enrichment | Optional Quick Scan probing with one active connection, per-scan deduplication/cap, timeout/cancellation, and a read-only characteristic allowlist |
| Manual GATT | Connect/disconnect, services, characteristics, descriptors, reads, confirmed writes, and notification subscriptions |
| Hunter | One-device duplicate-advertisement RSSI tracking with generated audio, haptics, and stale-signal timeout |
| Library | Saved devices, notes, nicknames, alert templates, compound any/all criteria, previews, current-result testing, toggles, and live-scan rule refresh |
| Persistence | Versioned settings, append-only alert seed migrations, cached device snapshots, atomic metadata writes, and idempotent session recovery |
| Widget | Small, medium, large, and extra-large recent-session summaries from the shared App Group |
| Compatibility | iOS/iPadOS 15.2+, with conditional iOS 26 Liquid Glass controls |

## Important constraints

- CoreBluetooth does not expose BLE MAC addresses on iOS; peripheral identifiers are app-scoped.
- Classification and alert profiles are heuristic and must not be treated as authenticated identity.
- Map coordinates are the phone's observation location, not a verified device location.
- Unrestricted BLE scanning stops when the app backgrounds.
- Session-replay connections require a fresh matching realtime observation.
- Simulator tests cannot validate real radio discovery, RSSI behavior, or GATT interoperability.

## Current TODOs

- [ ] TODO: Introduce protocols for persistence, scanning, location, and notifications at the composition boundary.
- [ ] TODO: Move all persistence and recovery work off the main thread behind a serial worker or actor.
- [ ] TODO: Add deterministic UI automation and physical-device BLE integration coverage.
- [ ] TODO: Add session rename, tags, notes, retention policies, and bulk deletion.
- [ ] TODO: Add structured storage corruption/recovery reporting.
- [ ] TODO: Evaluate SQLite/GRDB after measuring large-session launch, replay, and query performance.
- [ ] TODO: Add localization and complete VoiceOver, Dynamic Type, and contrast audits.
- [ ] TODO: Add widget deep links and explicit stale/unavailable-data states.

