#!/usr/bin/env ruby

require "json"
require "shellwords"
require "yaml"

if ARGV.length < 2 || ARGV.length > 3
  warn "Usage: generate_bluetooth_sig_lookups.rb <bluetooth-sig-public-root> <output-swift> [member-wrapper-swift]"
  exit 64
end

source_root = File.expand_path(ARGV[0])
output_path = File.expand_path(ARGV[1])
member_wrapper_path = ARGV[2] && File.expand_path(ARGV[2])

def load_uuid_entries(source_root, relative_path)
  document = YAML.safe_load(File.read(File.join(source_root, relative_path)))
  document.fetch("uuids").map do |entry|
    {
      value: Integer(entry.fetch("uuid")),
      name: entry.fetch("name"),
      identifier: entry["id"]
    }
  end.sort_by { |entry| entry[:value] }
end

def swift_string(value)
  JSON.generate(value)
end

def render_metadata_dictionary(name, entries, kind)
  lines = entries.map do |entry|
    identifier = entry[:identifier] ? swift_string(entry[:identifier]) : "nil"
    format(
      "        0x%04X: BluetoothAssignedUUIDMetadata(value: 0x%04X, name: %s, kind: .%s, identifier: %s),",
      entry[:value], entry[:value], swift_string(entry[:name]), kind, identifier
    )
  end
  <<~SWIFT
        private static let #{name}: [UInt16: BluetoothAssignedUUIDMetadata] = [
    #{lines.join("\n")}
        ]
  SWIFT
end

service_entries = load_uuid_entries(
  source_root,
  "assigned_numbers/uuids/service_uuids.yaml"
)
characteristic_entries = load_uuid_entries(
  source_root,
  "assigned_numbers/uuids/characteristic_uuids.yaml"
)
descriptor_entries = load_uuid_entries(
  source_root,
  "assigned_numbers/uuids/descriptors.yaml"
)
unit_entries = load_uuid_entries(
  source_root,
  "assigned_numbers/uuids/units.yaml"
)
sdo_entries = load_uuid_entries(
  source_root,
  "assigned_numbers/uuids/sdo_uuids.yaml"
)
member_entries = load_uuid_entries(
  source_root,
  "assigned_numbers/uuids/member_uuids.yaml"
)

appearance_document = YAML.safe_load(
  File.read(File.join(source_root, "assigned_numbers/core/appearance_values.yaml"))
)
appearance_categories = {}
appearance_subcategories = {}
appearance_document.fetch("appearance_values").each do |entry|
  category = Integer(entry.fetch("category"))
  appearance_categories[category] = entry.fetch("name").strip
  entry.fetch("subcategory", []).each do |subcategory|
    raw_value = (category << 6) | Integer(subcategory.fetch("value"))
    appearance_subcategories[raw_value] = subcategory.fetch("name").strip
  end
end

category_lines = appearance_categories.sort.map do |value, name|
  format("        0x%03X: %s,", value, swift_string(name))
end
subcategory_lines = appearance_subcategories.sort.map do |value, name|
  format("        0x%04X: %s,", value, swift_string(name))
end

source_commit = `git -C #{Shellwords.escape(source_root)} rev-parse HEAD 2>/dev/null`.strip
source_commit = "unknown" if source_commit.empty?

output = <<~SWIFT
  import Foundation

  // Generated from Bluetooth SIG public assigned numbers at commit #{source_commit}.
  // See scripts/generate_bluetooth_sig_lookups.rb. Do not edit the generated tables by hand.

  enum BluetoothAssignedUUIDKind: String, CaseIterable, Hashable {
      case adoptedService
      case characteristic
      case descriptor
      case unit
      case member
      case standardsOrganization
  }

  struct BluetoothAssignedUUIDMetadata: Hashable {
      let value: UInt16
      let name: String
      let kind: BluetoothAssignedUUIDKind
      let identifier: String?

      var hexadecimalValue: String {
          String(format: "0x%04X", value)
      }

      var displayName: String {
          "\\(name) (\\(hexadecimalValue))"
      }

      var assignmentDescription: String {
          switch kind {
          case .adoptedService:
              return "Bluetooth SIG adopted service: \\(name)"
          case .characteristic:
              return "Bluetooth SIG characteristic: \\(name)"
          case .descriptor:
              return "Bluetooth SIG descriptor: \\(name)"
          case .unit:
              return "Bluetooth SIG assigned unit: \\(name)"
          case .member:
              return "UUID assigned to \\(name)"
          case .standardsOrganization:
              return "Standards organization UUID: \\(name)"
          }
      }
  }

  struct BluetoothAppearanceMetadata: Hashable {
      let rawValue: UInt16
      let categoryName: String
      let subcategoryName: String?

      var displayName: String {
          subcategoryName ?? categoryName
      }
  }

  enum BluetoothAssignedUUIDLookup {
      static func metadata(
          for rawUUID: String,
          kind: BluetoothAssignedUUIDKind
      ) -> BluetoothAssignedUUIDMetadata? {
          guard let value = canonical16BitValue(from: rawUUID) else { return nil }
          switch kind {
          case .adoptedService:
              return adoptedServices[value]
          case .characteristic:
              return characteristics[value]
          case .descriptor:
              return descriptors[value]
          case .unit:
              return units[value]
          case .member:
              return memberUUIDs[value]
          case .standardsOrganization:
              return standardsOrganizationUUIDs[value]
          }
      }

      static func serviceMetadata(for rawUUID: String) -> BluetoothAssignedUUIDMetadata? {
          metadata(for: rawUUID, kind: .adoptedService)
              ?? metadata(for: rawUUID, kind: .standardsOrganization)
              ?? metadata(for: rawUUID, kind: .member)
      }

      static func allMetadata(for rawUUID: String) -> [BluetoothAssignedUUIDMetadata] {
          BluetoothAssignedUUIDKind.allCases.compactMap { metadata(for: rawUUID, kind: $0) }
      }

      static func canonical16BitValue(from rawUUID: String) -> UInt16? {
          let trimmed = rawUUID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
          let withoutPrefix = trimmed.hasPrefix("0X") ? String(trimmed.dropFirst(2)) : trimmed

          if withoutPrefix.count == 4 {
              return UInt16(withoutPrefix, radix: 16)
          }

          if withoutPrefix.count == 8, withoutPrefix.hasPrefix("0000") {
              return UInt16(withoutPrefix.suffix(4), radix: 16)
          }

          let baseSuffix = "-0000-1000-8000-00805F9B34FB"
          let compactBaseSuffix = "00001000800000805F9B34FB"
          let compact = withoutPrefix.replacingOccurrences(of: "-", with: "")
          guard (withoutPrefix.count == 36 && withoutPrefix.hasSuffix(baseSuffix))
                  || (compact.count == 32 && compact.hasSuffix(compactBaseSuffix)) else {
              return nil
          }
          let assignedPortion = String(compact.prefix(8))
          guard assignedPortion.hasPrefix("0000") else { return nil }
          return UInt16(assignedPortion.suffix(4), radix: 16)
      }

      static func canonical16BitString(from rawUUID: String) -> String? {
          canonical16BitValue(from: rawUUID).map { String(format: "0x%04X", $0) }
      }

  #{render_metadata_dictionary("adoptedServices", service_entries, "adoptedService")}
  #{render_metadata_dictionary("characteristics", characteristic_entries, "characteristic")}
  #{render_metadata_dictionary("descriptors", descriptor_entries, "descriptor")}
  #{render_metadata_dictionary("units", unit_entries, "unit")}
  #{render_metadata_dictionary("memberUUIDs", member_entries, "member")}
  #{render_metadata_dictionary("standardsOrganizationUUIDs", sdo_entries, "standardsOrganization")}
  }

  enum BluetoothAppearanceLookup {
      static func metadata(for rawValue: UInt16) -> BluetoothAppearanceMetadata? {
          let category = rawValue >> 6
          guard let categoryName = categoryNames[category] else { return nil }
          return BluetoothAppearanceMetadata(
              rawValue: rawValue,
              categoryName: categoryName,
              subcategoryName: subcategoryNames[rawValue]
          )
      }

      private static let categoryNames: [UInt16: String] = [
  #{category_lines.join("\n")}
      ]

      private static let subcategoryNames: [UInt16: String] = [
  #{subcategory_lines.join("\n")}
      ]
  }
SWIFT

File.write(output_path, output)

if member_wrapper_path
  wrapper = <<~SWIFT
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
  SWIFT
  File.write(member_wrapper_path, wrapper)
end
