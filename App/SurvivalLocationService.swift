import CoreLocation
import Foundation
import Network

@MainActor
protocol LocationProviding: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    func updates() -> AsyncStream<LocationFix>
    func requestWhenInUseAuthorization()
    func startDisplayUpdates()
    func startRecordingUpdates()
    func stopRecordingUpdates()
}

@MainActor
final class SurvivalLocationService: NSObject, LocationProviding,
    @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuations: [UUID: AsyncStream<LocationFix>.Continuation] = [:]
    private var latestHeading: Double?
    private var serviceSession: CLServiceSession?
    private var backgroundSession: CLBackgroundActivitySession?

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.pausesLocationUpdatesAutomatically = true
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func updates() -> AsyncStream<LocationFix> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations.removeValue(forKey: id) }
            }
        }
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startDisplayUpdates() {
        serviceSession = CLServiceSession(authorization: .whenInUse)
        manager.allowsBackgroundLocationUpdates = false
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    func startRecordingUpdates() {
        serviceSession = CLServiceSession(authorization: .whenInUse)
        backgroundSession = CLBackgroundActivitySession()
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func stopRecordingUpdates() {
        backgroundSession?.invalidate()
        backgroundSession = nil
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        manager.pausesLocationUpdatesAutomatically = true
        startDisplayUpdates()
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        for location in locations {
            let fix = LocationFix(
                coordinate: GeoCoordinate(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                ),
                altitude: location.altitude,
                horizontalAccuracy: location.horizontalAccuracy,
                verticalAccuracy: location.verticalAccuracy,
                speed: location.speed,
                course: location.course,
                heading: latestHeading,
                timestamp: location.timestamp
            )
            continuations.values.forEach { $0.yield(fix) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        latestHeading = newHeading.trueHeading >= 0
            ? newHeading.trueHeading : newHeading.magneticHeading
    }
}

protocol ConnectivityProviding: Sendable {
    func connectivityUpdates() -> AsyncStream<Bool>
}

final class NetworkConnectivityService: ConnectivityProviding, @unchecked Sendable {
    func connectivityUpdates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "Aurora.MapConnectivity"))
        }
    }
}
