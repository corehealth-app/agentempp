import Foundation
import SwiftUI
import UIKit

struct WorkoutProposalPresentation: Equatable, Sendable {
    let registrationID: String
    let status: String
    let workoutType: String?
    let durationMin: Decimal?
    let estimatedKcal: Decimal?
    let intensity: String?
    let expiresAt: APITimestamp

    var allowsPendingActions: Bool { status == "pending" }

    init(registration: RegistrationSnapshot) {
        registrationID = registration.id
        status = registration.status
        expiresAt = registration.expiresAt
        switch registration.proposal {
        case let .workout(proposal):
            workoutType = proposal.workoutType
            durationMin = proposal.durationMin
            estimatedKcal = proposal.estimatedKcal
            intensity = proposal.intensity
        case .meal, .unknown:
            workoutType = nil
            durationMin = nil
            estimatedKcal = nil
            intensity = nil
        }
    }
}

struct WorkoutProposalView: View {
    let proposal: WorkoutProposalPresentation
    let isSubmitting: Bool
    let edit: @MainActor () -> Void
    let confirm: @MainActor () -> Void
    let cancel: @MainActor () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Text(copy("registration.proposal.workout-title"))
                .font(BodyFlowTypography.title)
                .fontWeight(.semibold)
            if let workoutType = proposal.workoutType { Text(workoutType) }
            if let durationMin = proposal.durationMin { Text("\(decimalText(durationMin)) min") }
            if let intensity = proposal.intensity { Text(intensity) }
            if let estimatedKcal = proposal.estimatedKcal {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                    Text(copy("registration.workout.estimated-energy"))
                        .font(BodyFlowTypography.callout)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                    Text("\(decimalText(estimatedKcal)) kcal")
                }
            }
            Text(expiryText)
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)
            if proposal.allowsPendingActions {
                WorkoutProposalActionButton(
                    title: copy("registration.proposal.confirm"),
                    isEnabled: !isSubmitting,
                    identifier: "registration.proposal.confirm",
                    role: .primary,
                    action: confirm
                )
                WorkoutProposalActionButton(
                    title: copy("registration.proposal.edit"),
                    isEnabled: !isSubmitting,
                    identifier: "registration.proposal.edit",
                    role: .secondary,
                    action: edit
                )
                WorkoutProposalActionButton(
                    title: copy("registration.proposal.cancel"),
                    isEnabled: !isSubmitting,
                    identifier: "registration.proposal.cancel",
                    role: .tertiary,
                    action: cancel
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("registration.proposal")
    }

    private func decimalText(_ value: Decimal) -> String {
        value.formatted(.number.locale(language.formattingLocale))
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private var expiryText: String {
        let value = proposal.expiresAt.value.formatted(Date.FormatStyle(
            date: .abbreviated,
            time: .shortened,
            locale: language.formattingLocale
        ))
        return String(
            format: copy("registration.proposal.expires"),
            locale: language.formattingLocale,
            value
        )
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(key, language: language)
    }
}

private struct WorkoutProposalActionButton: UIViewRepresentable {
    let title: String
    let isEnabled: Bool
    let identifier: String
    let role: BodyFlowButtonRole
    let action: @MainActor () -> Void

    func makeUIView(context: Context) -> UIButton {
        var configuration = configuration(for: role)
        configuration.cornerStyle = .medium
        configuration.title = title
        let button = UIButton(configuration: configuration)
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.tintColor = UIColor(BodyFlowColor.color(
            role == .destructive ? .feedbackDestructive : .brandPrimary
        ))
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

    private func configuration(
        for role: BodyFlowButtonRole
    ) -> UIButton.Configuration {
        switch role {
        case .primary: .filled()
        case .secondary: .bordered()
        case .tertiary: .plain()
        case .destructive: .bordered()
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        private let action: @MainActor () -> Void

        init(action: @escaping @MainActor () -> Void) { self.action = action }

        @objc func tapped() { action() }
    }
}
