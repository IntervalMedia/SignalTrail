import Foundation
import WidgetKit

enum WidgetSummaryPublisher {
    static let appGroupIdentifier = "group.com.intervalmedia.DiscoveraBLE"
    static let storageKey = "signalTrail.widget.summary"
    static let widgetKind = "SignalTrailWidget"

    static func publish(sessions: [ScanSession]) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        let recentSessions = sessions
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(4)
            .map {
                SessionSummary(
                    name: $0.name,
                    startedAt: $0.startedAt,
                    endedAt: $0.endedAt,
                    detectionCount: $0.detectionCount,
                    uniqueDeviceCount: $0.uniqueDeviceCount
                )
            }
        let snapshot = SummarySnapshot(
            updatedAt: Date(),
            totalSessionCount: sessions.count,
            recentSessions: Array(recentSessions)
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}

private struct SummarySnapshot: Encodable {
    let updatedAt: Date
    let totalSessionCount: Int
    let recentSessions: [SessionSummary]
}

private struct SessionSummary: Encodable {
    let name: String
    let startedAt: Date
    let endedAt: Date?
    let detectionCount: Int
    let uniqueDeviceCount: Int
}
