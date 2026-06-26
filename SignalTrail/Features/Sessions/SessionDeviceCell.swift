import UIKit

final class SessionDeviceCell: UITableViewCell {
    static let reuseIdentifier = "SessionDeviceCell"

    func configure(name: String, identifier: UUID, observationCount: Int, latestRSSI: Int, timestamp: Date) {
        var content = defaultContentConfiguration()
        content.text = name
        content.secondaryText = "\(observationCount) observations • \(latestRSSI) dBm • \(DateFormatter.signalTrailTime.string(from: timestamp))\n\(identifier.uuidString)"
        content.secondaryTextProperties.numberOfLines = 2
        content.image = UIImage(systemName: "antenna.radiowaves.left.and.right")
        content.imageProperties.tintColor = AppTheme.accent
        contentConfiguration = content
        accessoryType = .disclosureIndicator
    }
}
