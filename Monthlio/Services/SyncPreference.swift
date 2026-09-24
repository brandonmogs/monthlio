import Foundation

/// Local, never-synced decisions about iCloud sync. Read at launch, before
/// the store opens, because the container's CloudKit option can't change
/// while the app runs.
///
/// Installs from before Monthlio Pro keep sync for free: the first launch of
/// this version finds an existing store and marks the device grandfathered.
enum SyncPreference {
    /// Where the flags live. DEBUG builds swap in a throwaway suite for
    /// `-MonthlioFreshInstall` so UI tests see a brand-new install.
    static var standard: UserDefaults = .standard

    static let enabledKey = "sync.enabled"
    static let grandfatheredKey = "sync.grandfathered"
    static let migrationKey = "sync.migrationVersion"
    static let currentMigration = 1

    static func isEnabled(_ defaults: UserDefaults = standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    static func setEnabled(_ enabled: Bool, _ defaults: UserDefaults = standard) {
        defaults.set(enabled, forKey: enabledKey)
    }

    static func isGrandfathered(_ defaults: UserDefaults = standard) -> Bool {
        defaults.bool(forKey: grandfatheredKey)
    }

    /// Pro owners and early installs may sync.
    static func canSync(isPro: Bool, _ defaults: UserDefaults = standard) -> Bool {
        isPro || isGrandfathered(defaults)
    }

    /// Runs once per install. `storeExists` is whether a SwiftData store was
    /// already on disk, which is how an upgrade from a pre-Pro version looks.
    static func migrateIfNeeded(storeExists: Bool, _ defaults: UserDefaults = standard) {
        guard defaults.integer(forKey: migrationKey) < currentMigration else { return }
        if storeExists {
            defaults.set(true, forKey: grandfatheredKey)
            defaults.set(true, forKey: enabledKey)
        } else {
            defaults.set(false, forKey: enabledKey)
        }
        defaults.set(currentMigration, forKey: migrationKey)
    }

    /// Turns sync off when the entitlement that allowed it is gone (a refund,
    /// or a restore onto a device that never had Pro).
    static func reconcile(isPro: Bool, _ defaults: UserDefaults = standard) {
        if isEnabled(defaults), !canSync(isPro: isPro, defaults) {
            setEnabled(false, defaults)
        }
    }
}
