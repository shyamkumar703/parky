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
    @Published private(set) var currentParkingLocation: CLLocationCoordinate2D?
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
        self.currentParkingLocation = localStorageService.getParkingLocation()
        self.streetCleaningDate = locationManager.
        // DEBUG: request location to simulate a nearby parked car
        debugLocationManager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate (DEBUG)
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        // Offset by ~200m
        let parked = CLLocationCoordinate2D(
            latitude: location.coordinate.latitude + 0.002,
            longitude: location.coordinate.longitude + 0.001
        )
        localStorageService.saveParkingLocation(location: parked)
        self.currentParkingLocation = parked
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

struct ContentView: View {
    @StateObject private var vm = AppViewModel()
    @State private var isTimerPressed = false
    @State private var isButtonPressed = false

    private var mapPosition: MapCameraPosition {
        if let parked = vm.currentParkingLocation {
            .camera(.init(centerCoordinate: parked, distance: 1000))
        } else {
            .userLocation(fallback: .automatic)
        }
    }

    var body: some View {
        ZStack {
            Map(initialPosition: mapPosition) {
                UserAnnotation()
                if let parked = vm.currentParkingLocation {
                    Marker("Parked", systemImage: "car.fill", coordinate: parked)
                        .tint(.red)
                }
            }
            VStack(spacing: 16) {
                Spacer()
                Text("Street cleaning in 0d 5hrs 25mins")
                    .font(.system(size: 14))
                    .fontDesign(.monospaced)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .glassEffect(.regular.tint(.red), in: .capsule)
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
