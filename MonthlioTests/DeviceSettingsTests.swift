import XCTest
@testable import Monthlio

final class DeviceSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "DeviceSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testDefaults() {
        XCTAssertFalse(DeviceSettings.isLockEnabled(defaults))
        XCTAssertEqual(DeviceSettings.lockGrace(defaults), .oneMinute)
        XCTAssertFalse(DeviceSettings.remindersEnabled(defaults))
        XCTAssertEqual(DeviceSettings.reminderHour(defaults), 9)
    }

    func testSettersRoundTrip() {
        DeviceSettings.setLockEnabled(true, defaults)
        DeviceSettings.setLockGrace(.fiveMinutes, defaults)
        DeviceSettings.setRemindersEnabled(true, defaults)
        DeviceSettings.setReminderHour(18, defaults)

        XCTAssertTrue(DeviceSettings.isLockEnabled(defaults))
        XCTAssertEqual(DeviceSettings.lockGrace(defaults), .fiveMinutes)
        XCTAssertTrue(DeviceSettings.remindersEnabled(defaults))
        XCTAssertEqual(DeviceSettings.reminderHour(defaults), 18)

        DeviceSettings.setReminderHour(99, defaults)
        XCTAssertEqual(DeviceSettings.reminderHour(defaults), 9, "an impossible hour falls back")
    }

    func testMigrationAdoptsTheLockOnlyWhereThisDeviceCanOpenIt() {
        DeviceSettings.migrateIfNeeded(lockWasEnabled: true, remindersWereEnabled: true, canAuthenticate: false, defaults)

        XCTAssertFalse(DeviceSettings.isLockEnabled(defaults), "a synced lock must not lock out a device without a passcode")
        XCTAssertTrue(DeviceSettings.remindersEnabled(defaults))

        DeviceSettings.migrateIfNeeded(lockWasEnabled: true, remindersWereEnabled: true, canAuthenticate: true, defaults)
        XCTAssertFalse(DeviceSettings.isLockEnabled(defaults), "migration runs once")
    }

    func testMigrationAdoptsTheLockWhenAuthenticationIsAvailable() {
        DeviceSettings.migrateIfNeeded(lockWasEnabled: true, remindersWereEnabled: false, canAuthenticate: true, defaults)
        XCTAssertTrue(DeviceSettings.isLockEnabled(defaults))
        XCTAssertFalse(DeviceSettings.remindersEnabled(defaults))
    }

    func testALockWithoutAPasscodeIsTurnedOffAndReported() {
        DeviceSettings.setLockEnabled(true, defaults)
        let kept = DeviceSettings.resolveLock(canAuthenticate: true, defaults)
        XCTAssertEqual(kept.enabled, true)
        XCTAssertFalse(kept.turnedOffForMissingPasscode)

        let dropped = DeviceSettings.resolveLock(canAuthenticate: false, defaults)
        XCTAssertFalse(dropped.enabled)
        XCTAssertTrue(dropped.turnedOffForMissingPasscode, "the user is told why")
        XCTAssertFalse(DeviceSettings.isLockEnabled(defaults), "and the setting follows, so Settings shows it off")

        let off = DeviceSettings.resolveLock(canAuthenticate: false, defaults)
        XCTAssertFalse(off.turnedOffForMissingPasscode, "nothing to report when the lock was already off")
    }

    func testHourLabelUsesTheCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        XCTAssertEqual(DeviceSettings.hourLabel(9, calendar: calendar, locale: Locale(identifier: "en_US")).replacingOccurrences(of: "\u{202F}", with: " "), "9:00 AM")
    }
}
