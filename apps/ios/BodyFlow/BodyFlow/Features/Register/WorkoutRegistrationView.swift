import SwiftUI
import UIKit

/// What the workout form opens with. A proposal being edited always shows
/// its own values. A new proposal on a real account starts empty, so nothing
/// the person did not type can be proposed; only the local demonstration
/// keeps its sample workout.
struct WorkoutRegistrationFormSeed: Equatable, Sendable {
    let workoutType: String
    let duration: String

    init(
        initialProposal: WorkoutProposalRequest?,
        presentsLocalDemonstration: Bool
    ) {
        if let initialProposal {
            workoutType = initialProposal.workoutType
            duration = String(initialProposal.durationMin)
        } else if presentsLocalDemonstration {
            workoutType = "musculacao"
            duration = "47"
        } else {
            workoutType = ""
            duration = ""
        }
    }

    /// What the server accepts, so the action is offered only for a proposal
    /// it will take: a type of 1 to 80 characters once trimmed (counted as the
    /// server counts them) and a whole number of minutes from 1 to 1440.
    static let workoutTypeLengthLimit = 80
    static let durationRange = 1...1_440

    static func canPropose(workoutType: String, duration: String) -> Bool {
        let type = workoutType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !type.isEmpty, type.utf16.count <= workoutTypeLengthLimit,
              let minutes = Int(duration) else { return false }
        return durationRange.contains(minutes)
    }

    var canPropose: Bool {
        Self.canPropose(workoutType: workoutType, duration: duration)
    }
}

struct WorkoutRegistrationView: View {
    private let submit: @MainActor (WorkoutProposalRequest) -> Void
    private let actionTitle: String
    private let isSubmitting: Bool
    @State private var workoutType: String
    @State private var duration: String
    @State private var intensity: WorkoutIntensity
    @State private var performedAt: Date
    @Environment(\.locale) private var locale

    init(
        initialPerformedAt: Date,
        initialProposal: WorkoutProposalRequest? = nil,
        presentsLocalDemonstration: Bool = false,
        actionTitle: String = "Propor treino",
        isSubmitting: Bool,
        submit: @escaping @MainActor (WorkoutProposalRequest) -> Void
    ) {
        let seed = WorkoutRegistrationFormSeed(
            initialProposal: initialProposal,
            presentsLocalDemonstration: presentsLocalDemonstration
        )
        _workoutType = State(initialValue: seed.workoutType)
        _duration = State(initialValue: seed.duration)
        _intensity = State(initialValue: initialProposal?.intensity ?? .moderate)
        _performedAt = State(initialValue: initialProposal?.performedAt?.value ?? initialPerformedAt)
        self.actionTitle = actionTitle
        self.isSubmitting = isSubmitting
        self.submit = submit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Text(copy("registration.kind.workout"))
                .font(BodyFlowTypography.headline)
            WorkoutFieldLabel(copy("registration.workout.type"))
            WorkoutTextField(
                placeholder: copy("registration.workout.type"), text: $workoutType,
                keyboardType: .default,
                identifier: "registration.workout.type",
                accessibilityLabel: copy("registration.workout.type")
            )
            WorkoutFieldLabel(copy("registration.workout.duration"))
            WorkoutTextField(
                placeholder: copy("registration.workout.duration"), text: $duration,
                keyboardType: .numberPad,
                identifier: "registration.workout.duration",
                accessibilityLabel: copy("registration.workout.duration")
            )
            WorkoutFieldLabel(copy("registration.workout.intensity"))
            WorkoutIntensityPicker(
                intensity: $intensity,
                titles: WorkoutIntensity.allCases.map {
                    RegistrationCopy.workoutIntensityTitle($0, language: language)
                },
                accessibilityLabel: copy("registration.workout.intensity")
            )
            WorkoutFieldLabel(copy("registration.workout.performed-at"))
            WorkoutDatePicker(
                performedAt: $performedAt,
                accessibilityLabel: copy("registration.workout.performed-at")
            )
            WorkoutActionButton(
                title: actionTitle == "Propor treino"
                    ? copy("registration.workout.propose")
                    : copy("registration.editor.save"),
                isEnabled: !isSubmitting && isValid,
                identifier: "registration.workout.propose",
                action: submitProposal
            )
            // SwiftUI writes the environment's enabled state into a bridged
            // UIControl after `updateUIView`, so an incomplete form has to be
            // declared here for the button to be disabled at all.
            .disabled(isSubmitting || !isValid)
        }
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(
            key,
            language: language
        )
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private var isValid: Bool {
        WorkoutRegistrationFormSeed.canPropose(workoutType: workoutType, duration: duration)
    }

    private func submitProposal() {
        guard isValid, let durationMin = Int(duration) else { return }
        submit(WorkoutProposalRequest(
            workoutType: workoutType, durationMin: durationMin,
            intensity: intensity, performedAt: APITimestamp(value: performedAt)
        ))
    }
}

private struct WorkoutFieldLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(BodyFlowTypography.body)
            .foregroundStyle(BodyFlowColor.primaryText)
    }
}

private struct WorkoutActionButton: UIViewRepresentable {
    let title: String
    let isEnabled: Bool
    let identifier: String
    let action: @MainActor () -> Void

    func makeUIView(context: Context) -> UIButton {
        var configuration = RegistrationBridgedButtonStyle.primary()
        configuration.cornerStyle = .medium
        configuration.title = title
        let button = UIButton(configuration: configuration)
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.tintColor = UIColor(BodyFlowColor.color(.brandPrimary))
        button.accessibilityIdentifier = identifier
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.tapped),
            for: .touchUpInside
        )
        button.heightAnchor.constraint(
            greaterThanOrEqualToConstant: BodyFlowSpacing.minimumTapTarget + 4
        ).isActive = true
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.configuration?.title = title
        button.isEnabled = isEnabled
        context.coordinator.isEnabled = isEnabled
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UIButton,
        context: Context
    ) -> CGSize? {
        RegistrationControlSizing.fittedSize(
            uiView,
            proposal: proposal,
            minimumHeight: BodyFlowSpacing.minimumTapTarget + 4
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        private let action: @MainActor () -> Void
        /// Kept current by `updateUIView`, so a touch that still arrives
        /// while a request is in flight does not propose twice.
        var isEnabled = true

        init(action: @escaping @MainActor () -> Void) { self.action = action }

        @objc func tapped() {
            guard isEnabled else { return }
            action()
        }
    }
}

private struct WorkoutIntensityPicker: UIViewRepresentable {
    @Binding var intensity: WorkoutIntensity
    let titles: [String]
    let accessibilityLabel: String

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: titles)
        control.selectedSegmentTintColor = UIColor(BodyFlowColor.color(.brandPrimary))
        control.accessibilityIdentifier = "registration.workout.intensity"
        control.accessibilityLabel = accessibilityLabel
        control.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged),
            for: .valueChanged
        )
        control.heightAnchor.constraint(
            greaterThanOrEqualToConstant: BodyFlowSpacing.minimumTapTarget + 4
        ).isActive = true
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        for (index, title) in titles.enumerated() {
            control.setTitle(title, forSegmentAt: index)
        }
        control.selectedSegmentIndex = WorkoutIntensity.allCases.firstIndex(of: intensity) ?? 0
        control.accessibilityLabel = accessibilityLabel
        control.setTitleTextAttributes(
            [.font: UIFont.preferredFont(forTextStyle: .body)],
            for: .normal
        )
        control.setTitleTextAttributes(
            [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor(BodyFlowColor.color(.onPrimary)),
            ],
            for: .selected
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(intensity: $intensity) }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UISegmentedControl,
        context: Context
    ) -> CGSize? {
        RegistrationControlSizing.fittedSize(
            uiView,
            proposal: proposal,
            minimumHeight: BodyFlowSpacing.minimumTapTarget + 4
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        private var intensity: Binding<WorkoutIntensity>

        init(intensity: Binding<WorkoutIntensity>) { self.intensity = intensity }

        @objc func valueChanged(_ sender: UISegmentedControl) {
            guard WorkoutIntensity.allCases.indices.contains(sender.selectedSegmentIndex) else {
                return
            }
            intensity.wrappedValue = WorkoutIntensity.allCases[sender.selectedSegmentIndex]
        }
    }
}

private struct WorkoutDatePicker: UIViewRepresentable {
    @Binding var performedAt: Date
    let accessibilityLabel: String

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .compact
        picker.tintColor = UIColor(BodyFlowColor.color(.brandPrimary))
        picker.accessibilityIdentifier = "registration.workout.performed-at"
        picker.accessibilityLabel = accessibilityLabel
        picker.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged),
            for: .valueChanged
        )
        picker.heightAnchor.constraint(
            greaterThanOrEqualToConstant: BodyFlowSpacing.minimumTapTarget + 4
        ).isActive = true
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        if picker.date != performedAt { picker.date = performedAt }
        picker.accessibilityLabel = accessibilityLabel
    }

    func makeCoordinator() -> Coordinator { Coordinator(performedAt: $performedAt) }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UIDatePicker,
        context: Context
    ) -> CGSize? {
        RegistrationControlSizing.fittedSize(
            uiView,
            proposal: proposal,
            minimumHeight: BodyFlowSpacing.minimumTapTarget + 4
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        private var performedAt: Binding<Date>

        init(performedAt: Binding<Date>) { self.performedAt = performedAt }

        @objc func valueChanged(_ sender: UIDatePicker) {
            performedAt.wrappedValue = sender.date
        }
    }
}

private struct WorkoutTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let keyboardType: UIKeyboardType
    let identifier: String
    let accessibilityLabel: String

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.borderStyle = .roundedRect
        field.placeholder = placeholder
        field.keyboardType = keyboardType
        field.adjustsFontForContentSizeCategory = true
        field.font = .preferredFont(forTextStyle: .body)
        field.tintColor = UIColor(BodyFlowColor.color(.brandPrimary))
        field.accessibilityIdentifier = identifier
        field.accessibilityLabel = accessibilityLabel
        if keyboardType == .numberPad || keyboardType == .decimalPad {
            RegistrationNumericKeyboardAccessory.install(
                on: field, locale: context.environment.locale
            )
        }
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged),
            for: .editingChanged
        )
        field.heightAnchor.constraint(
            greaterThanOrEqualToConstant: BodyFlowSpacing.minimumTapTarget + 4
        ).isActive = true
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        if field.text != text { field.text = text }
        RegistrationNumericKeyboardAccessory.update(
            on: field, locale: context.environment.locale
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextField,
        context: Context
    ) -> CGSize? {
        RegistrationControlSizing.fittedSize(
            uiView,
            proposal: proposal,
            minimumHeight: BodyFlowSpacing.minimumTapTarget + 4
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        private var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        @objc func valueChanged(_ sender: UITextField) {
            text.wrappedValue = sender.text ?? ""
        }
    }
}
