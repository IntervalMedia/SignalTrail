import Foundation

///  BluetoothCompanyLookup is created from the data file 'company_identifiers.yaml' availble from: https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/company_identifiers/company_identifiers.yaml
enum BluetoothCompanyLookup {
  private static let names = loadNames()

  private final class BundleToken {}

  private static func loadNames() -> [UInt16: String] {
    let bundles = [Bundle(for: BundleToken.self), .main]

    guard let url = bundles.lazy.compactMap({
      $0.url(forResource: "company_identifiers", withExtension: "yaml")
    }).first,
    let contents = try? String(contentsOf: url, encoding: .utf8) else {
      assertionFailure("Missing bundled company_identifiers.yaml")
      return [:]
    }

    var lookup: [UInt16: String] = [:]
    lookup.reserveCapacity(4096)

    var pendingIdentifier: UInt16?

    for rawLine in contents.split(whereSeparator: \.isNewline) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)

      if line.hasPrefix("- value:") {
        let value = line.dropFirst("- value:".count).trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("0x") {
          pendingIdentifier = UInt16(value.dropFirst(2), radix: 16)
        } else {
          pendingIdentifier = UInt16(value, radix: 10)
        }
        continue
      }

      guard line.hasPrefix("name:"), let identifier = pendingIdentifier else {
        continue
      }

      let value = line.dropFirst("name:".count).trimmingCharacters(in: .whitespaces)
      let name: String

      if value.count >= 2, value.first == "'", value.last == "'" {
        name = String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
      } else if value.count >= 2, value.first == "\"", value.last == "\"" {
        name = String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
      } else {
        name = String(value)
      }

      lookup[identifier] = name
      pendingIdentifier = nil
    }

    return lookup
  }

  static func name(for identifier: UInt16?) -> String? {
    guard let identifier = identifier else { return nil }
    return names[identifier]
  }

  static func displayName(for identifier: UInt16?) -> String {
    guard let identifier = identifier else { return "Not advertised" }
    let hex = String(format: "0x%04X", identifier)
    if let name = names[identifier] { return "\(name) (\(hex))" }
    return hex
  }

  static var commonCompanies: [(UInt16, String)] {
    names.map { ($0.key, $0.value) }.sorted { $0.1 < $1.1 }
  }
}
