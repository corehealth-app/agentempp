import SwiftUI

/// Read-only text from the confirmed receipt, under the parent model's session ownership.
struct RegistrationFeedbackView: View {
    let feedback: RegistrationFeedbackSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            ForEach(feedback.lines, id: \.key) { line in
                Text(verbatim: line.text)
                    .accessibilityIdentifier("registration.feedback.line.\(line.key.rawValue)")
            }
            if let comment = feedback.foodComment {
                Text(verbatim: comment).accessibilityIdentifier("registration.feedback.food-comment")
            }
            if let incentive = feedback.incentive {
                Text(verbatim: incentive).accessibilityIdentifier("registration.feedback.incentive")
            }
        }
        .font(BodyFlowTypography.body)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("registration.feedback")
    }
}

/// History displays a saved receipt, including after a later C11 edit.
struct OriginalRegistrationFeedbackView: View {
    let feedback: RegistrationFeedbackSnapshot
    @Environment(\.locale) private var locale
    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(RegistrationCopy.string("registration.feedback.original",
                language: BodyFlowPresentationLanguage.resolve(locale)))
                .font(BodyFlowTypography.cardTitle)
                .foregroundStyle(BodyFlowColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            RegistrationFeedbackView(feedback: feedback)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("registration.feedback.original")
    }
}
