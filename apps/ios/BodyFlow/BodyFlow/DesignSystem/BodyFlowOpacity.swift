import SwiftUI

/// Decorative alpha tokens. Washes carry no meaning on their own (the text or
/// symbol inside them does), so one shared value replaces the ad-hoc
/// 0.08 / 0.10 / 0.12 / 0.25 family that had drifted between screens.
enum BodyFlowOpacity {
    /// Tinted informational background behind readable text.
    static let tintWash: Double = 0.10
    /// Pressed state of card/row buttons.
    static let pressed: Double = 0.85
    /// Peak of the loading shimmer highlight.
    static let shimmer: Double = 0.55
}

/// A flat semantic wash with accessibility fallbacks: opaque secondary
/// surface under Increase Contrast, and a subtle outline under
/// Differentiate Without Color so the block is not distinguished by tint
/// alone.
struct BodyFlowWashModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.bodyFlowDifferentiateWithoutColor) private var differentiateWithoutColor
    let role: BodyFlowColor.Role

    func body(content: Content) -> some View {
        content
            .background(fill, in: shape)
            .overlay {
                if differentiateWithoutColor {
                    shape.strokeBorder(BodyFlowColor.color(.borderSubtle), lineWidth: 1)
                }
            }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: BodyFlowRadius.field, style: .continuous)
    }

    private var fill: Color {
        contrast == .increased
            ? BodyFlowColor.color(.backgroundSecondary)
            : BodyFlowColor.color(role).opacity(BodyFlowOpacity.tintWash)
    }
}

extension View {
    func bodyFlowWash(_ role: BodyFlowColor.Role) -> some View {
        modifier(BodyFlowWashModifier(role: role))
    }
}
