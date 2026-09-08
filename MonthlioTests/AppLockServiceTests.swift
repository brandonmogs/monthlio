import SwiftUI
import XCTest
@testable import Monthlio

private final class FakeAuthenticator: Authenticating {
    var biometryName = "Face ID"
    var canAuthenticate = true
    var shouldSucceed = true
    var attempts = 0

    func authenticate(reason: String) async -> Bool {
        attempts += 1
        return shouldSucceed
    }
}

@MainActor
final class AppLockServiceTests: XCTestCase {
    func testDisabledLockStartsUnlockedAndIgnoresBackground() {
        let lock = AppLockService(isEnabled: false, authenticator: FakeAuthenticator())
        XCTAssertFalse(lock.isLocked)
        lock.handleScenePhase(.background)
        XCTAssertFalse(lock.isLocked)
    }

    func testEnabledLockStartsLocked() {
        let lock = AppLockService(isEnabled: true, authenticator: FakeAuthenticator())
        XCTAssertTrue(lock.isLocked)
    }

    func testSuccessfulUnlockClearsLockAndError() async {
        let auth = FakeAuthenticator()
        let lock = AppLockService(isEnabled: true, authenticator: auth)
        await lock.unlock()
        XCTAssertFalse(lock.isLocked)
        XCTAssertNil(lock.lastError)
        XCTAssertEqual(auth.attempts, 1)
    }

    func testFailedUnlockStaysLockedWithError() async {
        let auth = FakeAuthenticator()
        auth.shouldSucceed = false
        let lock = AppLockService(isEnabled: true, authenticator: auth)
        await lock.unlock()
        XCTAssertTrue(lock.isLocked)
        XCTAssertNotNil(lock.lastError)
    }

    func testBackgroundRelocksAfterUnlock() async {
        let lock = AppLockService(isEnabled: true, authenticator: FakeAuthenticator())
        await lock.unlock()
        XCTAssertFalse(lock.isLocked)
        lock.handleScenePhase(.background)
        XCTAssertTrue(lock.isLocked)
    }

    func testDisablingUnlocksImmediately() {
        let lock = AppLockService(isEnabled: true, authenticator: FakeAuthenticator())
        lock.isEnabled = false
        XCTAssertFalse(lock.isLocked)
    }

    func testUnlockIsNoOpWhenNotLocked() async {
        let auth = FakeAuthenticator()
        let lock = AppLockService(isEnabled: false, authenticator: auth)
        await lock.unlock()
        XCTAssertEqual(auth.attempts, 0)
    }
}
