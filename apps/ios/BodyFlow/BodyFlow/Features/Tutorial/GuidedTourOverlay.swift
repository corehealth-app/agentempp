import SwiftUI

/// The guided tour drawn over the real screen: the rest dims, the control
/// of the step stays lit inside a rounded cutout, and one short callout sits
/// next to it (below when it fits, otherwise above). Nothing underneath is
/// tappable while a step is shown; the tour only explains.
@MainActor
struct GuidedTourOverlay: View {
    let model: GuidedTourModel
    let anchors: [GuidedTourTarget: Anchor<CGRect>]
    let proxy: GeometryProxy
    let finish: @MainActor (GuidedTutorialOutcome) -> Void

    @State private var calloutSize: CGSize = .zero
    @State private var contentHeight: CGFloat = 120
    @State private var actionsHeight: CGFloat = 60
    @AccessibilityFocusState private var focusedStep: String?
    @Environment(\.locale) private var locale
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    nonisolated static let dimOpacity: Double = 0.55
    nonisolated static let maxCalloutWidth: CGFloat = 360

    var body: some View {
        let step = model.current
        let insets = proxy.safeAreaInsets
        let container = proxy.frame(in: .local).inset(by: UIEdgeInsets(
            top: insets.top, left: insets.leading, bottom: insets.bottom, right: insets.trailing
        ))
        // A target that is not on screen (still loading, scrolled away) gets
        // no cutout: the callout is centred instead of pointing at nothing.
        let target = step.target.flatMap { anchors[$0] }.map { proxy[$0] }
            .flatMap { container.intersects($0) ? $0 : nil }
        let cutout = target.map(GuidedTourPlacement.cutout(for:))
        let width = min(container.width - 2 * GuidedTourPlacement.gutter, Self.maxCalloutWidth)
        let placement = cutout.map {
            GuidedTourPlacement.callout(target: $0, size: calloutSize, container: container)
        }
        // Inside the room next to the target, or the whole screen for a card.
        let maxHeight = max(96, placement?.maxHeight ?? (container.height - 2 * GuidedTourPlacement.gutter))

        ZStack(alignment: .topLeading) {
            dim(cutout: cutout)
            if let cutout {
                RoundedRectangle(cornerRadius: GuidedTourPlacement.cutoutRadius, style: .continuous)
                    .strokeBorder(BodyFlowColor.color(.brandPrimary), lineWidth: 2)
                    .frame(width: cutout.width, height: cutout.height)
                    .offset(x: cutout.minX, y: cutout.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            callout(step, maxHeight: maxHeight)
                .frame(width: width)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { calloutSize = $0 }
                // Measured first, then shown: no jump from a zero-size guess.
                .opacity(calloutSize == .zero ? 0 : 1)
                .offset(
                    x: placement?.origin.x ?? (container.midX - width / 2),
                    y: placement?.origin.y ?? max(container.minY + GuidedTourPlacement.gutter,
                                                   container.midY - calloutSize.height / 2)
                )
        }
        .animation(BodyFlowMotion.animation(.content, reduceMotion: reduceMotion), value: step.id)
        .animation(BodyFlowMotion.animation(.content, reduceMotion: reduceMotion), value: calloutSize)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tour.overlay")
        .task(id: step.id) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            focusedStep = step.id
        }
    }

    /// Everything but the target is dimmed; the cutout is punched out of the
    /// dim layer so the real control keeps its own colors.
    private func dim(cutout: CGRect?) -> some View {
        Color.black.opacity(Self.dimOpacity)
            .mask {
                Rectangle()
                    .fill(.black)
                    .overlay {
                        if let cutout {
                            RoundedRectangle(cornerRadius: GuidedTourPlacement.cutoutRadius, style: .continuous)
                                .fill(.black)
                                .frame(width: cutout.width, height: cutout.height)
                                .position(x: cutout.midX, y: cutout.midY)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
            }
            .contentShape(Rectangle())
            .onTapGesture {}
            .accessibilityHidden(true)
    }

    /// The actions stay pinned at the bottom of the callout; when the text
    /// outgrows the room (AXXXL) only the text scrolls, so Próximo, Voltar
    /// and Pular are always visible and reachable.
    private func callout(_ step: GuidedTourStep, maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                calloutContent(step)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(contentHeight, max(48, maxHeight - actionsHeight)))
            actions(step)
                .padding(.horizontal, BodyFlowSpacing.md)
                .padding(.bottom, BodyFlowSpacing.md)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { actionsHeight = $0 }
        }
        .bodyFlowSurface(.modal, cornerRadius: BodyFlowRadius.card)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("tour.callout")
    }

    private func calloutContent(_ step: GuidedTourStep) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            if !model.isTip {
                Text(GuidedTutorialCopy.stepPosition(model.index + 1, of: model.steps.count, language: language))
                    .font(BodyFlowTypography.caption)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .accessibilityIdentifier("tour.position")
            }
            Text(copy(step.titleKey))
                .font(BodyFlowTypography.sectionTitle)
                .foregroundStyle(BodyFlowColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusedStep, equals: step.id)
                .accessibilityIdentifier("tour.step.\(step.id)")
            Text(copy(step.bodyKey))
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("tour.body.\(step.id)")
            if step.kind == .trail { trail }
        }
        .padding(BodyFlowSpacing.md)
    }

    /// The day's trail: register → Today updates → 7,700 kcal block →
    /// Progress. The plan line says how Plano and Flow fit around it.
    private var trail: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            let nodes: [(BodyFlowSymbol, String)] = [
                (.meals, "tour.trail.node.register"),
                (.energy, "tour.trail.node.today"),
                (.block, "tour.trail.node.block"),
                (.weight, "tour.trail.node.progress"),
            ]
            ViewThatFits(in: .horizontal) {
                HStack(spacing: BodyFlowSpacing.xs) { trailNodes(nodes, vertical: false) }
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) { trailNodes(nodes, vertical: true) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tour.trail.diagram")
            Text(copy("tour.trail.plan"))
                .font(BodyFlowTypography.callout)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func trailNodes(_ nodes: [(BodyFlowSymbol, String)], vertical: Bool) -> some View {
        ForEach(Array(nodes.enumerated()), id: \.offset) { index, node in
            if index > 0 {
                Image(symbol: .chevron)
                    .font(BodyFlowTypography.caption)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .rotationEffect(.degrees(vertical ? 90 : 0))
                    .accessibilityHidden(true)
            }
            Label(verbatim: copy(node.1), symbol: node.0)
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.primaryText)
                .labelStyle(.titleAndIcon)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func actions(_ step: GuidedTourStep) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: BodyFlowSpacing.xs) { actionButtons(step) }
            VStack(spacing: BodyFlowSpacing.xs) { actionButtons(step) }
        }
    }

    @ViewBuilder
    private func actionButtons(_ step: GuidedTourStep) -> some View {
        if model.isTip {
            Button(copy("tour.got-it")) { finish(.finished) }
                .buttonStyle(BodyFlowButtonStyle(role: .primary))
                .accessibilityIdentifier("tour.got-it")
        } else if model.isFirst {
            Button(copy(model.origin == .firstEntry ? "tutorial.later" : "tutorial.close")) {
                finish(.closedEarly)
            }
            .buttonStyle(BodyFlowButtonStyle(role: .secondary))
            .accessibilityIdentifier(model.origin == .firstEntry ? "tour.later" : "tour.close")
            Button(copy("tutorial.start")) { model.next() }
                .buttonStyle(BodyFlowButtonStyle(role: .primary))
                .accessibilityIdentifier("tour.start")
        } else {
            Button(copy("tour.skip")) { finish(.closedEarly) }
                .buttonStyle(BodyFlowButtonStyle(role: .tertiary, isCompact: true))
                .accessibilityIdentifier("tour.skip")
            Button(copy("tutorial.back")) { model.back() }
                .buttonStyle(BodyFlowButtonStyle(role: .secondary, isCompact: true))
                .accessibilityIdentifier("tour.back")
            if model.isLast {
                Button(copy("tutorial.finish")) { finish(.finished) }
                    .buttonStyle(BodyFlowButtonStyle(role: .primary))
                    .accessibilityIdentifier("tour.finish")
            } else {
                Button(copy("tutorial.next")) { model.next() }
                    .buttonStyle(BodyFlowButtonStyle(role: .primary))
                    .accessibilityIdentifier("tour.next")
            }
        }
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String) -> String {
        GuidedTutorialCopy.string(key, language: language)
    }
}
