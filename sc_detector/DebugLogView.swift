//
//  DebugLogView.swift
//  sc_detector
//
//  Created by Shyam Kumar on 2/12/26.
//

import SwiftUI

struct DebugLogView: View {
    @State private var logs: [LogEntry] = Logger.shared.logs
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            List(logs.reversed()) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.level)
                            .font(.caption.weight(.bold))
                            .fontDesign(.monospaced)
                            .foregroundStyle(colorForLevel(entry.level))
                        Spacer()
                        Text(entry.timestamp, format: .dateTime.month().day().hour().minute().second())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.message)
                        .font(.caption)
                        .fontDesign(.monospaced)
                }
            }
            .navigationTitle("Debug Logs")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        Logger.shared.clear()
                        logs = []
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: Logger.shared.exportText()) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .onAppear {
                logs = Logger.shared.logs
            }
        }
    }

    private func colorForLevel(_ level: String) -> Color {
        switch level {
        case "ERROR": return .red
        case "WARN": return .yellow
        default: return .green
        }
    }
}

#Preview {
    DebugLogView()
}
