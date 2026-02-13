//
//  Dependencies.swift
//  sc_detector
//
//  Created by Shyam Kumar on 2/8/26.
//

class Dependencies {
    static let notificationManager = NotificationManager()
    static let apiService = SCAPIService()
    static let localStorageService = LocalStorageService()
    static let locationManager = LocationManager(
        notificationManager: notificationManager,
        apiService: apiService,
        localStorageService: localStorageService
    )
}
