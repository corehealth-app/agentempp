import SwiftUI

@MainActor
struct RegistrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let sheet: AppSheet
    let dependencies: AppDependencies
    let invalidationCenter: FeatureInvalidationCenter
    @State private var mealModel: MealRegistrationModel
    @State private var workoutModel: WorkoutRegistrationModel
    @State private var hydrationModel: HydrationRegistrationModel
    @State private var weightModel: WeightRegistrationModel
    @State private var taskCoordinator = RegistrationSheetTaskCoordinator()

    init(
        sheet: AppSheet,
        dependencies: AppDependencies,
        invalidationCenter: FeatureInvalidationCenter
    ) {
        self.sheet = sheet
        self.dependencies = dependencies
        self.invalidationCenter = invalidationCenter
        _mealModel = State(initialValue: MealRegistrationModel(
            detector: dependencies.mealDetection,
            registration: dependencies.registration,
            timeProvider: dependencies.timeProvider,
            keyProvider: dependencies.idempotencyKeyProvider,
            invalidationCenter: invalidationCenter,
            demonstrationTextLimit: Self.demonstrationTextLimit
        ))
        _workoutModel = State(initialValue: WorkoutRegistrationModel(
            registration: dependencies.registration,
            timeProvider: dependencies.timeProvider,
            keyProvider: dependencies.idempotencyKeyProvider,
            invalidationCenter: invalidationCenter
        ))
        _hydrationModel = State(initialValue: HydrationRegistrationModel(
            recording: dependencies.hydration,
            timeProvider: dependencies.timeProvider,
            keyProvider: dependencies.idempotencyKeyProvider,
            invalidationCenter: invalidationCenter
        ))
        _weightModel = State(initialValue: WeightRegistrationModel(
            recording: dependencies.weight,
            timeProvider: dependencies.timeProvider,
            keyProvider: dependencies.idempotencyKeyProvider,
            invalidationCenter: invalidationCenter
        ))
    }

    private var kind: RegistrationKind {
        switch sheet {
        case let .registration(kind):
            kind
        }
    }

    private static var demonstrationTextLimit: ClosedRange<Int>? {
        #if DEBUG
        1...1_000
        #else
        nil
        #endif
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BodyFlowColor.background.ignoresSafeArea()

                if kind == .meal {
                    MealRegistrationContent(
                        model: mealModel,
                        submit: { source in
                            perform(.capture(source)) {
                                await mealModel.submit(source)
                            }
                        },
                        operationAction: { action in
                            perform(.operationAction(action)) {
                                await RegistrationOperationCoordinator(
                                    model: mealModel
                                ).perform(action)
                            }
                        },
                        saveEdit: { edit in
                            perform(.edit(edit)) { await mealModel.saveEdit(edit) }
                        },
                        confirm: {
                            perform(.confirm) { await mealModel.confirm() }
                        },
                        cancel: {
                            perform(.cancel) { await mealModel.cancel() }
                        }
                    )
                        .accessibilityIdentifier(sheet.id)
                } else if kind == .training {
                    WorkoutRegistrationContent(
                        model: workoutModel,
                        propose: { proposal in
                            perform(.workoutProposal(proposal)) {
                                await workoutModel.submit(proposal)
                            }
                        },
                        saveEdit: { proposal in
                            perform(.workoutEdit(proposal)) {
                                await workoutModel.saveEdit(proposal)
                            }
                        },
                        retry: {
                            perform(.operationAction(.retry)) {
                                await workoutModel.retry()
                            }
                        },
                        confirm: { perform(.confirm) { await workoutModel.confirm() } },
                        cancel: { perform(.cancel) { await workoutModel.cancel() } }
                    )
                    .accessibilityIdentifier(sheet.id)
                } else if kind == .hydration {
                    HydrationRegistrationContent(
                        model: hydrationModel,
                        submit: { quickAmount, customAmount, occurredAt in
                            perform(.hydration(
                                amountML: quickAmount,
                                customAmount: customAmount,
                                occurredAt: occurredAt
                            )) {
                                if let quickAmount {
                                    await hydrationModel.submitQuick(
                                        quickAmount,
                                        occurredAt: occurredAt
                                    )
                                } else {
                                    await hydrationModel.submitCustom(
                                        customAmount,
                                        occurredAt: occurredAt
                                    )
                                }
                            }
                        },
                        retry: { perform(.operationAction(.retry)) { await hydrationModel.retry() } }
                    )
                    .accessibilityIdentifier(sheet.id)
                } else if kind == .weight {
                    WeightRegistrationContent(
                        model: weightModel,
                        submit: { value, recordedAt in
                            let parsedValue = Double(value.replacingOccurrences(of: ",", with: "."))
                            perform(.weight(value: parsedValue, recordedAt: recordedAt)) {
                                await weightModel.submit(
                                    weightKG: parsedValue ?? .nan,
                                    recordedAt: recordedAt
                                )
                            }
                        },
                        retry: { perform(.operationAction(.retry)) { await weightModel.retry() } }
                    )
                    .accessibilityIdentifier(sheet.id)
                } else {
                    GeometryReader { geometry in
                        ScrollView {
                            VStack(spacing: BodyFlowSpacing.lg) {
                                Image(systemName: kind.systemImage)
                                    .font(BodyFlowTypography.largeTitle)
                                    .foregroundStyle(BodyFlowColor.accent)
                                    .accessibilityHidden(true)

                                Text(kind.title)
                                    .font(BodyFlowTypography.title)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BodyFlowColor.primaryText)

                                Text(AppFixtures.registration.disclaimer)
                                    .font(BodyFlowTypography.body)
                                    .foregroundStyle(BodyFlowColor.secondaryText)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(BodyFlowSpacing.lg)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: geometry.size.height
                            )
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier(sheet.id)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                }
            }
            .navigationTitle("Demonstração")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        discardSheet()
                    } label: {
                        Image(systemName: "xmark")
                            .font(BodyFlowTypography.headline)
                            .frame(
                                width: BodyFlowSpacing.minimumTapTarget,
                                height: BodyFlowSpacing.minimumTapTarget
                            )
                    }
                    .accessibilityLabel("Fechar")
                    .accessibilityIdentifier("sheet.fechar")
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                }
            }
        }
        .presentationDetents(
            Self.presentationDetents(for: dynamicTypeSize)
        )
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
        .onDisappear {
            discardOperation()
        }
    }

    private func perform(
        _ intent: RegistrationSheetOperationIntent,
        _ operation: @escaping @MainActor () async -> Void
    ) {
        taskCoordinator.perform(intent, operation: operation)
    }

    private func discardSheet() {
        discardOperation()
        dismiss()
    }

    private func discardOperation() {
        taskCoordinator.discard()
        mealModel.discardSheet()
        workoutModel.discardSheet()
        hydrationModel.discardSheet()
        weightModel.discardSheet()
    }

    static func presentationDetents(
        for dynamicTypeSize: DynamicTypeSize
    ) -> Set<PresentationDetent> {
        dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium]
    }
}

@MainActor
private struct HydrationRegistrationContent: View {
    let model: HydrationRegistrationModel
    let submit: @MainActor (Int?, String, Date) -> Void
    let retry: @MainActor () -> Void
    @AccessibilityFocusState private var operationFocus: RegistrationAccessibilityFocusTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                HydrationRegistrationView(
                    initialOccurredAt: model.initialOccurredAt,
                    isSubmitting: model.isSubmitting,
                    submit: submit
                )
                OperationResultSummary(
                    state: model.mutationState,
                    captureError: model.captureError,
                    validationMessage: "Informe um valor inteiro entre 1 e 5.000 ml.",
                    successMessage: "Hidratação registrada.",
                    retry: retry
                )
                .accessibilityFocused($operationFocus, equals: .operationSummary)
            }
            .padding(BodyFlowSpacing.lg)
        }
        .onChange(of: model.accessibilityFocusTarget) { _, target in
            guard let target else { return }
            operationFocus = target
            model.consumeAccessibilityFocus()
        }
    }
}

@MainActor
private struct WeightRegistrationContent: View {
    let model: WeightRegistrationModel
    let submit: @MainActor (String, Date) -> Void
    let retry: @MainActor () -> Void
    @AccessibilityFocusState private var operationFocus: RegistrationAccessibilityFocusTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                WeightRegistrationView(
                    initialRecordedAt: model.initialRecordedAt,
                    isSubmitting: model.isSubmitting,
                    submit: submit
                )
                OperationResultSummary(
                    state: model.mutationState,
                    captureError: model.captureError,
                    validationMessage: "Informe um valor entre 30 e 300 kg.",
                    successMessage: nil,
                    demoReceipt: model.receipt,
                    retry: retry
                )
                .accessibilityFocused($operationFocus, equals: .operationSummary)
            }
            .padding(BodyFlowSpacing.lg)
        }
        .onChange(of: model.accessibilityFocusTarget) { _, target in
            guard let target else { return }
            operationFocus = target
            model.consumeAccessibilityFocus()
        }
    }
}

private struct OperationResultSummary<Attempt: Equatable & Sendable, Receipt: Equatable & Sendable>: View {
    let state: FeatureMutationState<Attempt, Receipt>
    let captureError: BodyFlowCapabilityError?
    let validationMessage: String
    let successMessage: String?
    var demoReceipt: WeightDemoReceipt? = nil
    let retry: @MainActor () -> Void

    var body: some View {
        Group {
            if let message {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text(message)
                    if retryIsAvailable {
                        Button("Tentar novamente", action: retry)
                            .buttonStyle(.bordered)
                            .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                            .accessibilityIdentifier("registration.mutation.retry")
                    }
                }
                .font(BodyFlowTypography.callout)
                .foregroundStyle(BodyFlowColor.secondaryText)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(demoReceipt == nil ? "registration.operation.summary" : "registration.weight.demo-receipt")
    }

    private var message: String? {
        if let demoReceipt { return demoReceipt.label }
        if captureError == .invalidInput { return validationMessage }
        switch state {
        case .unavailable: return "Indisponível nesta versão"
        case .succeeded: return successMessage
        case .failed: return "Não foi possível concluir. Tente novamente."
        case .idle, .submitting: return nil
        }
    }

    private var retryIsAvailable: Bool {
        if case .failed = state { true } else { false }
    }
}

@MainActor
private struct WorkoutRegistrationContent: View {
    let model: WorkoutRegistrationModel
    let propose: @MainActor (WorkoutProposalRequest) -> Void
    let saveEdit: @MainActor (WorkoutProposalRequest) -> Void
    let retry: @MainActor () -> Void
    let confirm: @MainActor () -> Void
    let cancel: @MainActor () -> Void
    @State private var showingEditor = false
    @AccessibilityFocusState private var operationFocus: RegistrationAccessibilityFocusTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                content
                RegistrationOperationSummary(
                    state: model.mutationState,
                    captureError: model.captureError
                ) { action in
                    if action == .retry { retry() } else { model.startNewProposal() }
                }
                .accessibilityFocused($operationFocus, equals: .operationSummary)
            }
            .padding(BodyFlowSpacing.lg)
        }
        .navigationDestination(isPresented: $showingEditor) {
            if let draft = model.pendingDraft {
                WorkoutRegistrationView(
                    initialPerformedAt: model.initialPerformedAt,
                    initialProposal: draft,
                    actionTitle: "Salvar", isSubmitting: model.isSubmitting
                ) { edit in
                    showingEditor = false
                    saveEdit(edit)
                }
                .navigationTitle("Editar proposta")
            }
        }
        .onChange(of: model.accessibilityFocusTarget) { _, target in
            guard let target else { return }
            operationFocus = target
            model.consumeAccessibilityFocus()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let proposal = model.currentProposal {
            WorkoutProposalView(
                proposal: WorkoutProposalPresentation(registration: proposal),
                isSubmitting: model.isSubmitting,
                edit: { showingEditor = true }, confirm: confirm, cancel: cancel
            )
        } else if model.phase == .confirmed {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                Text("Treino confirmado").font(BodyFlowTypography.title).fontWeight(.semibold)
                Text("O registro confirmado não pode ser editado nesta tela.")
                    .foregroundStyle(BodyFlowColor.secondaryText)
            }
            .accessibilityIdentifier("registration.proposal.confirmed")
        } else {
            WorkoutRegistrationView(
                initialPerformedAt: model.initialPerformedAt,
                isSubmitting: model.isSubmitting, submit: propose
            )
        }
    }

}


#Preview("Registro · Refeição") {
    let dependencies = AppDependencies.scaffold()
    RegistrationSheet(
        sheet: .registration(.meal),
        dependencies: dependencies,
        invalidationCenter: FeatureInvalidationCenter()
    )
}

@MainActor
private struct MealRegistrationContent: View {
    let model: MealRegistrationModel
    let submit: @MainActor (MealCaptureSource) -> Void
    let operationAction: @MainActor (RegistrationOperationAction) -> Void
    let saveEdit: @MainActor (MealProposalRequest) -> Void
    let confirm: @MainActor () -> Void
    let cancel: @MainActor () -> Void
    @State private var choice: MealCaptureChoice?
    @State private var textDraft = "Refeição de demonstração"
    @State private var showingEditor = false
    @AccessibilityFocusState private var operationFocus: RegistrationAccessibilityFocusTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                content
                RegistrationOperationSummary(
                    state: model.mutationState,
                    captureError: model.captureError
                ) { action in
                    operationAction(action)
                }
                .accessibilityFocused($operationFocus, equals: .operationSummary)
            }
            .padding(BodyFlowSpacing.lg)
        }
        .navigationDestination(isPresented: $showingEditor) {
            if let proposal = model.currentProposal {
                MealProposalEditorView(
                    registration: proposal,
                    initialConsumedAt: model.initialConsumedAt,
                    isSubmitting: model.isSubmitting
                ) { edit in
                    showingEditor = false
                    saveEdit(edit)
                }
            }
        }
        .onChange(of: model.accessibilityFocusTarget) { _, target in
            guard let target else { return }
            operationFocus = target
            model.consumeAccessibilityFocus()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let proposal = model.currentProposal {
            MealProposalView(
                proposal: MealProposalPresentation(registration: proposal),
                isSubmitting: model.isSubmitting,
                edit: { showingEditor = true },
                confirm: confirm,
                cancel: cancel
            )
        } else if model.phase == .confirmed {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                Text("Refeição confirmada")
                    .font(BodyFlowTypography.title)
                    .fontWeight(.semibold)
                Text("O registro confirmado não pode ser editado nesta tela.")
                    .foregroundStyle(BodyFlowColor.secondaryText)
            }
            .accessibilityIdentifier("registration.proposal.confirmed")
        } else {
            captureContent
        }
    }

    @ViewBuilder
    private var captureContent: some View {
        if let choice {
            switch choice {
            case .text:
                MealTextDraftView(
                    draft: $textDraft,
                    isSubmitting: model.isSubmitting
                ) {
                    submit(.text(textDraft))
                }
            case .photo:
                MealDemonstrationSourceView(
                    choice: .photo,
                    isSubmitting: model.isSubmitting
                ) {
                    submit(.photoDemonstration(
                        label: "Amostra fotográfica local"
                    ))
                }
            case .audio:
                MealDemonstrationSourceView(
                    choice: .audio,
                    isSubmitting: model.isSubmitting
                ) {
                    submit(.audioDemonstration(
                        label: "Amostra de áudio local"
                    ))
                }
            }
        } else {
            MealCaptureSourceView { selected in
                choice = selected
            }
        }
    }
}
