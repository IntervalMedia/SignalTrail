import SwiftUI
import UIKit

final class LibraryHostingController: UIHostingController<AnyView> {
    private let environment: AppEnvironment
    private let model = LibraryScreenModel()

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(rootView: AnyView(EmptyView()))
        rootView = AnyView(LibraryScreen(
            model: model,
            openDevice: { [weak self] in self?.openDevice($0) },
            openRule: { [weak self] in self?.openRule($0) },
            deleteDevice: { [weak self] in self?.deleteDevice($0) },
            deleteRule: { [weak self] in self?.deleteRule($0) },
            createDeviceAlert: { [weak self] in self?.createDeviceAlert($0) },
            setRuleEnabled: { [weak self] in self?.setRuleEnabled($0, enabled: $1) },
            segmentChanged: { [weak self] in self?.configureNavigation() }
        ))
        title = "Library"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        model.devices = environment.store.loadKnownDevices().sorted {
            $0.nickname.localizedCaseInsensitiveCompare($1.nickname) == .orderedAscending
        }
        let rules = environment.store.loadAlertRules()
        model.rules = rules
        model.currentMatches = environment.scanCoordinator.devices.filter { device in
            rules.contains { AlertMatcher.matches(rule: $0, device: device) }
        }.count
        configureNavigation()
    }

    private func configureNavigation() {
        navigationItem.rightBarButtonItem = model.showAlerts
            ? UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addRule))
            : nil
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Create alert rule"
    }

    private func openDevice(_ device: KnownDevice) {
        let controller = KnownDeviceEditorViewController(device: device, environment: environment)
        controller.onSave = { [weak self] in self?.reload() }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func openRule(_ rule: AlertRule, isNew: Bool = false) {
        let controller = AlertRuleEditorViewController(rule: rule, environment: environment, isNewRule: isNew)
        controller.onSave = { [weak self] _ in self?.reload() }
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func addRule() {
        openRule(AlertRule(
            id: UUID(), name: "", matchType: .localNameContains, matchValue: "",
            isEnabled: true, notifyOncePerSession: true, cooldownSeconds: 300
        ), isNew: true)
    }

    private func createDeviceAlert(_ device: KnownDevice) {
        openRule(AlertRule(
            id: UUID(), name: "\(device.nickname) detected", matchType: .peripheralIdentifier,
            matchValue: device.peripheralIdentifier.uuidString, isEnabled: true,
            notifyOncePerSession: true, cooldownSeconds: 300
        ), isNew: true)
    }

    private func setRuleEnabled(_ rule: AlertRule, enabled: Bool) {
        let updated = AlertRule(
            id: rule.id, name: rule.name, matchType: rule.matchType, matchValue: rule.matchValue,
            additionalMatches: rule.additionalMatches, matchMode: rule.matchMode, isEnabled: enabled,
            notifyOncePerSession: rule.notifyOncePerSession, cooldownSeconds: rule.cooldownSeconds
        )
        do {
            try environment.store.upsertAlertRule(updated)
            reload()
        } catch {
            reload()
            presentError("Unable to update alert: \(error.localizedDescription)")
        }
    }

    private func deleteDevice(_ device: KnownDevice) {
        do {
            try environment.store.deleteKnownDevice(device)
            reload()
        } catch {
            presentError("Unable to delete device: \(error.localizedDescription)")
        }
    }

    private func deleteRule(_ rule: AlertRule) {
        do {
            try environment.store.deleteAlertRule(rule)
            reload()
        } catch {
            presentError("Unable to delete alert: \(error.localizedDescription)")
        }
    }
}

private final class LibraryScreenModel: ObservableObject {
    @Published var devices: [KnownDevice] = []
    @Published var rules: [AlertRule] = []
    @Published var currentMatches = 0
    @Published var showAlerts = false
}

private struct LibraryScreen: View {
    @ObservedObject var model: LibraryScreenModel
    let openDevice: (KnownDevice) -> Void
    let openRule: (AlertRule) -> Void
    let deleteDevice: (KnownDevice) -> Void
    let deleteRule: (AlertRule) -> Void
    let createDeviceAlert: (KnownDevice) -> Void
    let setRuleEnabled: (AlertRule, Bool) -> Void
    let segmentChanged: () -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("A FAMILIAR SIGNAL", systemImage: "bookmark")
                        .font(.caption.weight(.bold)).foregroundStyle(TrailTheme.accent)
                    Text("Keep what\ncatches your attention.")
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Give devices a name. Set alerts for the signals that matter to you.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Picker("Library collection", selection: $model.showAlerts) {
                        Text("Devices").tag(false)
                        Text("Alerts").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 8)
                    .onChange(of: model.showAlerts) { _ in segmentChanged() }
                }
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            }
            if model.showAlerts {
                alertSections
            } else {
                deviceSections
            }
        }
        .listStyle(.insetGrouped)
        .tint(TrailTheme.accent)
    }

    @ViewBuilder private var deviceSections: some View {
        if model.devices.isEmpty {
            Section {
                LibraryEmptyState(
                    symbol: "bookmark", title: "Make a signal familiar",
                    message: "Save a device from Scan to give it a nickname, keep notes, and create an alert."
                )
            }
        } else {
            Section("Saved devices · \(model.devices.count)") {
                ForEach(model.devices) { device in
                    Button { openDevice(device) } label: {
                        LibraryItemRow(
                            symbol: "antenna.radiowaves.left.and.right", title: device.nickname,
                            detail: [device.lastKnownName, BluetoothCompanyLookup.name(for: device.companyIdentifier)]
                                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                            footnote: device.peripheralIdentifier.uuidString, active: true
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", role: .destructive) { deleteDevice(device) }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button { createDeviceAlert(device) } label: {
                            Label("Create alert", systemImage: "bell.badge")
                        }
                        .tint(TrailTheme.accent)
                    }
                    .contextMenu {
                        Button { createDeviceAlert(device) } label: {
                            Label("Create alert", systemImage: "bell.badge")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var alertSections: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Alert activity", systemImage: "waveform.path")
                    .font(.headline).foregroundStyle(TrailTheme.accent)
                Text("\(model.rules.filter(\.isEnabled).count) enabled · \(model.rules.filter { !$0.isEnabled }.count) disabled")
                    .font(.title3.weight(.semibold))
                Text("\(model.currentMatches) recent matches in current live results")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
        if model.rules.isEmpty {
            Section {
                LibraryEmptyState(
                    symbol: "bell", title: "Listen for what matters",
                    message: "Tap + to create an alert, or create one from a device or recorded session."
                )
            }
        } else {
            Section("Alert rules · \(model.rules.count)") {
                ForEach(model.rules) { rule in
                    VStack(alignment: .leading, spacing: 4) {
                        Button { openRule(rule) } label: {
                            LibraryItemRow(
                                symbol: rule.isEnabled ? "bell" : "bell.slash", title: rule.name,
                                detail: rule.matchSummary, footnote: rule.isEnabled ? "Enabled" : "Disabled",
                                active: rule.isEnabled
                            )
                        }
                        .buttonStyle(.plain)
                        Toggle("Enabled", isOn: Binding(
                            get: { rule.isEnabled },
                            set: { setRuleEnabled(rule, $0) }
                        ))
                        .font(.subheadline)
                        .accessibilityLabel("Enable \(rule.name)")
                        .padding(.bottom, 8)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { deleteRule(rule) }
                    }
                }
            }
        }
    }
}

private struct LibraryItemRow: View {
    let symbol: String
    let title: String
    let detail: String
    let footnote: String
    let active: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3)
                .foregroundStyle(active ? TrailTheme.accent : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline).foregroundStyle(.primary)
                if !detail.isEmpty {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(footnote).font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

private struct LibraryEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol).font(.system(size: 36, weight: .light))
                .foregroundStyle(TrailTheme.accent)
            Text(title).font(.title2.weight(.bold))
            Text(message).foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
    }
}
