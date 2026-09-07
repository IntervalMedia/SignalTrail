# OUI-SPY detection research

Thank you to colonelpanichacks for the OUI-SPY code and BLE detection research.
SignalTrail implements the Meta/Ray-Ban composite and Axon/TASER BLE rules in
Swift, informed by these sources:

- Project index: https://github.com/colonelpanichacks/oui-spy
- Detector: https://github.com/colonelpanichacks/ouispy-detector/blob/13f6a0ab11cc4a77ecf1cb2dd888c286d899e7ad/src/main.cpp
  (`matchesMetaComposite` and `PRESET_AXON`).
- Unified firmware: https://github.com/colonelpanichacks/oui-spy-unified-blue/blob/37aa77d68002ff73de6ac07fe375c30a4c3e6664/src/raw/detector.cpp
  (same rules).

The checked revisions contain no MIT license file. The standalone detector's
README license section says: "Open source project. Modifications welcome."
This notice records provenance; it does not assert an MIT license grant or
relicense upstream work.

## Review and iOS adaptation

The Meta rule requires manufacturer bytes `53 0D` and advertised service `FD5F`
in one advertisement, or a case-insensitive advertised-name substring of
`Ray-Ban`, `Wayfarer`, or `Oakley Meta`. Neither identifier alone is sufficient.
SignalTrail accepts short UUIDs and full Bluetooth base UUIDs, including iOS
advertisement overflow services. Unlike the upstream substring check, arbitrary
128-bit UUIDs containing `FD5F` do not match. Solicited services, derived member
names, and service-data keys do not substitute for the advertised service list.

The Axon rule matches Bluetooth company ID `034D` or advertised service `FC81`.
Upstream also uses MAC OUI `00:25:DF`. iOS does not expose BLE MAC addresses,
so this is omitted; it must not be used as a manufacturer-data prefix.
Existing saved alert rules are preserved, including older Axon criteria. New
installations use the Axon detector profile. Existing installations can use
`axonTaser` as a built-in detector criterion.

Generic upstream name, company, and service filters already have equivalents in
SignalTrail. Wi-Fi fingerprints, MAC filters, and raw radio capture are outside
CoreBluetooth's capabilities. Find My, Flipper, Flock/Penguin, and HC-module
rules already present in SignalTrail are unchanged by this work.

## OUI-SPY Foxhunter

Thank you to colonelpanichacks for publishing the OUI-SPY Foxhunter source:

- https://github.com/colonelpanichacks/ouispy-foxhunter/blob/866be0680d46e23be9babd1efad35d5aeb05f72d/src/main.cpp

SignalTrail ports its piecewise RSSI-to-beep interval mapping and five-second
last-seen window. The iOS version tracks an app-scoped CoreBluetooth peripheral
UUID rather than a hardware MAC address, generates its own alert tones, and adds
configurable haptic feedback. Audio and haptic playback uses an 80 ms minimum
cadence at the strongest readings so each phone-generated pulse can complete.
The checked revision has no license file; its
README says, "Open source project. Modifications welcome." This notice records
the exact source revision and does not assert an MIT license grant.

Matches are device-family hints based on unauthenticated advertisements. They
do not verify a product model, ownership, or device purpose. On-device BLE
verification remains necessary; simulator tests validate fixture matching only.
