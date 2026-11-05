import SwiftUI

/// Dormant read-only component. Callers own trusted transport/session fencing;
/// an HTTP success or this presentation never acknowledges an outbox command.
struct ConversationFeedbackPresentationView: View {
    let feedback: ConversationFeedbackPresentationSnapshot.Bound
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(verbatim: "Flow AI")
                .font(BodyFlowTypography.cardTitle)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: historicalTitle)
                .font(BodyFlowTypography.body)
                .accessibilityIdentifier("conversation.feedback.historical")
            switch feedback.presentation.content {
            case let .sections(_, sections), let .v3Sections(_, sections), let .placeholder(sections):
                ForEach(sections, id: \.key) { section in
                    Text(verbatim: section.text)
                        .accessibilityIdentifier("conversation.feedback.section.\(section.key.rawValue)")
                }
            case let .legacy(body):
                RegistrationFeedbackView(feedback: .v1(body))
            }
        }
        .font(BodyFlowTypography.body)
        .foregroundStyle(BodyFlowColor.primaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversation.feedback.presentation")
    }

    private var historicalTitle: String {
        let date = feedback.presentation.original.localDate
        return BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates
            ? "Historical registration (\(date))" : "Registro histórico (\(date))"
    }
}
