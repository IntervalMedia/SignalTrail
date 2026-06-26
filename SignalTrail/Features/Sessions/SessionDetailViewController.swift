import MapKit
import UIKit

final class SessionDetailViewController: UIViewController {
  private let session: ScanSession
  private let environment: AppEnvironment
  private var detections: [BLEDetection] = []
  private var filteredDetections: [BLEDetection] = []
  private var deviceGroups: [(UUID, [BLEDetection])] = []

  private let mapView = MKMapView()
  private let timelineSlider = UISlider()
  private let elapsedLabel = UILabel()
  private let wallClockLabel = UILabel()
  private let playButton = UIButton(type: .system)
  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private var playbackTimer: Timer?

  init(session: ScanSession, environment: AppEnvironment) {
    self.session = session
    self.environment = environment
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  deinit { playbackTimer?.invalidate() }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = session.name
    navigationItem.largeTitleDisplayMode = .never
    view.backgroundColor = AppTheme.groupedBackground
    configureNavigation()
    configureLayout()
    loadData()
  }

  private func configureNavigation() {
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      image: UIImage(systemName: "square.and.arrow.up"),
      style: .plain,
      target: self,
      action: #selector(exportTapped)
    )
  }

  private func configureLayout() {
    mapView.delegate = self
    mapView.register(
      MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "Observation")
    mapView.layer.cornerRadius = 18
    mapView.layer.cornerCurve = .continuous
    mapView.showsCompass = true
    mapView.showsScale = true

    timelineSlider.minimumValue = 0
    timelineSlider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
    elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    elapsedLabel.textAlignment = .right
    elapsedLabel.textColor = .secondaryLabel

    wallClockLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    wallClockLabel.textAlignment = .center
    wallClockLabel.textColor = .tertiaryLabel
    wallClockLabel.adjustsFontSizeToFitWidth = true
    wallClockLabel.minimumScaleFactor = 0.8

    var playConfiguration = UIButton.Configuration.tinted()
    playConfiguration.image = UIImage(systemName: "play.fill")
    playConfiguration.cornerStyle = .capsule
    playButton.configuration = playConfiguration
    playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)

    let timelineRow = UIStackView(arrangedSubviews: [playButton, timelineSlider, elapsedLabel])
    timelineRow.axis = .horizontal
    timelineRow.alignment = .center
    timelineRow.spacing = 10
    elapsedLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true

    // wallClockLabel sits below the slider row, centred between the play button and the elapsed counter.
    let timelineStack = UIStackView(arrangedSubviews: [timelineRow, wallClockLabel])
    timelineStack.axis = .vertical
    timelineStack.spacing = 2

    tableView.dataSource = self
    tableView.delegate = self
    tableView.register(
      SessionDeviceCell.self, forCellReuseIdentifier: SessionDeviceCell.reuseIdentifier)
    tableView.backgroundColor = .clear

    let mapContainer = CardView()
    mapContainer.addSubview(mapView)
    mapView.pinEdges(to: mapContainer, insets: UIEdgeInsets(top: 1, left: 1, bottom: 1, right: 1))

    let stack = UIStackView(arrangedSubviews: [mapContainer, timelineStack, tableView])
    stack.axis = .vertical
    stack.spacing = 12
    view.addSubview(stack)
    stack.pinEdges(to: view, insets: UIEdgeInsets(top: 12, left: 12, bottom: 0, right: 12))

    let mapHeight = mapContainer.heightAnchor.constraint(
      equalTo: view.heightAnchor, multiplier: 0.42)
    mapHeight.priority = .defaultHigh
    mapHeight.isActive = true
    tableView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
  }

  private func loadData() {
    do {
      detections = try environment.store.loadDetections(sessionID: session.id)
        .sorted { $0.timestamp < $1.timestamp }
      timelineSlider.maximumValue = Float(
        max(
          session.duration,
          detections.last.map { $0.timestamp.timeIntervalSince(session.startedAt) } ?? 0))
      timelineSlider.value = timelineSlider.maximumValue
      applyTimeline()
      zoomToObservations()
    } catch {
      presentError("Unable to load observations: \(error.localizedDescription)")
    }
  }

  private func applyTimeline() {
    let cutoff = session.startedAt.addingTimeInterval(TimeInterval(timelineSlider.value))
    filteredDetections = detections.filter { $0.timestamp <= cutoff }
    elapsedLabel.text =
      "\(TimeInterval(timelineSlider.value).clockString) / \(TimeInterval(timelineSlider.maximumValue).clockString)"

    let wallClock = DateFormatter.wallClock(timeZone: session.timeZone)
    wallClockLabel.text = wallClock.string(from: cutoff)

    let grouped = Dictionary(grouping: filteredDetections, by: \.peripheralIdentifier)
    deviceGroups = grouped.map { ($0.key, $0.value.sorted { $0.timestamp < $1.timestamp }) }
      .sorted { lhs, rhs in
        let left = lhs.1.last?.displayName ?? ""
        let right = rhs.1.last?.displayName ?? ""
        return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
      }

    updateMap()
    tableView.reloadData()
  }

  private func updateMap() {
    mapView.removeAnnotations(mapView.annotations)
    mapView.removeOverlays(mapView.overlays)

    // A marker represents the phone location of the most recent observation for each peripheral.
    let latestByDevice = Dictionary(
      grouping: filteredDetections.compactMap { $0.coordinate == nil ? nil : $0 },
      by: \.peripheralIdentifier
    )
    .compactMap { $0.value.last }
    mapView.addAnnotations(latestByDevice.map { ObservationAnnotation(detection: $0) })

    // The path represents the phone's observation route, sampled from BLE detections.
    let coordinates = filteredDetections.compactMap(\.coordinate)
    guard coordinates.count > 1 else { return }
    mapView.addOverlay(MKPolyline(coordinates: coordinates, count: coordinates.count))
  }

  private func zoomToObservations() {
    let coordinates = detections.compactMap(\.coordinate)
    guard !coordinates.isEmpty else { return }
    let points = coordinates.map { MKMapPoint($0) }
    var rect = MKMapRect.null
    for point in points {
      let small = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
      rect = rect.union(small)
    }
    mapView.setVisibleMapRect(
      rect, edgePadding: UIEdgeInsets(top: 60, left: 50, bottom: 60, right: 50), animated: false)
  }

  @objc private func sliderChanged() {
    stopPlayback()
    applyTimeline()
  }

  @objc private func playTapped() {
    if playbackTimer != nil {
      stopPlayback()
      return
    }
    if timelineSlider.value >= timelineSlider.maximumValue { timelineSlider.value = 0 }
    var configuration = playButton.configuration
    configuration?.image = UIImage(systemName: "pause.fill")
    playButton.configuration = configuration

    playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      guard let self = self else { return }
      let step = max(1, self.timelineSlider.maximumValue / 120)
      self.timelineSlider.value = min(
        self.timelineSlider.maximumValue, self.timelineSlider.value + step)
      self.applyTimeline()
      if self.timelineSlider.value >= self.timelineSlider.maximumValue { self.stopPlayback() }
    }
  }

  private func stopPlayback() {
    playbackTimer?.invalidate()
    playbackTimer = nil
    var configuration = playButton.configuration
    configuration?.image = UIImage(systemName: "play.fill")
    playButton.configuration = configuration
  }

  private func makeSnapshot(for observations: [BLEDetection], identifier: UUID) -> BLEDeviceSnapshot {
    // observations are already sorted ascending by timestamp inside deviceGroups
    let latest = observations.last!
    let strongestRSSI = observations.max { $0.rssi < $1.rssi }!.rssi
    return BLEDeviceSnapshot(
      peripheralIdentifier: identifier,
      displayName: latest.displayName,
      latestRSSI: latest.rssi,
      strongestRSSI: strongestRSSI,
      firstSeen: observations.first!.timestamp,
      lastSeen: latest.timestamp,
      sightingCount: observations.count,
      advertisement: latest.advertisement
    )
  }

  @objc private func exportTapped() {
    let alert = UIAlertController(
      title: "Export Session", message: nil, preferredStyle: .actionSheet)
    alert.addAction(
      UIAlertAction(title: "JSON", style: .default) { [weak self] _ in self?.export(.json) })
    alert.addAction(
      UIAlertAction(title: "CSV", style: .default) { [weak self] _ in self?.export(.csv) })
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.barButtonItem = navigationItem.rightBarButtonItem
    }
    present(alert, animated: true)
  }

  private func export(_ format: SessionExporter.Format) {
    do {
      let url = try SessionExporter.makeTemporaryExport(
        session: session, detections: detections, format: format)
      let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
      if let popover = activity.popoverPresentationController {
        popover.barButtonItem = navigationItem.rightBarButtonItem
      }
      present(activity, animated: true)
    } catch {
      presentError("Export failed: \(error.localizedDescription)")
    }
  }
}

extension SessionDetailViewController: UITableViewDataSource, UITableViewDelegate {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    deviceGroups.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let (identifier, observations) = deviceGroups[indexPath.row]
    let latest = observations.last!
    let cell =
      tableView.dequeueReusableCell(
        withIdentifier: SessionDeviceCell.reuseIdentifier, for: indexPath) as! SessionDeviceCell
    cell.configure(
      name: latest.displayName,
      identifier: identifier,
      observationCount: observations.count,
      latestRSSI: latest.rssi,
      timestamp: latest.timestamp
    )
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let (identifier, observations) = deviceGroups[indexPath.row]

    // If the device has a known coordinate, pan the map to it.
    if let coordinate = observations.last?.coordinate {
      mapView.setRegion(
        MKCoordinateRegion(center: coordinate, latitudinalMeters: 250, longitudinalMeters: 250),
        animated: true)
    }

    // Navigate to the same device-detail view used in realtime mode.
    let snapshot = makeSnapshot(for: observations, identifier: identifier)
    navigationController?.pushViewController(
      DeviceDetailViewController(device: snapshot, environment: environment),
      animated: true)
  }
}

extension SessionDetailViewController: MKMapViewDelegate {
  func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
    guard let observation = annotation as? ObservationAnnotation else { return nil }
    let view =
      mapView.dequeueReusableAnnotationView(withIdentifier: "Observation", for: annotation)
      as! MKMarkerAnnotationView
    view.canShowCallout = true
    view.clusteringIdentifier = "BLEObservation"
    view.glyphImage = UIImage(systemName: "antenna.radiowaves.left.and.right")
    switch SignalLevel(rssi: observation.rssi) {
    case .excellent: view.markerTintColor = .systemGreen
    case .good: view.markerTintColor = .systemTeal
    case .fair: view.markerTintColor = .systemOrange
    case .weak: view.markerTintColor = .systemRed
    case .unknown: view.markerTintColor = .systemGray
    }
    return view
  }

  func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
    guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
    let renderer = MKPolylineRenderer(polyline: polyline)
    renderer.strokeColor = AppTheme.accent.withAlphaComponent(0.8)
    renderer.lineWidth = 4
    renderer.lineCap = .round
    renderer.lineJoin = .round
    return renderer
  }
}
