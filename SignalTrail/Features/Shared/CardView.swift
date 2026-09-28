import UIKit

class CardView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = AppTheme.cardBackground
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        layer.borderWidth = 1 / UIScreen.main.scale
        layer.borderColor = AppTheme.separator.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
