import SwiftUI

/// One line under a total that was summed 1:1 for want of a rate, so the
/// figure isn't taken at face value. Empty when every rate is known.
struct MissingRatesNote: View {
    let codes: [String]

    var body: some View {
        if !codes.isEmpty {
            Text("Rate needed for \(codes.sorted().joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityLabel(Text("Some amounts are counted at face value: rate needed for \(codes.sorted().joined(separator: ", "))"))
        }
    }
}
