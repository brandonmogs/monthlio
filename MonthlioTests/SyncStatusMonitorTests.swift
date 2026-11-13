import CloudKit
import XCTest
@testable import Monthlio

@MainActor
final class SyncStatusMonitorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "SyncStatusMonitorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private struct StubError: LocalizedError {
        var errorDescription: String? { "Something went wrong" }
    }

    func testASuccessfulExportIsRememberedAcrossLaunches() {
        let monitor = SyncStatusMonitor(defaults: defaults)
        XCTAssertNil(monitor.summary())

        monitor.record(kind: .exporting, succeeded: false, error: nil, endDate: nil)
        XCTAssertEqual(monitor.phase, .running(.exporting))

        let finished = Date(timeIntervalSince1970: 1_700_000_000)
        monitor.record(kind: .exporting, succeeded: true, error: nil, endDate: finished)
        XCTAssertEqual(monitor.phase, .idle)
        XCTAssertEqual(monitor.lastSynced, finished)
        XCTAssertEqual(monitor.summary(now: finished.addingTimeInterval(30)), "Last synced just now.")

        let relaunched = SyncStatusMonitor(defaults: defaults)
        XCTAssertEqual(relaunched.lastSynced, finished, "the last sync survives a relaunch")
    }

    func testSetupSuccessIsNotASync() {
        let monitor = SyncStatusMonitor(defaults: defaults)
        monitor.record(kind: .setup, succeeded: false, error: nil, endDate: nil)
        XCTAssertEqual(monitor.summary(), "Setting up iCloud sync…")
        monitor.record(kind: .setup, succeeded: true, error: nil, endDate: .now)
        XCTAssertNil(monitor.lastSynced)
        XCTAssertNil(monitor.summary())
    }

    func testAFailureIsExplainedUntilTheNextSuccess() {
        let monitor = SyncStatusMonitor(defaults: defaults)
        let failed = Date(timeIntervalSince1970: 1_700_000_000)
        monitor.record(kind: .exporting, succeeded: false, error: StubError(), endDate: failed)
        XCTAssertEqual(monitor.lastError, "Something went wrong")
        XCTAssertEqual(monitor.summary(now: failed.addingTimeInterval(10)), "iCloud sync failed just now: Something went wrong")

        let relaunched = SyncStatusMonitor(defaults: defaults)
        XCTAssertEqual(relaunched.lastError, "Something went wrong", "the failure survives a relaunch")

        monitor.record(kind: .importing, succeeded: true, error: nil, endDate: failed.addingTimeInterval(60))
        XCTAssertNil(monitor.lastError)
        XCTAssertNil(defaults.string(forKey: SyncStatusMonitor.lastErrorKey))
        XCTAssertEqual(monitor.summary(now: failed.addingTimeInterval(61)), "Last synced just now.")
    }

    func testCloudKitErrorsGetPlainWords() {
        XCTAssertEqual(SyncStatusMonitor.describe(CKError(.notAuthenticated)), "sign in to iCloud in the Settings app.")
        XCTAssertEqual(SyncStatusMonitor.describe(CKError(.quotaExceeded)), "your iCloud storage is full.")
        XCTAssertEqual(SyncStatusMonitor.describe(CKError(.networkUnavailable)), "no network connection.")
        XCTAssertTrue(SyncStatusMonitor.describe(CKError(.partialFailure)).hasPrefix("some records couldn't be saved to iCloud."))
        XCTAssertEqual(SyncStatusMonitor.describe(StubError()), "Something went wrong")
    }
}
