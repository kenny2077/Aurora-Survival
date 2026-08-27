import MapKit
import MapLibre
import SwiftUI

struct MapCameraFocus: Equatable {
    let id = UUID()
    let coordinate: GeoCoordinate
}

struct AppleMapCanvas: UIViewRepresentable {
    let source: MapSource
    let scene: MapSceneSnapshot
    let bottomChromeInset: CGFloat
    let showsChrome: Bool
    let focus: MapCameraFocus?
    let onLongPress: (GeoCoordinate) -> Void
    let onSingleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLongPress: onLongPress, onSingleTap: onSingleTap)
    }

    func makeUIView(context: Context) -> MKMapView {
        let view = MKMapView()
        view.delegate = context.coordinator
        view.showsCompass = false
        view.showsScale = false
        view.tintColor = .systemBlue
        view.showsUserLocation = true
        view.setUserTrackingMode(.follow, animated: false)
        view.isRotateEnabled = true
        view.accessibilityIdentifier = "maps.canvas"
        let press = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.longPressed(_:))
        )
        press.minimumPressDuration = 0.5
        press.cancelsTouchesInView = false
        press.delegate = context.coordinator
        view.addGestureRecognizer(press)
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.singleTapped(_:))
        )
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.gestureRecognizers?
            .compactMap { $0 as? UITapGestureRecognizer }
            .filter { $0.numberOfTapsRequired > 1 }
            .forEach { tap.require(toFail: $0) }
        view.addGestureRecognizer(tap)
        context.coordinator.mapView = view
        context.coordinator.installChrome(
            on: view,
            bottomInset: bottomChromeInset,
            showsChrome: showsChrome
        )
        return view
    }

    func updateUIView(_ view: MKMapView, context: Context) {
        view.mapType = source == .appleSatellite ? .satellite : .standard
        view.isRotateEnabled = true
        context.coordinator.updateConfiguration(
            onLongPress: onLongPress,
            onSingleTap: onSingleTap,
            bottomInset: bottomChromeInset,
            showsChrome: showsChrome
        )
        context.coordinator.update(scene: scene, focus: focus, on: view)
    }

    final class Coordinator: NSObject, MKMapViewDelegate,
        UIGestureRecognizerDelegate {
        weak var mapView: MKMapView?
        private var onLongPress: (GeoCoordinate) -> Void
        private var onSingleTap: () -> Void
        private var waypointPins: [MKPointAnnotation] = []
        private var waypointSnapshot: [Waypoint] = []
        private var trackOverlay: MKPolyline?
        private var trackSnapshot: [GeoCoordinate] = []
        private var headingAnnotation: HeadingLocationAnnotation?
        private weak var headingBeam: HeadingBeamView?
        private var latestHeading: Double?
        private weak var compass: MKCompassButton?
        private weak var scale: MKScaleView?
        private var compassBottomConstraint: NSLayoutConstraint?
        private var chromeVisible: Bool?
        private var appliedFocusID: UUID?
        #if DEBUG
        private var appliedUITestBearing = false
        #endif

        init(
            onLongPress: @escaping (GeoCoordinate) -> Void,
            onSingleTap: @escaping () -> Void
        ) {
            self.onLongPress = onLongPress
            self.onSingleTap = onSingleTap
        }

        @objc func longPressed(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let mapView else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let coordinate = mapView.convert(
                recognizer.location(in: mapView),
                toCoordinateFrom: mapView
            )
            onLongPress(GeoCoordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ))
        }

        @objc func singleTapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onSingleTap()
        }

        @objc func toggleChromeFromAccessibility() -> Bool {
            onSingleTap()
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer:
                UIGestureRecognizer
        ) -> Bool { true }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            var candidate = touch.view
            while let view = candidate {
                if view is UIControl || view is MKAnnotationView {
                    return false
                }
                candidate = view.superview
            }
            return true
        }

        func updateConfiguration(
            onLongPress: @escaping (GeoCoordinate) -> Void,
            onSingleTap: @escaping () -> Void,
            bottomInset: CGFloat,
            showsChrome: Bool
        ) {
            self.onLongPress = onLongPress
            self.onSingleTap = onSingleTap
            compassBottomConstraint?.constant = -(bottomInset + 12)
            setChromeVisibility(showsChrome)
            updateAccessibilityAction(showsChrome: showsChrome)
        }

        func installChrome(
            on view: MKMapView,
            bottomInset: CGFloat,
            showsChrome: Bool
        ) {
            let compass = MKCompassButton(mapView: view)
            compass.compassVisibility = .adaptive
            compass.translatesAutoresizingMaskIntoConstraints = false
            compass.isAccessibilityElement = true
            compass.accessibilityLabel = "Compass"
            compass.accessibilityIdentifier = "maps.compass"
            view.addSubview(compass)
            let compassBottom = compass.bottomAnchor.constraint(
                equalTo: view.bottomAnchor,
                constant: -(bottomInset + 12)
            )
            NSLayoutConstraint.activate([
                compass.trailingAnchor.constraint(
                    equalTo: view.trailingAnchor,
                    constant: -12
                ),
                compassBottom,
            ])
            self.compass = compass
            compassBottomConstraint = compassBottom

            let scale = MKScaleView(mapView: view)
            scale.scaleVisibility = .visible
            scale.legendAlignment = .center
            scale.translatesAutoresizingMaskIntoConstraints = false
            scale.isAccessibilityElement = true
            scale.accessibilityLabel = "Map scale"
            scale.accessibilityIdentifier = "maps.scale"
            view.addSubview(scale)
            self.scale = scale
            NSLayoutConstraint.activate([
                scale.topAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.topAnchor,
                    constant: 6
                ),
                scale.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                scale.widthAnchor.constraint(lessThanOrEqualToConstant: 180),
            ])
            setChromeVisibility(showsChrome, animated: false)
            updateAccessibilityAction(showsChrome: showsChrome)
        }

        private func setChromeVisibility(
            _ isVisible: Bool,
            animated: Bool = true
        ) {
            guard chromeVisible != isVisible else { return }
            chromeVisible = isVisible
            let views = [compass as UIView?, scale as UIView?].compactMap { $0 }
            views.forEach { $0.isHidden = false }
            let changes = { views.forEach { $0.alpha = isVisible ? 1 : 0 } }
            let completion: (Bool) -> Void = { _ in
                views.forEach {
                    $0.isHidden = !isVisible
                    $0.isAccessibilityElement = isVisible
                    $0.accessibilityElementsHidden = !isVisible
                }
            }
            guard animated, !UIAccessibility.isReduceMotionEnabled else {
                changes()
                completion(true)
                return
            }
            UIView.animate(
                withDuration: 0.24,
                animations: changes,
                completion: completion
            )
        }

        private func updateAccessibilityAction(showsChrome: Bool) {
            mapView?.accessibilityCustomActions = [
                UIAccessibilityCustomAction(
                    name: showsChrome
                        ? "Hide map controls"
                        : "Show map controls",
                    target: self,
                    selector: #selector(toggleChromeFromAccessibility)
                ),
            ]
        }

        func update(
            scene: MapSceneSnapshot,
            focus: MapCameraFocus?,
            on view: MKMapView
        ) {
            if let focus, appliedFocusID != focus.id {
                appliedFocusID = focus.id
                view.setUserTrackingMode(.none, animated: false)
                view.setCenter(
                    CLLocationCoordinate2D(
                        latitude: focus.coordinate.latitude,
                        longitude: focus.coordinate.longitude
                    ),
                    animated: !UIAccessibility.isReduceMotionEnabled
                )
            }
            if let heading = scene.location?.heading {
                latestHeading = heading
            }
            updateHeadingAnnotation(with: scene.location, on: view)
            #if DEBUG
            applyUITestBearingIfNeeded(with: scene.location, on: view)
            #endif
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
            regionDidChangeAnimated animated: Bool
        ) {
            updateHeadingPresentation(on: mapView)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            updateHeadingPresentation(on: mapView)
            mapView.accessibilityValue = String(
                format: "%.5f, %.5f",
                mapView.centerCoordinate.latitude,
                mapView.centerCoordinate.longitude
            )
        }

        func mapView(
            _ mapView: MKMapView,
            didUpdate userLocation: MKUserLocation
        ) {
            if let nativeView = mapView.view(for: userLocation) {
                nativeView.alpha = 0
                nativeView.isAccessibilityElement = false
            }
            if CLLocationCoordinate2DIsValid(userLocation.coordinate) {
                headingAnnotation?.coordinate = userLocation.coordinate
            }
        }

        func mapView(
            _ mapView: MKMapView,
            didAdd views: [MKAnnotationView]
        ) {
            if let nativeView = views.first(where: {
                $0.annotation is MKUserLocation
            }) {
                nativeView.alpha = 0
                nativeView.isAccessibilityElement = false
            }
        }

        func mapView(
            _ mapView: MKMapView,
            viewFor annotation: MKAnnotation
        ) -> MKAnnotationView? {
            guard annotation is HeadingLocationAnnotation else { return nil }
            let identifier = "heading-location"
            let annotationView = mapView.dequeueReusableAnnotationView(
                withIdentifier: identifier
            ) ?? MKAnnotationView(
                annotation: annotation,
                reuseIdentifier: identifier
            )
            annotationView.annotation = annotation
            annotationView.bounds = CGRect(x: 0, y: 0, width: 96, height: 96)
            annotationView.backgroundColor = .clear
            annotationView.isEnabled = false
            annotationView.isAccessibilityElement = true
            annotationView.accessibilityLabel = "Current location"
            annotationView.accessibilityIdentifier = "maps.current-location"
            annotationView.displayPriority = .required
            annotationView.collisionMode = .none
            annotationView.zPriority = .max
            let beam: HeadingBeamView
            if let existing = annotationView.subviews.first(
                where: { $0 is HeadingBeamView }
            ) as? HeadingBeamView {
                beam = existing
            } else {
                beam = HeadingBeamView(frame: annotationView.bounds)
                beam.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                annotationView.addSubview(beam)
            }
            if annotationView.viewWithTag(1_307) == nil {
                let dot = UIView(
                    frame: CGRect(x: 37, y: 37, width: 22, height: 22)
                )
                dot.tag = 1_307
                dot.isUserInteractionEnabled = false
                dot.backgroundColor = .systemBlue
                dot.layer.cornerRadius = 11
                dot.layer.borderColor = UIColor.white.cgColor
                dot.layer.borderWidth = 3
                dot.layer.shadowColor = UIColor.black.cgColor
                dot.layer.shadowOpacity = 0.18
                dot.layer.shadowRadius = 2
                dot.layer.shadowOffset = CGSize(width: 0, height: 1)
                annotationView.addSubview(dot)
            }
            headingBeam = beam
            updateHeadingPresentation(on: mapView)
            return annotationView
        }

        private func updateHeadingAnnotation(
            with fix: LocationFix?,
            on mapView: MKMapView
        ) {
            guard let fix else {
                if let headingAnnotation {
                    mapView.removeAnnotation(headingAnnotation)
                    self.headingAnnotation = nil
                    headingBeam = nil
                }
                return
            }
            let coordinate = mapView.userLocation.location?.coordinate
                ?? CLLocationCoordinate2D(
                    latitude: fix.coordinate.latitude,
                    longitude: fix.coordinate.longitude
                )
            if let headingAnnotation {
                headingAnnotation.coordinate = coordinate
            } else {
                let annotation = HeadingLocationAnnotation(coordinate: coordinate)
                headingAnnotation = annotation
                mapView.addAnnotation(annotation)
            }
            updateHeadingPresentation(on: mapView)
        }

        private func updateHeadingPresentation(on mapView: MKMapView) {
            let bearing = mapView.camera.heading
            let displayedHeading = latestHeading.map { $0 - bearing }
            headingBeam?.setHeading(displayedHeading)
            compass?.accessibilityValue = "Bearing \(Int(bearing.rounded())) degrees"
        }

        #if DEBUG
        private func applyUITestBearingIfNeeded(
            with fix: LocationFix?,
            on mapView: MKMapView
        ) {
            guard !appliedUITestBearing,
                  let fix,
                  let rawBearing = ProcessInfo.processInfo.environment[
                    "TRAILGUARD_UI_MAP_BEARING"
                  ],
                  let bearing = CLLocationDirection(rawBearing)
            else { return }
            appliedUITestBearing = true
            mapView.setUserTrackingMode(.none, animated: false)
            let camera = MKMapCamera(
                lookingAtCenter: CLLocationCoordinate2D(
                    latitude: fix.coordinate.latitude,
                    longitude: fix.coordinate.longitude
                ),
                fromDistance: 2_500,
                pitch: 0,
                heading: bearing
            )
            mapView.setCamera(camera, animated: false)
            updateHeadingPresentation(on: mapView)
        }
        #endif

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

private final class HeadingLocationAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}

private final class HeadingBeamView: UIView {
    private let gradient = CAGradientLayer()
    private let beamMask = CAShapeLayer()
    private var displayedHeading = 0.0
    private var hasHeading = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
        gradient.colors = [
            UIColor.systemBlue.withAlphaComponent(0).cgColor,
            UIColor.systemBlue.withAlphaComponent(0.18).cgColor,
            UIColor.systemBlue.withAlphaComponent(0.42).cgColor,
        ]
        gradient.locations = [0, 0.52, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.mask = beamMask
        layer.addSublayer(gradient)
        alpha = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = UIBezierPath()
        path.move(to: center)
        path.addCurve(
            to: CGPoint(x: 27, y: 2),
            controlPoint1: CGPoint(x: 43, y: 38),
            controlPoint2: CGPoint(x: 32, y: 13)
        )
        path.addLine(to: CGPoint(x: bounds.maxX - 27, y: 2))
        path.addCurve(
            to: center,
            controlPoint1: CGPoint(x: bounds.maxX - 32, y: 13),
            controlPoint2: CGPoint(x: bounds.maxX - 43, y: 38)
        )
        path.close()
        beamMask.path = path.cgPath
    }

    func setHeading(_ heading: Double?) {
        guard let heading else {
            alpha = 0
            hasHeading = false
            return
        }
        let normalized = heading.truncatingRemainder(dividingBy: 360)
        if hasHeading {
            let delta = (normalized - displayedHeading + 540)
                .truncatingRemainder(dividingBy: 360) - 180
            displayedHeading += delta
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseOut]
            ) {
                self.transform = CGAffineTransform(
                    rotationAngle: self.displayedHeading * .pi / 180
                )
                self.alpha = 1
            }
        } else {
            displayedHeading = normalized
            transform = CGAffineTransform(
                rotationAngle: displayedHeading * .pi / 180
            )
            alpha = 1
            hasHeading = true
        }
    }
}

struct SurvivalOfflineMapCanvas: UIViewRepresentable {
    let map: ResolvedOfflineMap
    let layer: OfflineMapLayer
    let styleURL: URL
    let scene: MapSceneSnapshot
    let showsChrome: Bool
    let focus: MapCameraFocus?
    let onLongPress: (GeoCoordinate) -> Void
    let onSingleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLongPress: onLongPress, onSingleTap: onSingleTap)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let view = MLNMapView(frame: .zero, styleURL: styleURL)
        view.delegate = context.coordinator
        view.minimumZoomLevel = Double(map.pack.minimumZoom)
        view.maximumZoomLevel = Double(map.pack.maximumZoom)
        view.preferredFramesPerSecond = .default
        view.showsScale = true
        view.scaleBarPosition = .topLeft
        view.scaleBarMargins = CGPoint(x: 8, y: 6)
        view.tintColor = .systemBlue
        view.showsUserLocation = true
        view.showsUserHeadingIndicator = true
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
        press.minimumPressDuration = 0.5
        press.cancelsTouchesInView = false
        press.delegate = context.coordinator
        view.addGestureRecognizer(press)
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.singleTapped(_:))
        )
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.gestureRecognizers?
            .compactMap { $0 as? UITapGestureRecognizer }
            .filter { $0.numberOfTapsRequired > 1 }
            .forEach { tap.require(toFail: $0) }
        view.addGestureRecognizer(tap)
        context.coordinator.mapView = view
        context.coordinator.updateConfiguration(
            onLongPress: onLongPress,
            onSingleTap: onSingleTap,
            showsChrome: showsChrome,
            on: view,
            animated: false
        )
        context.coordinator.fit(map: map, on: view)
        return view
    }

    func updateUIView(_ view: MLNMapView, context: Context) {
        context.coordinator.updateConfiguration(
            onLongPress: onLongPress,
            onSingleTap: onSingleTap,
            showsChrome: showsChrome,
            on: view
        )
        if view.bounds.width > 0 {
            view.scaleBarMargins = CGPoint(
                x: max(8, (view.bounds.width - view.scaleBar.bounds.width) / 2),
                y: 6
            )
        }
        context.coordinator.update(scene: scene, focus: focus, on: view)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate,
        UIGestureRecognizerDelegate {
        weak var mapView: MLNMapView?
        private var onLongPress: (GeoCoordinate) -> Void
        private var onSingleTap: () -> Void
        private var waypointAnnotations: [MLNPointAnnotation] = []
        private var waypointSnapshot: [Waypoint] = []
        private var trackSnapshot: [GeoCoordinate] = []
        private var track: MLNPolyline?
        private var chromeVisible: Bool?
        private var appliedFocusID: UUID?

        init(
            onLongPress: @escaping (GeoCoordinate) -> Void,
            onSingleTap: @escaping () -> Void
        ) {
            self.onLongPress = onLongPress
            self.onSingleTap = onSingleTap
        }

        @objc func longPressed(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let mapView else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let coordinate = mapView.convert(
                recognizer.location(in: mapView),
                toCoordinateFrom: mapView
            )
            onLongPress(GeoCoordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ))
        }

        @objc func singleTapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onSingleTap()
        }

        @objc func toggleChromeFromAccessibility() -> Bool {
            onSingleTap()
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer:
                UIGestureRecognizer
        ) -> Bool { true }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            var candidate = touch.view
            while let view = candidate {
                if view is UIControl || view is MLNAnnotationView {
                    return false
                }
                candidate = view.superview
            }
            return true
        }

        func updateConfiguration(
            onLongPress: @escaping (GeoCoordinate) -> Void,
            onSingleTap: @escaping () -> Void,
            showsChrome: Bool,
            on view: MLNMapView,
            animated: Bool = true
        ) {
            self.onLongPress = onLongPress
            self.onSingleTap = onSingleTap
            setChromeVisibility(showsChrome, on: view, animated: animated)
            view.accessibilityCustomActions = [
                UIAccessibilityCustomAction(
                    name: showsChrome
                        ? "Hide map controls"
                        : "Show map controls",
                    target: self,
                    selector: #selector(toggleChromeFromAccessibility)
                ),
            ]
        }

        private func setChromeVisibility(
            _ isVisible: Bool,
            on view: MLNMapView,
            animated: Bool
        ) {
            guard chromeVisible != isVisible else { return }
            chromeVisible = isVisible
            if isVisible {
                view.showsScale = true
                view.showsCompassView = true
            }
            let ornaments = [view.scaleBar as UIView, view.compassView as UIView]
            ornaments.forEach { $0.isHidden = false }
            let changes = {
                ornaments.forEach { $0.alpha = isVisible ? 1 : 0 }
            }
            let completion: (Bool) -> Void = { _ in
                if !isVisible {
                    view.showsScale = false
                    view.showsCompassView = false
                }
                ornaments.forEach {
                    $0.isAccessibilityElement = isVisible
                    $0.accessibilityElementsHidden = !isVisible
                }
            }
            guard animated, !UIAccessibility.isReduceMotionEnabled else {
                changes()
                completion(true)
                return
            }
            UIView.animate(
                withDuration: 0.24,
                animations: changes,
                completion: completion
            )
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

        func update(
            scene: MapSceneSnapshot,
            focus: MapCameraFocus?,
            on view: MLNMapView
        ) {
            if let focus, appliedFocusID != focus.id {
                appliedFocusID = focus.id
                view.setCenter(
                    CLLocationCoordinate2D(
                        latitude: focus.coordinate.latitude,
                        longitude: focus.coordinate.longitude
                    ),
                    animated: !UIAccessibility.isReduceMotionEnabled
                )
            }
            if waypointSnapshot != scene.waypoints {
                if !waypointAnnotations.isEmpty {
                    view.removeAnnotations(waypointAnnotations)
                }
                waypointAnnotations = scene.waypoints.map { waypoint in
                    let pin = MLNPointAnnotation()
                    pin.title = waypoint.kind.displayName
                    pin.subtitle = waypoint.note
                    pin.coordinate = CLLocationCoordinate2D(
                        latitude: waypoint.coordinate.latitude,
                        longitude: waypoint.coordinate.longitude
                    )
                    return pin
                }
                if !waypointAnnotations.isEmpty {
                    view.addAnnotations(waypointAnnotations)
                }
                waypointSnapshot = scene.waypoints
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
