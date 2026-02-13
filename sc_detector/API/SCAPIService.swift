//
//  SCAPIService.swift
//  sc_detector
//
//  Created by Shyam Kumar on 2/12/26.
//

import CoreLocation

class SCAPIService {
    private let baseURL = "https://data.sfgov.org/resource/yhqp-riqs.json"
    
    func getStreetCleaningTimes(
        location: CLLocationCoordinate2D,
        radius: CLLocationAccuracy,
        completion: @escaping (Result<[StreetCleaningSchedule], Error>) -> Void
    ) {
        let query = "$where=within_circle(line,\(location.latitude),\(location.longitude),\(radius))"
        guard let url = URL(string: "\(baseURL)?\(query)") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            do {
                let schedules = try JSONDecoder().decode([StreetCleaningSchedule].self, from: data)
                completion(.success(schedules))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
