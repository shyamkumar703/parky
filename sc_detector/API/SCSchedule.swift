//
//  SCSchedule.swift
//  sc_detector
//
//  Created by Shyam Kumar on 2/12/26.
//

import Foundation

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
    /// Returns the soonest upcoming cleaning across all schedules.
    func nextCleaning(after date: Date = Date()) -> Date? {
        // TODO: - is there a way to make this more accurate?
        // soonest probably isn't the best idea - I wonder if there's a better way to do this without user input?
        self.compactMap { $0.nextCleaning(after: date) }.min()
    }
}

