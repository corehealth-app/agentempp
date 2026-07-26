import SwiftUI

@MainActor
struct BodyFlowCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(BodyFlowSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                BodyFlowColor.surface,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(BodyFlowColor.accent.opacity(0.10), lineWidth: 1)
            }
    }
}

@MainActor
struct FixtureMetricRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let value: String
    var systemImage: String?

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    metricTitle
                    metricValue
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: BodyFlowSpacing.sm) {
                    metricTitle
                    Spacer(minLength: BodyFlowSpacing.sm)
                    metricValue
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var metricTitle: some View {
        HStack(spacing: BodyFlowSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(BodyFlowColor.accent)
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.secondaryText)
        }
    }

    private var metricValue: some View {
        Text(value)
            .font(BodyFlowTypography.headline)
            .foregroundStyle(BodyFlowColor.primaryText)
    }
}

@MainActor
struct FeatureActionLabel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    HStack(spacing: BodyFlowSpacing.sm) {
                        actionIcon
                        actionTitle
                        Spacer(minLength: BodyFlowSpacing.xs)
                        chevron
                    }
                    actionDetail
                }
            } else {
                HStack(spacing: BodyFlowSpacing.md) {
                    actionIcon

                    VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                        actionTitle
                        actionDetail
                    }

                    Spacer(minLength: BodyFlowSpacing.xs)
                    chevron
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget)
        .contentShape(Rectangle())
    }

    private var actionIcon: some View {
        Image(systemName: systemImage)
            .font(BodyFlowTypography.title)
            .foregroundStyle(BodyFlowColor.accent)
            .frame(minWidth: BodyFlowSpacing.minimumTapTarget)
            .accessibilityHidden(true)
    }

    private var actionTitle: some View {
        Text(title)
            .font(BodyFlowTypography.headline)
            .foregroundStyle(BodyFlowColor.primaryText)
    }

    private var actionDetail: some View {
        Text(detail)
            .font(BodyFlowTypography.callout)
            .foregroundStyle(BodyFlowColor.secondaryText)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(BodyFlowTypography.caption)
            .foregroundStyle(BodyFlowColor.secondaryText)
            .accessibilityHidden(true)
    }
}
