import SwiftUI

@MainActor
enum WorkoutRegistrationSheetModelFactory {
    static func make(dependencies: AppDependencies, context: WorkoutRegistrationReadyContext?,
                     invalidationCenter: FeatureInvalidationCenter) -> WorkoutRegistrationModel? {
        if dependencies.presentsRealAccountIdentity {
            guard let context, context.isActive else { return nil }
            return WorkoutRegistrationModel(registration: context.provider,
                timeProvider: dependencies.timeProvider, keyProvider: dependencies.idempotencyKeyProvider,
                invalidationCenter: invalidationCenter, registrationProtocol: context.registrationProtocol,
                isSessionActive: { context.isActive })
        }
        return WorkoutRegistrationModel(registration: dependencies.registration,
            timeProvider: dependencies.timeProvider, keyProvider: dependencies.idempotencyKeyProvider,
            invalidationCenter: invalidationCenter)
    }
}

/// The model only exists in the ready branch. It is never created globally
/// and replaced later in @State when `/me` finishes.
@MainActor
struct WorkoutRegistrationSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sheet: AppSheet
    let owner: Prompt14SessionOwner
    let dependencies: AppDependencies
    let invalidationCenter: FeatureInvalidationCenter

    var body: some View {
        if let context = owner.workoutRegistrationContext {
            RegistrationSheet(sheet: sheet, dependencies: dependencies,
                invalidationCenter: invalidationCenter, workoutContext: context)
                .id(ObjectIdentifier(context))
        } else {
            NavigationStack {
                VStack(spacing: BodyFlowSpacing.lg) {
                    Text(LocalizedStringKey(owner.isResolvingWorkoutRegistration
                        ? "registration.workout.session-loading"
                        : "registration.workout.session-unavailable"))
                        .multilineTextAlignment(.center)
                    if let binding = owner.workoutRegistrationBinding, binding.canRetryMe {
                        Button("app.retry") {
                            Task { await owner.resolveWorkoutRegistration(binding, retrying: true) }
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("registration.workout.session-retry")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BodyFlowColor.background)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("registration.sheet.close") { dismiss() }
                            .accessibilityIdentifier("registration.workout.session-close")
                    }
                }
            }
        }
    }
}
