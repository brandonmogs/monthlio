import SwiftUI
import UIKit

/// Hosts the lock screen and the app-switcher blur in their own window
/// above everything else, including sheets and alerts. A SwiftUI overlay
/// can't do that: presentations live in a layer above the root view.
@MainActor
final class PrivacyShield {
    enum Mode: Equatable {
        case hidden
        case blurred
        case locked
    }

    private var window: UIWindow?
    private var mode: Mode = .hidden

    func update(to newMode: Mode, lock: AppLockService) {
        guard newMode != mode else { return }
        mode = newMode

        switch newMode {
        case .hidden:
            window?.isHidden = true
            window = nil
        case .blurred, .locked:
            guard let scene = activeScene() else { return }
            let content: AnyView = newMode == .locked
                ? AnyView(LockScreenView().environment(lock))
                : AnyView(BlurShieldView())
            let host = UIHostingController(rootView: content)
            host.view.backgroundColor = .clear
            host.view.accessibilityViewIsModal = true

            let window = window ?? UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            window.rootViewController = host
            window.isHidden = false
            self.window = window

            if newMode == .locked {
                // Drop the keyboard so it can't float above the shield.
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                window.makeKey()
            }
        }
    }

    private func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive } ?? scenes.first
    }
}

/// Opaque enough that the app-switcher snapshot shows nothing useful.
private struct BlurShieldView: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .ignoresSafeArea()
            .overlay {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }
    }
}
