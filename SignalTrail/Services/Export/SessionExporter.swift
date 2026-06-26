import Foundation

struct SessionExporter {
  enum Format {
    case json
    case csv
  }

  static func makeTemporaryExport(
    session: ScanSession,
    detections: [BLEDetection],
    format: Format
  ) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
    switch format {
    case .json:
      let export = ExportPayload(session: session, detections: detections)
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let url = directory.appendingPathComponent("SignalTrail-\(session.id.uuidString).json")
      try encoder.encode(export).write(to: url, options: .atomic)
      return url

    case .csv:
      let url = directory.appendingPathComponent("SignalTrail-\(session.id.uuidString).csv")
      var rows = [
        "timestamp,device_name,peripheral_identifier,rssi,latitude,longitude,horizontal_accuracy,company_identifier,manufacturer_data,service_uuids"
      ]
      let formatter = ISO8601DateFormatter()
      for detection in detections {
        let latitude = detection.latitude.map { String($0) } ?? ""
        let longitude = detection.longitude.map { String($0) } ?? ""
        let accuracy = detection.horizontalAccuracy.map { String($0) } ?? ""
        let companyIdentifier =
          detection.advertisement.companyIdentifier.map {
            String(format: "0x%04X", $0)
          } ?? ""
        let serviceUUIDs = escape(detection.advertisement.serviceUUIDs.joined(separator: "|"))
        let values: [String] = [
          formatter.string(from: detection.timestamp),
          escape(detection.displayName),
          detection.peripheralIdentifier.uuidString,
          String(detection.rssi),
          latitude,
          longitude,
          accuracy,
          companyIdentifier,
          detection.advertisement.manufacturerDataHex ?? "",
          serviceUUIDs,
        ]
        rows.append(values.joined(separator: ","))
      }
      guard let data = rows.joined(separator: "\n").data(using: .utf8) else {
        throw CocoaError(.fileWriteInapplicableStringEncoding)
      }
      try data.write(to: url, options: .atomic)
      return url
    }
  }

  private static func escape(_ value: String) -> String {
    "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
  }
}

private struct ExportPayload: Codable {
  let session: ScanSession
  let detections: [BLEDetection]
}
