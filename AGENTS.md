# Repository Guidelines

## Project Structure & Module Organization
`SignalTrail/` contains the iOS app target. Keep app wiring in `App/`, shared models and formatting in `Domain/`, feature UI flows in `Features/`, and platform/service code in `Services/` (`Bluetooth`, `Location`, `Notifications`, `Persistence`, `Export`). Assets and `Info.plist` live under `Resources/`. Unit tests are in `SignalTrailTests/`. Read [README.md](/Volumes/Elements/SignalTrail/README.md) for runtime constraints and [ARCHITECTURE.md](/Volumes/Elements/SignalTrail/ARCHITECTURE.md) before changing service boundaries.

## Build, Test, and Development Commands
Open `SignalTrail.xcodeproj` in Xcode 14+ for day-to-day work. Useful CLI commands:

- `xcodebuild -project SignalTrail.xcodeproj -scheme SignalTrail -destination 'generic/platform=iOS' build` builds the app target.
- `xcodebuild -project SignalTrail.xcodeproj -scheme SignalTrail -destination 'platform=iOS Simulator,name=<installed simulator>' test` runs `SignalTrailTests`; replace the simulator name with one installed locally.
- `plutil -lint SignalTrail/Info.plist` validates the app plist.
- `plutil -lint SignalTrail.xcodeproj/project.pbxproj` catches malformed project-file edits.

BLE scanning must be verified on a physical iPhone or iPad; the Simulator is only suitable for unit tests.

## Coding Style & Naming Conventions
Write Swift in the existing UIKit-first style: types in `UpperCamelCase`, methods/properties in `lowerCamelCase`, and enum cases in `lowerCamelCase`. Name screens as `...ViewController`, view models as `...ViewModel`, and services by responsibility, for example `NotificationService`. Use 4-space indentation in new Swift code and keep line wrapping/readability consistent with the surrounding file. No formatter or linter is checked into this repo, so do not introduce wholesale style churn.

## Testing Guidelines
Tests use `XCTest` in `SignalTrailTests/`. Name files `*Tests.swift` and methods `test...`, for example `testSessionRoundTrip`. Add unit coverage for persistence, alert matching, and advertisement parsing when behavior changes. Alert changes should cover seeded defaults, direct enable/disable toggles, and any derived Bluetooth SIG company/member-name matching paths. For Bluetooth or location flows that cannot be exercised in XCTest alone, note the required on-device verification in the PR.

## Commit & Pull Request Guidelines
Use short imperative commit subjects such as `Add manufacturer data parsing test` or `Fix session replay map state`. Keep commits scoped to one change and avoid mixing UI, persistence, and Bluetooth behavior without a clear reason. PRs should summarize user-visible impact, list validation performed (`xcodebuild test`, device checks), link related issues, and include screenshots for UI changes.

## Security & Configuration Tips
The app stores data locally in Application Support and `UserDefaults`; do not add secrets or remote credentials. Keep privacy-sensitive changes aligned with the location/Bluetooth disclosures already called out in `README.md`.
