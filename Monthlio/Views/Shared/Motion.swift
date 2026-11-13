import SwiftUI
import UIKit

/// Animations that respect Reduce Motion: when the user asked for it,
/// state changes land without moving.
enum Motion {
    /// The animation for an explicit `withAnimation` or a binding's
    /// `.animation(_:)`, or nil under Reduce Motion.
    static func animation(_ animation: Animation = .default) -> Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : animation
    }
}

private struct MotionAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// `.animation(_:value:)` that becomes a plain state change under Reduce Motion.
    func motionAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(MotionAnimation(animation: animation, value: value))
    }
}
