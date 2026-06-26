import UIKit

final class ScanStatusCard: CardView {
  let modeControl = UISegmentedControl(items: ["Active", "Record"])
  let statusLabel = UILabel()
  let timerLabel = UILabel()
  let deviceCountLabel = UILabel()
  let observationCountLabel = UILabel()
  let actionButton = UIButton(type: .system)
  let recordingNoteLabel = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)

    modeControl.selectedSegmentIndex = 0
    statusLabel.font = .preferredFont(forTextStyle: .headline)
    statusLabel.text = "Ready"

    timerLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .semibold)
    timerLabel.text = "02:00"

    deviceCountLabel.font = .preferredFont(forTextStyle: .headline)
    observationCountLabel.font = .preferredFont(forTextStyle: .headline)

    recordingNoteLabel.font = .preferredFont(forTextStyle: .caption1)
    recordingNoteLabel.textColor = .secondaryLabel
    recordingNoteLabel.numberOfLines = 0
    recordingNoteLabel.text =
      "Recording saves repeated BLE observations with the phone’s current location. It does not determine a device’s actual position."
    recordingNoteLabel.isHidden = true

    var configuration = UIButton.Configuration.filled()
    configuration.cornerStyle = .large
    configuration.baseBackgroundColor = AppTheme.accent
    configuration.image = UIImage(systemName: "play.fill")
    configuration.imagePadding = 8
    configuration.title = "Start Scan"
    actionButton.configuration = configuration
    actionButton.heightAnchor.constraint(equalToConstant: 50).isActive = true

    let deviceMetric = makeMetric(title: "Devices", valueLabel: deviceCountLabel)
    let observationMetric = makeMetric(title: "Observations", valueLabel: observationCountLabel)
    let metrics = UIStackView(arrangedSubviews: [deviceMetric, observationMetric])
    metrics.axis = .horizontal
    metrics.distribution = .fillEqually
    metrics.spacing = 12

    let stack = UIStackView(arrangedSubviews: [
      modeControl, statusLabel, timerLabel, metrics, recordingNoteLabel, actionButton,
    ])
    stack.axis = .vertical
    stack.spacing = 14
    addSubview(stack)
    stack.pinEdges(to: self, insets: UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18))

    updateMetrics(devices: 0, observations: 0)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func updateMetrics(devices: Int, observations: Int) {
    deviceCountLabel.text = "\(devices)"
    observationCountLabel.text = "\(observations)"
  }

  func setRunning(
    _ running: Bool, mode: ScanMode, burstActive: Bool = true, statusText: String? = nil
  ) {
    modeControl.isEnabled = !running
    recordingNoteLabel.isHidden = mode != .recording

    var configuration = actionButton.configuration
    configuration?.title = running ? "Stop" : (mode == .active ? "Start Scan" : "Start Recording")
    configuration?.image = UIImage(
      systemName: running ? "stop.fill" : (mode == .active ? "play.fill" : "record.circle"))
    configuration?.baseBackgroundColor = running ? .systemRed : AppTheme.accent
    actionButton.configuration = configuration

    if let statusText = statusText {
      statusLabel.text = statusText
    } else if running {
      statusLabel.text =
        mode == .active
        ? "Scanning continuously"
        : (burstActive ? "Recording • scan burst" : "Recording • battery pause")
    } else {
      statusLabel.text = "Ready"
    }
  }

  private func makeMetric(title: String, valueLabel: UILabel) -> UIView {
    let titleLabel = UILabel()
    titleLabel.text = title
    titleLabel.font = .preferredFont(forTextStyle: .caption1)
    titleLabel.textColor = .secondaryLabel

    let stack = UIStackView(arrangedSubviews: [valueLabel, titleLabel])
    stack.axis = .vertical
    stack.spacing = 1

    let container = UIView()
    container.backgroundColor = UIColor.tertiarySystemGroupedBackground
    container.layer.cornerRadius = 12
    container.addSubview(stack)
    stack.pinEdges(to: container, insets: UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12))
    return container
  }
}
