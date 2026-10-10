import CoreLocation
import SwiftUI

final class TrailSettingsModel: ObservableObject {
    @Published private(set) var settings: AppSettings
    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
        settings = store.settings
    }

    func refresh() { settings = store.settings }

    func set<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>, to value: Value) {
        // Start with the latest persisted value so Scan's RSSI edits are preserved.
        var updated = store.settings
        updated[keyPath: keyPath] = value
        store.settings = updated
        settings = updated
    }

    func reset() {
        store.reset()
        refresh()
    }
}

final class SettingsHostingController: UIHostingController<SettingsScreen> {
    private let model: TrailSettingsModel
    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        let model = TrailSettingsModel(store: environment.settingsStore)
        self.model = model
        self.environment = environment
        super.init(rootView: SettingsScreen(model: model, environment: environment))
        title = "Settings"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Intel",
            style: .plain,
            target: self,
            action: #selector(showIntel)
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.refresh()
    }

    @objc private func showIntel() {
        navigationController?.pushViewController(
            IntelViewController(environment: environment),
            animated: true
        )
    }
}

struct SettingsScreen: View {
    @ObservedObject var model: TrailSettingsModel
    let environment: AppEnvironment
    @State private var confirmReset = false
    @State private var confirmClear = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("ON YOUR TERMS", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold)).foregroundStyle(TrailTheme.accent)
                    Text("Make it your field kit.").font(.title2.bold())
                    Text("Tune your scans, feedback and permissions. Your observations stay on this device.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
            quickScan
            recording
            feedback
            permissions
            Section("About") {
                HStack {
                    Text("SignalTrail")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
                Label("Stored locally on this device", systemImage: "lock.shield")
                Button("Reset settings", role: .destructive) { confirmReset = true }
            }
        }
        .tint(TrailTheme.accent)
        .alert("Reset settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { model.reset() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Recorded sessions and saved devices will not be deleted.") }
        .alert("Clear live results?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { environment.scanCoordinator.clearResults() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This clears the current device list. Saved sessions will remain available.") }
        .onChange(of: scenePhase) { phase in if phase == .active { model.refresh() } }
    }

    private var quickScan: some View {
        Section {
            durationPicker("Duration", keyPath: \.activeScanDuration, options: [30, 60, 120, 180, 300])
            Toggle("Automatic GATT enrichment", isOn: binding(\.isAutomaticGATTEnrichmentEnabled))
            Button("Clear live scan results", role: .destructive) { confirmClear = true }
        } header: { Label("Quick Scan", systemImage: "dot.radiowaves.left.and.right") }
        footer: {
            Text("Quick Scan listens continuously. Automatic enrichment connects to available devices one at a time to read standard identity and battery information.")
        }
    }

    private var recording: some View {
        Section {
            durationPicker("Scan burst", keyPath: \.recordingBurstDuration, options: [1, 2, 3, 5, 8, 10, 15])
            durationPicker("Pause between bursts", keyPath: \.recordingPauseDuration, options: [5, 10, 12, 15, 30, 60])
            Toggle("Keep screen awake", isOn: binding(\.keepScreenAwakeDuringRecording))
        } header: { Label("Recorded sessions", systemImage: "map") }
        footer: { Text("Short bursts and pauses reduce battery and storage use while recording observations along your route.") }
    }

    private var feedback: some View {
        Section {
            Toggle("Sound", isOn: binding(\.isHunterSoundEnabled))
            Picker("Alert tone", selection: binding(\.hunterAlertTone)) {
                ForEach(HunterAlertTone.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.menu)
            Picker("Haptic feedback", selection: binding(\.hunterHapticStyle)) {
                ForEach(HunterHapticStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.menu)
            Button { environment.hunter.previewFeedback() } label: {
                Label("Preview feedback", systemImage: "speaker.wave.2")
            }
        } header: { Label("Hunter feedback", systemImage: "waveform") }
        footer: { Text("Faster pulses indicate a stronger received signal from your selected device.") }
    }

    private var permissions: some View {
        Section {
            Button {
                switch environment.locationProvider.authorizationStatus {
                case .denied, .restricted: openSettings()
                default: environment.locationProvider.requestWhenInUseAuthorization()
                }
            } label: { Label("Location permission", systemImage: "location") }
            Button {
                environment.notificationService.requestAuthorization { granted in
                    if !granted { DispatchQueue.main.async { openSettings() } }
                }
            } label: { Label("Notification permission", systemImage: "bell") }
            Button("Open system settings", action: openSettings)
        } header: { Label("Permissions", systemImage: "hand.raised") }
        footer: { Text("Location records where your phone observed a signal, not the device's position. Notifications support your enabled detection alerts.") }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { model.set(keyPath, to: $0) })
    }

    private func durationPicker(_ title: String, keyPath: WritableKeyPath<AppSettings, TimeInterval>, options: [TimeInterval]) -> some View {
        Picker(title, selection: binding(keyPath)) {
            ForEach(options, id: \.self) { value in
                Text(value >= 60 ? value.clockString : "\(Int(value)) seconds").tag(value)
            }
        }.pickerStyle(.menu)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
