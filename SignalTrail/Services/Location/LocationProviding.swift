import Foundation
import CoreLocation

protocol LocationProviding: AnyObject {
    var currentLocation: CLLocation? { get }
    var authorizationStatus: CLAuthorizationStatus { get }
    var onAuthorizationChanged: ((CLAuthorizationStatus) -> Void)? { get set }

    func requestWhenInUseAuthorization()
    func startUpdating()
    func stopUpdating()
}
