import SwiftUI

struct WeightRegistrationView: View {
    let initialRecordedAt: Date
    let isSubmitting: Bool
    let submit: @MainActor (String, Date) -> Void

    @State private var value = ""
    @State private var recordedAt: Date

    init(
        initialRecordedAt: Date,
        isSubmitting: Bool,
        submit: @escaping @MainActor (String, Date) -> Void
    ) {
        self.initialRecordedAt = initialRecordedAt
        self.isSubmitting = isSubmitting
        self.submit = submit
        _recordedAt = State(initialValue: initialRecordedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Text("Peso")
                .font(BodyFlowTypography.headline)
            Text("Peso (kg)")
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.primaryText)
            RegistrationBoundedTextField(
                placeholder: "Peso em kg",
                text: $value,
                keyboardType: .decimalPad,
                identifier: "registration.weight.value",
                accessibilityLabel: "Peso (kg)"
            )
                .frame(
                    maxWidth: .infinity,
                    minHeight: BodyFlowSpacing.minimumTapTarget + 4
                )
            Text("Data e hora")
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.primaryText)
            RegistrationBoundedDatePicker(
                value: $recordedAt,
                identifier: "registration.weight.recorded-at",
                accessibilityLabel: "Data e hora"
            )
                .frame(
                    maxWidth: .infinity,
                    minHeight: BodyFlowSpacing.minimumTapTarget + 4
                )
            RegistrationBoundedButton(
                title: "Registrar peso",
                isEnabled: !isSubmitting,
                identifier: "registration.weight.submit"
            ) { submit(value, recordedAt) }
            .frame(maxWidth: .infinity)
        }
    }
}
