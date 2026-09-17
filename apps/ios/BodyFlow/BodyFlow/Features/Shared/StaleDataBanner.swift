import SwiftUI

@MainActor
struct StaleDataBanner: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    icon
                    message
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: BodyFlowSpacing.sm) {
                    icon
                    message
                }
            }
        }
        .padding(BodyFlowSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            BodyFlowColor.color(.backgroundSecondary),
            in: RoundedRectangle(cornerRadius: BodyFlowRadius.field, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("state.stale-banner")
    }

    private var icon: some View {
        Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(BodyFlowColor.color(.feedbackWarning))
            .accessibilityHidden(true)
    }

    private var message: some View {
        Text("state.stale.detail")
            .font(BodyFlowTypography.supporting)
            .foregroundStyle(BodyFlowColor.color(.feedbackWarning))
    }
}
