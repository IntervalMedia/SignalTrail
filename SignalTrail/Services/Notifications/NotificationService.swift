import Foundation
import UserNotifications
import UIKit

final class NotificationService {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion?(granted) }
        }
    }

    func notify(rule: AlertRule, device: BLEDeviceSnapshot) {
        let content = UNMutableNotificationContent()
        content.title = rule.name.isEmpty ? "BLE device detected" : rule.name
        content.body = "\(device.displayName) was observed at \(DateFormatter.signalTrailTime.string(from: device.lastSeen))."
        content.sound = .default
        content.userInfo = ["peripheralIdentifier": device.peripheralIdentifier.uuidString]

        let request = UNNotificationRequest(
            identifier: "\(rule.id.uuidString)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}
