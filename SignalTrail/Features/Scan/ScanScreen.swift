import SwiftUI

enum ScanDeviceAction { case rename, export, reset, save, alert }

struct ScanScreen: View {
    @ObservedObject var model: ScanScreenModel
    var onAction: () -> Void = {}
    var onDevice: (BLEDeviceSnapshot) -> Void = { _ in }
    var onDeviceAction: (ScanDeviceAction, BLEDeviceSnapshot) -> Void = { _, _ in }
    var onInfo: (String, String) -> Void = { _, _ in }
    var onSettings: () -> Void = {}
    @State private var showsControls = false
    @Environment(\.scenePhase) private var scenePhase
    private let accent = Color(AppTheme.accent)

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                content.safeAreaBar(edge: .bottom) { actionBar }
            } else {
                content.safeAreaInset(edge: .bottom) { actionBar.background(Color(uiColor: .systemBackground)) }
            }
        }
        .tint(accent)
        .onChange(of: scenePhase) { phase in if phase == .active { model.refresh() } }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                readiness
                resultsHeader
                search
                if showsControls { controls }
                if model.scan.devices.isEmpty { emptyState }
                else {
                    LazyVStack(spacing: 12) {
                        ForEach(model.scan.devices, id: \.peripheralIdentifier) { device in
                            deviceRow(device)
                        }
                    }
                }
                Text("Broadcast identities are clues, not verified identities.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("SIGNAL FIELD", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.bold))
                Spacer()
                Button { onInfo("Scan modes", "Quick Scan temporarily discovers nearby BLE devices. Record Session saves repeated observations with the phone's location. Locations show where this phone heard a signal; they do not verify the device's location.") } label: {
                    Image(systemName: "info").frame(width: 44, height: 44)
                }
                .accessibilityLabel("About scan modes")
            }
            .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 6) {
                Text(model.scan.isRunning ? model.scan.statusText : "Discover your surroundings.")
                    .font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                Text(model.scan.selectedMode == .active
                     ? "Listen for nearby Bluetooth signals."
                     : "Capture signals along your route.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(model.scan.timerText)
                    .font(.system(.largeTitle, design: .monospaced).weight(.light))
                    .minimumScaleFactor(0.6)
                Text(model.scan.isRunning && !model.scan.burstActive ? "Between bursts" : model.scan.statusText)
                    .font(.caption.weight(.semibold)).foregroundStyle(accent)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 24) {
                metric("Devices", value: model.scan.devices.count)
                Rectangle().fill(accent.opacity(0.2)).frame(width: 1, height: 32)
                metric("Observations", value: model.scan.observationCount)
                Spacer(minLength: 0)
                Image(systemName: "waveform.path")
                    .font(.largeTitle).foregroundStyle(accent.opacity(0.6)).accessibilityHidden(true)
            }

            Picker("Scan mode", selection: Binding(get: { model.scan.selectedMode }, set: model.selectMode)) {
                Text("Quick Scan").tag(ScanMode.active)
                Text("Record Session").tag(ScanMode.recording)
            }
            .pickerStyle(.segmented).disabled(model.scan.isRunning)
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))
    }

    private func metric(_ label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.formatted()).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var readiness: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                readinessRow("Bluetooth", value: model.bluetoothStatus, symbol: "antenna.radiowaves.left.and.right")
                readinessRow("Location", value: model.locationStatus, symbol: "location")
                readinessRow("Notifications", value: model.notificationStatus, symbol: "bell")
                Text("Bluetooth is required for scanning. Location is only needed for recording. Notifications power detection alerts.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Review Settings", action: onSettings).font(.subheadline.weight(.semibold))
            }.padding(.top, 12)
        } label: {
            Label("Readiness · Bluetooth \(model.bluetoothStatus.lowercased())", systemImage: "checkmark.shield")
                .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
        }
    }

    private func readinessRow(_ name: String, value: String, symbol: String) -> some View {
        HStack {
            Label(name, systemImage: symbol)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }.font(.caption)
    }

    private var resultsHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Live discoveries").font(.title2.weight(.bold))
                Text("\(model.scan.devices.count) in your signal field").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showsControls.toggle()
            } label: {
                Image(systemName: showsControls ? "line.3.horizontal.decrease" : "slider.horizontal.3")
                    .frame(width: 44, height: 44)
                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel("Filter and sort discoveries")
            .accessibilityValue(showsControls ? "Expanded" : "Collapsed")
        }
    }

    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search names, services, identifiers", text: Binding(
                get: { model.scan.searchText }, set: { model.scan.searchText = $0 }))
                .font(.subheadline).disableAutocorrection(true)
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Search discoveries")
            if !model.scan.searchText.isEmpty {
                Button { model.scan.searchText = "" } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135))], alignment: .leading, spacing: 8) {
                ForEach(LiveResultFilter.allCases, id: \.self) { filter in
                    Button { model.toggleFilter(filter) } label: {
                        HStack {
                            Text(filter.title)
                            Spacer(minLength: 0)
                            if model.scan.activeFilters.contains(filter) { Image(systemName: "checkmark") }
                        }
                        .font(.caption.weight(.semibold)).padding(10)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(model.scan.activeFilters.contains(filter) ? accent.opacity(0.18) : Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityAddTraits(model.scan.activeFilters.contains(filter) ? .isSelected : [])
                }
            }
            Picker("Sort discoveries", selection: Binding(get: { model.scan.sort }, set: model.selectSort)) {
                ForEach(LiveResultSort.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.menu)
            HStack {
                Text("Minimum signal").font(.subheadline)
                Spacer()
                Text("\(model.scan.minimumRSSI) dBm").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(model.scan.minimumRSSI) }, set: { model.scan.minimumRSSI = Int($0) }), in: -100 ... -40, step: 5)
                .accessibilityLabel("Minimum signal strength")
                .accessibilityValue("\(model.scan.minimumRSSI) dBm")
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func deviceRow(_ device: BLEDeviceSnapshot) -> some View {
        Button { onDevice(device) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(device.presentationName).font(.headline).foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text("\(device.latestRSSI) dBm").font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(accent)
                }
                Text("Inferred: \(device.intelligence.categoryTitle) · \(device.intelligence.probability)%")
                    .font(.caption).foregroundStyle(.secondary)
                if let company = device.intelligence.manufacturer {
                    Text("Company ID assigned to \(company)").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("\(device.sightingCount) observations · \(device.signalDescription)")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                }.font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    if model.scan.knownPeripheralIDs.contains(device.peripheralIdentifier) { Label("Known", systemImage: "star.fill") }
                    if model.scan.matchesAlert(device) { Label("Alert match", systemImage: "bell") }
                    if device.advertisement.isConnectable { Text("Connectable") }
                }.font(.caption2.weight(.semibold)).foregroundStyle(accent)
                Text("Last heard \(DateFormatter.signalTrailTime.string(from: device.lastSeen))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onDeviceAction(.rename, device) } label: { Label("Edit Display Name", systemImage: "pencil") }
            Button { onDeviceAction(.save, device) } label: { Label("Save Device", systemImage: "star") }
            Button { onDeviceAction(.alert, device) } label: { Label("Create Alert", systemImage: "bell") }
            Button { onDeviceAction(.export, device) } label: { Label("Export JSON", systemImage: "square.and.arrow.up") }
            Button(role: .destructive) { onDeviceAction(.reset, device) } label: { Label("Clear / Reset Data", systemImage: "arrow.counterclockwise") }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 36, weight: .light)).foregroundStyle(accent)
            Text(model.scan.isRunning ? "Listening for signals" : "A little curiosity. A new discovery.")
                .font(.headline).multilineTextAlignment(.center)
            Text(model.scan.searchText.isEmpty && model.scan.activeFilters.isEmpty
                 ? "Start a scan to explore nearby Bluetooth devices. Record a session to keep your observations."
                 : "No devices match these filters. Try a different search or minimum signal strength.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 26).padding(.horizontal, 12).frame(maxWidth: .infinity)
    }

    private var actionTitle: String {
        model.scan.isRunning ? "Stop \(model.scan.selectedMode == .active ? "scan" : "recording")"
            : (model.scan.selectedMode == .active ? "Start Quick Scan" : "Record Session")
    }

    @ViewBuilder private var actionBar: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 16) {
                    Button { model.scan.clear() } label: { Image(systemName: "arrow.counterclockwise").frame(minHeight: 24) }
                        .buttonStyle(.glass).buttonBorderShape(.circle)
                        .disabled(model.scan.isRunning || model.scan.devices.isEmpty)
                        .accessibilityLabel("Clear live results")
                    Button(action: onAction) {
                        Label(actionTitle, systemImage: model.scan.isRunning ? "stop.fill" : "dot.radiowaves.left.and.right")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 24)
                    }
                    .buttonStyle(.glassProminent).buttonBorderShape(.capsule)
                    .tint(model.scan.isRunning ? .red : accent)
                }.padding(.horizontal, 20).padding(.vertical, 10)
            }
        } else {
            HStack(spacing: 16) {
                Button { model.scan.clear() } label: { Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44) }
                    .disabled(model.scan.isRunning || model.scan.devices.isEmpty)
                    .accessibilityLabel("Clear live results")
                Button(action: onAction) {
                    Label(actionTitle, systemImage: model.scan.isRunning ? "stop.fill" : "dot.radiowaves.left.and.right")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .tint(model.scan.isRunning ? .red : accent)
            }.padding(.horizontal, 20).padding(.vertical, 10)
        }
    }
}
