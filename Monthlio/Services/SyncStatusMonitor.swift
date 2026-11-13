import CloudKit
import CoreData
import Foundation
import Observation

/// What iCloud sync has been doing, for the Sync section of Settings.
///
/// SwiftData runs on `NSPersistentCloudKitContainer`, which posts
/// `eventChangedNotification` when a setup, import or export starts and
/// again when it ends. Until now the app only ever showed "quit and reopen
/// to start syncing", whatever CloudKit was actually doing, so a sync that
/// failed every time (a missing schema, a full iCloud, a signed-out
/// account) looked the same as one that worked. The last success and the
/// last failure are kept in the preference store so Settings can show
/// them right after launch.
@MainActor
@Observable
final class SyncStatusMonitor {
    enum Kind: Equatable {
        case setup
        case importing
        case exporting
    }

    enum Phase: Equatable {
        case idle
        case running(Kind)
    }

    static let shared = SyncStatusMonitor()

    nonisolated static let lastSyncedKey = "sync.lastSynced"
    nonisolated static let lastErrorKey = "sync.lastError"
    nonisolated static let lastErrorAtKey = "sync.lastErrorAt"

    private(set) var phase: Phase = .idle
    /// When the last import or export finished successfully.
    private(set) var lastSynced: Date?
    /// The most recent failure, cleared by the next successful import or
    /// export.
    private(set) var lastError: String?
    private(set) var lastErrorAt: Date?

    /// True while CloudKit is bringing rows in. A month total recorded
    /// mid-import would freeze a partial figure into history.
    var isImporting: Bool { phase == .running(.importing) }

    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = SyncPreference.standard) {
        self.defaults = defaults
        lastSynced = defaults.object(forKey: Self.lastSyncedKey) as? Date
        lastError = defaults.string(forKey: Self.lastErrorKey)
        lastErrorAt = defaults.object(forKey: Self.lastErrorAtKey) as? Date
    }

    /// Starts listening for CloudKit events. Safe to call more than once.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            let kind: Kind
            switch event.type {
            case .setup: kind = .setup
            case .import: kind = .importing
            case .export: kind = .exporting
            @unknown default: return
            }
            // Delivered on the main queue; the monitor lives on the main actor.
            MainActor.assumeIsolated {
                SyncStatusMonitor.shared.record(kind: kind, succeeded: event.succeeded, error: event.error, endDate: event.endDate)
            }
        }
    }

    /// One CloudKit event, started (`endDate` nil) or finished. Pure
    /// state, so tests drive it without an iCloud account.
    func record(kind: Kind, succeeded: Bool, error: Error?, endDate: Date?, now: Date = .now) {
        guard let endDate else {
            phase = .running(kind)
            return
        }
        phase = .idle
        if succeeded {
            guard kind != .setup else { return }
            lastSynced = endDate
            defaults.set(endDate, forKey: Self.lastSyncedKey)
            if lastError != nil {
                lastError = nil
                lastErrorAt = nil
                defaults.removeObject(forKey: Self.lastErrorKey)
                defaults.removeObject(forKey: Self.lastErrorAtKey)
            }
        } else if let error {
            lastError = Self.describe(error)
            lastErrorAt = endDate
            defaults.set(lastError, forKey: Self.lastErrorKey)
            defaults.set(endDate, forKey: Self.lastErrorAtKey)
        }
        _ = now
    }

    /// A sentence for the Sync footer, or nil when there is nothing to
    /// report yet.
    func summary(now: Date = .now) -> String? {
        if let lastError {
            let when = lastErrorAt.map { Self.relative($0, now: now) } ?? String(localized: "just now")
            return String(localized: "iCloud sync failed \(when): \(lastError)")
        }
        if case .running(.setup) = phase {
            return String(localized: "Setting up iCloud sync…")
        }
        if let lastSynced {
            return String(localized: "Last synced \(Self.relative(lastSynced, now: now)).")
        }
        return nil
    }

    /// Plain words for the CloudKit errors a user can act on; everything
    /// else keeps the system description.
    nonisolated static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == CKError.errorDomain, let code = CKError.Code(rawValue: nsError.code) {
            switch code {
            case .notAuthenticated:
                return String(localized: "sign in to iCloud in the Settings app.")
            case .quotaExceeded:
                return String(localized: "your iCloud storage is full.")
            case .networkUnavailable, .networkFailure:
                return String(localized: "no network connection.")
            case .partialFailure:
                return String(localized: "some records couldn't be saved to iCloud. If this keeps happening after an update, the iCloud database may not be ready for this version yet.")
            case .accountTemporarilyUnavailable:
                return String(localized: "your iCloud account is temporarily unavailable.")
            default:
                break
            }
        }
        return nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func relative(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return String(localized: "just now") }
        return date.formatted(.relative(presentation: .named))
    }
}
