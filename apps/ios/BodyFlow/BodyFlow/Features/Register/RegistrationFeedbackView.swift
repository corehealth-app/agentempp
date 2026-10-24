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
