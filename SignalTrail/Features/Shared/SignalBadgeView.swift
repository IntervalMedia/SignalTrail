import UIKit

final class SignalBadgeView: UIView {
    private let imageView = UIImageView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 11
        layer.cornerCurve = .continuous

        imageView.image = UIImage(systemName: "antenna.radiowaves.left.and.right")
        imageView.contentMode = .scaleAspectFit
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

        let stack = UIStackView(arrangedSubviews: [imageView, label])
        stack.axis = .horizontal
        stack.spacing = 5
        stack.alignment = .center
        addSubview(stack)
        stack.pinEdges(to: self, insets: UIEdgeInsets(top: 5, left: 8, bottom: 5, right: 8))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(rssi: Int) {
        label.text = "\(rssi) dBm"
        let color: UIColor
        switch SignalLevel(rssi: rssi) {
        case .excellent: color = .systemGreen
        case .good: color = .systemTeal
        case .fair: color = .systemOrange
        case .weak: color = .systemRed
        case .unknown: color = .secondaryLabel
        }
        imageView.tintColor = color
        label.textColor = color
        backgroundColor = color.withAlphaComponent(0.12)
    }
}
