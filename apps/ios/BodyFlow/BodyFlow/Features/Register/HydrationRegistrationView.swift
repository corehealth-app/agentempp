import SwiftUI
import UIKit

@MainActor
enum RegistrationControlSizing {
    static func fittedSize(
        _ view: UIView,
        proposal: ProposedViewSize,
        minimumHeight: CGFloat
    ) -> CGSize {
        let width = proposal.width ?? view.intrinsicContentSize.width
        let fitting = view.sizeThatFits(CGSize(
            width: width,
            height: .greatestFiniteMagnitude
        ))
        let scaledMinimum = max(
            minimumHeight,
            UIFont.preferredFont(forTextStyle: .body).lineHeight
                + BodyFlowSpacing.md
        )
        return CGSize(width: width, height: max(scaledMinimum, fitting.height))
    }
}

@MainActor
enum RegistrationNumericKeyboardAccessory {
    static func install(on field: UITextField, locale: Locale) {
        let done = UIButton(type: .system)
        done.setTitle(title(for: locale), for: .normal)
        done.accessibilityIdentifier = "keyboard.done"
        done.frame = CGRect(x: 0, y: 0, width: 88, height: BodyFlowSpacing.minimumTapTarget)
        done.addAction(UIAction { [weak field] _ in
            field?.resignFirstResponder()
        }, for: .touchUpInside)

        let toolbar = UIToolbar()
        toolbar.items = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(customView: done),
        ]
        toolbar.sizeToFit()
        field.inputAccessoryView = toolbar
    }

    static func update(on field: UITextField, locale: Locale) {
        let toolbar = field.inputAccessoryView as? UIToolbar
        let done = toolbar?.items?.last?.customView as? UIButton
        done?.setTitle(title(for: locale), for: .normal)
    }

    private static func title(for locale: Locale) -> String {
        RegistrationCopy.string(
            "keyboard.done",
            language: BodyFlowPresentationLanguage.resolve(locale)
        )
    }
}

struct HydrationRegistrationView: View {
    let initialOccurredAt: Date
    let isSubmitting: Bool
    let submit: @MainActor (Int?, String, Date) -> Void

    @State private var selectedQuickAmount: Int?
    @State private var customAmount = ""
    @State private var occurredAt: Date
    @Environment(\.locale) private var locale

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
            Text(copy("registration.kind.hydration"))
                .font(BodyFlowTypography.headline)
            Text(copy("registration.hydration.quick"))
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.primaryText)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: BodyFlowSpacing.sm) { quickButtons }
                VStack(spacing: BodyFlowSpacing.sm) { quickButtons }
            }
            Text(copy("registration.hydration.custom"))
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.primaryText)
            RegistrationBoundedTextField(
                placeholder: copy("registration.hydration.placeholder"),
                text: $customAmount,
                keyboardType: .numberPad,
                identifier: "registration.hydration.custom",
                accessibilityLabel: copy("registration.hydration.custom")
            )
                .frame(maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget + 4)
                .onChange(of: customAmount) { _, _ in selectedQuickAmount = nil }
            Text(copy("registration.field.date-time"))
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.primaryText)
            RegistrationBoundedDatePicker(
                value: $occurredAt,
                identifier: "registration.hydration.occurred-at",
                accessibilityLabel: copy("registration.field.date-time")
            )
                .frame(maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget + 4)
            RegistrationBoundedButton(
                title: copy("registration.hydration.submit"),
                isEnabled: !isSubmitting,
                identifier: "registration.hydration.submit"
            ) { submit(selectedQuickAmount, customAmount, occurredAt) }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var quickButtons: some View {
                ForEach([250, 500, 750], id: \.self) { amount in
                    RegistrationBoundedButton(
                        title: "\(amount) ml",
                        isEnabled: !isSubmitting,
                        identifier: "registration.hydration.quick.\(amount)",
                        minimumWidth: BodyFlowSpacing.minimumTapTarget + 4
                    ) { selectedQuickAmount = amount }
                }
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(
            key,
            language: BodyFlowPresentationLanguage.resolve(locale)
        )
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
        field.tintColor = UIColor(BodyFlowColor.color(.brandPrimary))
        field.accessibilityIdentifier = identifier
        field.accessibilityLabel = accessibilityLabel
        if keyboardType == .numberPad || keyboardType == .decimalPad {
            RegistrationNumericKeyboardAccessory.install(
                on: field, locale: context.environment.locale
            )
        }
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed), for: .editingChanged)
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

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        RegistrationControlSizing.fittedSize(
            uiView, proposal: proposal,
            minimumHeight: BodyFlowSpacing.minimumTapTarget + 4
        )
    }

    @MainActor
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
        picker.tintColor = UIColor(BodyFlowColor.color(.brandPrimary))
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
        RegistrationControlSizing.fittedSize(
            uiView, proposal: proposal,
            minimumHeight: BodyFlowSpacing.minimumTapTarget + 4
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        private var value: Binding<Date>
        init(value: Binding<Date>) { self.value = value }
        @objc func changed(_ sender: UIDatePicker) { value.wrappedValue = sender.date }
    }
}

/// The primary look of the registration sheets' UIKit-bridged buttons.
/// `UIButton.Configuration.filled()` paints its title white whatever the
/// tint: on the dark palette the brand fill is a light teal and white text
/// on it is unreadable (iPhone, 2026-10-04: "Propor treino", "Registrar
/// hidratação", "Registrar peso"). Fill and title come from the same token
/// pair as every other primary button.
enum RegistrationBridgedButtonStyle {
    @MainActor
    static func primary() -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = UIColor(BodyFlowColor.color(.brandPrimary))
        configuration.baseForegroundColor = UIColor(BodyFlowColor.color(.onPrimary))
        return configuration
    }
}

struct RegistrationBoundedButton: UIViewRepresentable {
    let title: String
    let isEnabled: Bool
    let identifier: String
    var minimumWidth: CGFloat = 0
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
        var size = RegistrationControlSizing.fittedSize(
            uiView, proposal: proposal,
            minimumHeight: BodyFlowSpacing.minimumTapTarget + 4
        )
        size.width = max(size.width, minimumWidth)
        return size
    }

    @MainActor
    final class Coordinator: NSObject {
        private let action: @MainActor () -> Void
        init(action: @escaping @MainActor () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}
