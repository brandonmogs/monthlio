import SwiftUI

/// Floating "Deleted X · Undo" strip shown above the tab bar for a few
/// seconds after a delete; several quick deletes share one strip.
struct UndoDeleteBar: View {
    @Environment(DeletedExpenseBuffer.self) private var deleted
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if !deleted.pending.isEmpty {
            HStack(spacing: 12) {
                label
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Undo") {
                    if !deleted.undo(in: modelContext).isEmpty {
                        Haptics.success()
                    } else {
                        Haptics.warning()
                    }
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

    private var label: Text {
        let pending = deleted.pending
        if pending.count == 1 { return Text("Deleted \(pending[0].name)") }
        return Text("Deleted ^[\(pending.count) expense](inflect: true)")
    }
}
