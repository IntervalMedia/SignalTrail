import SwiftUI

/// A received signal expires even if the last RSSI value remains cached by the radio.
struct HunterReading {
    let rssi: Int?

    init(rssi: Int?, lastSeen: Date?, now: Date = Date()) {
        self.rssi = lastSeen.map { now.timeIntervalSince($0) < 5 } == true ? rssi : nil
    }

    var level: Double { rssi.map { Double(HunterProximity.signalLevel(forRSSI: $0)) } ?? 0 }

    var proximity: String {
        guard let rssi else { return "No recent signal" }
        switch rssi {
        case (-45)...: return "Very close"
        case (-60)..<(-45): return "Close"
        case (-75)..<(-60): return "Nearby"
        default: return "Distant"
        }
    }
}

final class HunterScreenModel: ObservableObject, HunterControllerDelegate {
    let environment: AppEnvironment
    @Published private(set) var revision = 0

    init(environment: AppEnvironment) {
        self.environment = environment
        environment.hunter.delegate = self
    }

    var hunter: HunterController { environment.hunter }
    var reading: HunterReading { HunterReading(rssi: hunter.latestRSSI, lastSeen: hunter.lastSeen) }

    func refresh() {
        hunter.delegate = self
        revision += 1
    }

    func hunterControllerDidUpdate(_ controller: HunterController) { revision += 1 }
}

final class HunterHostingController: UIHostingController<HunterScreen> {
    private let model: HunterScreenModel

    init(environment: AppEnvironment) {
        let model = HunterScreenModel(environment: environment)
        self.model = model
        super.init(rootView: HunterScreen(model: model))
        title = "Hunter"
        rootView.chooseTarget = { [weak self] in self?.tabBarController?.selectedIndex = 0 }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.refresh()
    }
}

struct HunterScreen: View {
    @ObservedObject var model: HunterScreenModel
    var chooseTarget: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                TrailSectionHeading(title: "Follow the signal.", subtitle: "A closer look at one device in your surroundings.")
                instrument
                TrailCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Your target", systemImage: "scope").font(.subheadline.bold()).foregroundStyle(TrailTheme.accent)
                        Text(model.hunter.target?.presentationName ?? "Choose a device to begin")
                            .font(.title2.bold()).textSelection(.enabled)
                        Text(model.hunter.target == nil
                             ? "Open a device from Scan, then choose Hunt this device."
                             : "Move slowly and watch for a stronger signal. Faster sound and haptic pulses help guide you.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Label("Signal strength is relative, not a distance. Walls, reflections and phone orientation affect readings.", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
            .frame(maxWidth: 680).padding(20).frame(maxWidth: .infinity)
        }
        .background(TrailTheme.background)
        .trailActionBar {
            VStack(spacing: 10) {
                if model.hunter.target == nil {
                    TrailPrimaryButton(title: "Find a device", symbol: "dot.radiowaves.left.and.right", action: chooseTarget)
                } else {
                    TrailPrimaryButton(title: model.hunter.isHunting ? "Stop hunting" : "Start hunting",
                                       symbol: model.hunter.isHunting ? "stop.fill" : "scope") {
                        model.hunter.isHunting ? model.hunter.stop() : model.hunter.start()
                    }
                    TrailSecondaryButton(title: "Clear target", symbol: "xmark") { model.hunter.clearTarget() }
                }
            }.frame(maxWidth: 680)
        }
    }

    private var instrument: some View {
        TrailCard {
            VStack(spacing: 18) {
                HStack {
                    Label(status, systemImage: model.hunter.isHunting ? "dot.radiowaves.left.and.right" : "pause")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("LIVE RSSI").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                ZStack {
                    ForEach(0..<3) { ring in
                        Circle().stroke(TrailTheme.accent.opacity(0.10 + Double(ring) * 0.05), lineWidth: 1)
                            .padding(CGFloat(ring) * 28)
                    }
                    Circle().trim(from: 0, to: model.reading.level)
                        .stroke(TrailTheme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(5)
                    VStack(spacing: 6) {
                        Text(model.reading.rssi.map(String.init) ?? "—")
                            .font(.system(size: 58, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("dBm").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 250).aspectRatio(1, contentMode: .fit)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.reading.rssi.map { "Signal strength \($0) dBm" } ?? "No recent signal")
                Text(model.reading.proximity).font(.title3.bold())
            }
        }
    }

    private var status: String {
        guard model.hunter.isHunting else { return model.hunter.target == nil ? "Standby" : "Ready" }
        return model.environment.bluetoothScanner.isReady ? "Listening" : "Waiting for Bluetooth"
    }
}
