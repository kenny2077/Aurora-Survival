import MapKit
import MapLibre
import SwiftUI

struct AppleMapCanvas: UIViewRepresentable {
    let source: MapSource
    let scene: MapSceneSnapshot
    let onLongPress: (GeoCoordinate) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLongPress: onLongPress) }

    func makeUIView(context: Context) -> MKMapView {
        let view = MKMapView()
        view.delegate = context.coordinator
        view.showsCompass = true
        view.showsScale = true
        view.showsUserLocation = false
        view.layoutMargins = UIEdgeInsets(
            top: 60,
            left: 8,
            bottom: 8,
            right: 8
        )
        let press = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.longPressed(_:))
        )
        view.addGestureRecognizer(press)
        context.coordinator.mapView = view
        return view
    }

    func updateUIView(_ view: MKMapView, context: Context) {
        view.mapType = source == .appleSatellite ? .satellite : .standard
        context.coordinator.update(scene: scene, on: view)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var mapView: MKMapView?
        private let onLongPress: (GeoCoordinate) -> Void
        private var centered = false
        private var currentPin: MKPointAnnotation?
        private var waypointPins: [MKPointAnnotation] = []
        private var waypointSnapshot: [Waypoint] = []
        private var trackOverlay: MKPolyline?
        private var trackSnapshot: [GeoCoordinate] = []

        init(onLongPress: @escaping (GeoCoordinate) -> Void) {
            self.onLongPress = onLongPress
        }

        @objc func longPressed(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let mapView else { return }
            let coordinate = mapView.convert(
                recognizer.location(in: mapView),
                toCoordinateFrom: mapView
            )
            onLongPress(GeoCoordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ))
        }

        func update(scene: MapSceneSnapshot, on view: MKMapView) {
            if let location = scene.location {
                let pin = currentPin ?? MKPointAnnotation()
                pin.title = "Current location"
                pin.coordinate = CLLocationCoordinate2D(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                if currentPin == nil {
                    currentPin = pin
                    view.addAnnotation(pin)
                }
                if !centered {
                    centered = true
                    view.setRegion(
                        MKCoordinateRegion(
                            center: pin.coordinate,
                            latitudinalMeters: 8_000,
                            longitudinalMeters: 8_000
                        ),
                        animated: false
                    )
                }
            } else if let currentPin {
                view.removeAnnotation(currentPin)
                self.currentPin = nil
            }
            if waypointSnapshot != scene.waypoints {
                view.removeAnnotations(waypointPins)
                waypointPins = scene.waypoints.map { waypoint in
                    let pin = MKPointAnnotation()
                    pin.title = waypoint.kind.displayName
                    pin.subtitle = waypoint.note
                    pin.coordinate = CLLocationCoordinate2D(
                        latitude: waypoint.coordinate.latitude,
                        longitude: waypoint.coordinate.longitude
                    )
                    return pin
                }
                view.addAnnotations(waypointPins)
                waypointSnapshot = scene.waypoints
            }
            if trackSnapshot != scene.activeTrack {
                if let trackOverlay { view.removeOverlay(trackOverlay) }
                trackOverlay = nil
                trackSnapshot = scene.activeTrack
            }
            if trackOverlay == nil, scene.activeTrack.count > 1 {
                let coordinates = scene.activeTrack.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                let overlay = MKPolyline(coordinates: coordinates, count: coordinates.count)
                trackOverlay = overlay
                view.addOverlay(overlay)
            }
        }

        func mapView(
            _ mapView: MKMapView,
            rendererFor overlay: MKOverlay
        ) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = UIColor.systemOrange
            renderer.lineWidth = 5
            renderer.lineJoin = .round
            return renderer
        }
    }
}

struct SurvivalOfflineMapCanvas: UIViewRepresentable {
    let map: ResolvedOfflineMap
    let layer: OfflineMapLayer
    let styleURL: URL
    let scene: MapSceneSnapshot
    let onLongPress: (GeoCoordinate) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLongPress: onLongPress) }

    func makeUIView(context: Context) -> MLNMapView {
        let view = MLNMapView(frame: .zero, styleURL: styleURL)
        view.delegate = context.coordinator
        view.minimumZoomLevel = Double(map.pack.minimumZoom)
        view.maximumZoomLevel = Double(map.pack.maximumZoom)
        view.preferredFramesPerSecond = .default
        view.showsScale = true
        view.compassViewPosition = .topRight
        view.layoutMargins = UIEdgeInsets(
            top: 60,
            left: 8,
            bottom: 8,
            right: 8
        )
        let press = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.longPressed(_:))
        )
        view.addGestureRecognizer(press)
        context.coordinator.mapView = view
        context.coordinator.fit(map: map, on: view)
        return view
    }

    func updateUIView(_ view: MLNMapView, context: Context) {
        context.coordinator.update(scene: scene, on: view)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        weak var mapView: MLNMapView?
        private let onLongPress: (GeoCoordinate) -> Void
        private var annotations: [MLNAnnotation] = []
        private var waypointSnapshot: [Waypoint] = []
        private var locationSnapshot: LocationFix?
        private var trackSnapshot: [GeoCoordinate] = []
        private var track: MLNPolyline?

        init(onLongPress: @escaping (GeoCoordinate) -> Void) {
            self.onLongPress = onLongPress
        }

        @objc func longPressed(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let mapView else { return }
            let coordinate = mapView.convert(
                recognizer.location(in: mapView),
                toCoordinateFrom: mapView
            )
            onLongPress(GeoCoordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ))
        }

        func fit(map: ResolvedOfflineMap, on view: MLNMapView) {
            view.setVisibleCoordinateBounds(
                MLNCoordinateBounds(
                    sw: CLLocationCoordinate2D(
                        latitude: map.pack.bounds.southWest.latitude,
                        longitude: map.pack.bounds.southWest.longitude
                    ),
                    ne: CLLocationCoordinate2D(
                        latitude: map.pack.bounds.northEast.latitude,
                        longitude: map.pack.bounds.northEast.longitude
                    )
                ),
                edgePadding: UIEdgeInsets(top: 80, left: 20, bottom: 180, right: 20),
                animated: false,
                completionHandler: nil
            )
        }

        func update(scene: MapSceneSnapshot, on view: MLNMapView) {
            if waypointSnapshot != scene.waypoints || locationSnapshot != scene.location {
                if !annotations.isEmpty { view.removeAnnotations(annotations) }
                annotations = []
                if let location = scene.location {
                    let pin = MLNPointAnnotation()
                    pin.title = "Current location"
                    pin.coordinate = CLLocationCoordinate2D(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    )
                    annotations.append(pin)
                }
                for waypoint in scene.waypoints {
                    let pin = MLNPointAnnotation()
                    pin.title = waypoint.kind.displayName
                    pin.subtitle = waypoint.note
                    pin.coordinate = CLLocationCoordinate2D(
                        latitude: waypoint.coordinate.latitude,
                        longitude: waypoint.coordinate.longitude
                    )
                    annotations.append(pin)
                }
                if !annotations.isEmpty { view.addAnnotations(annotations) }
                waypointSnapshot = scene.waypoints
                locationSnapshot = scene.location
            }
            if trackSnapshot != scene.activeTrack {
                if let track { view.removeAnnotation(track) }
                track = nil
                trackSnapshot = scene.activeTrack
            }
            if track == nil, scene.activeTrack.count > 1 {
                var coordinates = scene.activeTrack.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                let line = MLNPolyline(coordinates: &coordinates, count: UInt(coordinates.count))
                track = line
                view.addAnnotation(line)
            }
        }

        func mapView(
            _ mapView: MLNMapView,
            alphaForShapeAnnotation annotation: MLNShape
        ) -> CGFloat { 1 }

        func mapView(
            _ mapView: MLNMapView,
            strokeColorForShapeAnnotation annotation: MLNShape
        ) -> UIColor { .systemOrange }

        func mapView(
            _ mapView: MLNMapView,
            lineWidthForPolylineAnnotation annotation: MLNPolyline
        ) -> CGFloat { 5 }
    }
}
