import SwiftUI

/// Swatches plus a system color picker. "Auto" (nil) means the category's
/// color; anything else is stored as "#RRGGBB" on the expense.
struct ExpenseColorPicker: View {
    @Binding var selection: String?
    /// The category color, shown as the Auto swatch.
    let fallback: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    swatch(hex: nil, color: fallback, label: String(localized: "Auto"))
                    ForEach(ExpenseColor.palette) { preset in
                        swatch(hex: preset.hex, color: preset.color, label: preset.name)
                    }
                }
                .padding(.vertical, 4)
            }
            ColorPicker("Custom color", selection: customBinding, supportsOpacity: false)
        }
    }

    private func swatch(hex: String?, color: Color, label: String) -> some View {
        let isSelected = selection?.uppercased() == hex?.uppercased()
        return Button {
            selection = hex
            Haptics.selection()
        } label: {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 34, height: 34)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else if hex == nil {
                    Text(verbatim: "A")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .overlay(Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.5 : 0), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var customBinding: Binding<Color> {
        Binding(
            get: { selection.flatMap { Color(hex: $0) } ?? fallback },
            set: { selection = $0.hexString }
        )
    }
}

#Preview {
    Form {
        ExpenseColorPicker(selection: .constant("#FF9500"), fallback: .indigo)
    }
}
