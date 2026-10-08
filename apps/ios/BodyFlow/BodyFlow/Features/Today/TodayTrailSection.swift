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
    let showsBlock7700: Bool

    init(
        recordCount: Int,
        remainingFood: String?,
        blockPercentage: Int?,
        showsBlock7700: Bool = false,
        language: SupportedAppLanguage
    ) {
        self.showsBlock7700 = showsBlock7700
        var nodes = [
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
        if !showsBlock7700 { nodes.removeAll { $0.kind == .block } }
        self.nodes = nodes
    }
}

@MainActor
struct TodayTrailSection: View {
    let descriptor: TodayTrailDescriptor
    @Environment(\.locale) private var locale

    var body: some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                Label(verbatim: copy("today.trail.title"), symbol: .routine)
                    .font(BodyFlowTypography.cardTitle)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .accessibilityAddTraits(.isHeader)
                // A vertical timeline at every size: titles and details read
                // on full lines instead of four squeezed columns.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(descriptor.nodes.enumerated()), id: \.element.id) { index, node in
                        timelineRow(node, isLast: index == descriptor.nodes.count - 1)
                    }
                }
                Text(copy(descriptor.showsBlock7700 ? "today.trail.detail" : "today.trail.detail.without-block"))
                    .font(BodyFlowTypography.caption)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.trail")
    }

    private func timelineRow(_ node: TodayTrailDescriptor.Node, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
            VStack(spacing: 0) {
                Image(symbol: node.reached ? .confirm : symbol(for: node.kind))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(BodyFlowColor.color(node.reached ? .onPrimary : fillRole(for: node.kind)))
                    .frame(width: 28, height: 28)
                    .background(
                        BodyFlowColor.color(node.reached ? .brandPrimary : fillRole(for: node.kind))
                            .opacity(node.reached ? 1 : BodyFlowOpacity.glyphWash),
                        in: Circle()
                    )
                if !isLast {
                    // The connector lights up once this node is reached.
                    Rectangle()
                        .fill(BodyFlowColor.color(node.reached ? .brandPrimary : .borderSubtle))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: copy(node.kind.titleKey))
                    .font(BodyFlowTypography.headline)
                    .foregroundStyle(BodyFlowColor.primaryText)
                Text(verbatim: node.detail ?? copy("today.trail.pending"))
                    .font(BodyFlowTypography.caption)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : BodyFlowSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityValue(node.reached ? copy("today.trail.reached") : "")
            .accessibilityIdentifier("today.trail.\(node.kind.rawValue)")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func fillRole(for kind: TodayTrailDescriptor.Node.Kind) -> BodyFlowColor.Role {
        switch kind {
        case .register: .energyVivid
        case .today: .brandPrimary
        case .block: .blockVivid
        case .progress: .progressVivid
        }
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
