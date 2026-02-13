//
//  SCSchedule.swift
//  sc_detector
//
//  Created by Shyam Kumar on 2/12/26.
//

import CoreLocation
import Foundation

// MARK: - GeoJSON Line Geometry

struct GeoJSONLine: Codable {
    let type: String
    private let rawCoordinates: [[[Double]]]

    enum CodingKeys: String, CodingKey {
        case type, coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        switch type {
        case "MultiLineString":
            rawCoordinates = try container.decode([[[Double]]].self, forKey: .coordinates)
        case "LineString":
            let coords = try container.decode([[Double]].self, forKey: .coordinates)
            rawCoordinates = [coords]
        default:
            rawCoordinates = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(rawCoordinates, forKey: .coordinates)
    }

    /// All line segments as arrays of CLLocationCoordinate2D (GeoJSON uses [lng, lat] order).
    var lineSegments: [[CLLocationCoordinate2D]] {
        rawCoordinates.map { line in
            line.compactMap { coord in
                guard coord.count >= 2 else { return nil }
                return CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0])
            }
        }
    }

    /// Returns the closest point on this line geometry to the given point, and the distance in meters.
    func closestPoint(to point: CLLocationCoordinate2D) -> (distance: Double, point: CLLocationCoordinate2D) {
        var bestDist = Double.greatestFiniteMagnitude
        var bestPoint = point

        for segment in lineSegments {
            guard segment.count >= 2 else { continue }
            for i in 0..<(segment.count - 1) {
                let (dist, pt) = Self.closestPointOnSegment(point: point, a: segment[i], b: segment[i + 1])
                if dist < bestDist {
                    bestDist = dist
                    bestPoint = pt
                }
            }
        }

        return (bestDist, bestPoint)
    }

    /// Closest point on segment A→B to P, using Cartesian projection with geodesic distance.
    private static func closestPointOnSegment(
        point: CLLocationCoordinate2D,
        a: CLLocationCoordinate2D,
        b: CLLocationCoordinate2D
    ) -> (distance: Double, point: CLLocationCoordinate2D) {
        let dx = b.longitude - a.longitude
        let dy = b.latitude - a.latitude
        let lenSq = dx * dx + dy * dy

        var t: Double = 0
        if lenSq > 0 {
            t = ((point.longitude - a.longitude) * dx + (point.latitude - a.latitude) * dy) / lenSq
            t = max(0, min(1, t))
        }

        let closest = CLLocationCoordinate2D(
            latitude: a.latitude + t * dy,
            longitude: a.longitude + t * dx
        )

        let distance = CLLocation(latitude: point.latitude, longitude: point.longitude)
            .distance(from: CLLocation(latitude: closest.latitude, longitude: closest.longitude))

        return (distance, closest)
    }
}

// MARK: - Street Cleaning Schedule

struct StreetCleaningSchedule: Codable {
    let corridor: String
    let limits: String
    let blockside: String
    let weekday: String
    let fromhour: String
    let tohour: String
    let week1: String
    let week2: String
    let week3: String
    let week4: String
    let week5: String
    let holidays: String
    let line: GeoJSONLine?

    private static let weekdayMap: [String: Int] = [
        "Mon": 2, "Tues": 3, "Wed": 4, "Thu": 5, "Fri": 6, "Sat": 7, "Sun": 1
    ]

    var activeWeeks: [Int] {
        [(1, week1), (2, week2), (3, week3), (4, week4), (5, week5)]
            .filter { $0.1 == "1" }
            .map(\.0)
    }

    /// Returns the next cleaning start date after `date`, or nil if the schedule can't be parsed.
    func nextCleaning(after date: Date = Date()) -> Date? {
        let calendar = Calendar.current
        guard let targetWeekday = Self.weekdayMap[weekday],
              let hour = Int(fromhour) else { return nil }

        // Walk forward day by day (max 35 days covers a full 5-week cycle)
        for dayOffset in 0...35 {
            guard let candidate = calendar.date(byAdding: .day, value: dayOffset, to: date) else { continue }
            let candidateWeekday = calendar.component(.weekday, from: candidate)
            guard candidateWeekday == targetWeekday else { continue }

            // Which occurrence of this weekday in its month? (1st, 2nd, 3rd...)
            let day = calendar.component(.day, from: candidate)
            let weekOfMonth = ((day - 1) / 7) + 1
            guard activeWeeks.contains(weekOfMonth) else { continue }

            // Build the full datetime with the cleaning start hour
            var components = calendar.dateComponents([.year, .month, .day], from: candidate)
            components.hour = hour
            components.minute = 0
            components.second = 0
            guard let cleaningDate = calendar.date(from: components) else { continue }

            // If it's today but the cleaning window already passed, skip
            if cleaningDate > date { return cleaningDate }
        }
        return nil
    }
}

extension Array where Element == StreetCleaningSchedule {
    /// Returns the soonest upcoming cleaning, filtered to the nearest street and matching side
    /// if `parkingLocation` is provided and line geometry is available.
    func nextCleaning(after date: Date = Date(), near parkingLocation: CLLocationCoordinate2D? = nil) -> Date? {
        let filtered = filteredByLocation(parkingLocation)

        for (i, schedule) in self.enumerated() {
            let next = schedule.nextCleaning(after: date)
            let isExcluded = !filtered.contains(where: {
                $0.corridor == schedule.corridor && $0.limits == schedule.limits && $0.blockside == schedule.blockside
            })
            let suffix = isExcluded ? " [filtered out]" : ""
            Logger.shared.info("Schedule \(i+1)/\(count): \(schedule.corridor) (\(schedule.limits)) \(schedule.blockside) — \(schedule.weekday) \(schedule.fromhour):00-\(schedule.tohour):00, weeks \(schedule.activeWeeks) → next: \(next.map { "\($0)" } ?? "none")\(suffix)")
        }

        let selected = filtered.compactMap { $0.nextCleaning(after: date) }.min()
        if let selected {
            Logger.shared.info("Selected earliest cleaning: \(selected)")
        } else {
            Logger.shared.warning("No upcoming cleaning found from \(filtered.count) filtered schedules")
        }
        return selected
    }

    /// Filters schedules to the nearest street and matching side of the centerline.
    private func filteredByLocation(_ parkingLocation: CLLocationCoordinate2D?) -> [StreetCleaningSchedule] {
        guard let parkingLocation else { return self }

        let withDistances: [(schedule: StreetCleaningSchedule, distance: Double, closestPoint: CLLocationCoordinate2D)] = self.compactMap { schedule in
            guard let line = schedule.line else { return nil }
            let (dist, pt) = line.closestPoint(to: parkingLocation)
            return (schedule, dist, pt)
        }

        // If no schedules have line geometry, fall back to all
        guard !withDistances.isEmpty else {
            Logger.shared.warning("No line geometry in schedules, using all \(count)")
            return self
        }

        guard let minDist = withDistances.map(\.distance).min() else { return self }

        // Keep schedules whose centerline is within 20m of the closest (same street, possibly adjacent segments)
        let nearestStreet = withDistances.filter { $0.distance <= minDist + 20 }
        Logger.shared.info("Proximity filter: closest centerline is \(String(format: "%.1f", minDist))m away, \(nearestStreet.count)/\(count) schedules within threshold")

        guard let nearest = nearestStreet.min(by: { $0.distance < $1.distance }) else { return self }

        // If parking point is very close to centerline, can't reliably determine side
        if nearest.distance < 5 {
            Logger.shared.warning("Parking point is \(String(format: "%.1f", nearest.distance))m from centerline — too close to determine side, using all \(nearestStreet.count) nearby schedules")
            return nearestStreet.map(\.schedule)
        }

        // Determine which side of the centerline the parking point is on
        let deltaLat = parkingLocation.latitude - nearest.closestPoint.latitude
        let deltaLon = parkingLocation.longitude - nearest.closestPoint.longitude

        let determinedSide: String
        if abs(deltaLat) > abs(deltaLon) {
            determinedSide = deltaLat > 0 ? "North" : "South"
        } else {
            determinedSide = deltaLon > 0 ? "East" : "West"
        }

        Logger.shared.info("Side determination: parking is \(determinedSide) of centerline (Δlat=\(String(format: "%.6f", deltaLat)), Δlon=\(String(format: "%.6f", deltaLon)))")

        let matchingSide = nearestStreet.filter { $0.schedule.blockside == determinedSide }

        if matchingSide.isEmpty {
            Logger.shared.warning("No schedules match determined side '\(determinedSide)', falling back to all \(nearestStreet.count) nearby")
            return nearestStreet.map(\.schedule)
        }

        Logger.shared.info("Side filter: \(matchingSide.count) schedule(s) match '\(determinedSide)' side")
        return matchingSide.map(\.schedule)
    }
}

