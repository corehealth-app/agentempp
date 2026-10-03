import SwiftUI

/// The one strong surface of a screen: a teal sweep from `heroBackground` to
/// `heroGradientEnd` with `onHero` text, like the summary card of the
/// reference apps. Increase Contrast and Reduce Transparency flatten it to
/// the plain hero fill; every text pair stays ≥ 4.5:1 across the sweep.
struct BodyFlowHeroCard<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .foregroundStyle(BodyFlowColor.color(.onHero))
            .padding(BodyFlowSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: BodyFlowRadius.card, style: .continuous))
    }

    private var fill: AnyShapeStyle {
        if contrast == .increased || reduceTransparency {
            return AnyShapeStyle(BodyFlowColor.color(.heroBackground))
        }
        return AnyShapeStyle(LinearGradient(
            colors: [BodyFlowColor.color(.heroBackground), BodyFlowColor.color(.heroGradientEnd)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ))
    }
}
