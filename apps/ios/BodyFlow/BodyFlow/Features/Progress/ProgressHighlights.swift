import SwiftUI

/// The two official figures people look for first — the current streak and
/// XP with its level — as chips above the charts. Values are the ones the
/// progress snapshot already carries; nothing is computed here.
@MainActor
struct ProgressHighlights: View {
    let presentation: ProgressPresentation
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Side by side at regular sizes, stacked at larger ones. The texts
        // always wrap (a rigid one-line text reads as "may be clipped at
        // larger sizes" to the accessibility audit).
        Group {
            if dynamicTypeSize <= .xLarge {
                HStack(alignment: .top, spacing: BodyFlowSpacing.xs) { chips }
            } else {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) { chips }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.highlights")
    }

    @ViewBuilder
    private var chips: some View {
        chip(
            String(format: copy("progress.highlight.streak"), presentation.currentStreakText),
            symbol: .streak, domain: .energy
        )
        chip(
            String(format: copy("progress.highlight.xp"), presentation.xpText, presentation.levelText),
            symbol: .xp, domain: .progress
        )
    }

    private func chip(_ text: String, symbol: BodyFlowSymbol, domain: BodyFlowDomain) -> some View {
        let shape = RoundedRectangle(cornerRadius: BodyFlowRadius.card, style: .continuous)
        return HStack(alignment: .firstTextBaseline, spacing: BodyFlowSpacing.xxs) {
            Image(symbol: symbol)
                .foregroundStyle(domain.color)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .foregroundStyle(BodyFlowColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(BodyFlowTypography.callout.weight(.semibold))
        .padding(.horizontal, BodyFlowSpacing.sm)
        .padding(.vertical, BodyFlowSpacing.xs)
        .background(BodyFlowColor.color(.surfaceElevated), in: shape)
        .overlay(shape.strokeBorder(domain.fill.opacity(0.55), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        ProgressCopy.string(key, language: BodyFlowPresentationLanguage.resolve(locale))
    }
}
