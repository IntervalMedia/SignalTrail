import Foundation

/// Compatibility facade for member-assignment alert matching and presentation.
enum BluetoothMemberUUIDLookup {
    static func name(for uuid: String) -> String? {
        BluetoothAssignedUUIDLookup.metadata(for: uuid, kind: .member)?.name
    }

    static func displayName(for uuid: String) -> String {
        BluetoothAssignedUUIDLookup.metadata(for: uuid, kind: .member)?.displayName ?? uuid
    }

    static func contains(_ uuid: String) -> Bool {
        BluetoothAssignedUUIDLookup.metadata(for: uuid, kind: .member) != nil
    }

    static func displayList(for uuids: [String]) -> [String] {
        uuids.compactMap {
            BluetoothAssignedUUIDLookup.metadata(for: $0, kind: .member)?.displayName
        }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
