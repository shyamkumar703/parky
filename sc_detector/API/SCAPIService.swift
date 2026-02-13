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
        let searchRadius = max(radius, 100) // street centerlines can be 10-30m from parked position
        let query = "$where=within_circle(line,\(location.latitude),\(location.longitude),\(searchRadius))"
        guard let url = URL(string: "\(baseURL)?\(query)") else {
            Logger.shared.error("API: failed to construct URL")
            completion(.failure(URLError(.badURL)))
            return
        }

        Logger.shared.info("API: querying radius=\(searchRadius)m at \(location.latitude), \(location.longitude)")
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error {
                Logger.shared.error("API: network error — \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            guard let data else {
                Logger.shared.error("API: no data in response")
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            do {
                let schedules = try JSONDecoder().decode([StreetCleaningSchedule].self, from: data)
                Logger.shared.info("API: returned \(schedules.count) schedules")
                completion(.success(schedules))
            } catch {
                Logger.shared.error("API: decode error — \(error.localizedDescription)")
                completion(.failure(error))
            }
        }.resume()
    }
}
