import Foundation
import MapKit

final class ObservationAnnotation: NSObject, MKAnnotation {
    let peripheralIdentifier: UUID
    let title: String?
    let subtitle: String?
    let coordinate: CLLocationCoordinate2D
    let rssi: Int

    init(detection: BLEDetection) {
        peripheralIdentifier = detection.peripheralIdentifier
        title = detection.displayName
        subtitle = "\(detection.rssi) dBm • \(DateFormatter.signalTrailTime.string(from: detection.timestamp))"
        coordinate = detection.coordinate ?? CLLocationCoordinate2D()
        rssi = detection.rssi
        super.init()
    }
}
