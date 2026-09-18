import SwiftUI

struct WeightRegistrationView: View {
    let initialRecordedAt: Date
    let isSubmitting: Bool
    let submit: @MainActor (String, Date) -> Void

    @State private var value = ""
    @State private var recordedAt: Date
    @Environment(\.locale) private var locale

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
            Text(copy("registration.kind.weight"))
                .font(BodyFlowTypography.headline)
            Text(copy("registration.weight.value"))
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.primaryText)
            RegistrationBoundedTextField(
                placeholder: copy("registration.weight.placeholder"),
                text: $value,
                keyboardType: .decimalPad,
                identifier: "registration.weight.value",
                accessibilityLabel: copy("registration.weight.value")
            )
                .frame(
                    maxWidth: .infinity,
                    minHeight: BodyFlowSpacing.minimumTapTarget + 4
                )
            Text(copy("registration.field.date-time"))
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.primaryText)
            RegistrationBoundedDatePicker(
                value: $recordedAt,
                identifier: "registration.weight.recorded-at",
                accessibilityLabel: copy("registration.field.date-time")
            )
                .frame(
                    maxWidth: .infinity,
                    minHeight: BodyFlowSpacing.minimumTapTarget + 4
                )
            RegistrationBoundedButton(
                title: copy("registration.weight.submit"),
                isEnabled: !isSubmitting,
                identifier: "registration.weight.submit"
            ) { submit(value, recordedAt) }
            .frame(maxWidth: .infinity)
        }
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(
            key,
            language: BodyFlowPresentationLanguage.resolve(locale)
        )
    }
}
