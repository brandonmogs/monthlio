import SwiftUI

/// Full-screen cover shown while the app is locked.
struct LockScreenView: View {
    @Environment(AppLockService.self) private var lock

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Monthlio is locked")
                .font(.title2.bold())

            if let error = lock.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                Task { await lock.unlock() }
            } label: {
                Label("Unlock with \(lock.biometryName)", systemImage: lock.biometrySymbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(lock.isAuthenticating)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    LockScreenView()
        .environment(AppLockService(isEnabled: true))
}
