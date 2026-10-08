import Foundation
import LocalAuthentication
import Observation
import SwiftUI

enum AuthenticationOutcome: Equatable {
    case success
    /// The user dismissed the prompt; not an error, and not a reason to re-prompt.
    case cancelled
    case failed(String)
}

/// Abstracts LocalAuthentication so the lock state machine can be tested.
protocol Authenticating {
    var biometryName: String { get }
    /// SF Symbol matching `biometryName`. Defaults to Face ID's glyph.
    var biometrySymbol: String { get }
    var canAuthenticate: Bool { get }
    func authenticate(reason: String) async -> AuthenticationOutcome
}

extension Authenticating {
    var biometrySymbol: String { "faceid" }
}

/// Face ID / Touch ID with device passcode fallback.
struct DeviceAuthenticator: Authenticating {
    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return String(localized: "Passcode")
        }
    }

    var biometrySymbol: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        case .faceID: return "faceid"
        default: return "lock.fill"
        }
    }

    var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func authenticate(reason: String) async -> AuthenticationOutcome {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Cancel")
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) ? .success : .failed(Self.genericFailure)
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .systemCancel, .appCancel, .userFallback:
                return .cancelled
            case .passcodeNotSet:
                return .failed(String(localized: "Set a device passcode in Settings to unlock Monthlio."))
            default:
                return .failed(Self.genericFailure)
            }
        } catch {
            return .failed(Self.genericFailure)
        }
    }

    private static var genericFailure: String {
        String(localized: "Couldn't verify it's you. Try again.")
    }
}

/// Locks the app when it leaves the foreground and gates it behind
/// biometrics or passcode on return.
@MainActor
@Observable
final class AppLockService {
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    private(set) var lastError: String?

    var isEnabled: Bool {
        didSet { if !isEnabled { isLocked = false } }
    }

    /// Seconds after leaving the app within which coming back skips the
    /// prompt. Zero locks on every return. The switcher snapshot is still
    /// covered, because the app locks the moment it leaves.
    var gracePeriod: TimeInterval
    /// Injected so tests can move time.
    var now: () -> Date = { .now }

    /// Set when the app locks; consumed by the first return to `.active`.
    /// The biometric prompt itself bounces the scene inactive→active, so
    /// without this a cancelled prompt would re-prompt forever.
    private var pendingAutoUnlock: Bool
    private var backgroundedAt: Date?
    private let authenticator: Authenticating

    init(isEnabled: Bool, gracePeriod: TimeInterval = 0, authenticator: Authenticating = DeviceAuthenticator()) {
        self.isEnabled = isEnabled
        self.isLocked = isEnabled
        self.pendingAutoUnlock = isEnabled
        self.gracePeriod = gracePeriod
        self.authenticator = authenticator
    }

    var biometryName: String { authenticator.biometryName }
    var biometrySymbol: String { authenticator.biometrySymbol }
    var canAuthenticate: Bool { authenticator.canAuthenticate }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            lockIfEnabled()
        case .active:
            guard isLocked else { return }
            if let backgroundedAt, now().timeIntervalSince(backgroundedAt) < gracePeriod {
                // A quick hop to another app and back: no prompt.
                isLocked = false
                pendingAutoUnlock = false
                self.backgroundedAt = nil
                return
            }
            if pendingAutoUnlock {
                pendingAutoUnlock = false
                Task { await unlock() }
            }
        default:
            break
        }
    }

    func lockIfEnabled() {
        guard isEnabled else { return }
        // The grace period is measured from an authenticated session only:
        // leaving while still locked (a cancelled prompt) must not let a
        // quick return in without authenticating.
        backgroundedAt = isLocked ? nil : now()
        isLocked = true
        pendingAutoUnlock = true
        lastError = nil
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        switch await authenticator.authenticate(reason: String(localized: "Unlock Monthlio")) {
        case .success:
            isLocked = false
            lastError = nil
        case .cancelled:
            lastError = nil
        case .failed(let message):
            lastError = message
        }
    }

    /// One-off confirmation used before turning the lock on.
    func verify(reason: String) async -> Bool {
        await authenticator.authenticate(reason: reason) == .success
    }
}
