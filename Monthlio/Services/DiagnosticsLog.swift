import Foundation
import MetricKit
import os

private let log = Logger(subsystem: "com.monthlio.app", category: "diagnostics")

/// Crash and hang reports from MetricKit, kept on the device so they can be
/// shared from Settings when something went wrong. Nothing leaves the device
/// by itself: Apple's own crash reporting is opt-in and lands in Xcode's
/// Organizer; this is the user's copy for a support conversation, and it is
/// capped so it never grows unbounded.
@MainActor
final class DiagnosticsLog: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticsLog()
    static let maxReports = 20

    let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "Diagnostics")) {
        self.directory = directory
        super.init()
    }

    /// Starts receiving payloads; iOS delivers them about once a day, and
    /// crash reports on the next launch after the crash.
    func start() {
        MXMetricManager.shared.add(self)
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let blobs = payloads.map { ($0.timeStampEnd, $0.jsonRepresentation()) }
        Task { @MainActor in
            for (date, data) in blobs { self.store(data, at: date) }
        }
    }

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        // Daily performance metrics are not kept; only diagnostics matter here.
    }

    /// One file per payload, newest kept, oldest pruned beyond the cap.
    func store(_ data: Data, at date: Date = .now) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stamp = date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().time(includingFractionalSeconds: true).dateSeparator(.dash).timeSeparator(.omitted))
            let url = directory.appending(path: "diagnostic-\(stamp).json")
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            let extra = reports().dropFirst(Self.maxReports)
            for old in extra { try? FileManager.default.removeItem(at: old) }
        } catch {
            log.error("Couldn't keep a diagnostic report: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The kept reports, newest first.
    func reports() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func clear() {
        for url in reports() { try? FileManager.default.removeItem(at: url) }
    }
}
