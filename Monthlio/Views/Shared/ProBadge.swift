import SwiftUI

/// The small "Pro" capsule on rows that open the Pro page for free users.
struct ProBadge: View {
    var body: some View {
        Text("Pro")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
    }
}

/// A row that looks like a navigation link but opens the Pro page: the
/// label, the badge and a chevron.
struct ProLockedRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                ProBadge()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .tint(.primary)
    }
}
