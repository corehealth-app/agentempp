import SwiftUI

@MainActor
struct RoutineSnoozeView: View {
    let model: RoutineActionModel
    let submit: @MainActor (RoutineSnoozeSelection) -> Void
    @State private var customTime: Date

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
            Text("Adiar ocorrência")
                .font(BodyFlowTypography.title)
                .fontWeight(.semibold)

            presetButton(15)
            presetButton(30)
            presetButton(60)

            DatePicker(
                "Horário personalizado",
                selection: $customTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
            .contentShape(Rectangle())
            .accessibilityIdentifier("routine.snooze.custom-time")

            Button {
                submit(.custom(customTime))
            } label: {
                Text("Usar horário personalizado")
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
                    .contentShape(Rectangle())
            }
            .disabled(model.isSubmitting || model.snoozeDate(for: .custom(customTime)) == nil)
            .accessibilityIdentifier("routine.snooze.custom")
        }
        .padding(BodyFlowSpacing.lg)
    }

    private func presetButton(_ minutes: Int) -> some View {
        Button {
            submit(.minutes(minutes))
        } label: {
            Text("\(minutes) minutos")
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
                .contentShape(Rectangle())
        }
        .disabled(model.isSubmitting || model.snoozeDate(for: .minutes(minutes)) == nil)
        .accessibilityIdentifier("routine.snooze.\(minutes)")
    }
}
