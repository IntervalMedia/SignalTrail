import UIKit

class CardView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = AppTheme.cardBackground
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0 : 0.06
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 5)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
