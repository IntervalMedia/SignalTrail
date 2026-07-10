# Validation notes

This document tracks what should be verified for the current SignalTrail implementation. It is intentionally source-aligned and avoids preserving stale one-off results from older build environments.

## Current implementation summary

- App target deployment target: **iOS/iPadOS 15.2**
- Test target deployment target: **iOS/iPadOS 16.0**
- UI structure: **Scan**, **Sessions**, **Library**, and **Settings** tabs
- Persistence: JSON and JSONL files in Application Support, plus a single Codable settings object in `UserDefaults`
- Bluetooth assigned numbers:
  - company identifiers loaded at runtime from bundled `company_identifiers.yaml`
  - 16-bit member UUID names generated into `BluetoothMemberUUIDLookup.swift`
- Alert defaults: seeded detector rules for Axon/TASER, Apple Find My-like broadcasts, Flipper Zero, Flock/Penguin battery-like broadcasts, HC serial-module names, and Meta/Ray-Ban identifiers
- Scan UX: first-run onboarding, Bluetooth/Location/Notification readiness, Quick Scan, Record Session, live filter chips, sorting, and minimum RSSI in the scan screen
- Alert UX: Library Devices/Alerts switcher, alert templates, plain-language preview, and current-result test action before saving
- Background behavior: any running scan stops when the app scene enters the background
- External dependencies: none

## Recommended verification on macOS

1. Open `SignalTrail.xcodeproj` in Xcode 14 or newer.
2. Select a development team and build the `SignalTrail` target.
3. Run on a physical iPhone or iPad, not the Simulator.
4. Confirm the main flows:
   - first-run onboarding appears on a fresh install
   - Quick Scan starts, counts down, and stops automatically
   - Record Session explains and requests location permission when needed
   - readiness checklist reflects Bluetooth, Location, and Notification state
   - live-result search, filter chips, sorting, and minimum RSSI update the displayed list
   - recorded sessions appear in the Sessions tab
   - known devices can be saved from device detail
   - device detail shows the summary first and expands/copies technical data on demand
   - detection alerts can be created from live rows, device details, recorded-session rows, and the Library tab
   - alert save returns without hanging and only then offers contextual notification permission
   - alert rules can be previewed, tested against current results, toggled on/off, and persisted
   - a fresh install seeds each built-in default alert exactly once
   - company-name and member-UUID-name rules match the same devices as their advertised lookup names
   - GATT writes appear under Advanced tools and require confirmation
   - JSON and CSV export both succeed from session detail
5. Confirm app limits remain accurate:
   - no BLE MAC address is exposed
   - map points represent phone observation locations
   - scanning stops when the app backgrounds

## Optional command-line checks

- `plutil -lint SignalTrail/Info.plist`
- `plutil -lint SignalTrail.xcodeproj/project.pbxproj`
- `swiftc -module-cache-path /tmp/swift-module-cache -typecheck SignalTrail/Services/Bluetooth/BluetoothCompanyLookup.swift`
- `xcodebuild -project SignalTrail.xcodeproj -scheme SignalTrail -destination 'generic/platform=iOS Simulator' build`
- `xcodebuild -project SignalTrail.xcodeproj -scheme SignalTrail -destination 'platform=iOS Simulator,name=<installed simulator>' test`
- `xcodebuild -project SignalTrail.xcodeproj -scheme SignalTrail -destination 'generic/platform=iOS' build`

The generic iOS device build can fail at signing if the configured provisioning profile is expired or does not match the selected team and bundle identifier.

## Review date

Reviewed against the current source layout and implementation on **2026-07-11**.
