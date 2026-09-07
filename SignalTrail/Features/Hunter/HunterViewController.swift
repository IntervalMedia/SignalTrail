import AVFoundation
import CoreBluetooth
import UIKit

protocol HunterControllerDelegate: AnyObject {
    func hunterControllerDidUpdate(_ controller: HunterController)
}

enum HunterProximity {
    static func pulseInterval(forRSSI rssi: Int) -> TimeInterval {
        // Ported from colonelpanichacks/ouispy-foxhunter's calculateBeepInterval().
        // Thank you to that project for publishing its foxhunting implementation.
        switch rssi {
        case (-35)...:
            return interpolate(rssi, from: -35...(-25), output: (0.025, 0.010))
        case (-45)..<(-35):
            return interpolate(rssi, from: -45...(-35), output: (0.050, 0.025))
        case (-55)..<(-45):
            return interpolate(rssi, from: -55...(-45), output: (0.100, 0.050))
        case (-65)..<(-55):
            return interpolate(rssi, from: -65...(-55), output: (0.200, 0.100))
        case (-75)..<(-65):
            return interpolate(rssi, from: -75...(-65), output: (0.500, 0.200))
        case (-85)..<(-75):
            return interpolate(rssi, from: -85...(-75), output: (1.000, 0.500))
        default:
            return 3.000
        }
    }

    static func signalLevel(forRSSI rssi: Int) -> Float {
        Float(max(0, min(1, Double(rssi + 95) / 70)))
    }

    private static func interpolate(
        _ value: Int,
        from input: ClosedRange<Int>,
        output: (lower: TimeInterval, upper: TimeInterval)
    ) -> TimeInterval {
        let clamped = min(max(value, input.lowerBound), input.upperBound)
        let progress = Double(clamped - input.lowerBound) / Double(input.upperBound - input.lowerBound)
        return output.lower + progress * (output.upper - output.lower)
    }
}

final class HunterController: BluetoothScannerDelegate {
    weak var delegate: HunterControllerDelegate?

    private let scanner: BluetoothScanner
    private let settingsStore: SettingsStore
    private var pulseTimer: Timer?
    private var staleTimer: Timer?
    private let feedback = HunterFeedbackPlayer()
    private weak var scanCoordinator: ScanCoordinator?

    private(set) var target: BLEDeviceSnapshot?
    private(set) var isHunting = false
    private(set) var latestRSSI: Int?
    private(set) var lastSeen: Date?

    init(
        scanner: BluetoothScanner,
        settingsStore: SettingsStore,
        scanCoordinator: ScanCoordinator
    ) {
        self.scanner = scanner
        self.settingsStore = settingsStore
        self.scanCoordinator = scanCoordinator
        scanner.addObserver(self)
    }

    func selectTarget(_ target: BLEDeviceSnapshot, startImmediately: Bool = true) {
        stop()
        self.target = target
        latestRSSI = nil
        lastSeen = nil
        notifyDelegate()
        if startImmediately { start() }
    }

    func clearTarget() {
        stop()
        target = nil
        latestRSSI = nil
        lastSeen = nil
        notifyDelegate()
    }

    func start() {
        guard target != nil, !isHunting else { return }
        scanCoordinator?.stop()
        isHunting = true
        latestRSSI = nil
        lastSeen = nil
        if scanner.isReady { scanner.startScanning(allowDuplicates: true) }
        notifyDelegate()
    }

    func stop() {
        guard isHunting else { return }
        isHunting = false
        pulseTimer?.invalidate()
        staleTimer?.invalidate()
        pulseTimer = nil
        staleTimer = nil
        feedback.stop()
        scanner.stopScanning()
        notifyDelegate()
    }

    func previewFeedback() {
        feedback.play(settings: settingsStore.settings)
    }

    func bluetoothScannerDidChangeState(_ scanner: BluetoothScanner) {
        if isHunting && scanner.isReady && !scanner.isScanning {
            scanner.startScanning(allowDuplicates: true)
        }
        notifyDelegate()
    }

    func bluetoothScanner(
        _ scanner: BluetoothScanner,
        didDiscover peripheral: CBPeripheral,
        advertisement: BLEAdvertisement,
        rssi: Int,
        timestamp: Date
    ) {
        guard isHunting, peripheral.identifier == target?.peripheralIdentifier else { return }
        latestRSSI = rssi
        lastSeen = timestamp
        scheduleStaleTimeout()
        if pulseTimer == nil { playPulseAndScheduleNext() }
        notifyDelegate()
    }

    private func playPulseAndScheduleNext() {
        guard isHunting, let rssi = latestRSSI, let lastSeen,
              Date().timeIntervalSince(lastSeen) < 5 else {
            pulseTimer = nil
            return
        }
        feedback.play(settings: settingsStore.settings)
        let interval = max(0.08, HunterProximity.pulseInterval(forRSSI: rssi))
        pulseTimer?.invalidate()
        pulseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) {
            [weak self] _ in
            self?.playPulseAndScheduleNext()
        }
    }

    private func scheduleStaleTimeout() {
        staleTimer?.invalidate()
        staleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.pulseTimer?.invalidate()
            self?.pulseTimer = nil
            self?.feedback.stop()
            self?.notifyDelegate()
        }
    }

    private func notifyDelegate() {
        delegate?.hunterControllerDidUpdate(self)
    }
}

private final class HunterFeedbackPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isPrepared = false

    func play(settings: AppSettings) {
        if settings.isHunterSoundEnabled { playTone(settings.hunterAlertTone) }
        playHaptic(settings.hunterHapticStyle)
    }

    func stop() {
        player.stop()
    }

    private func playTone(_ tone: HunterAlertTone) {
        prepareIfNeeded()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = makeBuffer(tone: tone, format: format) else { return }
        player.stop()
        player.scheduleBuffer(buffer)
        if !engine.isRunning { try? engine.start() }
        player.play()
    }

    private func prepareIfNeeded() {
        guard !isPrepared else { return }
        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        engine.prepare()
        isPrepared = true
    }

    private func makeBuffer(tone: HunterAlertTone, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let duration: Double = 0.085
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount
        let frequencies: (Double, Double)
        switch tone {
        case .sonar: frequencies = (880, 660)
        case .deepPing: frequencies = (520, 390)
        case .brightPing: frequencies = (1_320, 990)
        }
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / format.sampleRate
            let decay = exp(-35 * time)
            let fundamental = sin(2 * .pi * frequencies.0 * time)
            let echo = sin(2 * .pi * frequencies.1 * time) * 0.32
            samples[frame] = Float((fundamental + echo) * decay * 0.32)
        }
        return buffer
    }

    private func playHaptic(_ style: HunterHapticStyle) {
        let impactStyle: UIImpactFeedbackGenerator.FeedbackStyle
        switch style {
        case .off: return
        case .light: impactStyle = .light
        case .medium: impactStyle = .medium
        case .heavy: impactStyle = .heavy
        }
        let generator = UIImpactFeedbackGenerator(style: impactStyle)
        generator.prepare()
        generator.impactOccurred()
    }
}

final class HunterViewController: UIViewController, HunterControllerDelegate {
    private let environment: AppEnvironment
    private let targetLabel = UILabel()
    private let statusLabel = UILabel()
    private let rssiLabel = UILabel()
    private let lastSeenLabel = UILabel()
    private let signalBar = UIProgressView(progressViewStyle: .bar)
    private let actionButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Hunter"
        view.backgroundColor = AppTheme.groupedBackground
        let infoItem = UIBarButtonItem(
            image: UIImage(systemName: "info.circle"),
            style: .plain,
            target: self,
            action: #selector(showHunterInfo)
        )
        infoItem.accessibilityLabel = "About Hunter signal guidance"
        infoItem.accessibilityHint = "Shows more information"
        navigationItem.rightBarButtonItem = infoItem
        configureUI()
        updateUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        environment.hunter.delegate = self
        updateUI()
    }

    func hunterControllerDidUpdate(_ controller: HunterController) {
        updateUI()
    }

    private func configureUI() {
        let icon = UIImageView(image: UIImage(systemName: "scope"))
        icon.tintColor = AppTheme.accent
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.heightAnchor.constraint(equalToConstant: 72).isActive = true

        targetLabel.font = .preferredFont(forTextStyle: .title2)
        targetLabel.textAlignment = .center
        targetLabel.numberOfLines = 2
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.textColor = .secondaryLabel
        rssiLabel.font = .monospacedDigitSystemFont(ofSize: 42, weight: .semibold)
        rssiLabel.textAlignment = .center
        lastSeenLabel.font = .preferredFont(forTextStyle: .footnote)
        lastSeenLabel.textAlignment = .center
        lastSeenLabel.textColor = .secondaryLabel
        signalBar.trackTintColor = .tertiarySystemFill
        signalBar.progressTintColor = AppTheme.accent
        signalBar.layer.cornerRadius = 3
        signalBar.clipsToBounds = true
        signalBar.heightAnchor.constraint(equalToConstant: 8).isActive = true

        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .large
        actionButton.configuration = configuration
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        clearButton.setTitle("Clear target", for: .normal)
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            icon, targetLabel, statusLabel, rssiLabel, signalBar, lastSeenLabel,
            actionButton, clearButton
        ])
        stack.axis = .vertical
        stack.spacing = 18
        stack.setCustomSpacing(30, after: icon)
        stack.setCustomSpacing(28, after: lastSeenLabel)
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])
    }

    private func updateUI() {
        let hunter = environment.hunter
        targetLabel.text = hunter.target?.presentationName ?? "No target selected"
        actionButton.isEnabled = hunter.target != nil
        clearButton.isHidden = hunter.target == nil
        actionButton.configuration?.title = hunter.isHunting ? "Stop hunting" : "Start hunting"

        if hunter.target == nil {
            rssiLabel.text = "— dBm"
            signalBar.progress = 0
            statusLabel.text = "No target selected"
            lastSeenLabel.text = "Choose Hunt this device from a device detail screen."
            return
        }

        guard let rssi = hunter.latestRSSI, let lastSeen = hunter.lastSeen,
              Date().timeIntervalSince(lastSeen) < 5 else {
            rssiLabel.text = "— dBm"
            signalBar.progress = 0
            lastSeenLabel.text = hunter.isHunting ? "Listening for the target" : "Hunter is stopped"
            statusLabel.text = hunter.isHunting
                ? (environment.bluetoothScanner.isReady ? "Searching" : "Waiting for Bluetooth")
                : "Ready"
            return
        }
        rssiLabel.text = "\(rssi) dBm"
        signalBar.setProgress(HunterProximity.signalLevel(forRSSI: rssi), animated: true)
        lastSeenLabel.text = "Seen less than 5 seconds ago"
        statusLabel.text = proximityText(for: rssi)
    }

    private func proximityText(for rssi: Int) -> String {
        switch rssi {
        case (-45)...: return "Very close"
        case (-60)..<(-45): return "Close"
        case (-75)..<(-60): return "Nearby"
        default: return "Distant"
        }
    }

    @objc private func actionTapped() {
        environment.hunter.isHunting ? environment.hunter.stop() : environment.hunter.start()
    }

    @objc private func clearTapped() {
        environment.hunter.clearTarget()
    }

    @objc private func showHunterInfo() {
        presentInfo(
            title: "Using Hunter",
            message: "Pulse speed increases as the received signal grows stronger. Walls, reflections, phone orientation, device transmit power, and antenna placement can change RSSI, so use it as relative guidance while moving around."
        )
    }
}
