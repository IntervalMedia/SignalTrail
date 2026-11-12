import SwiftUI
import CoreBluetooth
import CoreLocation
import UserNotifications

/// Adapts the existing scan coordinator without creating a second scanning lifecycle.
final class ScanScreenModel: ObservableObject, ScanViewModelDelegate {
    let scan: ScanViewModel
    let environment: AppEnvironment
    @Published private(set) var notificationStatus = "Checking"
    var onError: ((String) -> Void)?

    init(environment: AppEnvironment) {
        self.environment = environment
        scan = ScanViewModel(coordinator: environment.scanCoordinator,
                             store: environment.store, settingsStore: environment.settingsStore)
        scan.delegate = self
    }

    var bluetoothStatus: String {
        switch environment.bluetoothScanner.state {
        case .poweredOn: return "Ready"
        case .unknown, .resetting: return "Checking"
        default: return "Unavailable"
        }
    }

    var locationStatus: String {
        switch environment.locationProvider.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return "Granted"
        default: return "Required for recording"
        }
    }

    func refresh() {
        scan.refreshKnownDevices()
        environment.notificationService.authorizationStatus { [weak self] status in
            self?.notificationStatus = [.authorized, .provisional, .ephemeral].contains(status)
                ? "Enabled" : "Disabled"
        }
    }

    func selectMode(_ mode: ScanMode) {
        guard !scan.isRunning else { return }
        objectWillChange.send()
        scan.selectedMode = mode
    }

    func toggleFilter(_ filter: LiveResultFilter) {
        var filters = scan.activeFilters
        if filters.contains(filter) { filters.remove(filter) }
        else {
            if filter == .strongest { filters.remove(.recentlySeen) }
            if filter == .recentlySeen { filters.remove(.strongest) }
            filters.insert(filter)
        }
        scan.activeFilters = filters
    }

    func selectSort(_ sort: LiveResultSort) {
        scan.activeFilters = scan.activeFilters.subtracting([.strongest, .recentlySeen])
        scan.sort = sort
    }

    func scanViewModelDidUpdate(_ viewModel: ScanViewModel) { objectWillChange.send() }
    func scanViewModelDidTick(_ viewModel: ScanViewModel) { objectWillChange.send() }
    func scanViewModel(_ viewModel: ScanViewModel, didEncounter message: String) { onError?(message) }
}

final class ScanHostingController: UIHostingController<ScanScreen> {
    private let model: ScanScreenModel

    init(environment: AppEnvironment) {
        let model = ScanScreenModel(environment: environment)
        self.model = model
        super.init(rootView: ScanScreen(model: model))
        rootView.onAction = { [weak self] in self?.toggleScan() }
        rootView.onDevice = { [weak self] device in
            self?.navigationController?.pushViewController(
                DeviceDetailViewController(device: device, environment: environment), animated: true)
        }
        rootView.onDeviceAction = { [weak self] action, device in self?.perform(action, for: device) }
        rootView.onInfo = { [weak self] title, message in self?.presentInfo(title: title, message: message) }
        rootView.onSettings = { [weak self] in self?.tabBarController?.selectedIndex = 4 }
        model.onError = { [weak self] in self?.presentError($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Scan"
        navigationItem.title = "SignalTrail"
        navigationItem.largeTitleDisplayMode = .always
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let key = "SignalTrail.ScanOnboardingShown"
        guard !UserDefaults.standard.bool(forKey: key), presentedViewController == nil else { return }
        UserDefaults.standard.set(true, forKey: key)
        presentInfo(title: "Welcome to SignalTrail", message: "Quick Scan temporarily discovers nearby BLE devices.\n\nRecord Session saves repeated signal observations with the phone's location.\n\nObservation points show where this phone heard a signal, not a verified device location.")
    }

    private func toggleScan() {
        guard !model.scan.isRunning, model.scan.selectedMode == .recording,
              model.environment.locationProvider.authorizationStatus == .notDetermined else {
            model.scan.toggleScan()
            return
        }
        let alert = UIAlertController(title: "Allow location for recording?", message: "Record Session saves where this phone observed each signal so you can replay your route. It does not prove where the broadcasting device was located.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self] _ in
            self?.model.scan.toggleScan()
        })
        present(alert, animated: true)
    }

    private func perform(_ action: ScanDeviceAction, for device: BLEDeviceSnapshot) {
        switch action {
        case .rename: rename(device)
        case .export: export(device)
        case .reset: reset(device)
        case .save: save(device)
        case .alert: createAlert(device)
        }
    }

    private func rename(_ device: BLEDeviceSnapshot) {
        let alert = UIAlertController(title: "Edit Display Name", message: "Enter a custom name for this device.", preferredStyle: .alert)
        alert.addTextField { field in
            field.text = device.customName
            field.placeholder = "Custom display name"
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            let entered = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            self?.model.scan.updateCustomName(entered?.isEmpty == false ? entered : nil,
                                              for: device.peripheralIdentifier)
        })
        present(alert, animated: true)
    }

    private func export(_ device: BLEDeviceSnapshot) {
        guard let url = model.scan.exportDeviceJSON(for: device.peripheralIdentifier) else {
            presentError("Could not generate device JSON export file.")
            return
        }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        anchor(controller.popoverPresentationController)
        present(controller, animated: true)
    }

    private func reset(_ device: BLEDeviceSnapshot) {
        let alert = UIAlertController(title: "Reset Stored Data", message: "This will remove the stored JSON record and reset custom names and explored capabilities for this device.", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Clear / Reset Data", style: .destructive) { [weak self] _ in
            self?.model.scan.clearStoredData(for: device.peripheralIdentifier)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        anchor(alert.popoverPresentationController)
        present(alert, animated: true)
    }

    private func save(_ device: BLEDeviceSnapshot) {
        let known = model.environment.store.loadKnownDevices().first {
            $0.peripheralIdentifier == device.peripheralIdentifier
        } ?? KnownDevice(id: UUID(), peripheralIdentifier: device.peripheralIdentifier,
                         nickname: device.presentationName, lastKnownName: device.displayName,
                         companyIdentifier: device.advertisement.companyIdentifier,
                         manufacturerPrefixHex: device.advertisement.manufacturerDataHex.map { String($0.prefix(8)) },
                         notes: "", createdAt: Date(), lastSeenAt: device.lastSeen)
        let editor = KnownDeviceEditorViewController(device: known, environment: model.environment)
        editor.onSave = { [weak self] in self?.model.refresh() }
        present(UINavigationController(rootViewController: editor), animated: true)
    }

    private func createAlert(_ device: BLEDeviceSnapshot) {
        let alert = UIAlertController(title: "Create Alert", message: nil, preferredStyle: .actionSheet)
        for template in alertTemplates(for: device) {
            alert.addAction(UIAlertAction(title: template.title, style: .default) { [weak self] _ in
                guard let self else { return }
                let editor = AlertRuleEditorViewController(rule: template.rule,
                    environment: self.model.environment, isNewRule: true)
                editor.onSave = { [weak self] _ in self?.model.refresh() }
                self.navigationController?.pushViewController(editor, animated: true)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        anchor(alert.popoverPresentationController)
        present(alert, animated: true)
    }

    private func anchor(_ popover: UIPopoverPresentationController?) {
        popover?.sourceView = view
        popover?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
    }
}
