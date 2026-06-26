import Foundation

extension DateFormatter {
    static func wallClock(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        formatter.timeZone = timeZone
        return formatter
    }

    static let signalTrailList: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let signalTrailTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()
}

extension TimeInterval {
    var clockString: String {
        let total = max(0, Int(self.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension Data {
    var hexadecimalString: String {
        map { String(format: "%02X", $0) }.joined()
    }

    init?(hexadecimalString: String) {
        let cleaned = hexadecimalString
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ":", with: "")
            .uppercased()
        guard cleaned.count.isMultiple(of: 2) else { return nil }

        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}

extension String {
    var normalizedHex: String {
        replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ":", with: "")
            .uppercased()
    }
}
