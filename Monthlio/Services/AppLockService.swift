import Foundation
import LocalAuthentication
import Observation
import SwiftUI

/// Abstracts LocalAuthentication so the lock state machine can be tested.
protocol Authenticating {
    var biometryName: String { get }
    var canAuthenticate: Bool { get }
    func authenticate(reason: String) async -> Bool
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
        default: return "Passcode"
        }
    }

    var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
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

    private let authenticator: Authenticating

    init(isEnabled: Bool, authenticator: Authenticating = DeviceAuthenticator()) {
        self.isEnabled = isEnabled
        self.isLocked = isEnabled
        self.authenticator = authenticator
    }

    var biometryName: String { authenticator.biometryName }
    var canAuthenticate: Bool { authenticator.canAuthenticate }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            lockIfEnabled()
        case .active:
            if isLocked { Task { await unlock() } }
        default:
            break
        }
    }

    func lockIfEnabled() {
        guard isEnabled else { return }
        isLocked = true
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        if await authenticator.authenticate(reason: "Unlock Monthlio") {
            isLocked = false
            lastError = nil
        } else {
            lastError = "Couldn't verify it's you. Try again."
        }
    }

    /// One-off confirmation used before turning the lock on.
    func verify(reason: String) async -> Bool {
        await authenticator.authenticate(reason: reason)
    }
}
