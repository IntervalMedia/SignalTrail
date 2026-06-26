import Foundation
import CoreLocation

final class CoreLocationProvider: NSObject, LocationProviding {
    private let manager = CLLocationManager()

    private(set) var currentLocation: CLLocation?
    var onAuthorizationChanged: ((CLAuthorizationStatus) -> Void)?

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = true
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }
}

extension CoreLocationProvider: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let candidate = locations.last, candidate.horizontalAccuracy >= 0 else { return }
        currentLocation = candidate
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChanged?(manager.authorizationStatus)
    }
}
