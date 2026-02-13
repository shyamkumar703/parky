//
//  ContentView.swift
//  sc_detector
//
//  Created by Shyam Kumar on 2/8/26.
//

import Combine
import CoreLocation
import MapKit
import SwiftUI

class AppViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager: LocationManager
    private let notificationManager: NotificationManager
    private let apiService: SCAPIService
    private let localStorageService: LocalStorageService
    @Published private(set) var currentParkingLocationWA: CLLocationWithAccuracy?
    // uncomment below for sim
    //    @Published private(set) var streetCleaningDate: Date? = Calendar.current.date(byAdding: .hour, value: -1, to: Date())
    @Published private(set) var streetCleaningDate: Date?


    // DEBUG
    private let debugLocationManager = CLLocationManager()

    override init() {
        self.locationManager = Dependencies.locationManager
        self.notificationManager = Dependencies.notificationManager
        self.apiService = Dependencies.apiService
        self.localStorageService = Dependencies.localStorageService
        super.init()
        debugLocationManager.delegate = self
    }

    func onAppear() {
        self.currentParkingLocationWA = localStorageService.getParkingLocation()
        // DEBUG: request location to simulate a nearby parked car
        debugLocationManager.requestLocation()
    }
    
    private func calculateStreetCleaningDate() {
        guard let currentParkingLocationWA else { return }
        apiService.getStreetCleaningTimes(location: currentParkingLocationWA.location, radius: currentParkingLocationWA.accuracy) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let streetCleaningTimes):
                self.streetCleaningDate = streetCleaningTimes.nextCleaning()
            case .failure(let error):
                print(error)
            }
        }
    }

    // MARK: - CLLocationManagerDelegate (DEBUG)
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        // Offset by ~200m
        let parked = CLLocationCoordinate2D(
            latitude: location.coordinate.latitude + 0.002,
            longitude: location.coordinate.longitude + 0.001
        )
        self.currentParkingLocationWA = .init(location: parked, accuracy: 0)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

struct ContentView: View {
    @StateObject private var vm = AppViewModel()
    @State private var isTimerPressed = false
    @State private var isButtonPressed = false

    private var mapPosition: MapCameraPosition {
        if let parked = vm.currentParkingLocationWA?.location {
            .camera(.init(centerCoordinate: parked, distance: 1000))
        } else {
            .userLocation(fallback: .automatic)
        }
    }
    
    private var pillText: String {
        guard vm.currentParkingLocationWA != nil,
              let cleaningDate = vm.streetCleaningDate else {
            return "No ticket risk"
        }
        let interval = cleaningDate.timeIntervalSince(Date())
        guard interval > 0 else { return "TICKET RISK" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let days = hours / 24
        let remainingHours = hours % 24
        if days > 0 {
            return "Street cleaning in \(days)d \(remainingHours)hr \(minutes)min"
        } else {
            return "Street cleaning in \(remainingHours)hr \(minutes)min"
        }
    }

    private var pillTint: Color? {
        guard vm.currentParkingLocationWA != nil,
              let cleaningDate = vm.streetCleaningDate else {
            return .green
        }
        let hoursUntil = cleaningDate.timeIntervalSince(Date()) / 3600
        if hoursUntil <= 0 {
            return .red
        } else if hoursUntil <= 2 {
            return .red
        } else if hoursUntil <= 12 {
            return .yellow
        } else {
            return nil
        }
    }

    var body: some View {
        ZStack {
            Map(initialPosition: mapPosition) {
                UserAnnotation()
                if let parked = vm.currentParkingLocationWA?.location {
                    Marker("Parked", systemImage: "car.fill", coordinate: parked)
                        .tint(.red)
                }
            }
            VStack(spacing: 16) {
                Spacer()
                Text(pillText)
                    .font(.system(size: 14))
                    .fontDesign(.monospaced)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .glassEffect(pillTint.map { .regular.tint($0) } ?? .regular, in: .capsule)
                    .scaleEffect(isTimerPressed ? 0.93 : 1.0)
                    .animation(.spring(duration: 0.2), value: isTimerPressed)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in isTimerPressed = true }
                            .onEnded { _ in isTimerPressed = false }
                    )
                Button {

                } label: {
                    Text("I moved my car")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(.blue), in: .capsule)
                .scaleEffect(isButtonPressed ? 0.93 : 1.0)
                .animation(.spring(duration: 0.2), value: isButtonPressed)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isButtonPressed = true }
                        .onEnded { _ in isButtonPressed = false }
                )
            }
            .padding()
        }
        .onAppear {
            vm.onAppear()
        }
    }
}

#Preview {
    ContentView()
}
