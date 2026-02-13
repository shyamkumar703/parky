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
    }

    private func handleParking(location: CLLocationCoordinate2D, accuracy: CLLocationAccuracy) {
        Logger.shared.info("Handling parking at \(location.latitude), \(location.longitude) (accuracy: \(accuracy)m)")
        notificationManager.clearAllScheduledNotifications()
        localStorageService.saveParkingLocation(location: .init(location: location, accuracy: accuracy))
        notificationManager.sendLocalNotification(title: "Parked", subtitle: "\(location) with accuracy \(accuracy)")
        apiService.getStreetCleaningTimes(location: location, radius: accuracy) { [weak self] result in
            switch result {
            case .success(let schedules):
                if let nextCleaning = schedules.nextCleaning(near: location) {
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
            wasRecentlyDriving(before: visit.arrivalDate) { [weak self] wasDriving in
                if wasDriving {
                    self?.handleParking(location: visit.coordinate, accuracy: visit.horizontalAccuracy)
                } else {
                    Logger.shared.info("Arrival ignored — user was not driving")
                }
            }
        } else {
            Logger.shared.info("Visit: DEPARTURE from \(visit.coordinate.latitude), \(visit.coordinate.longitude)")
            notificationManager.clearAllScheduledNotifications()
            localStorageService.clearParkingLocation()
        }
    }
}
