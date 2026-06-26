import UIKit

final class DeviceCell: UITableViewCell {
    static let reuseIdentifier = "DeviceCell"

    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let countLabel = UILabel()
    private let signalBadge = SignalBadgeView()
    private let savedImageView = UIImageView(image: UIImage(systemName: "star.fill"))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        backgroundColor = .clear

        nameLabel.font = .preferredFont(forTextStyle: .headline)
        nameLabel.adjustsFontForContentSizeCategory = true

        detailLabel.font = .preferredFont(forTextStyle: .caption1)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 2

        countLabel.font = .preferredFont(forTextStyle: .caption2)
        countLabel.textColor = .tertiaryLabel

        savedImageView.tintColor = .systemYellow
        savedImageView.isHidden = true
        savedImageView.setContentHuggingPriority(.required, for: .horizontal)

        let titleRow = UIStackView(arrangedSubviews: [nameLabel, savedImageView, UIView(), signalBadge])
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [titleRow, detailLabel, countLabel])
        stack.axis = .vertical
        stack.spacing = 4
        contentView.addSubview(stack)
        stack.pinEdges(to: contentView, insets: UIEdgeInsets(top: 11, left: 16, bottom: 11, right: 8))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with device: BLEDeviceSnapshot, isKnown: Bool) {
        nameLabel.text = device.displayName
        signalBadge.configure(rssi: device.latestRSSI)
        savedImageView.isHidden = !isKnown

        var details: [String] = [device.peripheralIdentifier.uuidString]
        if let company = device.advertisement.companyIdentifier {
            details.append(BluetoothCompanyLookup.displayName(for: company))
        } else if !device.advertisement.memberServiceUUIDs.isEmpty {
            details.append(
                BluetoothMemberUUIDLookup.displayList(for: device.advertisement.memberServiceUUIDs)
                    .prefix(2)
                    .joined(separator: ", ")
            )
        } else if !device.advertisement.serviceUUIDs.isEmpty {
            details.append(device.advertisement.serviceUUIDs.prefix(2).joined(separator: ", "))
        }
        detailLabel.text = details.joined(separator: "  •  ")
        countLabel.text = "\(device.sightingCount) observation\(device.sightingCount == 1 ? "" : "s") • last seen \(DateFormatter.signalTrailTime.string(from: device.lastSeen))"
    }
}
