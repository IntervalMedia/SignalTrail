import Foundation

final class AppEnvironment {
    let store: LocalStore
    let settingsStore: SettingsStore
    let notificationService: NotificationService
    let locationProvider: LocationProviding
    let bluetoothScanner: BluetoothScanner
    let scanCoordinator: ScanCoordinator

    init() {
        do {
            store = try LocalStore()
        } catch {
            fatalError("Unable to initialise local storage: \(error)")
        }

        settingsStore = SettingsStore()
        notificationService = NotificationService()
        locationProvider = CoreLocationProvider()
        bluetoothScanner = BluetoothScanner()
        scanCoordinator = ScanCoordinator(
            scanner: bluetoothScanner,
            locationProvider: locationProvider,
            store: store,
            settingsStore: settingsStore,
            notificationService: notificationService
        )
    }
}
