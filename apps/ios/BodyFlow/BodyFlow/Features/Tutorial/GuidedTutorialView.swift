import SwiftUI

/// How the tour was opened: offered on the first entry, or asked for from
/// Profile. Identity keeps one presentation per request.
struct GuidedTutorialPresentation: Identifiable, Equatable {
    enum Origin: Equatable {
        case firstEntry
        case profile
    }

    let id = UUID()
    let origin: Origin
    /// Captured when opened: an answer is written for this account only,
    /// even if it arrives after the shell changed.
    let ownerKey: String
}

/// The guided tour. It only explains: nothing here sends a message, records
/// data, asks for a permission or changes a plan, reminder or setting.
@MainActor
struct GuidedTutorialView: View {
    let presentation: GuidedTutorialPresentation
    let steps: [GuidedTutorialStep]
    let finish: @MainActor (GuidedTutorialOutcome) -> Void

    @State private var progress: GuidedTutorialProgress
    @AccessibilityFocusState private var focusedStep: String?
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    init(
        presentation: GuidedTutorialPresentation,
        steps: [GuidedTutorialStep],
        finish: @escaping @MainActor (GuidedTutorialOutcome) -> Void
    ) {
        self.presentation = presentation
        self.steps = steps
        self.finish = finish
        _progress = State(initialValue: GuidedTutorialProgress(stepCount: steps.count))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                BodyFlowColor.background.ignoresSafeArea()
                // A new scroll view per step: every step opens at its title,
                // and the cross-fade overlays instead of stacking.
                ScrollView {
                    stepContent
                        .padding(BodyFlowSpacing.md)
                        .frame(maxWidth: 640, alignment: .leading)
                        .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .id(step.id)
                .transition(BodyFlowMotion.stateTransition(reduceMotion: motionReduced))
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { actions }
            .navigationTitle(copy("tutorial.navigation.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy("tutorial.close")) { end(.closedEarly) }
                        .accessibilityIdentifier("tutorial.close")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.tutorial")
        }
        .interactiveDismissDisabled()
        .task(id: step.id) {
            // After the sheet or the step change settles, VoiceOver lands on
            // the step's title rather than on Close or the tapped button.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            focusedStep = step.id
        }
    }

    private var step: GuidedTutorialStep { steps[progress.index] }

    private var motionReduced: Bool { reduceMotion || systemReduceMotion }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private var stepContent: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Text(GuidedTutorialCopy.stepPosition(progress.index + 1, of: steps.count, language: language))
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .accessibilityIdentifier("tutorial.position")

            HStack(alignment: .firstTextBaseline, spacing: BodyFlowSpacing.sm) {
                Image(symbol: step.symbol)
                    .font(BodyFlowTypography.screenTitle)
                    .foregroundStyle(BodyFlowColor.accent)
                    .accessibilityHidden(true)
                Text(copy(step.titleKey))
                    .font(BodyFlowTypography.screenTitle)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focusedStep, equals: step.id)
                    .accessibilityIdentifier("tutorial.step.\(step.id)")
            }

            BodyFlowCard(surface: .content) {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    ForEach(step.lineKeys, id: \.self) { key in
                        Text(copy(key))
                            .font(BodyFlowTypography.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("tutorial.line.\(key)")
                    }
                }
            }

            if presentation.origin == .profile && progress.isFirst {
                areaShortcuts
            }
        }
    }

    /// From Profile, one area can be reviewed directly.
    private var areaShortcuts: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Text(copy("tutorial.areas.title"))
                .font(BodyFlowTypography.sectionTitle)
                .foregroundStyle(BodyFlowColor.primaryText)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(steps.enumerated()).dropFirst(), id: \.element.id) { position, area in
                Button {
                    move { progress.jump(to: position) }
                } label: {
                    HStack(spacing: BodyFlowSpacing.sm) {
                        Image(symbol: area.symbol)
                            .foregroundStyle(BodyFlowColor.accent)
                            .frame(minWidth: BodyFlowSpacing.minimumTapTarget)
                            .accessibilityHidden(true)
                        Text(copy(area.titleKey))
                            .font(BodyFlowTypography.body)
                            .foregroundStyle(BodyFlowColor.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: BodyFlowSpacing.xs)
                        Image(symbol: .chevron)
                            .foregroundStyle(BodyFlowColor.secondaryText)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bodyFlowRow)
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                .accessibilityIdentifier("tutorial.area.\(area.id)")
            }
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: BodyFlowSpacing.sm) { actionButtons }
            VStack(spacing: BodyFlowSpacing.sm) { actionButtons }
        }
        .padding(.horizontal, BodyFlowSpacing.md)
        .padding(.vertical, BodyFlowSpacing.sm)
        .background(BodyFlowColor.background)
    }

    @ViewBuilder private var actionButtons: some View {
        if progress.isFirst {
            // A replay asked for from Profile only closes; "Agora não" answers
            // the first-entry offer.
            if presentation.origin == .firstEntry {
                Button(copy("tutorial.later")) { end(.closedEarly) }
                    .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                    .accessibilityIdentifier("tutorial.later")
            }
            Button(copy("tutorial.start")) { move { progress.next() } }
                .buttonStyle(BodyFlowButtonStyle(role: .primary))
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("tutorial.start")
        } else {
            Button(copy("tutorial.back")) { move { progress.back() } }
                .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                .accessibilityIdentifier("tutorial.back")
            if progress.isLast {
                Button(copy("tutorial.finish")) { end(.finished) }
                    .buttonStyle(BodyFlowButtonStyle(role: .primary))
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("tutorial.finish")
            } else {
                Button(copy("tutorial.next")) { move { progress.next() } }
                    .buttonStyle(BodyFlowButtonStyle(role: .primary))
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("tutorial.next")
            }
        }
    }

    private func move(_ change: () -> Void) {
        focusedStep = nil
        withAnimation(BodyFlowMotion.animation(.content, reduceMotion: motionReduced)) {
            change()
        }
    }

    /// The answer is recorded by the owner; the sheet always closes, even if
    /// that presentation was already replaced.
    private func end(_ outcome: GuidedTutorialOutcome) {
        finish(outcome)
        dismiss()
    }

    private func copy(_ key: String) -> String {
        GuidedTutorialCopy.string(key, language: language)
    }
}
