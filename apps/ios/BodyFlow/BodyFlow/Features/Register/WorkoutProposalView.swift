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

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Text("Proposta de treino")
                .font(BodyFlowTypography.title)
                .fontWeight(.semibold)
            if let workoutType = proposal.workoutType { Text(workoutType) }
            if let durationMin = proposal.durationMin { Text("\(decimalText(durationMin)) min") }
            if let intensity = proposal.intensity { Text(intensity) }
            if let estimatedKcal = proposal.estimatedKcal { Text("\(decimalText(estimatedKcal)) kcal") }
            Text("Expira em \(proposal.expiresAt.value.formatted(date: .abbreviated, time: .shortened))")
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)
            if proposal.allowsPendingActions {
                WorkoutProposalActionButton(
                    title: "Editar",
                    isEnabled: !isSubmitting,
                    identifier: "registration.proposal.edit",
                    action: edit
                )
                WorkoutProposalActionButton(
                    title: "Confirmar",
                    isEnabled: !isSubmitting,
                    identifier: "registration.proposal.confirm",
                    action: confirm
                )
                WorkoutProposalActionButton(
                    title: "Cancelar proposta",
                    isEnabled: !isSubmitting,
                    identifier: "registration.proposal.cancel",
                    action: cancel
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("registration.proposal")
    }

    private func decimalText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}

private struct WorkoutProposalActionButton: UIViewRepresentable {
    let title: String
    let isEnabled: Bool
    let identifier: String
    let action: @MainActor () -> Void

    func makeUIView(context: Context) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .medium
        configuration.title = title
        let button = UIButton(configuration: configuration)
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
        CGSize(
            width: proposal.width ?? uiView.intrinsicContentSize.width,
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
