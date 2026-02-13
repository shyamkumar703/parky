//
//  Logger.swift
//  sc_detector
//
//  Created by Shyam Kumar on 2/12/26.
//

import Foundation

enum LogLevel: String {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

struct LogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: String
    let message: String

    init(level: LogLevel, message: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level.rawValue
        self.message = message
    }

    var formatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm:ss"
        return "[\(formatter.string(from: timestamp))] [\(level)] \(message)"
    }
}

class Logger {
    static let shared = Logger()
    private let key = "debug_logs"
    private let maxLogs = 500

    private(set) var logs: [LogEntry] = []

    init() {
        load()
    }

    func info(_ message: String) {
        append(LogEntry(level: .info, message: message))
    }

    func warning(_ message: String) {
        append(LogEntry(level: .warning, message: message))
    }

    func error(_ message: String) {
        append(LogEntry(level: .error, message: message))
    }

    func clear() {
        logs = []
        save()
    }

    func exportText() -> String {
        logs.map(\.formatted).joined(separator: "\n")
    }

    private func append(_ entry: LogEntry) {
        logs.append(entry)
        if logs.count > maxLogs {
            logs.removeFirst(logs.count - maxLogs)
        }
        save()
        #if DEBUG
        print(entry.formatted)
        #endif
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(logs) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([LogEntry].self, from: data) else { return }
        logs = saved
    }
}
