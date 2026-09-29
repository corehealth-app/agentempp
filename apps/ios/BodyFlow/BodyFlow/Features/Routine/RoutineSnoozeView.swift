import SwiftUI

@MainActor
struct RoutineSnoozeView: View {
    @Environment(\.locale) private var locale
    let model: RoutineActionModel
    let submit: @MainActor (RoutineSnoozeSelection) -> Void
    @State private var customTime: Date
    /// The choice being sent, so only its button shows the spinner.
    @State private var submittedPreset: Int?

    init(
        model: RoutineActionModel,
        submit: @escaping @MainActor (RoutineSnoozeSelection) -> Void
    ) {
        self.model = model
        self.submit = submit
        _customTime = State(initialValue: model.occurredAt.addingTimeInterval(15 * 60))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Text(copy("routine.snooze.title"))
                .font(BodyFlowTypography.screenTitle)
                .foregroundStyle(BodyFlowColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            // The three presets share a row while they fit and stack when
            // the text grows; each keeps the 44 pt floor.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: BodyFlowSpacing.sm) {
                    presetButton(15)
                    presetButton(30)
                    presetButton(60)
                }
                VStack(spacing: BodyFlowSpacing.sm) {
                    presetButton(15)
                    presetButton(30)
                    presetButton(60)
                }
            }

            // The wheel's own label would squeeze into a narrow hyphenated
            // column beside it; the title sits above instead and the picker
            // keeps the same spoken label.
            Text(copy("routine.snooze.custom-time"))
                .font(BodyFlowTypography.cardTitle)
                .foregroundStyle(BodyFlowColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            DatePicker(
                copy("routine.snooze.custom-time"),
                selection: $customTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .tint(BodyFlowColor.accent)
            .frame(maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget + 1)
            .contentShape(Rectangle())
            .accessibilityLabel(copy("routine.snooze.custom-time"))
            .accessibilityIdentifier("routine.snooze.custom-time")

            Button {
                submittedPreset = nil
                submit(.custom(customTime))
            } label: {
                Text(copy("routine.snooze.use-custom"))
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
            }
            .buttonStyle(BodyFlowButtonStyle(role: .primary, isLoading: isSubmittingCustom))
            .disabled(model.isSubmitting || model.snoozeDate(for: .custom(customTime)) == nil)
            .accessibilityIdentifier("routine.snooze.custom")
        }
    }

    private func presetButton(_ minutes: Int) -> some View {
        Button {
            submittedPreset = minutes
            submit(.minutes(minutes))
        } label: {
            Text(String(
                format: copy("routine.snooze.minutes-format"),
                locale: language.formattingLocale,
                minutes
            ))
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
        }
        .buttonStyle(BodyFlowButtonStyle(role: .secondary, isLoading: isSubmitting(minutes)))
        .disabled(model.isSubmitting || model.snoozeDate(for: .minutes(minutes)) == nil)
        .accessibilityIdentifier("routine.snooze.\(minutes)")
    }

    private var isSubmittingCustom: Bool {
        model.isSubmitting && submittedPreset == nil
    }

    private func isSubmitting(_ minutes: Int) -> Bool {
        model.isSubmitting && submittedPreset == minutes
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RoutineCopy.string(key, language: language)
    }
}
