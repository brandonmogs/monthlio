import Foundation

/// Local, never-synced decisions about iCloud sync. Read at launch, before
/// the store opens, because the container's CloudKit option can't change
/// while the app runs.
///
/// Anyone who downloaded Monthlio before Pro existed keeps sync for free.
/// Two signals establish that: an existing store on disk at the first launch
/// of this version (an in-place upgrade), and the App Store's record of the
/// build the account first downloaded (`AppTransaction.originalAppVersion`),
/// which also covers reinstalls and new devices.
enum SyncPreference {
    /// Where the flags live. DEBUG builds swap in a throwaway suite for
    /// `-MonthlioFreshInstall` so UI tests see a brand-new install.
    static var standard: UserDefaults = .standard
    /// DEBUG: set with `-MonthlioFreshInstall` so the App Store record can't
    /// grandfather a UI test run.
    static var ignoresAppTransaction = false

    static let enabledKey = "sync.enabled"
    static let grandfatheredKey = "sync.grandfathered"
    static let migrationKey = "sync.migrationVersion"
    static let originalBuildKey = "sync.originalBuild"
    static let currentMigration = 1
    /// The first build that sells Pro (1.3 is build 6; 1.0 through 1.2 were
    /// builds 1 to 4). Earlier downloads keep sync free.
    static let firstProBuild = 6

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

    /// A sandbox answer (TestFlight, App Review, Xcode) is remembered but
    /// not final: the same device may later run the App Store build, whose
    /// production transaction is the one that can grandfather.
    static func hasRecordedOriginalBuild(_ defaults: UserDefaults = standard) -> Bool {
        guard let recorded = defaults.string(forKey: originalBuildKey) else { return false }
        return recorded != "sandbox"
    }

    /// Records the build the account first downloaded, as reported by the
    /// App Store, and grandfathers downloads from before Pro. Sync was always
    /// on before Pro, so a grandfathered install gets it back on. Returns
    /// true when this call turned grandfathering on.
    @discardableResult
    static func recordOriginalBuild(_ version: String, _ defaults: UserDefaults = standard) -> Bool {
        defaults.set(version, forKey: originalBuildKey)
        guard let build = leadingInteger(in: version), build < firstProBuild, !isGrandfathered(defaults) else { return false }
        defaults.set(true, forKey: grandfatheredKey)
        defaults.set(true, forKey: enabledKey)
        return true
    }

    /// "3" -> 3, "1.0" -> 1, "sandbox" or "abc" -> nil.
    static func leadingInteger(in version: String) -> Int? {
        Int(version.prefix { $0.isNumber })
    }

    /// Turns sync off when the entitlement that allowed it is gone (a refund,
    /// or a restore onto a device that never had Pro).
    static func reconcile(isPro: Bool, _ defaults: UserDefaults = standard) {
        if isEnabled(defaults), !canSync(isPro: isPro, defaults) {
            setEnabled(false, defaults)
        }
    }
}
