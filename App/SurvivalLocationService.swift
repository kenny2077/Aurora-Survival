import CoreLocation
import Foundation
import Network

@MainActor
protocol LocationProviding: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    func updates() -> AsyncStream<LocationFix>
    func authorizationUpdates() -> AsyncStream<CLAuthorizationStatus>
    func requestWhenInUseAuthorization()
    func startDisplayUpdates()
    func stopDisplayUpdates()
    func startRecordingUpdates()
    func stopRecordingUpdates()
}

@MainActor
final class SurvivalLocationService: NSObject, LocationProviding,
    @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuations: [UUID: AsyncStream<LocationFix>.Continuation] = [:]
    private var authorizationContinuations: [UUID: AsyncStream<CLAuthorizationStatus>.Continuation] = [:]
    private var latestLocation: CLLocation?
    private var latestHeading: Double?
    private var serviceSession: CLServiceSession?
    private var backgroundSession: CLBackgroundActivitySession?

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.headingFilter = 1
        manager.pausesLocationUpdatesAutomatically = true
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func updates() -> AsyncStream<LocationFix> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            if let latestLocation {
                continuation.yield(makeFix(from: latestLocation))
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations.removeValue(forKey: id) }
            }
        }
    }

    func authorizationUpdates() -> AsyncStream<CLAuthorizationStatus> {
        let id = UUID()
        return AsyncStream { continuation in
            authorizationContinuations[id] = continuation
            continuation.yield(manager.authorizationStatus)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.authorizationContinuations.removeValue(forKey: id) }
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

    func stopDisplayUpdates() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        serviceSession?.invalidate()
        serviceSession = nil
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
        stopDisplayUpdates()
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        for location in locations {
            latestLocation = location
            yield(makeFix(from: location))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        latestHeading = newHeading.trueHeading >= 0
            ? newHeading.trueHeading : newHeading.magneticHeading
        if let latestLocation {
            yield(makeFix(from: latestLocation))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationContinuations.values.forEach {
            $0.yield(manager.authorizationStatus)
        }
    }

    private func makeFix(from location: CLLocation) -> LocationFix {
        LocationFix(
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
    }

    private func yield(_ fix: LocationFix) {
        continuations.values.forEach { $0.yield(fix) }
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
