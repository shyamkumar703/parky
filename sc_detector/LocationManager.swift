//
//  LocationManager.swift
//  sc_detector
//
//  Created by Shyam Kumar on 2/8/26.
//

import CoreLocation
import CoreMotion

class LocationManager: NSObject {
    private let locationManager: CLLocationManager
    private let motionActivityManager: CMMotionActivityManager
    private let notificationManager: NotificationManager
    private let apiService: SCAPIService
    private let localStorageService: LocalStorageService

    /// How far back to check for automotive activity before an arrival event.
    private let automotiveLookbackInterval: TimeInterval = 10 * 60 // 10 minutes

    // MARK: - Geofence + Repark Tracking

    private let geofenceIdentifier = "parking_geofence"
    private let geofenceRadius: CLLocationDistance = 50
    /// Must exceed this speed within `drivingConfirmationRadius` of the parking spot to confirm driving.
    private let drivingSpeedThreshold: CLLocationSpeed = 5.0 // m/s (~18 km/h)
    /// Max distance from parking spot where driving speed counts as "driving their own car".
    private let drivingConfirmationRadius: CLLocationDistance = 250
    /// If no driving detected within this window, assume user walked away — cancel tracking.
    private let walkingTimeout: TimeInterval = 3 * 60
    /// Max walking speed for distance-over-time heuristic (brisk walk).
    private let maxWalkingSpeed: Double = 2.0 // m/s
    /// Min elapsed time before distance-over-time heuristic kicks in (avoids stale first update).
    private let distanceHeuristicMinElapsed: TimeInterval = 15
    /// Speed below this for `stoppedConfirmationDuration` = parked (walking ~1.5m/s counts as stopped).
    private let stoppedSpeedThreshold: CLLocationSpeed = 3.0 // m/s
    private let stoppedConfirmationDuration: TimeInterval = 30
    /// Max tracking time after driving confirmed before falling back to CLVisit.
    private let trackingTimeout: TimeInterval = 30 * 60

    private var isTrackingNewParking = false
    private var confirmedDriving = false
    private var stoppedSince: Date?
    private var stoppedLocation: CLLocation?
    private var trackingStartTime: Date?
    private var lastPhase1LogTime: Date?
    /// Saved at tracking start so we can measure distance even after clearing storage.
    private var lastParkingLocation: CLLocationCoordinate2D?

    init(
        notificationManager: NotificationManager,
        apiService: SCAPIService,
        localStorageService: LocalStorageService
    ) {
        self.locationManager = .init()
        self.motionActivityManager = .init()
        self.notificationManager = notificationManager
        self.apiService = apiService
        self.localStorageService = localStorageService
        super.init()
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization() // need to add some stuff to UI if this is rejected
        locationManager.startMonitoringVisits()
        Logger.shared.info("LocationManager initialized, monitoring visits")

        // Restore geofence if we have a saved parking location
        if let saved = localStorageService.getParkingLocation() {
            Logger.shared.info("Restoring geofence for saved parking at \(saved.location.latitude), \(saved.location.longitude)")
            setupGeofence(at: saved.location)
        } else {
            Logger.shared.info("No saved parking location — geofence not set, waiting for CLVisit or manual trigger")
        }
    }

    /// Public entry point for manual reset — user says they moved their car.
    func clearParking() {
        Logger.shared.info("Manual clear: clearing geofence and stopping tracking")
        if isTrackingNewParking {
            stopTrackingNewParking()
        }
        clearGeofence()
    }

    /// Public entry point for manual bootstrap — user tells us where their car is.
    func setInitialParking(location: CLLocationCoordinate2D, accuracy: CLLocationAccuracy) {
        Logger.shared.info("Manual bootstrap: setting parking at \(location.latitude), \(location.longitude) (accuracy: \(accuracy)m)")
        if isTrackingNewParking {
            Logger.shared.info("Manual bootstrap during active tracking — stopping tracker")
            stopTrackingNewParking()
        }
        handleParking(location: location, accuracy: accuracy)
    }

    private func handleParking(location: CLLocationCoordinate2D, accuracy: CLLocationAccuracy) {
        Logger.shared.info("Handling parking at \(location.latitude), \(location.longitude) (accuracy: \(accuracy)m)")
        notificationManager.clearAllScheduledNotifications()
        localStorageService.saveParkingLocation(location: .init(location: location, accuracy: accuracy))
        setupGeofence(at: location)
        // TODO: - remove noti for prod; testing only
        notificationManager.sendLocalNotification(title: "Parked", subtitle: "\(location) with accuracy \(accuracy)")
        apiService.getStreetCleaningTimes(location: location, radius: accuracy) { [weak self] result in
            switch result {
            case .success(let schedules):
                if let nextCleaning = schedules.nextCleaning(near: location, accuracy: accuracy) {
                    Logger.shared.info("Next cleaning: \(nextCleaning), scheduling notification 1hr before")
                    self?.notificationManager.scheduleLocalNotification(
                        title: "Move your car!",
                        subtitle: "Street cleaning starts soon",
                        date: nextCleaning.addingTimeInterval(-60 * 60)
                    )
                } else {
                    Logger.shared.warning("API returned \(schedules.count) schedules but no upcoming cleaning found")
                }
            case .failure(let error):
                Logger.shared.error("API call failed in handleParking: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Geofence Management

    private func setupGeofence(at location: CLLocationCoordinate2D) {
        clearGeofence()
        let region = CLCircularRegion(
            center: location,
            radius: geofenceRadius,
            identifier: geofenceIdentifier
        )
        region.notifyOnExit = true
        region.notifyOnEntry = false
        locationManager.startMonitoring(for: region)
        Logger.shared.info("Geofence set at \(location.latitude), \(location.longitude) (radius: \(geofenceRadius)m)")
    }

    private func clearGeofence() {
        var cleared = false
        for region in locationManager.monitoredRegions where region.identifier == geofenceIdentifier {
            locationManager.stopMonitoring(for: region)
            cleared = true
        }
        if cleared {
            Logger.shared.info("Geofence cleared")
        }
    }

    // MARK: - Repark Tracking

    private func startTrackingNewParking() {
        guard !isTrackingNewParking else {
            Logger.shared.warning("startTrackingNewParking called but already tracking — ignoring")
            return
        }
        // Snapshot the parking location before we potentially clear it later
        lastParkingLocation = localStorageService.getParkingLocation()?.location
        isTrackingNewParking = true
        confirmedDriving = false
        stoppedSince = nil
        stoppedLocation = nil
        lastPhase1LogTime = nil
        trackingStartTime = Date()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.startUpdatingLocation()
        Logger.shared.info("Started tracking for new parking location")
    }

    private func stopTrackingNewParking() {
        isTrackingNewParking = false
        confirmedDriving = false
        stoppedSince = nil
        stoppedLocation = nil
        lastPhase1LogTime = nil
        trackingStartTime = nil
        lastParkingLocation = nil
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        Logger.shared.info("Stopped tracking for new parking location")
    }

    /// Called when we've confirmed the user is driving — clear old parking state.
    private func confirmDriving() {
        confirmedDriving = true
        notificationManager.clearAllScheduledNotifications()
        localStorageService.clearParkingLocation()
        Logger.shared.info("Driving confirmed — cleared old parking state")
    }

    /// Checks recent motion activity to determine if the user was in a vehicle before arriving.
    private func wasRecentlyDriving(before date: Date, completion: @escaping (Bool) -> Void) {
        guard CMMotionActivityManager.isActivityAvailable() else {
            Logger.shared.warning("Motion activity unavailable, assuming driving")
            completion(true)
            return
        }
        let start = date.addingTimeInterval(-automotiveLookbackInterval)
        motionActivityManager.queryActivityStarting(from: start, to: date, to: .main) { activities, error in
            if let error {
                Logger.shared.error("Motion query failed: \(error.localizedDescription)")
            }
            let wasDriving = activities?.contains(where: { $0.automotive }) ?? false
            Logger.shared.info("Motion check: wasDriving=\(wasDriving) (\(activities?.count ?? 0) activities)")
            completion(wasDriving)
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let now = Date()
        if visit.departureDate > now {
            Logger.shared.info("Visit: ARRIVAL at \(visit.coordinate.latitude), \(visit.coordinate.longitude) (accuracy: \(visit.horizontalAccuracy)m)")
            if isTrackingNewParking {
                Logger.shared.info("CLVisit arrival during active tracking — ignoring, geofence tracking is more accurate")
                return
            }
            handleParking(location: visit.coordinate, accuracy: visit.horizontalAccuracy)
        } else {
            Logger.shared.info("Visit: DEPARTURE from \(visit.coordinate.latitude), \(visit.coordinate.longitude)")
            let hasActiveGeofence = locationManager.monitoredRegions.contains { $0.identifier == geofenceIdentifier }
            if isTrackingNewParking || hasActiveGeofence {
                Logger.shared.info("CLVisit departure ignored — \(isTrackingNewParking ? "active tracking" : "geofence active"), geofence handles departures")
                return
            }
            clearGeofence()
            notificationManager.clearAllScheduledNotifications()
            localStorageService.clearParkingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == geofenceIdentifier else { return }
        Logger.shared.info("Geofence exit — user left parking area")
        clearGeofence()
        startTrackingNewParking()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isTrackingNewParking, let location = locations.last else { return }
        guard let trackingStart = trackingStartTime else { return }

        let elapsed = Date().timeIntervalSince(trackingStart)

        // Phase 1: waiting for driving confirmation
        if !confirmedDriving {
            // Walking timeout — no driving detected, assume they walked away
            if elapsed > walkingTimeout {
                Logger.shared.info("Walking timeout (\(Int(walkingTimeout/60))min) — user walked away, preserving parking")
                stopTrackingNewParking()
                return
            }

            let speed = location.speed
            let distFromParking: CLLocationDistance? = lastParkingLocation.map {
                CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                    .distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
            }

            // Periodic status log every 10s so we can debug Phase 1
            let staleness = Date().timeIntervalSince(location.timestamp)
            if lastPhase1LogTime == nil || Date().timeIntervalSince(lastPhase1LogTime!) >= 10 {
                lastPhase1LogTime = Date()
                Logger.shared.info("Phase 1: speed=\(String(format: "%.1f", speed))m/s, dist=\(distFromParking.map { String(format: "%.0f", $0) } ?? "?")m, elapsed=\(Int(elapsed))s, stale=\(String(format: "%.1f", staleness))s, acc=\(String(format: "%.1f", location.horizontalAccuracy))m")
            }

            // Check for driving speed near the parking spot
            if speed > drivingSpeedThreshold, let distFromParking {
                if distFromParking <= drivingConfirmationRadius {
                    Logger.shared.info("Driving detected (speed): speed=\(String(format: "%.1f", speed))m/s, \(String(format: "%.0f", distFromParking))m from parking")
                    confirmDriving()
                } else {
                    Logger.shared.info("High speed (\(String(format: "%.1f", speed))m/s) but \(String(format: "%.0f", distFromParking))m from parking — ignoring (possible transit)")
                }
            }

            // Distance-over-time heuristic (catches cold-GPS scenarios where speed is stale)
            if elapsed > distanceHeuristicMinElapsed, let distFromParking {
                let maxWalkable = geofenceRadius + elapsed * maxWalkingSpeed
                if distFromParking > maxWalkable {
                    Logger.shared.info("Driving detected (distance): \(String(format: "%.0f", distFromParking))m from parking, max walkable=\(String(format: "%.0f", maxWalkable))m at \(Int(elapsed))s")
                    confirmDriving()
                }
            }
            return
        }

        // Phase 2: driving confirmed, waiting for user to stop
        if elapsed > trackingTimeout {
            Logger.shared.warning("Tracking timeout (\(Int(trackingTimeout/60))min) — falling back to CLVisit")
            stopTrackingNewParking()
            return
        }

        let speed = location.speed
        // Ignore invalid speed readings (< 0 means undetermined)
        guard speed >= 0 else { return }

        if speed < stoppedSpeedThreshold {
            if stoppedSince == nil {
                stoppedSince = Date()
                stoppedLocation = location
                Logger.shared.info("Phase 2: speed dropped to \(String(format: "%.1f", speed))m/s at \(location.coordinate.latitude), \(location.coordinate.longitude) — watching for \(Int(stoppedConfirmationDuration))s stop...")
            }
            if let stoppedSince, let stoppedLocation {
                let stoppedFor = Date().timeIntervalSince(stoppedSince)
                if stoppedFor >= stoppedConfirmationDuration {
                    Logger.shared.info("Phase 2: confirmed stop after \(Int(stoppedFor))s — using saved location \(stoppedLocation.coordinate.latitude), \(stoppedLocation.coordinate.longitude) (accuracy: \(String(format: "%.1f", stoppedLocation.horizontalAccuracy))m), current location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                    stopTrackingNewParking()
                    handleParking(location: stoppedLocation.coordinate, accuracy: stoppedLocation.horizontalAccuracy)
                }
            }
        } else {
            if stoppedSince != nil {
                Logger.shared.info("Phase 2: speed back up to \(String(format: "%.1f", speed))m/s — stop timer reset")
            }
            stoppedSince = nil
            stoppedLocation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Logger.shared.error("Location error: \(error.localizedDescription)")
    }
}
