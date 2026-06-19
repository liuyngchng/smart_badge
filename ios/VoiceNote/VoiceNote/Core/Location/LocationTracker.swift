import CoreLocation
import Foundation

/// GPS 位置采集 — 仅取单次位置
final class LocationTracker: NSObject {
    private let manager = CLLocationManager()
    private var singleRequestContinuation: CheckedContinuation<LocationPoint?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// 获取当前单次位置
    func requestCurrentLocation() async -> LocationPoint? {
        manager.requestWhenInUseAuthorization()
        return await withCheckedContinuation { continuation in
            singleRequestContinuation = continuation
            manager.requestLocation()
        }
    }
}

extension LocationTracker: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let point = LocationPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp
        )
        singleRequestContinuation?.resume(returning: point)
        singleRequestContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        singleRequestContinuation?.resume(returning: nil)
        singleRequestContinuation = nil
    }
}
