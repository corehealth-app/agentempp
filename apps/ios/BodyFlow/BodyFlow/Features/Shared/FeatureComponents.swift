import SwiftUI
import UIKit

@MainActor
struct FeatureStateContentStack<Content: View>: View {
    let showsStaleBanner: Bool
    private let retryAction: (@MainActor () -> Void)?
    private let content: Content

    init(
        showsStaleBanner: Bool,
        retryAction: (@MainActor () -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.showsStaleBanner = showsStaleBanner
        self.retryAction = retryAction
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            if showsStaleBanner {
                // Inset like the scrolled content below it, so the banner
                // never runs edge to edge under the navigation bar.
                FeatureStaleRecovery(retry: retryAction)
                    .padding([.horizontal, .top], BodyFlowSpacing.md)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum BodyFlowSurfaceRole: Sendable {
    case legacy, card, hero, elevated
    case canvas, content, floating, modal, interactive

    var colorRole: BodyFlowColor.Role {
        switch self {
        case .canvas: .backgroundPrimary
        case .legacy, .card, .content: .backgroundSecondary
        case .hero: .heroBackground
        case .elevated, .floating, .modal: .surfaceElevated
        case .interactive: .surfaceInteractive
        }
    }
}

@MainActor
struct BodyFlowCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    let surface: BodyFlowSurfaceRole
    /// Inner padding: the default for content cards, `sm` for compact tiles.
    let padding: CGFloat
    private let content: Content

    init(
        surface: BodyFlowSurfaceRole = .card,
        padding: CGFloat = BodyFlowSpacing.md,
        @ViewBuilder content: () -> Content
    ) {
        self.surface = surface
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        styledContent
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // Direction A: white cards float on the light canvas with a
                // soft lift; dark mode (direction B) separates by fill. The
                // shadow is on the shape only — a shadow on the card itself
                // would also shadow every text inside it.
                RoundedRectangle(cornerRadius: BodyFlowRadius.card, style: .continuous)
                    .fill(backgroundColor)
                    .shadow(
                        color: .black.opacity(liftsInLight ? BodyFlowElevation.heroOpacity : 0),
                        radius: BodyFlowElevation.heroBlur, y: BodyFlowElevation.heroY
                    )
            }
            .overlay {
                if surface == .legacy {
                    RoundedRectangle(cornerRadius: BodyFlowRadius.card, style: .continuous)
                        .stroke(legacyAccent.opacity(BodyFlowOpacity.tintWash), lineWidth: 1)
                } else if contrast == .increased {
                    // The lift is never the only boundary under Increase Contrast.
                    RoundedRectangle(cornerRadius: BodyFlowRadius.card, style: .continuous)
                        .strokeBorder(BodyFlowColor.color(.controlBoundary), lineWidth: 1)
                }
            }
    }

    private var liftsInLight: Bool {
        colorScheme == .light && surface != .legacy && surface != .hero && surface != .canvas
    }

    @ViewBuilder private var styledContent: some View {
        if surface == .legacy {
            content
        } else {
            content.foregroundStyle(BodyFlowColor.color(surface == .hero ? .onHero : .textPrimary))
        }
    }

    private var backgroundColor: Color {
        switch surface {
        case .legacy: Color(uiColor: .secondarySystemBackground)
        case .card: BodyFlowColor.color(.backgroundSecondary)
        case .hero: BodyFlowColor.color(.heroBackground)
        case .elevated: BodyFlowColor.color(.surfaceElevated)
        case .canvas, .content, .floating, .modal, .interactive:
            BodyFlowColor.color(surface.colorRole)
        }
    }

    private var legacyAccent: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(BodyFlowColor.softGold)
                : UIColor(BodyFlowColor.tealGreen)
        })
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
            .fixedSize(horizontal: false, vertical: true)
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
