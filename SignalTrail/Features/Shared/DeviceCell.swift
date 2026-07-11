import UIKit

final class DeviceCell: UITableViewCell {
    static let reuseIdentifier = "DeviceCell"

    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let countLabel = UILabel()
    private let signalBadge = SignalBadgeView()
    private let savedImageView = UIImageView(image: UIImage(systemName: "star.fill"))
    private let badgeStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        backgroundColor = .clear

        nameLabel.font = .preferredFont(forTextStyle: .headline)
        nameLabel.adjustsFontForContentSizeCategory = true

        detailLabel.font = .preferredFont(forTextStyle: .caption1)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 3

        countLabel.font = .preferredFont(forTextStyle: .caption2)
        countLabel.textColor = .tertiaryLabel

        savedImageView.tintColor = .systemYellow
        savedImageView.isHidden = true
        savedImageView.setContentHuggingPriority(.required, for: .horizontal)

        badgeStack.axis = .horizontal
        badgeStack.spacing = 6
        badgeStack.alignment = .center
        badgeStack.distribution = .fill

        let titleRow = UIStackView(arrangedSubviews: [nameLabel, savedImageView, UIView(), signalBadge])
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [titleRow, detailLabel, badgeStack, countLabel])
        stack.axis = .vertical
        stack.spacing = 4
        contentView.addSubview(stack)
        stack.pinEdges(to: contentView, insets: UIEdgeInsets(top: 11, left: 16, bottom: 11, right: 8))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with device: BLEDeviceSnapshot, isKnown: Bool, alertMatched: Bool = false) {
        nameLabel.text = device.presentationName
        signalBadge.configure(rssi: device.latestRSSI)
        savedImageView.isHidden = !isKnown

        badgeStack.arrangedSubviews.forEach {
            badgeStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let intelligence = device.intelligence
        let manufacturerLine = intelligence.manufacturer.map { "Manufacturer: \($0)" }
        detailLabel.text = [
            "Estimated category: \(intelligence.categoryTitle) (\(intelligence.probability)%)",
            manufacturerLine,
            "\(device.signalDescription) • last seen \(DateFormatter.signalTrailTime.string(from: device.lastSeen))"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")

        if isKnown {
            badgeStack.addArrangedSubview(makeBadge("Known", color: .systemYellow))
        }
        if alertMatched {
            badgeStack.addArrangedSubview(makeBadge("Alert match", color: .systemOrange))
        }
        if device.advertisement.isConnectable {
            badgeStack.addArrangedSubview(makeBadge("Connectable", color: AppTheme.accent))
        }
        if intelligence.category != .unknown {
            badgeStack.addArrangedSubview(makeBadge("Guess • \(intelligence.probability)%", color: .systemBlue))
        }
        badgeStack.isHidden = badgeStack.arrangedSubviews.isEmpty

        countLabel.text = "\(device.sightingCount) observation\(device.sightingCount == 1 ? "" : "s") • category is an estimate"
    }

    private func makeBadge(_ text: String, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .caption2)
        label.textColor = color
        label.backgroundColor = color.withAlphaComponent(0.12)
        label.layer.cornerRadius = 8
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.textAlignment = .center
        return PaddedLabel(wrapping: label)
    }
}

private final class PaddedLabel: UILabel {
    private let contentInsets = UIEdgeInsets(top: 3, left: 7, bottom: 3, right: 7)

    convenience init(wrapping source: UILabel) {
        self.init(frame: .zero)
        text = source.text
        font = source.font
        textColor = source.textColor
        backgroundColor = source.backgroundColor
        layer.cornerRadius = source.layer.cornerRadius
        layer.cornerCurve = source.layer.cornerCurve
        clipsToBounds = true
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + contentInsets.left + contentInsets.right,
            height: size.height + contentInsets.top + contentInsets.bottom
        )
    }
}

// Transitional compatibility for views not yet migrated from the old classification API.
extension DeviceIntelligence {
    var title: String { categoryTitle }
    var confidence: String { confidenceLabel }
}

extension BLEAdvertisement {
    var classification: DeviceIntelligence { intelligence }
}
