import MapKit
import UIKit

final class SessionDetailViewController: UIViewController {
    private final class SightingAnnotation: NSObject, MKAnnotation {
        let peripheralIdentifier: UUID
        let sequenceNumber: Int?
        let rssi: Int
        let title: String?
        let coordinate: CLLocationCoordinate2D

        init(detection: BLEDetection, sequenceNumber: Int? = nil) {
            peripheralIdentifier = detection.peripheralIdentifier
            self.sequenceNumber = sequenceNumber
            rssi = detection.rssi
            title = detection.displayName
            coordinate = detection.coordinate ?? CLLocationCoordinate2D()
        }
    }

    private let session: ScanSession
    private let environment: AppEnvironment
    private var detections: [BLEDetection] = []
    private var deviceGroups: [UUID: [BLEDetection]] = [:]

    private let mapView = MKMapView()
    private let sessionSummaryLabel = UILabel()
    private let recenterButton = UIButton(type: .system)

    init(session: ScanSession, environment: AppEnvironment) {
        self.session = session
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Trail"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.prompt = session.name
        view.backgroundColor = AppTheme.groupedBackground
        configureNavigation()
        configureLayout()
        loadData()
    }

    private func configureNavigation() {
        let export = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(exportTapped)
        )
        installBustAction(environment: environment, additionalItems: [export])
    }

    private func configureLayout() {
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
        configuration.pointOfInterestFilter = .excludingAll
        mapView.preferredConfiguration = configuration
        mapView.delegate = self
        mapView.overrideUserInterfaceStyle = .dark
        mapView.showsCompass = true
        mapView.showsScale = true

        sessionSummaryLabel.font = .preferredFont(forTextStyle: .footnote)
        sessionSummaryLabel.textColor = AppTheme.secondaryText
        sessionSummaryLabel.numberOfLines = 1
        sessionSummaryLabel.backgroundColor = AppTheme.surface.withAlphaComponent(0.94)
        sessionSummaryLabel.layer.cornerRadius = 8
        sessionSummaryLabel.layer.cornerCurve = .continuous
        sessionSummaryLabel.clipsToBounds = true
        sessionSummaryLabel.textAlignment = .center

        var recenterConfiguration = UIButton.Configuration.filled()
        recenterConfiguration.image = UIImage(systemName: "scope")
        recenterConfiguration.baseBackgroundColor = AppTheme.surface
        recenterConfiguration.baseForegroundColor = .label
        recenterConfiguration.cornerStyle = .medium
        recenterButton.configuration = recenterConfiguration
        recenterButton.accessibilityLabel = "Show all sightings"
        recenterButton.addTarget(self, action: #selector(showAllSightings), for: .touchUpInside)

        view.addSubview(mapView)
        mapView.pinEdges(to: view)

        view.addSubview(sessionSummaryLabel)
        sessionSummaryLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recenterButton)
        recenterButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            sessionSummaryLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            sessionSummaryLabel.trailingAnchor.constraint(lessThanOrEqualTo: recenterButton.leadingAnchor, constant: -10),
            sessionSummaryLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            sessionSummaryLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            recenterButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            recenterButton.centerYAnchor.constraint(equalTo: sessionSummaryLabel.centerYAnchor),
            recenterButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            recenterButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    private func loadData() {
        do {
            detections = try environment.store.loadDetections(sessionID: session.id)
                .sorted { $0.timestamp < $1.timestamp }
            deviceGroups = Dictionary(grouping: detections, by: \.peripheralIdentifier)
                .mapValues { $0.sorted { $0.timestamp < $1.timestamp } }

            sessionSummaryLabel.text = "  \(session.duration.clockString)  ·  \(deviceGroups.count) devices  ·  \(detections.count) sightings  "
            showOverviewAnnotations()
            zoomTo(detections.compactMap(\.coordinate))
        } catch {
            presentError("Unable to load trail: \(error.localizedDescription)")
        }
    }

    @objc private func showAllSightings() {
        showOverviewAnnotations()
        zoomTo(detections.compactMap(\.coordinate))
    }

    private func showOverviewAnnotations() {
        mapView.removeAnnotations(mapView.annotations)
        mapView.removeOverlays(mapView.overlays)

        let latest = deviceGroups.values.compactMap { observations in
            observations.last(where: { $0.coordinate != nil })
        }
        mapView.addAnnotations(latest.map { SightingAnnotation(detection: $0) })
        addRoute(detections.compactMap(\.coordinate))
    }

    private func focus(on observations: [BLEDetection]) {
        mapView.removeAnnotations(mapView.annotations)
        mapView.removeOverlays(mapView.overlays)

        let located = observations.filter { $0.coordinate != nil }
        let annotations = located.enumerated().map {
            SightingAnnotation(detection: $0.element, sequenceNumber: $0.offset + 1)
        }
        mapView.addAnnotations(annotations)
        let coordinates = located.compactMap(\.coordinate)
        addRoute(coordinates)
        zoomTo(coordinates)
    }

    private func addRoute(_ coordinates: [CLLocationCoordinate2D]) {
        guard coordinates.count > 1 else { return }
        mapView.addOverlay(MKPolyline(coordinates: coordinates, count: coordinates.count))
    }

    private func zoomTo(_ coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else { return }

        if coordinates.count == 1, let coordinate = coordinates.first {
            mapView.setRegion(
                MKCoordinateRegion(center: coordinate, latitudinalMeters: 350, longitudinalMeters: 350),
                animated: true
            )
            return
        }

        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        mapView.setVisibleMapRect(
            rect,
            edgePadding: UIEdgeInsets(top: 90, left: 44, bottom: 80, right: 44),
            animated: true
        )
    }

    private func makeSnapshot(for observations: [BLEDetection], identifier: UUID) -> BLEDeviceSnapshot {
        let latest = observations.last!
        let strongestRSSI = observations.max { $0.rssi < $1.rssi }!.rssi
        return BLEDeviceSnapshot(
            peripheralIdentifier: identifier,
            displayName: latest.displayName,
            latestRSSI: latest.rssi,
            strongestRSSI: strongestRSSI,
            firstSeen: observations.first!.timestamp,
            lastSeen: latest.timestamp,
            lastSeenMetadataTag: latest.advertisement.metadataTag,
            sightingCount: observations.count,
            advertisement: latest.advertisement
        )
    }

    private func presentDeviceSheet(for identifier: UUID) {
        guard let observations = deviceGroups[identifier], !observations.isEmpty else { return }
        focus(on: observations)
        let snapshot = makeSnapshot(for: observations, identifier: identifier)
        let sheet = DeviceTrailSheetViewController(
            device: snapshot,
            observations: observations,
            timeZone: session.timeZone
        )

        sheet.onOpenIntel = { [weak self, weak sheet] in
            guard let self else { return }
            sheet?.dismiss(animated: true) {
                self.navigationController?.pushViewController(
                    DeviceDetailViewController(device: snapshot, environment: self.environment),
                    animated: true
                )
            }
        }

        sheet.onAddHaunt = { [weak self, weak sheet] in
            guard let self else { return }
            self.environment.hunter.selectTarget(snapshot, startImmediately: false)
            sheet?.dismiss(animated: true) {
                self.tabBarController?.selectedIndex = 2
            }
        }

        sheet.modalPresentationStyle = .pageSheet
        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.selectedDetentIdentifier = .medium
            presentation.prefersGrabberVisible = true
            presentation.prefersScrollingExpandsWhenScrolledToEdge = true
            presentation.largestUndimmedDetentIdentifier = .medium
        }
        present(sheet, animated: true)
    }

    @objc private func exportTapped() {
        let alert = UIAlertController(title: "Export Trail", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "JSON", style: .default) { [weak self] _ in self?.export(.json) })
        alert.addAction(UIAlertAction(title: "CSV", style: .default) { [weak self] _ in self?.export(.csv) })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.last
        }
        present(alert, animated: true)
    }

    private func export(_ format: SessionExporter.Format) {
        do {
            let url = try SessionExporter.makeTemporaryExport(
                session: session,
                detections: detections,
                format: format
            )
            present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
        } catch {
            presentError("Export failed: \(error.localizedDescription)")
        }
    }
}

extension SessionDetailViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let sighting = annotation as? SightingAnnotation else { return nil }
        let identifier = "GhostBustaSighting"
        let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
            ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        view.annotation = annotation
        view.canShowCallout = false
        view.displayPriority = sighting.sequenceNumber == nil ? .defaultHigh : .required
        view.glyphText = sighting.sequenceNumber.map(String.init)
        view.glyphImage = sighting.sequenceNumber == nil ? UIImage(systemName: "wave.3.right") : nil

        switch SignalLevel(rssi: sighting.rssi) {
        case .excellent, .good:
            view.markerTintColor = AppTheme.known
        case .fair:
            view.markerTintColor = AppTheme.watch
        case .weak:
            view.markerTintColor = AppTheme.risk
        case .unknown:
            view.markerTintColor = .systemGray
        }
        return view
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let sighting = view.annotation as? SightingAnnotation else { return }
        presentDeviceSheet(for: sighting.peripheralIdentifier)
        mapView.deselectAnnotation(sighting, animated: false)
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.strokeColor = AppTheme.secondaryText.withAlphaComponent(0.78)
        renderer.lineWidth = 2
        renderer.lineDashPattern = [6, 5]
        renderer.lineCap = .round
        renderer.lineJoin = .round
        return renderer
    }
}

private final class DeviceTrailSheetViewController: UIViewController {
    var onOpenIntel: (() -> Void)?
    var onAddHaunt: (() -> Void)?

    private let device: BLEDeviceSnapshot
    private let observations: [BLEDetection]
    private let timeZone: TimeZone

    init(device: BLEDeviceSnapshot, observations: [BLEDetection], timeZone: TimeZone) {
        self.device = device
        self.observations = observations
        self.timeZone = timeZone
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppTheme.surface
        configureContent()
    }

    private func configureContent() {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.pinEdges(to: view)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 28, left: 20, bottom: 28, right: 20)
        scrollView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.text = device.presentationName

        let intelligence = device.intelligence
        let classification = UILabel()
        classification.font = .preferredFont(forTextStyle: .subheadline)
        classification.textColor = intelligence.category == .unknown ? AppTheme.secondaryText : AppTheme.risk
        classification.numberOfLines = 0
        classification.text = intelligence.category == .unknown
            ? "Unknown device type"
            : "\(intelligence.categoryTitle)  ·  \(intelligence.confidenceLabel)"

        let microcopy = UILabel()
        microcopy.font = .preferredFont(forTextStyle: .body)
        microcopy.textColor = AppTheme.secondaryText
        microcopy.numberOfLines = 0
        microcopy.text = observations.count >= 3 ? "This ghost keeps returning." : "Observed in this field session."

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(classification)
        stack.setCustomSpacing(8, after: classification)
        stack.addArrangedSubview(microcopy)
        stack.addArrangedSubview(makeSummary())
        stack.addArrangedSubview(makeTimeline())

        var primary = UIButton.Configuration.filled()
        primary.title = "Open INTEL"
        primary.image = UIImage(systemName: "doc.text.magnifyingglass")
        primary.imagePadding = 10
        primary.cornerStyle = .large
        let intelButton = UIButton(configuration: primary)
        intelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        intelButton.addAction(UIAction { [weak self] _ in self?.onOpenIntel?() }, for: .touchUpInside)
        stack.addArrangedSubview(intelButton)

        var secondary = UIButton.Configuration.bordered()
        secondary.title = "Add to HAUNTS"
        secondary.image = UIImage(systemName: "scope")
        secondary.imagePadding = 10
        secondary.cornerStyle = .large
        let hauntButton = UIButton(configuration: secondary)
        hauntButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        hauntButton.addAction(UIAction { [weak self] _ in self?.onAddHaunt?() }, for: .touchUpInside)
        stack.addArrangedSubview(hauntButton)
    }

    private func makeSummary() -> UIView {
        let latest = observations.last
        let locatedCount = Set(
            observations.compactMap { detection -> String? in
                guard let coordinate = detection.coordinate else { return nil }
                return String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
            }
        ).count

        let values: [(String, String)] = [
            ("Sightings", "\(observations.count)"),
            ("Locations", "\(locatedCount)"),
            ("Last seen", latest.map { relativeTime(from: $0.timestamp) } ?? "—"),
            ("RSSI", latest.map { "\($0.rssi) dBm" } ?? "—")
        ]

        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 12

        for chunk in stride(from: 0, to: values.count, by: 2) {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 12
            for item in values[chunk..<min(chunk + 2, values.count)] {
                let title = UILabel()
                title.text = item.0
                title.font = .preferredFont(forTextStyle: .caption1)
                title.textColor = AppTheme.secondaryText

                let value = UILabel()
                value.text = item.1
                value.font = item.0 == "RSSI"
                    ? .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
                    : .preferredFont(forTextStyle: .headline)
                value.adjustsFontForContentSizeCategory = true

                let column = UIStackView(arrangedSubviews: [title, value])
                column.axis = .vertical
                column.spacing = 4
                row.addArrangedSubview(column)
            }
            grid.addArrangedSubview(row)
        }
        return grid
    }

    private func makeTimeline() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 10

        let title = UILabel()
        title.text = "Sighting Timeline"
        title.font = .preferredFont(forTextStyle: .headline)
        container.addArrangedSubview(title)

        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.timeStyle = .short

        let samples = Array(observations.suffix(6))
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 4

        for (index, observation) in samples.enumerated() {
            let number = UILabel()
            number.text = "\(max(1, observations.count - samples.count + index + 1))"
            number.textAlignment = .center
            number.font = .preferredFont(forTextStyle: .caption1)
            number.textColor = AppTheme.accent

            let dot = UIImageView(image: UIImage(systemName: "circle.fill"))
            dot.tintColor = index == samples.count - 1 ? AppTheme.risk : AppTheme.secondaryText
            dot.contentMode = .scaleAspectFit
            dot.heightAnchor.constraint(equalToConstant: 14).isActive = true

            let time = UILabel()
            time.text = formatter.string(from: observation.timestamp)
            time.textAlignment = .center
            time.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            time.textColor = AppTheme.secondaryText
            time.adjustsFontSizeToFitWidth = true
            time.minimumScaleFactor = 0.75

            let item = UIStackView(arrangedSubviews: [number, dot, time])
            item.axis = .vertical
            item.spacing = 5
            row.addArrangedSubview(item)
        }

        container.addArrangedSubview(row)
        return container
    }

    private func relativeTime(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "Now" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        if seconds < 86_400 { return "\(seconds / 3600) hr ago" }

        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
