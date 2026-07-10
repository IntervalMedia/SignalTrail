import UIKit

final class ScanStatusCard: CardView {
  let modeControl = UISegmentedControl(items: ScanMode.allCases.map(\.title))
  let timerLabel = UILabel()
  let actionButton = UIButton(type: .system)

  private let quickDescriptionLabel = UILabel()
  private let recordingDescriptionLabel = UILabel()
  private let statusLabel = UILabel()
  private let timerTitleLabel = UILabel()
  private let deviceCountLabel = UILabel()
  private let observationCountLabel = UILabel()
  private let recordingNoteLabel = UILabel()
  private let activityIndicator = UIActivityIndicatorView(style: .medium)
  private let statusImageView = UIImageView()
  private let bluetoothValueLabel = UILabel()
  private let locationValueLabel = UILabel()
  private let notificationValueLabel = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)

    modeControl.selectedSegmentIndex = 0

    [quickDescriptionLabel, recordingDescriptionLabel].forEach {
      $0.font = .preferredFont(forTextStyle: .caption1)
      $0.textColor = .secondaryLabel
      $0.numberOfLines = 0
    }
    quickDescriptionLabel.text = ScanMode.active.description
    recordingDescriptionLabel.text = ScanMode.recording.description

    statusLabel.font = .preferredFont(forTextStyle: .headline)
    statusLabel.text = "Ready"
    statusLabel.numberOfLines = 0

    statusImageView.image = UIImage(systemName: "checkmark.circle.fill")
    statusImageView.tintColor = .systemGreen
    statusImageView.setContentHuggingPriority(.required, for: .horizontal)

    timerTitleLabel.font = .preferredFont(forTextStyle: .caption1)
    timerTitleLabel.textColor = .secondaryLabel
    timerTitleLabel.text = "Time remaining"

    timerLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .semibold)
    timerLabel.text = "02:00"

    deviceCountLabel.font = .preferredFont(forTextStyle: .headline)
    observationCountLabel.font = .preferredFont(forTextStyle: .headline)

    recordingNoteLabel.font = .preferredFont(forTextStyle: .caption1)
    recordingNoteLabel.textColor = .secondaryLabel
    recordingNoteLabel.numberOfLines = 0
    recordingNoteLabel.text =
      "SignalTrail records where this phone observed a signal. It does not verify the device's actual location."
    recordingNoteLabel.isHidden = true

    var configuration = UIButton.Configuration.filled()
    configuration.cornerStyle = .large
    configuration.baseBackgroundColor = AppTheme.accent
    configuration.image = UIImage(systemName: "play.fill")
    configuration.imagePadding = 8
    configuration.title = "Start Quick Scan"
    actionButton.configuration = configuration
    actionButton.heightAnchor.constraint(equalToConstant: 50).isActive = true

    let modeDescriptions = UIStackView(arrangedSubviews: [
      makeModeDescription(symbol: "bolt.fill", label: quickDescriptionLabel),
      makeModeDescription(symbol: "record.circle", label: recordingDescriptionLabel),
    ])
    modeDescriptions.axis = .vertical
    modeDescriptions.spacing = 5

    let readiness = makeReadinessChecklist()
    let statusRow = UIStackView(arrangedSubviews: [activityIndicator, statusImageView, statusLabel])
    statusRow.axis = .horizontal
    statusRow.spacing = 8
    statusRow.alignment = .center

    let timerStack = UIStackView(arrangedSubviews: [timerTitleLabel, timerLabel])
    timerStack.axis = .vertical
    timerStack.spacing = 2

    let deviceMetric = makeMetric(title: "Devices found", valueLabel: deviceCountLabel)
    let observationMetric = makeMetric(title: "Observations", valueLabel: observationCountLabel)
    let metrics = UIStackView(arrangedSubviews: [deviceMetric, observationMetric])
    metrics.axis = .horizontal
    metrics.distribution = .fillEqually
    metrics.spacing = 12

    let stack = UIStackView(arrangedSubviews: [
      readiness,
      modeControl,
      modeDescriptions,
      statusRow,
      timerStack,
      metrics,
      recordingNoteLabel,
      actionButton,
    ])
    stack.axis = .vertical
    stack.spacing = 14
    addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    let leading = stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18)
    let trailing = stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18)
    leading.priority = .defaultHigh
    trailing.priority = .defaultHigh
    NSLayoutConstraint.activate([
      leading,
      trailing,
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
    ])

    updateMetrics(devices: 0, observations: 0)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func updateMetrics(devices: Int, observations: Int) {
    deviceCountLabel.text = "\(devices)"
    observationCountLabel.text = "\(observations)"
  }

  func configureReadiness(bluetooth: String, location: String, notifications: String) {
    bluetoothValueLabel.text = bluetooth
    locationValueLabel.text = location
    notificationValueLabel.text = notifications
  }

  func setRunning(
    _ running: Bool, mode: ScanMode, burstActive: Bool = true, statusText: String? = nil
  ) {
    modeControl.isEnabled = !running
    recordingNoteLabel.isHidden = mode != .recording
    timerTitleLabel.text = mode == .active ? "Time remaining" : "Recording duration"

    var configuration = actionButton.configuration
    configuration?.title =
      running ? "Stop" : (mode == .active ? "Start Quick Scan" : "Start Recording")
    configuration?.image = UIImage(
      systemName: running ? "stop.fill" : (mode == .active ? "bolt.fill" : "record.circle"))
    configuration?.baseBackgroundColor = running ? .systemRed : AppTheme.accent
    actionButton.configuration = configuration

    if running {
      activityIndicator.startAnimating()
      activityIndicator.isHidden = false
      statusImageView.isHidden = true
    } else {
      activityIndicator.stopAnimating()
      activityIndicator.isHidden = true
      statusImageView.isHidden = false
    }

    let resolvedStatus: String
    if let statusText {
      resolvedStatus = statusText
    } else if running {
      resolvedStatus =
        mode == .active
        ? "Scanning"
        : (burstActive ? "Recording scan burst" : "Recording battery pause")
    } else {
      resolvedStatus = "Ready"
    }
    statusLabel.text = resolvedStatus
    applyTone(for: resolvedStatus, running: running, mode: mode, burstActive: burstActive)
  }

  private func applyTone(for status: String, running: Bool, mode: ScanMode, burstActive: Bool) {
    let color: UIColor
    let symbol: String

    if status.localizedCaseInsensitiveContains("Bluetooth") {
      color = .systemOrange
      symbol = "antenna.radiowaves.left.and.right.slash"
    } else if status.localizedCaseInsensitiveContains("location") {
      color = .systemBlue
      symbol = "location.circle.fill"
    } else if running && mode == .recording && !burstActive {
      color = .systemYellow
      symbol = "pause.circle.fill"
    } else if running && mode == .recording {
      color = .systemRed
      symbol = "record.circle.fill"
    } else if running {
      color = AppTheme.accent
      symbol = "dot.radiowaves.left.and.right"
    } else {
      color = .systemGreen
      symbol = "checkmark.circle.fill"
    }

    activityIndicator.color = color
    statusImageView.tintColor = color
    statusImageView.image = UIImage(systemName: symbol)
    statusLabel.textColor = color
  }

  private func makeReadinessChecklist() -> UIView {
    let title = UILabel()
    title.text = "Readiness"
    title.font = .preferredFont(forTextStyle: .caption1)
    title.textColor = .secondaryLabel

    let rows = UIStackView(arrangedSubviews: [
      makeReadinessRow(title: "Bluetooth", valueLabel: bluetoothValueLabel),
      makeReadinessRow(title: "Location", valueLabel: locationValueLabel),
      makeReadinessRow(title: "Notifications", valueLabel: notificationValueLabel),
    ])
    rows.axis = .vertical
    rows.spacing = 4

    let stack = UIStackView(arrangedSubviews: [title, rows])
    stack.axis = .vertical
    stack.spacing = 6

    let container = UIView()
    container.backgroundColor = UIColor.tertiarySystemGroupedBackground
    container.layer.cornerRadius = 12
    container.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    let leading = stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12)
    let trailing = stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12)
    leading.priority = .defaultHigh
    trailing.priority = .defaultHigh
    NSLayoutConstraint.activate([
      leading,
      trailing,
      stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
      stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
    ])
    return container
  }

  private func makeReadinessRow(title: String, valueLabel: UILabel) -> UIView {
    let titleLabel = UILabel()
    titleLabel.text = title
    titleLabel.font = .preferredFont(forTextStyle: .caption1)
    titleLabel.textColor = .label

    valueLabel.font = .preferredFont(forTextStyle: .caption1)
    valueLabel.textColor = .secondaryLabel
    valueLabel.textAlignment = .right
    valueLabel.text = "Checking"

    let stack = UIStackView(arrangedSubviews: [titleLabel, UIView(), valueLabel])
    stack.axis = .horizontal
    stack.spacing = 8
    stack.alignment = .firstBaseline
    return stack
  }

  private func makeModeDescription(symbol: String, label: UILabel) -> UIView {
    let imageView = UIImageView(image: UIImage(systemName: symbol))
    imageView.tintColor = .secondaryLabel
    imageView.setContentHuggingPriority(.required, for: .horizontal)
    let stack = UIStackView(arrangedSubviews: [imageView, label])
    stack.axis = .horizontal
    stack.spacing = 6
    stack.alignment = .firstBaseline
    return stack
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
    stack.translatesAutoresizingMaskIntoConstraints = false
    let leading = stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12)
    let trailing = stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12)
    leading.priority = .defaultHigh
    trailing.priority = .defaultHigh
    NSLayoutConstraint.activate([
      leading,
      trailing,
      stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
      stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
    ])
    return container
  }
}
