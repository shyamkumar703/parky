//
//  LocalStorageService.swift
//  sc_detector
//
//  Created by Shyam Kumar on 2/12/26.
//

import CoreLocation

fileprivate struct CLLocationWithAccuracyRaw: Codable {
    let lat: Double
    let long: Double
    let accuracy: CLLocationAccuracy
    
    init(_ locationWA: CLLocationWithAccuracy) {
        self.lat = locationWA.location.latitude
        self.long = locationWA.location.longitude
        self.accuracy = locationWA.accuracy
    }
}

struct CLLocationWithAccuracy {
    let location: CLLocationCoordinate2D
    let accuracy: CLLocationAccuracy
}

class LocalStorageService {
    init() { }
    
    func saveParkingLocation(location: CLLocationWithAccuracy) {
        UserDefaults.standard.set(location.toRaw().toDictionary(), forKey: Key.parkedLocation.rawValue)
    }
    
    func getParkingLocation() -> CLLocationWithAccuracy? {
        guard let dict = UserDefaults.standard.object(forKey: Key.parkedLocation.rawValue) as? [String: Any] else {
           return nil
        }
        guard let raw = CLLocationWithAccuracyRaw.fromDictionary(dict) else {
            return nil
        }
        return .init(raw)
    }
    
    func clearParkingLocation() {
        UserDefaults.standard.removeObject(forKey: Key.parkedLocation.rawValue)
    }
}

extension LocalStorageService {
    enum Key: String {
        case parkedLocation
    }
}

fileprivate extension CLLocationWithAccuracy {
    init(_ raw: CLLocationWithAccuracyRaw) {
        self.init(location: .init(latitude: raw.lat, longitude: raw.long), accuracy: raw.accuracy)
    }
    
    func toRaw() -> CLLocationWithAccuracyRaw {
        return .init(self)
    }
}

extension Encodable {
    func toDictionary() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }
}

extension Decodable {
    static func fromDictionary(_ dict: [String: Any]) -> Self? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let value = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }
        return value
    }
}
