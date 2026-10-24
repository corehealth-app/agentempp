import SwiftUI

@MainActor
struct RegistrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    let sheet: AppSheet
    let dependencies: AppDependencies
    let invalidationCenter: FeatureInvalidationCenter
    private let workoutContext: WorkoutRegistrationReadyContext?
    @State private var mealModel: MealRegistrationModel
    @State private var mealDraftModel: MealDraftModel
    @State private var mealRecorder: MealAudioRecorder
    @State private var workoutModel: WorkoutRegistrationModel?
    @State private var hydrationModel: HydrationRegistrationModel
    @State private var weightModel: WeightRegistrationModel
    @State private var taskCoordinator = RegistrationSheetTaskCoordinator()
    @State private var presentation = PerformeOperationPresentation()

    init(
        sheet: AppSheet,
        dependencies: AppDependencies,
        invalidationCenter: FeatureInvalidationCenter,
        workoutContext: WorkoutRegistrationReadyContext? = nil
    ) {
        self.sheet = sheet
        self.dependencies = dependencies
        self.invalidationCenter = invalidationCenter
        self.workoutContext = workoutContext
        _mealModel = State(initialValue: MealRegistrationModel(
            detector: dependencies.mealDetection,
            registration: dependencies.registration,
            timeProvider: dependencies.timeProvider,
            keyProvider: dependencies.idempotencyKeyProvider,
            invalidationCenter: invalidationCenter,
            demonstrationTextLimit: Self.demonstrationTextLimit,
            selectedMealType: sheet.selectedMealType
        ))
        let staging = dependencies.mealCapture?.staging ?? MediaStagingStore()
        _mealDraftModel = State(initialValue: MealDraftModel(
            media: dependencies.mealCapture?.media,
            drafts: dependencies.mealCapture?.drafts,
            uploader: dependencies.mealCapture?.uploader,
            staging: staging,
            timeProvider: dependencies.timeProvider,
            keyProvider: dependencies.idempotencyKeyProvider,
            selectedMealType: sheet.selectedMealType
        ))
        _mealRecorder = State(initialValue: MealAudioRecorder(staging: staging))
        _workoutModel = State(initialValue: WorkoutRegistrationSheetModelFactory.make(
            dependencies: dependencies, context: workoutContext,
            invalidationCenter: invalidationCenter))
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
        case let .registration(kind, _, _):
            kind
        }
    }

    /// The way of telling the meal already chosen on the Register screen.
    private var mealEntry: MealCaptureEntry? {
        switch sheet {
        case let .registration(kind, entry, _):
            kind == .meal ? entry : nil
        }
    }

    /// The local demonstration keeps its fixture copy; a real account sees
    /// the server-backed flow described as such.
    private var presentsLocalDemonstration: Bool {
        !dependencies.presentsRealAccountIdentity
    }

    private static var demonstrationTextLimit: ClosedRange<Int>? {
        #if DEBUG
        1...1_000
        #else
        nil
        #endif
    }

    /// The one decision about the wait of a meal analysis, read by the
    /// loading block and by the brand mark alike, so the two can never
    /// disagree: where the block is on screen the mark does not spin, and
    /// everywhere else the mark keeps its own indicator.
    ///
    /// `nil` — no block on screen — whenever a proposal is shown (confirm,
    /// save an edit and cancel a proposal keep the mark's indicator: it is
    /// the only one they have) or the meal is confirmed, and for everything
    /// that is not a meal captured through the live capture.
    static func mealAnalysisStage(
        kind: RegistrationKind,
        hasLiveCapture: Bool,
        hasProposal: Bool,
        registrationPhase: MealRegistrationPhase,
        draftPhase: MealDraftPhase,
        channel: MealSourceChannel?,
        isSubmitting: Bool
    ) -> MealAnalysisStage? {
        guard kind == .meal, hasLiveCapture, !hasProposal,
              registrationPhase != .confirmed else { return nil }
        return MealAnalysisStage.resolve(
            phase: draftPhase,
            channel: channel,
            isProposing: isSubmitting
        )
    }

    var body: some View {
        // Calculated once per evaluation and handed to both readers.
        let liveCapture = liveCapture
        let analysisStage = Self.mealAnalysisStage(
            kind: kind,
            hasLiveCapture: liveCapture != nil,
            hasProposal: mealModel.currentProposal != nil,
            registrationPhase: mealModel.phase,
            draftPhase: mealDraftModel.phase,
            channel: mealDraftModel.channel,
            isSubmitting: mealModel.isSubmitting
        )
        return NavigationStack {
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
                        },
                        presentsLocalDemonstration: presentsLocalDemonstration,
                        liveCapture: liveCapture,
                        entry: mealEntry,
                        analysisStage: analysisStage
                    )
                        .accessibilityIdentifier(sheet.id)
                } else if kind == .training {
                    if let workoutModel {
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
                        reviewCurrent: {
                            perform(.operationAction(.reviewCurrent)) {
                                await workoutModel.reviewCurrentVersion()
                            }
                        },
                        confirm: { perform(.confirm) { await workoutModel.confirm() } },
                        cancel: { perform(.cancel) { await workoutModel.cancel() } },
                        presentsLocalDemonstration: presentsLocalDemonstration,
                        strengthQuestion: WorkoutStrengthQuestionFactory.configuration(
                            workoutID: workoutModel.confirmedRegistration?.confirmedWorkoutID,
                            dependencies: dependencies, context: workoutContext,
                            invalidationCenter: invalidationCenter)
                    )
                    .accessibilityIdentifier(sheet.id)
                    } else {
                        Text("registration.workout.session-unavailable")
                            .multilineTextAlignment(.center).padding()
                    }
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

                                Text(presentsLocalDemonstration
                                    ? AppFixtures.registration.disclaimer
                                    : copy("registration.sheet.live-notice"))
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
            .navigationTitle(copy(presentsLocalDemonstration
                ? "registration.sheet.title"
                : "registration.sheet.title.live"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    RegistrationBrandMark(
                        state: presentation.state,
                        label: copy("tab.register"),
                        status: brandStatus,
                        analysisStage: analysisStage
                    )
                }
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
                    .accessibilityLabel(copy("registration.sheet.close"))
                    .accessibilityIdentifier("sheet.fechar")
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                }
            }
        }
        .environment(\.bodyFlowResultFeedbackEnabled, false)
        .sensoryFeedback(trigger: presentation.feedback) { _, value in
            value?.result.feedback
        }
        .task(id: presentation.successToken) {
            guard let token = presentation.successToken else { return }
            do {
                try await Task.sleep(for: .seconds(2))
                try Task.checkCancellation()
                presentation.expireSuccess(for: token)
            } catch { /* Sheet/operation changed. Persistent receipt stays visible. */ }
        }
        .presentationDetents(
            Self.presentationDetents(for: dynamicTypeSize)
        )
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
        .onChange(of: mealDraftModel.phase) { _, phase in
            guard kind == .meal else { return }
            presentation.capturePhaseChanged(phase)
        }
        .onDisappear {
            discardOperation()
        }
    }

    private func perform(
        _ intent: RegistrationSheetOperationIntent,
        _ operation: @escaping @MainActor () async -> Void
    ) {
        taskCoordinator.perform(intent) {
            let token = presentation.begin()
            await operation()
            presentation.finish(token, outcome: operationOutcome(for: intent), confirmation: confirmationIdentity, isCancelled: Task.isCancelled)
        }
    }

    private func discardSheet() {
        discardOperation()
        dismiss()
    }

    /// Where something reads text and media the capture goes through it (a
    /// real account); the plain demonstration keeps its local samples.
    private var liveCapture: MealLiveCapture? {
        guard dependencies.mealCapture != nil, mealDraftModel.isAvailable else { return nil }
        return MealLiveCapture(
            model: mealDraftModel,
            stager: MealMediaStager(
                staging: dependencies.mealCapture?.staging ?? MediaStagingStore()
            ),
            recorder: mealRecorder,
            camera: dependencies.mealCapture?.camera ?? .unavailable,
            submitText: { text in
                perform(.draftText(text)) { await mealDraftModel.submitText(text) }
            },
            submitMedia: { staged in
                perform(.draftMedia(staged)) { await mealDraftModel.submitMedia(staged) }
            },
            retry: {
                perform(.draftRetry) { await mealDraftModel.retry() }
            },
            propose: { request in
                perform(.reviewedProposal(request)) {
                    await mealModel.propose(reviewed: request)
                    // Only a proposal that exists owns the media it came from.
                    if mealModel.currentProposal != nil {
                        mealDraftModel.proposalCreated()
                    }
                }
            }
        )
    }

    private func discardOperation() {
        presentation.invalidate()
        taskCoordinator.discard()
        mealRecorder.discard()
        mealDraftModel.discardSheet()
        mealModel.discardSheet()
        workoutModel?.discardSheet()
        hydrationModel.discardSheet()
        weightModel.discardSheet()
    }

    private func operationOutcome(for intent: RegistrationSheetOperationIntent) -> PerformeOperationOutcome {
        switch kind {
        case .meal:
            return PerformeRegistrationProjection.meal(intent: intent, draft: mealDraftModel.phase, mutation: mealModel.mutationState, captureError: mealModel.captureError)
        case .training:
            guard let workoutModel else { return .cancelled }
            return PerformeRegistrationProjection.registration(workoutModel.mutationState, captureError: workoutModel.captureError)
        case .hydration:
            if hydrationModel.captureError != nil { return .failed }
            if case .failed = hydrationModel.mutationState { return .failed }
            if case .succeeded = hydrationModel.mutationState { return .confirmed }
        case .weight:
            if weightModel.captureError != nil { return .failed }
            if case .failed = weightModel.mutationState { return .failed }
            if case .succeeded = weightModel.mutationState { return .confirmed }
        }
        return .cancelled
    }

    private var confirmationIdentity: PerformeOperationPresentation.Confirmation? {
        switch kind {
        case .meal:
            return PerformeRegistrationProjection.confirmation(for: mealModel.mutationState)
        case .training:
            guard let workoutModel else { return nil }
            return PerformeRegistrationProjection.confirmation(for: workoutModel.mutationState)
        case .hydration:
            return hydrationModel.receipt.map { .hydration($0.data.hydrationLogID) }
        case .weight:
            return weightModel.receipt.map { .weight($0.weightKG, $0.recordedAt) }
        }
    }

    private var brandStatus: String {
        let key: String.LocalizationValue = switch presentation.state {
        case .processing: "brand.processing"
        case .error: "brand.error"
        case .success: "brand.confirmed"
        case .idle, .press, .active:
            presentation.outcome == .ready ? "brand.ready" : "tab.register"
        }
        return copy(key)
    }

    static func presentationDetents(
        for dynamicTypeSize: DynamicTypeSize
    ) -> Set<PresentationDetent> {
        dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium]
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(
            key,
            language: BodyFlowPresentationLanguage.resolve(locale)
        )
    }
}

@MainActor
private struct HydrationRegistrationContent: View {
    let model: HydrationRegistrationModel
    let submit: @MainActor (Int?, String, Date) -> Void
    let retry: @MainActor () -> Void
    @AccessibilityFocusState private var operationFocus: RegistrationAccessibilityFocusTarget?
    @Environment(\.locale) private var locale

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
                    validationMessage: copy("registration.hydration.validation"),
                    successMessage: copy("registration.hydration.success"),
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

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(
            key,
            language: BodyFlowPresentationLanguage.resolve(locale)
        )
    }
}

@MainActor
private struct WeightRegistrationContent: View {
    let model: WeightRegistrationModel
    let submit: @MainActor (String, Date) -> Void
    let retry: @MainActor () -> Void
    @AccessibilityFocusState private var operationFocus: RegistrationAccessibilityFocusTarget?
    @Environment(\.locale) private var locale

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
                    validationMessage: copy("registration.weight.validation"),
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

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(
            key,
            language: BodyFlowPresentationLanguage.resolve(locale)
        )
    }
}

private struct OperationResultSummary<Attempt: Equatable & Sendable, Receipt: Equatable & Sendable>: View {
    let state: FeatureMutationState<Attempt, Receipt>
    let captureError: BodyFlowCapabilityError?
    let validationMessage: String
    let successMessage: String?
    var demoReceipt: WeightDemoReceipt? = nil
    let retry: @MainActor () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let message {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text(message)
                    if retryIsAvailable {
                        Button(action: retry) {
                            Text(copy("state.retry"))
                                .frame(
                                    minHeight: BodyFlowSpacing.minimumTapTarget
                                )
                                .contentShape(Rectangle())
                        }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("registration.mutation.retry")
                    }
                }
                .font(BodyFlowTypography.callout)
                .foregroundStyle(BodyFlowColor.secondaryText)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            demoReceipt.map { $0.isServerRecord ? "registration.weight.receipt" : "registration.weight.demo-receipt" }
                ?? "registration.operation.summary"
        )
    }

    private var message: String? {
        if let demoReceipt {
            return demoReceipt.isServerRecord
                ? WeightReceiptPresentation.message(
                    for: demoReceipt,
                    language: BodyFlowPresentationLanguage.resolve(locale)
                )
                : demoReceipt.label
        }
        if captureError == .invalidInput { return validationMessage }
        switch state {
        case .unavailable: return copy("state.unavailable.title")
        case .succeeded: return successMessage
        case .failed: return copy("registration.operation.failed")
        case .idle, .submitting: return nil
        }
    }

    private var retryIsAvailable: Bool {
        if case .failed = state { true } else { false }
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(
            key,
            language: BodyFlowPresentationLanguage.resolve(locale)
        )
    }
}

/// What a server weight record says to the patient: the value in force and
/// whether the submitted measurement became it.
enum WeightReceiptPresentation {
    static func message(
        for receipt: WeightDemoReceipt,
        language: SupportedAppLanguage
    ) -> String {
        let key: String.LocalizationValue = switch receipt.outcome {
        case .applied: "registration.weight.recorded"
        case .sameMeasurement: "registration.weight.already-recorded"
        case .olderThanCurrent: "registration.weight.older-kept"
        case nil: "registration.weight.recorded-unknown"
        }
        let weight = Decimal(receipt.weightKG)
            .formatted(.number.precision(.fractionLength(0...2)).locale(language.formattingLocale))
        let date = receipt.recordedAt.formatted(Date.FormatStyle(
            date: .abbreviated,
            time: .shortened,
            locale: language.formattingLocale
        ))
        return String(
            format: RegistrationCopy.string(key, language: language),
            locale: language.formattingLocale,
            weight,
            date
        )
    }
}

#if DEBUG
enum Prompt13RegistrationReceiptPreviewKind {
    case hydration
    case weight
}

@MainActor
struct Prompt13RegistrationReceiptPreview: View {
    let kind: Prompt13RegistrationReceiptPreviewKind
    private let dependencies: AppDependencies
    @State private var hydrationModel: HydrationRegistrationModel
    @State private var weightModel: WeightRegistrationModel

    init(kind: Prompt13RegistrationReceiptPreviewKind) {
        self.kind = kind
        let dependencies = Prompt13PreviewSupport.dependencies(for: .loaded)
        let invalidationCenter = FeatureInvalidationCenter()
        self.dependencies = dependencies
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

    var body: some View {
        Group {
            switch kind {
            case .hydration:
                HydrationRegistrationContent(
                    model: hydrationModel,
                    submit: { quickAmount, customAmount, occurredAt in
                        Task {
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
                    retry: { Task { await hydrationModel.retry() } }
                )
            case .weight:
                WeightRegistrationContent(
                    model: weightModel,
                    submit: { value, recordedAt in
                        let parsed = Double(
                            value.replacingOccurrences(of: ",", with: ".")
                        ) ?? .nan
                        Task {
                            await weightModel.submit(
                                weightKG: parsed,
                                recordedAt: recordedAt
                            )
                        }
                    },
                    retry: { Task { await weightModel.retry() } }
                )
            }
        }
        .background(BodyFlowColor.background)
        .task {
            switch kind {
            case .hydration:
                if hydrationModel.receipt == nil {
                    await hydrationModel.submitQuick(250)
                }
            case .weight:
                if weightModel.receipt == nil {
                    await weightModel.submit(weightKG: 78.4)
                }
            }
        }
        .installAppDependencies(dependencies)
    }
}
#endif

@MainActor
struct WorkoutRegistrationContent: View {
    let model: WorkoutRegistrationModel
    let propose: @MainActor (WorkoutProposalRequest) -> Void
    let saveEdit: @MainActor (WorkoutProposalRequest) -> Void
    let retry: @MainActor () -> Void
    let reviewCurrent: @MainActor () -> Void
    let confirm: @MainActor () -> Void
    let cancel: @MainActor () -> Void
    /// Only the local demonstration opens the new-workout form prefilled.
    let presentsLocalDemonstration: Bool
    var strengthQuestion: WorkoutStrengthQuestionConfiguration? = nil
    @State private var showingEditor = false
    @AccessibilityFocusState private var operationFocus: RegistrationAccessibilityFocusTarget?
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                content
                RegistrationOperationSummary(
                    state: model.mutationState,
                    captureError: model.captureError,
                    isWorking: model.isBusy
                ) { action in
                    switch action {
                    case .retry: retry()
                    case .reviewCurrent: reviewCurrent()
                    case .newProposal: model.prepareNewProposal()
                    }
                }
                .accessibilityFocused($operationFocus, equals: .operationSummary)
                if model.isReviewingCurrent {
                    Text(copy("registration.operation.review-loading"))
                        .font(BodyFlowTypography.callout)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                }
            }
            .padding(BodyFlowSpacing.lg)
        }
        .navigationDestination(isPresented: $showingEditor) {
            if let draft = model.pendingDraft {
                WorkoutRegistrationView(
                    initialPerformedAt: model.initialPerformedAt,
                    initialProposal: draft,
                    actionTitle: "Salvar", isSubmitting: model.isBusy || model.requiresCurrentReview
                ) { edit in
                    showingEditor = false
                    saveEdit(edit)
                }
                .navigationTitle(copy("registration.editor.title"))
            }
        }
        .onChange(of: model.accessibilityFocusTarget) { _, target in
            guard let target else { return }
            operationFocus = target
            model.consumeAccessibilityFocus()
        }
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(
            key,
            language: BodyFlowPresentationLanguage.resolve(locale)
        )
    }

    @ViewBuilder
    private var content: some View {
        if let proposal = model.currentProposal {
            WorkoutProposalView(
                proposal: WorkoutProposalPresentation(registration: proposal),
                isSubmitting: model.isBusy,
                requiresCurrentReview: model.requiresCurrentReview,
                edit: { showingEditor = true }, confirm: confirm, cancel: cancel
            )
        } else if model.phase == .confirmed {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                Text(copy("registration.confirmed.workout-title")).font(BodyFlowTypography.title).fontWeight(.semibold)
                Text(copy(strengthQuestion == nil ? "registration.confirmed.read-only" : "registration.confirmed.workout-note"))
                    .foregroundStyle(BodyFlowColor.secondaryText)
                if let feedback = model.confirmedRegistration?.feedback {
                    RegistrationFeedbackView(feedback: feedback)
                }
            }
            .accessibilityIdentifier("registration.proposal.confirmed")
            if let strengthQuestion { WorkoutStrengthQuestionHost(configuration: strengthQuestion) }
        } else {
            WorkoutRegistrationView(
                initialPerformedAt: model.initialPerformedAt,
                initialProposal: model.pendingDraft,
                presentsLocalDemonstration: presentsLocalDemonstration,
                isSubmitting: model.isBusy || model.requiresCurrentReview, submit: propose
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

/// The brand mark in the bar of the registration sheet. It says the state of
/// the operation; where the staged loader of a meal analysis is on screen
/// (`analysisStage` is not `nil`) it draws no indicator of its own — one
/// wait, one indicator. A view of its own so that this is proven on what is
/// drawn, not only read in the source.
struct RegistrationBrandMark: View {
    let state: PerformeBrandState
    let label: String
    let status: String
    /// The stage of the meal analysis being waited for, decided by the sheet
    /// (`RegistrationSheet.mealAnalysisStage`); `nil` when there is none.
    let analysisStage: MealAnalysisStage?

    var body: some View {
        PerformeBrandAction(
            state: state,
            label: label,
            status: status,
            showsLabel: false,
            showsProgress: analysisStage == nil
        )
        .frame(width: BodyFlowSpacing.minimumTapTarget)
        .accessibilityIdentifier("registration.brand")
    }
}

/// What the sheet hands to the live meal capture.
@MainActor
struct MealLiveCapture {
    let model: MealDraftModel
    let stager: MealMediaStager
    let recorder: MealAudioRecorder
    let camera: MealCameraAccess
    let submitText: @MainActor (String) -> Void
    let submitMedia: @MainActor (StagedMedia) -> Void
    let retry: @MainActor () -> Void
    let propose: @MainActor (MealProposalRequest) -> Void
}

@MainActor
private struct MealRegistrationContent: View {
    let model: MealRegistrationModel
    let submit: @MainActor (MealCaptureSource) -> Void
    let operationAction: @MainActor (RegistrationOperationAction) -> Void
    let saveEdit: @MainActor (MealProposalRequest) -> Void
    let confirm: @MainActor () -> Void
    let cancel: @MainActor () -> Void
    let presentsLocalDemonstration: Bool
    let liveCapture: MealLiveCapture?
    /// The way already chosen on the Register screen, if any.
    let entry: MealCaptureEntry?
    /// The stage of the analysis being waited for, decided by the sheet.
    let analysisStage: MealAnalysisStage?
    @State private var choice: MealCaptureChoice?
    /// The sheet has finished arriving: only then is a keyboard asked for.
    @State private var sheetSettled = false
    /// What happened with the camera along this sheet. It lives here, above
    /// the capture view, so a capture view built again on the same sheet
    /// cannot open the camera by itself a second time.
    @State private var cameraLog = MealCameraLog()
    @State private var textDraft: String
    @State private var showingEditor = false
    @State private var editedItemIndex = 0
    @AccessibilityFocusState private var operationFocus: RegistrationAccessibilityFocusTarget?
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion

    /// Where the operation summary sits in the sheet's scroll.
    private static let summaryAnchor = "registration.operation.summary"

    init(
        model: MealRegistrationModel,
        submit: @escaping @MainActor (MealCaptureSource) -> Void,
        operationAction: @escaping @MainActor (RegistrationOperationAction) -> Void,
        saveEdit: @escaping @MainActor (MealProposalRequest) -> Void,
        confirm: @escaping @MainActor () -> Void,
        cancel: @escaping @MainActor () -> Void,
        presentsLocalDemonstration: Bool = true,
        liveCapture: MealLiveCapture? = nil,
        entry: MealCaptureEntry? = nil,
        analysisStage: MealAnalysisStage? = nil
    ) {
        self.model = model
        self.submit = submit
        self.operationAction = operationAction
        self.saveEdit = saveEdit
        self.confirm = confirm
        self.cancel = cancel
        self.presentsLocalDemonstration = presentsLocalDemonstration
        self.liveCapture = liveCapture
        self.entry = entry
        self.analysisStage = analysisStage
        // Without the live capture the sheet opens on the step of the way
        // already chosen, when there is one for it.
        _choice = State(initialValue: MealCaptureStart.demonstrationChoice(
            entry: entry,
            presentsLocalDemonstration: presentsLocalDemonstration
        ))
        // The demonstration pre-fills its sample text; a real account starts
        // empty and types the meal.
        _textDraft = State(initialValue: presentsLocalDemonstration
            ? "Refeição de demonstração" : "")
    }

    var body: some View {
        ScrollViewReader { scroll in
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
                    .id(Self.summaryAnchor)
                }
                .padding(BodyFlowSpacing.lg)
            }
            // A failure that can be tried again is brought into view by
            // itself: when the calculation fails the review comes back from
            // the top, and the error with its action is below it.
            .onChange(of: summaryAsksToBeSeen) { _, asks in
                if asks { showSummary(scroll) }
            }
            // The same moment VoiceOver is sent to the summary, so a second
            // failure in a row is brought into view too.
            .onChange(of: model.accessibilityFocusTarget) { _, target in
                if target == .operationSummary, summaryAsksToBeSeen { showSummary(scroll) }
            }
        }
        .background {
            MealSheetSettledProbe { sheetSettled = true }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .navigationDestination(isPresented: $showingEditor) {
            if let proposal = model.currentProposal {
                MealProposalEditorView(
                    registration: proposal,
                    initialConsumedAt: model.initialConsumedAt,
                    isSubmitting: model.isSubmitting,
                    editedIndex: editedItemIndex
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
                edit: {
                    editedItemIndex = 0
                    showingEditor = true
                },
                editItem: { index in
                    editedItemIndex = index
                    showingEditor = true
                },
                confirm: confirm,
                cancel: cancel
            )
        } else if model.phase == .confirmed {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                Text(copy("registration.confirmed.meal-title"))
                    .font(BodyFlowTypography.title)
                    .fontWeight(.semibold)
                Text(copy("registration.confirmed.read-only"))
                    .foregroundStyle(BodyFlowColor.secondaryText)
                if let feedback = model.confirmedRegistration?.feedback {
                    RegistrationFeedbackView(feedback: feedback)
                }
            }
            .accessibilityIdentifier("registration.proposal.confirmed")
        } else {
            captureContent
        }
    }

    private var summaryAsksToBeSeen: Bool {
        RegistrationOperationSummaryDescriptor(
            state: model.mutationState,
            captureError: model.captureError
        ).asksToBeSeen
    }

    private func showSummary(_ scroll: ScrollViewProxy) {
        withAnimation(BodyFlowMotion.animation(.content, reduceMotion: reduceMotion)) {
            scroll.scrollTo(Self.summaryAnchor, anchor: .bottom)
        }
    }

    @ViewBuilder
    private var captureContent: some View {
        if let liveCapture {
            MealLiveCaptureView(
                model: liveCapture.model,
                stager: liveCapture.stager,
                recorder: liveCapture.recorder,
                entry: entry,
                sheetSettled: sheetSettled,
                camera: liveCapture.camera,
                cameraLog: $cameraLog,
                analysisStage: analysisStage,
                isProposing: model.isSubmitting,
                submitText: liveCapture.submitText,
                submitMedia: liveCapture.submitMedia,
                retry: liveCapture.retry,
                propose: liveCapture.propose
            )
        } else if let choice {
            switch choice {
            case .text:
                MealTextDraftView(
                    draft: $textDraft,
                    isSubmitting: model.isSubmitting,
                    presentsLocalDemonstration: presentsLocalDemonstration,
                    takesKeyboard: MealCaptureStart.focusesDemonstrationText(
                        entry: entry,
                        sheetSettled: sheetSettled
                    )
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
            MealCaptureSourceView(
                presentsLocalDemonstration: presentsLocalDemonstration
            ) { selected in
                choice = selected
            }
        }
    }

    @Environment(\.locale) private var locale

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(
            key,
            language: BodyFlowPresentationLanguage.resolve(locale)
        )
    }
}
