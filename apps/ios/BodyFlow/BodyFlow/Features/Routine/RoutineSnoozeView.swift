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
            .accessibilityIdentifier("routine.snooze.custom-time")

            Button("Usar horário personalizado") {
                submit(.custom(customTime))
            }
            .disabled(model.isSubmitting || model.snoozeDate(for: .custom(customTime)) == nil)
            .accessibilityIdentifier("routine.snooze.custom")
            .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
        }
        .padding(BodyFlowSpacing.lg)
    }

    private func presetButton(_ minutes: Int) -> some View {
        Button("\(minutes) minutos") {
            submit(.minutes(minutes))
        }
        .disabled(model.isSubmitting || model.snoozeDate(for: .minutes(minutes)) == nil)
        .accessibilityIdentifier("routine.snooze.\(minutes)")
        .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
    }
}
