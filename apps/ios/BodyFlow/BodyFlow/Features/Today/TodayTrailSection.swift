import SwiftUI

/// The day's trail as four nodes — Registrar → Hoje → Bloco 7.700 →
/// Progresso — each with the official state it already has today. Nothing
/// is computed here beyond counting the records the server listed; a node
/// without data says so instead of inventing progress.
struct TodayTrailDescriptor: Equatable, Sendable {
    struct Node: Equatable, Sendable, Identifiable {
        enum Kind: String, Sendable {
            case register, today, block, progress

            /// Literal keys: an interpolated `String.LocalizationValue` would
            /// look up "today.trail.node.%@" and render the raw key.
            var titleKey: String.LocalizationValue {
                switch self {
                case .register: "today.trail.node.register"
                case .today: "today.trail.node.today"
                case .block: "today.trail.node.block"
                case .progress: "today.trail.node.progress"
                }
            }
        }
        let kind: Kind
        /// The official figure for the node, already formatted; nil when the
        /// server has none yet.
        let detail: String?
        /// Reached today: a record exists, or the day has records and a
        /// balance. The block is credited only when the day closes and
        /// Progress shows the weeks, so neither is ever ticked here.
        let reached: Bool
        var id: String { kind.rawValue }
    }

    let nodes: [Node]

    init(
        recordCount: Int,
        remainingFood: String?,
        blockPercentage: Int?,
        language: SupportedAppLanguage
    ) {
        nodes = [
            Node(
                kind: .register,
                detail: String(
                    format: TodayCopy.string("today.trail.records", language: language),
                    recordCount
                ),
                reached: recordCount > 0
            ),
            Node(kind: .today, detail: remainingFood, reached: recordCount > 0 && remainingFood != nil),
            Node(
                kind: .block,
                detail: blockPercentage.map {
                    String(
                        format: TodayCopy.string("today.trail.block.detail", language: language),
                        "\(TodayValueFormatter.integer($0, language: language))%"
                    )
                },
                reached: false
            ),
            Node(
                kind: .progress,
                detail: TodayCopy.string("today.trail.progress.detail", language: language),
                reached: false
            ),
        ]
    }
}

@MainActor
struct TodayTrailSection: View {
    let descriptor: TodayTrailDescriptor
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                Label(verbatim: copy("today.trail.title"), symbol: .routine)
                    .font(BodyFlowTypography.cardTitle)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .accessibilityAddTraits(.isHeader)
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) { nodes(vertical: true) }
                } else {
                    HStack(alignment: .top, spacing: BodyFlowSpacing.xxs) { nodes(vertical: false) }
                }
                Text(copy("today.trail.detail"))
                    .font(BodyFlowTypography.caption)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.trail")
    }

    @ViewBuilder
    private func nodes(vertical: Bool) -> some View {
        ForEach(Array(descriptor.nodes.enumerated()), id: \.element.id) { index, node in
            if index > 0 {
                Image(symbol: .chevron)
                    .font(BodyFlowTypography.caption)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .rotationEffect(.degrees(vertical ? 90 : 0))
                    .frame(maxHeight: .infinity, alignment: vertical ? .leading : .center)
                    .padding(.top, vertical ? 0 : BodyFlowSpacing.sm)
                    .accessibilityHidden(true)
            }
            nodeView(node)
        }
    }

    private func nodeView(_ node: TodayTrailDescriptor.Node) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
            HStack(spacing: BodyFlowSpacing.xxs) {
                Image(symbol: node.reached ? .success : symbol(for: node.kind))
                    .foregroundStyle(BodyFlowColor.color(node.reached ? .feedbackPositive : .brandPrimary))
                    .accessibilityHidden(true)
                Text(verbatim: copy(node.kind.titleKey))
                    .font(BodyFlowTypography.caption.weight(.semibold))
                    .foregroundStyle(BodyFlowColor.primaryText)
            }
            Text(verbatim: node.detail ?? copy("today.trail.pending"))
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityValue(node.reached ? copy("today.trail.reached") : "")
        .accessibilityIdentifier("today.trail.\(node.kind.rawValue)")
    }

    private func symbol(for kind: TodayTrailDescriptor.Node.Kind) -> BodyFlowSymbol {
        switch kind {
        case .register: .meals
        case .today: .energy
        case .block: .block
        case .progress: .weight
        }
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        TodayCopy.string(key, language: BodyFlowPresentationLanguage.resolve(locale))
    }
}
