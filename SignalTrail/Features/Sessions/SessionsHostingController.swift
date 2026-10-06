import SwiftUI
import UIKit

final class SessionsHostingController: UIHostingController<AnyView> {
    private let environment: AppEnvironment
    private let model = SessionsScreenModel()

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(rootView: AnyView(EmptyView()))
        rootView = AnyView(SessionsScreen(
            model: model,
            open: { [weak self] in self?.open($0) },
            delete: { [weak self] in self?.delete($0) }
        ))
        title = "Sessions"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        do {
            model.sessions = try environment.store.loadSessions()
        } catch {
            presentError("Unable to load sessions: \(error.localizedDescription)")
        }
    }

    private func open(_ session: ScanSession) {
        navigationController?.pushViewController(
            SessionDetailViewController(session: session, environment: environment), animated: true
        )
    }

    private func delete(_ session: ScanSession) {
        do {
            try environment.store.deleteSession(session)
            reload()
        } catch {
            presentError("Unable to delete session: \(error.localizedDescription)")
        }
    }
}

private final class SessionsScreenModel: ObservableObject {
    @Published var sessions: [ScanSession] = []
}

private struct SessionsScreen: View {
    @ObservedObject var model: SessionsScreenModel
    let open: (ScanSession) -> Void
    let delete: (ScanSession) -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("YOUR FIELD NOTES", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrailTheme.accent)
                    Text("Every signal.\nA place in time.")
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Revisit your recordings, explore the map, and follow the observations.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(model.sessions.count) saved recordings")
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 4)
                }
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            }

            if model.sessions.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "map")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(TrailTheme.accent)
                        Text("Your next discovery starts here")
                            .font(.title2.weight(.bold))
                        Text("Choose Record on the Scan tab to save Bluetooth observations and your phone’s location. Your recordings will appear here.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                }
            } else {
                Section("Recordings") {
                    ForEach(model.sessions) { session in
                        Button { open(session) } label: {
                            SessionRecordingRow(session: session)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", role: .destructive) { delete(session) }
                        }
                        .accessibilityHint("Open recording details, map, and export options")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .tint(TrailTheme.accent)
    }
}

private struct SessionRecordingRow: View {
    let session: ScanSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "map.fill")
                    .font(.title3)
                    .foregroundStyle(TrailTheme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.name).font(.headline).foregroundStyle(.primary)
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Text("\(session.duration.clockString)  ·  \(session.uniqueDeviceCount) devices  ·  \(session.detectionCount) observations")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
