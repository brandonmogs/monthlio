import XCTest
@testable import Monthlio

final class SyncPreferenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "SyncPreferenceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testUpgradeFromPreProVersionKeepsSyncForFree() {
        SyncPreference.migrateIfNeeded(storeExists: true, defaults)

        XCTAssertTrue(SyncPreference.isGrandfathered(defaults))
        XCTAssertTrue(SyncPreference.isEnabled(defaults))
        XCTAssertTrue(SyncPreference.canSync(isPro: false, defaults))
    }

    func testFreshInstallStartsLocalOnly() {
        SyncPreference.migrateIfNeeded(storeExists: false, defaults)

        XCTAssertFalse(SyncPreference.isGrandfathered(defaults))
        XCTAssertFalse(SyncPreference.isEnabled(defaults))
        XCTAssertFalse(SyncPreference.canSync(isPro: false, defaults))
        XCTAssertTrue(SyncPreference.canSync(isPro: true, defaults))
    }

    func testMigrationRunsOnce() {
        SyncPreference.migrateIfNeeded(storeExists: false, defaults)
        SyncPreference.setEnabled(true, defaults)
        // A store exists now, but the migration must not re-run and grandfather it.
        SyncPreference.migrateIfNeeded(storeExists: true, defaults)

        XCTAssertFalse(SyncPreference.isGrandfathered(defaults))
        XCTAssertTrue(SyncPreference.isEnabled(defaults))
    }

    func testReconcileTurnsSyncOffWhenEntitlementIsGone() {
        SyncPreference.migrateIfNeeded(storeExists: false, defaults)
        SyncPreference.setEnabled(true, defaults)

        SyncPreference.reconcile(isPro: true, defaults)
        XCTAssertTrue(SyncPreference.isEnabled(defaults))

        SyncPreference.reconcile(isPro: false, defaults)
        XCTAssertFalse(SyncPreference.isEnabled(defaults))
    }

    func testReconcileLeavesGrandfatheredDevicesAlone() {
        SyncPreference.migrateIfNeeded(storeExists: true, defaults)
        SyncPreference.reconcile(isPro: false, defaults)
        XCTAssertTrue(SyncPreference.isEnabled(defaults))
    }
}
