# Validation notes

This document tracks what should be verified for the current SignalTrail implementation. It is intentionally source-aligned and avoids preserving stale one-off results from older build environments.

## Current implementation summary

- App target deployment target: **iOS/iPadOS 15.2**
- Test target deployment target: **iOS/iPadOS 16.0**
- UI structure: **Scan**, **Sessions**, **Known**, and **Settings** tabs
- Persistence: JSON and JSONL files in Application Support, plus a single Codable settings object in `UserDefaults`
- Bluetooth assigned numbers:
  - company identifiers loaded at runtime from bundled `company_identifiers.yaml`
  - 16-bit member UUID names generated into `BluetoothMemberUUIDLookup.swift`
- Background behavior: any running scan stops when the app scene enters the background
- External dependencies: none

## Recommended verification on macOS

1. Open `SignalTrail.xcodeproj` in Xcode 14 or newer.
2. Select a development team and build the `SignalTrail` target.
3. Run on a physical iPhone or iPad, not the Simulator.
4. Confirm the main flows:
   - active scan starts, counts down, and stops automatically
   - record mode requests location permission when needed
   - recorded sessions appear in the Sessions tab
   - known devices can be saved from device detail
   - detection alerts can be created and persisted
   - JSON and CSV export both succeed from session detail
5. Confirm app limits remain accurate:
   - no BLE MAC address is exposed
   - map points represent phone observation locations
   - scanning stops when the app backgrounds

## Optional command-line checks

- `plutil -lint SignalTrail/Info.plist`
- `plutil -lint SignalTrail.xcodeproj/project.pbxproj`
- `swiftc -module-cache-path /tmp/swift-module-cache -typecheck SignalTrail/Services/Bluetooth/BluetoothCompanyLookup.swift`

## Review date

Reviewed against the current source layout and implementation on **2026-06-25**.
