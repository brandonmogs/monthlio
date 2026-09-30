import SwiftUI
import XCTest
@testable import Monthlio

private final class FakeAuthenticator: Authenticating {
    var biometryName = "Face ID"
    var canAuthenticate = true
    var outcome: AuthenticationOutcome = .success
    var shouldSucceed: Bool {
        get { outcome == .success }
        set { outcome = newValue ? .success : .failed("Couldn't verify it's you. Try again.") }
    }
    var attempts = 0

    func authenticate(reason: String) async -> AuthenticationOutcome {
        attempts += 1
        return outcome
    }
}

/// The auto-prompt runs in a Task; wait for it instead of sleeping a fixed
/// time, which flaked when the machine was busy.
@MainActor
private func waitForAttempts(_ expected: Int, on auth: FakeAuthenticator, timeout: Duration = .seconds(3)) async {
    let deadline = ContinuousClock.now + timeout
    while auth.attempts < expected, ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
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

    func testCancelledPromptLeavesNoErrorAndDoesNotRePrompt() async {
        let auth = FakeAuthenticator()
        auth.outcome = .cancelled
        let lock = AppLockService(isEnabled: true, authenticator: auth)

        // Launch: the first activation auto-prompts once.
        lock.handleScenePhase(.active)
        await waitForAttempts(1, on: auth)
        XCTAssertEqual(auth.attempts, 1)
        XCTAssertTrue(lock.isLocked)
        XCTAssertNil(lock.lastError, "a cancel is not an error")

        // The system prompt bounces the scene inactive → active. No re-prompt.
        lock.handleScenePhase(.inactive)
        lock.handleScenePhase(.active)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(auth.attempts, 1)

        // The manual button still works.
        auth.outcome = .success
        await lock.unlock()
        XCTAssertFalse(lock.isLocked)
    }

    func testBackgroundReArmsTheAutoPrompt() async {
        let auth = FakeAuthenticator()
        auth.outcome = .cancelled
        let lock = AppLockService(isEnabled: true, authenticator: auth)
        lock.handleScenePhase(.active)
        await waitForAttempts(1, on: auth)
        XCTAssertEqual(auth.attempts, 1)

        lock.handleScenePhase(.background)
        lock.handleScenePhase(.active)
        await waitForAttempts(2, on: auth)
        XCTAssertEqual(auth.attempts, 2)
    }

    func testPasscodeNotSetMessageSurfaces() async {
        let auth = FakeAuthenticator()
        auth.outcome = .failed("Set a device passcode in Settings to unlock Monthlio.")
        let lock = AppLockService(isEnabled: true, authenticator: auth)
        await lock.unlock()
        XCTAssertEqual(lock.lastError, "Set a device passcode in Settings to unlock Monthlio.")
    }

    func testReturnWithinGracePeriodSkipsThePrompt() async {
        let auth = FakeAuthenticator()
        let lock = AppLockService(isEnabled: true, gracePeriod: 60, authenticator: auth)
        var clock = Date(timeIntervalSince1970: 1_000)
        lock.now = { clock }
        await lock.unlock()
        XCTAssertEqual(auth.attempts, 1)

        lock.handleScenePhase(.background)
        XCTAssertTrue(lock.isLocked, "the app switcher snapshot must not show data")
        clock += 30
        lock.handleScenePhase(.active)
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(lock.isLocked)
        XCTAssertEqual(auth.attempts, 1, "back within a minute: no prompt")
    }

    func testReturnAfterGracePeriodPromptsAgain() async {
        let auth = FakeAuthenticator()
        let lock = AppLockService(isEnabled: true, gracePeriod: 60, authenticator: auth)
        var clock = Date(timeIntervalSince1970: 1_000)
        lock.now = { clock }
        await lock.unlock()

        lock.handleScenePhase(.background)
        clock += 61
        lock.handleScenePhase(.active)
        await waitForAttempts(2, on: auth)

        XCTAssertEqual(auth.attempts, 2)
        XCTAssertFalse(lock.isLocked)
    }

    func testColdStartPromptsRegardlessOfGracePeriod() async {
        let auth = FakeAuthenticator()
        let lock = AppLockService(isEnabled: true, gracePeriod: 300, authenticator: auth)
        lock.handleScenePhase(.active)
        await waitForAttempts(1, on: auth)
        XCTAssertEqual(auth.attempts, 1)
    }

    func testUnlockIsNoOpWhenNotLocked() async {
        let auth = FakeAuthenticator()
        let lock = AppLockService(isEnabled: false, authenticator: auth)
        await lock.unlock()
        XCTAssertEqual(auth.attempts, 0)
    }
}
