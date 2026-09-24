import SwiftUI

/// Caps scrolling content at a comfortable line length and centers it, so
/// the dashboard and empty state don't stretch edge to edge on iPad.
struct ReadableWidth: ViewModifier {
    static let maxWidth: CGFloat = 720

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: Self.maxWidth)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func readableWidth() -> some View {
        modifier(ReadableWidth())
    }
}
