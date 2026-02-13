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
//        @Published private(set) var streetCleaningDate: Date? = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
    @Published private(set) var streetCleaningDate: Date?
    @Published private(set) var isLoadingCleaningDate = false
    @Published private(set) var userLocation: CLLocationCoordinate2D?

    private let userLocationManager = CLLocationManager()

    override init() {
        self.locationManager = Dependencies.locationManager
        self.notificationManager = Dependencies.notificationManager
        self.apiService = Dependencies.apiService
        self.localStorageService = Dependencies.localStorageService
        super.init()
        userLocationManager.delegate = self
    }

    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        userLocation = locations.last?.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Logger.shared.error("User location error: \(error.localizedDescription)")
    }

    func onAppear() {
        self.currentParkingLocationWA = localStorageService.getParkingLocation()
        if let loc = currentParkingLocationWA {
            Logger.shared.info("App opened: restored parking at \(loc.location.latitude), \(loc.location.longitude)")
        } else {
            Logger.shared.info("App opened: no saved parking location")
        }
        // 37.7749, -122.4194
        // 37.779129, -122.446135
//        let loc = CLLocationCoordinate2DMake(37.779465, -122.446212)
//        self.currentParkingLocationWA = .init(location: loc, accuracy: 1)
        calculateStreetCleaningDate()
        userLocationManager.requestLocation()
    }
    
    private func calculateStreetCleaningDate() {
        guard let currentParkingLocationWA else { return }
        isLoadingCleaningDate = true
        apiService.getStreetCleaningTimes(location: currentParkingLocationWA.location, radius: currentParkingLocationWA.accuracy) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isLoadingCleaningDate = false
                switch result {
                case .success(let streetCleaningTimes):
                    self.streetCleaningDate = streetCleaningTimes.nextCleaning(near: currentParkingLocationWA.location, accuracy: currentParkingLocationWA.accuracy)
                    if let date = self.streetCleaningDate {
                        Logger.shared.info("Next cleaning date resolved: \(date)")
                    } else {
                        Logger.shared.warning("No upcoming cleaning date found from \(streetCleaningTimes.count) schedules")
                    }
                case .failure(let error):
                    Logger.shared.error("Failed to fetch cleaning times: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func onIMovedMyCarTapped() {
        Logger.shared.info("User tapped 'I moved my car'")
        withAnimation {
            self.currentParkingLocationWA = nil
        }
        localStorageService.clearParkingLocation()
        notificationManager.clearAllScheduledNotifications()
    }

    // MARK: - CLLocationManagerDelegate (DEBUG)
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        guard let location = locations.first else { return }
//        // Offset by ~200m
//        let parked = CLLocationCoordinate2D(
//            latitude: location.coordinate.latitude + 0.002,
//            longitude: location.coordinate.longitude + 0.001
//        )
//        self.currentParkingLocationWA = .init(location: parked, accuracy: 0)
//    }
//
//    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

struct GlassModifier<S: Shape>: ViewModifier {
    let tint: Color?
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                content.glassEffect(.regular.tint(tint), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        } else {
            if let tint {
                content
                    .background(tint.opacity(0.3), in: shape)
                    .background(.ultraThinMaterial, in: shape)
            } else {
                content
                    .background(.ultraThinMaterial, in: shape)
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = AppViewModel()
    @State private var isTimerPressed = false
    @State private var isButtonPressed = false
    @State private var showDebugLogs = false
    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    private func updateMapPosition() {
        guard let parked = vm.currentParkingLocationWA?.location,
              let user = vm.userLocation else {
            if vm.currentParkingLocationWA == nil {
                mapPosition = .userLocation(fallback: .automatic)
            }
            return
        }
        let midLat = (parked.latitude + user.latitude) / 2
        let midLon = (parked.longitude + user.longitude) / 2
        let latDelta = abs(parked.latitude - user.latitude) * 1.5
        let lonDelta = abs(parked.longitude - user.longitude) * 1.5
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: midLat, longitude: midLon),
            span: MKCoordinateSpan(latitudeDelta: max(latDelta, 0.005), longitudeDelta: max(lonDelta, 0.005))
        )
        withAnimation {
            mapPosition = .region(region)
        }
    }

    private func pillText(now: Date) -> String {
        guard vm.currentParkingLocationWA != nil else {
            return "No ticket risk"
        }
        if vm.isLoadingCleaningDate {
            return "Loading..."
        }
        guard let cleaningDate = vm.streetCleaningDate else {
            return "No ticket risk"
        }
        let interval = cleaningDate.timeIntervalSince(now)
        guard interval > 0 else { return "TICKET RISK" }
        let total = Int(interval)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if days > 0 {
            return "Street cleaning in \(days)d \(hours)hr \(minutes)m"
        } else if hours > 0 {
            return "Street cleaning in \(hours)hr \(minutes)m"
        } else {
            return "Street cleaning in \(minutes)m \(seconds)s"
        }
    }

    private func pillTint(now: Date) -> Color? {
        guard vm.currentParkingLocationWA != nil,
              let cleaningDate = vm.streetCleaningDate else {
            return .green
        }
        let hoursUntil = cleaningDate.timeIntervalSince(now) / 3600
        if hoursUntil <= 0 {
            return .red
        } else if hoursUntil <= 2 {
            return .red
        } else if hoursUntil <= 12 {
            return .red.opacity(0.7)
        } else {
            return nil
        }
    }

    var body: some View {
        ZStack {
            Map(position: $mapPosition) {
                UserAnnotation()
                if let parked = vm.currentParkingLocationWA?.location {
                    Marker("Parked", systemImage: "car.fill", coordinate: parked)
                        .tint(.red)
                }
            }
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button {
                        showDebugLogs = true
                    } label: {
                        Image(systemName: "ladybug.fill")
                            .font(.body)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .modifier(GlassModifier(tint: nil, shape: .circle))
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let text = pillText(now: context.date)
                    let tint = pillTint(now: context.date)
                    Text(text)
                        .font(.system(size: 14))
                        .fontDesign(.monospaced)
                        .contentTransition(.numericText())
                        .animation(.default, value: text)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .modifier(GlassModifier(tint: tint, shape: .capsule))
                }
                    .scaleEffect(isTimerPressed ? 0.93 : 1.0)
                    .animation(.spring(duration: 0.2), value: isTimerPressed)
                    .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.4), trigger: isTimerPressed)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in isTimerPressed = true }
                            .onEnded { _ in isTimerPressed = false }
                    )
                if vm.currentParkingLocationWA != nil {
                    Button {
                        vm.onIMovedMyCarTapped()
                    } label: {
                        Text("I moved my car")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .modifier(GlassModifier(tint: .blue, shape: .capsule))
                    .scaleEffect(isButtonPressed ? 0.93 : 1.0)
                    .animation(.spring(duration: 0.2), value: isButtonPressed)
                    .sensoryFeedback(.impact(weight: .medium), trigger: isButtonPressed)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in isButtonPressed = true }
                            .onEnded { _ in isButtonPressed = false }
                    )
                }
            }
            .padding()
        }
        .onAppear {
            vm.onAppear()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            vm.onAppear()
        }
        .sheet(isPresented: $showDebugLogs) {
            DebugLogView()
        }
        .onChange(of: vm.currentParkingLocationWA?.location.latitude) {
            updateMapPosition()
        }
        .onChange(of: vm.userLocation?.latitude) {
            updateMapPosition()
        }
    }
}

#Preview {
    ContentView()
}
