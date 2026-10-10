import SwiftUI

/// One wait, said once: the liquid loader, a title that does not change and
/// one line for the stage the work is really in.
///
/// - No layout jump: the stage line is drawn over every line it may show
///   (`reservedStages`), so the tallest one sets the height from the start,
///   and the cancel action keeps its place whether enabled or not.
/// - VoiceOver reads the title and the stage as one element (label and
///   value); the animation is decorative.
/// - It appears at once and never asks for a minimum time on screen: the
///   wait it shows is never made longer by it. No percentage is ever shown.
struct BodyFlowStagedLoader: View {
    struct CancelAction {
        let title: String
        var isEnabled = true
        var identifier: String?
        let perform: @MainActor () -> Void
    }

    let title: String
    let stage: String
    /// Every line the stage may show during this wait.
    var reservedStages: [String] = []
    var cancel: CancelAction?
    var statusIdentifier: String?
    /// Lets the host move VoiceOver to the status when the wait begins.
    var statusFocus: AccessibilityFocusState<Bool>.Binding?

    var body: some View {
        VStack(spacing: BodyFlowSpacing.md) {
            BodyFlowLiquidLoader()
                .accessibilityHidden(true)

            status

            if let cancel {
                Button(action: cancel.perform) {
                    Text(verbatim: cancel.title)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
                }
                .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                .disabled(!cancel.isEnabled)
                .optionalAccessibilityIdentifier(cancel.identifier)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BodyFlowSpacing.md)
    }

    private var status: some View {
        VStack(spacing: BodyFlowSpacing.xxs) {
            Text(verbatim: title)
                .font(BodyFlowTypography.cardTitle)
                .foregroundStyle(BodyFlowColor.primaryText)
            ZStack {
                // Reserved, invisible: the tallest line sets the height.
                ForEach(reservedStages.filter { $0 != stage }, id: \.self) { line in
                    Text(verbatim: line).hidden()
                }
                Text(verbatim: stage)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            }
            .font(BodyFlowTypography.supporting)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        // The status is the whole row for VoiceOver too: its outline does
        // not follow the width of whichever line is showing.
        .contentShape(.accessibility, Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(stage)
        .accessibilityAddTraits(.updatesFrequently)
        .modifier(StatusFocus(focus: statusFocus))
        .optionalAccessibilityIdentifier(statusIdentifier)
    }
}

/// VoiceOver focus on the status, for a host that asks for it.
private struct StatusFocus: ViewModifier {
    let focus: AccessibilityFocusState<Bool>.Binding?

    func body(content: Content) -> some View {
        if let focus {
            content.accessibilityFocused(focus)
        } else {
            content
        }
    }
}

private extension View {
    @ViewBuilder
    func optionalAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}
