import SwiftUI

/// Floating "Deleted X · Undo" strip shown above the tab bar for a few
/// seconds after a delete.
struct UndoDeleteBar: View {
    @Environment(DeletedExpenseBuffer.self) private var deleted
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if let pending = deleted.pending {
            HStack(spacing: 12) {
                Text("Deleted \(pending.name)")
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Undo") {
                    deleted.undo(in: modelContext)
                    Haptics.success()
                }
                .font(.body.weight(.semibold))
                .accessibilityIdentifier("undo-delete")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
