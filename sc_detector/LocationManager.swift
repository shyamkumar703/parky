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
    }

    private func handleParking(location: CLLocationCoordinate2D, accuracy: CLLocationAccuracy) {
        notificationManager.clearAllScheduledNotifications()
        localStorageService.saveParkingLocation(location: .init(location: location, accuracy: accuracy))
        notificationManager.sendLocalNotification(title: "Parked", subtitle: "\(location) with accuracy \(accuracy)")
        apiService.getStreetCleaningTimes(location: location, radius: accuracy) { [weak self] result in
            guard let schedules = try? result.get(),
                  let nextCleaning = schedules.nextCleaning() else { return }
            self?.notificationManager.scheduleLocalNotification(
                title: "Move your car!",
                subtitle: "Street cleaning starts soon",
                date: nextCleaning.addingTimeInterval(-60 * 60) // 1 hour before
            )
        }
    }

    /// Checks recent motion activity to determine if the user was in a vehicle before arriving.
    private func wasRecentlyDriving(before date: Date, completion: @escaping (Bool) -> Void) {
        guard CMMotionActivityManager.isActivityAvailable() else {
            // Can't determine motion — assume driving to be safe
            completion(true)
            return
        }
        let start = date.addingTimeInterval(-automotiveLookbackInterval)
        motionActivityManager.queryActivityStarting(from: start, to: date, to: .main) { activities, _ in
            let wasDriving = activities?.contains(where: { $0.automotive }) ?? false
            completion(wasDriving)
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let now = Date()
        if visit.departureDate > now {
            // User arrived — only treat as parking if they were recently driving
            wasRecentlyDriving(before: visit.arrivalDate) { [weak self] wasDriving in
                guard wasDriving else { return }
                self?.handleParking(location: visit.coordinate, accuracy: visit.horizontalAccuracy)
            }
        } else {
            // User departed — clear any scheduled notifications
            notificationManager.clearAllScheduledNotifications()
            localStorageService.clearParkingLocation()
        }
    }
}
