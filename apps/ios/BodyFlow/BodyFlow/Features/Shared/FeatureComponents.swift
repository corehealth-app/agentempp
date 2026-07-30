import SwiftUI

@MainActor
struct FeatureStateContentStack<Content: View>: View {
    let showsStaleBanner: Bool
    private let content: Content

    init(
        showsStaleBanner: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.showsStaleBanner = showsStaleBanner
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            if showsStaleBanner {
                StaleDataBanner()
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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
    let showsDisclosureIndicator: Bool

    init(
        title: String,
        detail: String,
        systemImage: String,
        showsDisclosureIndicator: Bool = true
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.showsDisclosureIndicator = showsDisclosureIndicator
    }

    var disclosureSystemImage: String? {
        showsDisclosureIndicator ? "chevron.right" : nil
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    HStack(spacing: BodyFlowSpacing.sm) {
                        actionIcon
                        actionTitle
                        Spacer(minLength: BodyFlowSpacing.xs)
                        disclosureIndicator
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
                    disclosureIndicator
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

    @ViewBuilder
    private var disclosureIndicator: some View {
        if let disclosureSystemImage {
            Image(systemName: disclosureSystemImage)
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .accessibilityHidden(true)
        }
    }
}
