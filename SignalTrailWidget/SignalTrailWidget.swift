import SwiftUI
import WidgetKit

private enum WidgetStorage {
    static let appGroupIdentifier = "group.com.intervalmedia.DiscoveraBLE"
    static let storageKey = "signalTrail.widget.summary"
}

private struct SessionSummary: Codable, Hashable, Identifiable {
    var id: String { "\(name)-\(startedAt.timeIntervalSinceReferenceDate)" }

    let name: String
    let startedAt: Date
    let endedAt: Date?
    let detectionCount: Int
    let uniqueDeviceCount: Int

    var isActive: Bool { endedAt == nil }
}

private struct SummarySnapshot: Codable, Hashable {
    let updatedAt: Date
    let totalSessionCount: Int
    let recentSessions: [SessionSummary]

    static let empty = SummarySnapshot(
        updatedAt: Date(),
        totalSessionCount: 0,
        recentSessions: []
    )

    static let preview = SummarySnapshot(
        updatedAt: Date(),
        totalSessionCount: 12,
        recentSessions: [
            SessionSummary(
                name: "City walk",
                startedAt: Date().addingTimeInterval(-1_200),
                endedAt: nil,
                detectionCount: 84,
                uniqueDeviceCount: 17
            ),
            SessionSummary(
                name: "Morning scan",
                startedAt: Date().addingTimeInterval(-86_400),
                endedAt: Date().addingTimeInterval(-84_600),
                detectionCount: 42,
                uniqueDeviceCount: 9
            ),
            SessionSummary(
                name: "Station",
                startedAt: Date().addingTimeInterval(-172_800),
                endedAt: Date().addingTimeInterval(-171_900),
                detectionCount: 31,
                uniqueDeviceCount: 6
            )
        ]
    )
}

private struct SignalTrailEntry: TimelineEntry {
    let date: Date
    let summary: SummarySnapshot
}

private struct SignalTrailProvider: TimelineProvider {
    func placeholder(in context: Context) -> SignalTrailEntry {
        SignalTrailEntry(date: Date(), summary: .preview)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (SignalTrailEntry) -> Void
    ) {
        let summary = context.isPreview ? SummarySnapshot.preview : loadSummary()
        completion(SignalTrailEntry(date: Date(), summary: summary))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<SignalTrailEntry>) -> Void
    ) {
        let now = Date()
        let entry = SignalTrailEntry(date: now, summary: loadSummary())
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: now)
            ?? now.addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func loadSummary() -> SummarySnapshot {
        guard
            let defaults = UserDefaults(suiteName: WidgetStorage.appGroupIdentifier),
            let data = defaults.data(forKey: WidgetStorage.storageKey),
            let summary = try? JSONDecoder().decode(SummarySnapshot.self, from: data)
        else {
            return .empty
        }
        return summary
    }
}

private struct SignalTrailWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SignalTrailEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                CompactSummaryView(summary: entry.summary)
            case .systemMedium:
                MediumSummaryView(summary: entry.summary)
            case .systemLarge, .systemExtraLarge:
                DetailedSummaryView(summary: entry.summary, isExtraLarge: family == .systemExtraLarge)
            default:
                CompactSummaryView(summary: entry.summary)
            }
        }
        .padding()
        .modifier(SignalTrailWidgetBackground())
    }
}

private struct CompactSummaryView: View {
    let summary: SummarySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeaderView(isActive: summary.recentSessions.first?.isActive == true)

            Spacer(minLength: 0)

            if let latest = summary.recentSessions.first {
                Text(latest.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(latest.startedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    MetricView(value: latest.uniqueDeviceCount, label: "Devices")
                    Spacer()
                    MetricView(value: latest.detectionCount, label: "Signals")
                }
            } else {
                EmptySummaryView()
            }
        }
    }
}

private struct MediumSummaryView: View {
    let summary: SummarySnapshot

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                WidgetHeaderView(isActive: summary.recentSessions.first?.isActive == true)
                Spacer(minLength: 0)

                if let latest = summary.recentSessions.first {
                    Text(latest.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(latest.startedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    EmptySummaryView()
                }
            }

            if let latest = summary.recentSessions.first {
                Divider()
                VStack(spacing: 16) {
                    MetricView(value: latest.uniqueDeviceCount, label: "Devices")
                    MetricView(value: latest.detectionCount, label: "Signals")
                }
                .frame(minWidth: 72)
            }
        }
    }
}

private struct DetailedSummaryView: View {
    let summary: SummarySnapshot
    let isExtraLarge: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                WidgetHeaderView(isActive: summary.recentSessions.first?.isActive == true)
                Spacer()
                Text("\(summary.totalSessionCount) sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if summary.recentSessions.isEmpty {
                Spacer()
                EmptySummaryView()
                Spacer()
            } else {
                VStack(spacing: 0) {
                    ForEach(summary.recentSessions.prefix(isExtraLarge ? 4 : 3)) { session in
                        SessionRowView(session: session)
                        if session.id != summary.recentSessions.prefix(isExtraLarge ? 4 : 3).last?.id {
                            Divider()
                        }
                    }
                }
            }

            Spacer(minLength: 0)
            Text("Updated \(summary.updatedAt, style: .relative)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct WidgetHeaderView: View {
    let isActive: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(.cyan)
            Text("Signal Trail")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if isActive {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Recording")
            }
        }
    }
}

private struct MetricView: View {
    let value: Int
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value, format: .number)
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SessionRowView: View {
    let session: SessionSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.isActive ? "record.circle.fill" : "checkmark.circle")
                .foregroundStyle(session.isActive ? .green : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(session.startedAt, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label {
                Text(session.uniqueDeviceCount, format: .number)
            } icon: {
                Image(systemName: "antenna.radiowaves.left.and.right")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)

            Text(session.detectionCount, format: .number)
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 32, alignment: .trailing)
                .accessibilityLabel("\(session.detectionCount) signals")
        }
        .padding(.vertical, 9)
    }
}

private struct EmptySummaryView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ready to scan")
                .font(.headline)
            Text("Open Signal Trail to record a session.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

private struct SignalTrailWidgetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                LinearGradient(
                    colors: [Color(.systemBackground), Color.cyan.opacity(0.13)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else {
            content.background(
                LinearGradient(
                    colors: [Color(.systemBackground), Color.cyan.opacity(0.13)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}

struct SignalTrailWidget: Widget {
    let kind = "SignalTrailWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SignalTrailProvider()) { entry in
            SignalTrailWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Signal Trail Summary")
        .description("See recent scan sessions, devices, and detected signals.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct SignalTrailWidgetPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            SignalTrailWidgetEntryView(
                entry: SignalTrailEntry(date: .now, summary: .preview)
            )
            .previewContext(WidgetPreviewContext(family: .systemSmall))

            SignalTrailWidgetEntryView(
                entry: SignalTrailEntry(date: .now, summary: .preview)
            )
            .previewContext(WidgetPreviewContext(family: .systemMedium))
        }
    }
}
