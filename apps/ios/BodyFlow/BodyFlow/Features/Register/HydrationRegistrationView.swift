import SwiftUI
import UIKit

struct HydrationRegistrationView: View {
    let initialOccurredAt: Date
    let isSubmitting: Bool
    let submit: @MainActor (Int?, String, Date) -> Void

    @State private var selectedQuickAmount: Int?
    @State private var customAmount = ""
    @State private var occurredAt: Date

    init(
        initialOccurredAt: Date,
        isSubmitting: Bool,
        submit: @escaping @MainActor (Int?, String, Date) -> Void
    ) {
        self.initialOccurredAt = initialOccurredAt
        self.isSubmitting = isSubmitting
        self.submit = submit
        _occurredAt = State(initialValue: initialOccurredAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Text("Hidratação")
                .font(BodyFlowTypography.headline)
            Text("Quantidade rápida (ml)")
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.primaryText)
            HStack(spacing: BodyFlowSpacing.sm) {
                ForEach([250, 500, 750], id: \.self) { amount in
                    RegistrationBoundedButton(
                        title: "\(amount) ml",
                        isEnabled: !isSubmitting,
                        identifier: "registration.hydration.quick.\(amount)",
                        minimumWidth: BodyFlowSpacing.minimumTapTarget + 4
                    ) { selectedQuickAmount = amount }
                }
            }
            Text("Quantidade personalizada (ml)")
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.primaryText)
            RegistrationBoundedTextField(
                placeholder: "Quantidade em ml",
                text: $customAmount,
                keyboardType: .numberPad,
                identifier: "registration.hydration.custom",
                accessibilityLabel: "Quantidade personalizada (ml)"
            )
                .frame(
                    maxWidth: .infinity,
                    minHeight: BodyFlowSpacing.minimumTapTarget + 4
                )
                .onChange(of: customAmount) { _, _ in selectedQuickAmount = nil }
            Text("Data e hora")
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.primaryText)
            RegistrationBoundedDatePicker(
                value: $occurredAt,
                identifier: "registration.hydration.occurred-at",
                accessibilityLabel: "Data e hora"
            )
                .frame(
                    maxWidth: .infinity,
                    minHeight: BodyFlowSpacing.minimumTapTarget + 4
                )
            RegistrationBoundedButton(
                title: "Registrar hidratação",
                isEnabled: !isSubmitting,
                identifier: "registration.hydration.submit"
            ) { submit(selectedQuickAmount, customAmount, occurredAt) }
            .frame(maxWidth: .infinity)
        }
    }
}

struct RegistrationBoundedTextField: UIViewRepresentable {
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
        field.accessibilityIdentifier = identifier
        field.accessibilityLabel = accessibilityLabel
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed), for: .editingChanged)
        field.heightAnchor.constraint(
            greaterThanOrEqualToConstant: BodyFlowSpacing.minimumTapTarget + 4
        ).isActive = true
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        if field.text != text { field.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: BodyFlowSpacing.minimumTapTarget + 4)
    }

    final class Coordinator: NSObject {
        private var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        @objc func changed(_ sender: UITextField) { text.wrappedValue = sender.text ?? "" }
    }
}

struct RegistrationBoundedDatePicker: UIViewRepresentable {
    @Binding var value: Date
    let identifier: String
    let accessibilityLabel: String

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .compact
        picker.accessibilityIdentifier = identifier
        picker.accessibilityLabel = accessibilityLabel
        picker.addTarget(context.coordinator, action: #selector(Coordinator.changed), for: .valueChanged)
        picker.heightAnchor.constraint(
            greaterThanOrEqualToConstant: BodyFlowSpacing.minimumTapTarget + 4
        ).isActive = true
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        if picker.date != value { picker.date = value }
    }

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIDatePicker, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: BodyFlowSpacing.minimumTapTarget + 4)
    }

    final class Coordinator: NSObject {
        private var value: Binding<Date>
        init(value: Binding<Date>) { self.value = value }
        @objc func changed(_ sender: UIDatePicker) { value.wrappedValue = sender.date }
    }
}

struct RegistrationBoundedButton: UIViewRepresentable {
    let title: String
    let isEnabled: Bool
    let identifier: String
    var minimumWidth: CGFloat = 0
    let action: @MainActor () -> Void

    func makeUIView(context: Context) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .medium
        configuration.title = title
        let button = UIButton(configuration: configuration)
        button.accessibilityIdentifier = identifier
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        button.heightAnchor.constraint(
            greaterThanOrEqualToConstant: BodyFlowSpacing.minimumTapTarget + 4
        ).isActive = true
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.configuration?.title = title
        button.isEnabled = isEnabled
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        CGSize(
            width: max(proposal.width ?? uiView.intrinsicContentSize.width, minimumWidth),
            height: BodyFlowSpacing.minimumTapTarget + 4
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        private let action: @MainActor () -> Void
        init(action: @escaping @MainActor () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}
