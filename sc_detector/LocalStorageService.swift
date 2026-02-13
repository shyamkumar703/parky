//
//  LocalStorageService.swift
//  sc_detector
//
//  Created by Shyam Kumar on 2/12/26.
//

import CoreLocation

fileprivate struct CLLocation2DRaw: Codable {
    let lat: Double
    let long: Double
    
    init(_ location: CLLocationCoordinate2D) {
        self.lat = location.latitude
        self.long = location.longitude
    }
}

class LocalStorageService {
    init() { }
    
    func saveParkingLocation(location: CLLocationCoordinate2D) {
        UserDefaults.standard.set(location.toRaw().toDictionary(), forKey: Key.parkedLocation.rawValue)
    }
    
    func getParkingLocation() -> CLLocationCoordinate2D? {
        guard let dict = UserDefaults.standard.object(forKey: Key.parkedLocation.rawValue) as? [String: Any] else {
           return nil
        }
        guard let raw = CLLocation2DRaw.fromDictionary(dict) else {
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

fileprivate extension CLLocationCoordinate2D {
    init(_ raw: CLLocation2DRaw) {
        self.init(latitude: raw.lat, longitude: raw.long)
    }
    
    func toRaw() -> CLLocation2DRaw {
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
