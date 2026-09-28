import SwiftUI

@MainActor
struct RegistrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    let sheet: AppSheet
    let dependencies: AppDependencies
    let invalidationCenter: FeatureInvalidationCenter
    @State private var mealModel: MealRegistrationModel
    @State private var mealDraftModel: MealDraftModel
    @State private var mealRecorder: MealAudioRecorder
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
        let staging = dependencies.mealCapture?.staging ?? MediaStagingStore()
        _mealDraftModel = State(initialValue: MealDraftModel(
            media: dependencies.mealCapture?.media,
            drafts: dependencies.mealCapture?.drafts,
            uploader: dependencies.mealCapture?.uploader,
            staging: staging,
            timeProvider: dependencies.timeProvider,
            keyProvider: dependencies.idempotencyKeyProvider
        ))
        _mealRecorder = State(initialValue: MealAudioRecorder(staging: staging))
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
                        },
                        presentsLocalDemonstration: presentsLocalDemonstration,
                        liveCapture: liveCapture
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
                }
            }
        )
    }

    private func discardOperation() {
        taskCoordinator.discard()
        mealRecorder.discard()
        mealDraftModel.discardSheet()
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
private struct WorkoutRegistrationContent: View {
    let model: WorkoutRegistrationModel
    let propose: @MainActor (WorkoutProposalRequest) -> Void
    let saveEdit: @MainActor (WorkoutProposalRequest) -> Void
    let retry: @MainActor () -> Void
    let confirm: @MainActor () -> Void
    let cancel: @MainActor () -> Void
    @State private var showingEditor = false
    @AccessibilityFocusState private var operationFocus: RegistrationAccessibilityFocusTarget?
    @Environment(\.locale) private var locale

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
                isSubmitting: model.isSubmitting,
                edit: { showingEditor = true }, confirm: confirm, cancel: cancel
            )
        } else if model.phase == .confirmed {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                Text(copy("registration.confirmed.workout-title")).font(BodyFlowTypography.title).fontWeight(.semibold)
                Text(copy("registration.confirmed.read-only"))
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

/// What the sheet hands to the live meal capture.
@MainActor
struct MealLiveCapture {
    let model: MealDraftModel
    let stager: MealMediaStager
    let recorder: MealAudioRecorder
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
    @State private var choice: MealCaptureChoice?
    @State private var textDraft: String
    @State private var showingEditor = false
    @State private var editedItemIndex = 0
    @AccessibilityFocusState private var operationFocus: RegistrationAccessibilityFocusTarget?

    init(
        model: MealRegistrationModel,
        submit: @escaping @MainActor (MealCaptureSource) -> Void,
        operationAction: @escaping @MainActor (RegistrationOperationAction) -> Void,
        saveEdit: @escaping @MainActor (MealProposalRequest) -> Void,
        confirm: @escaping @MainActor () -> Void,
        cancel: @escaping @MainActor () -> Void,
        presentsLocalDemonstration: Bool = true,
        liveCapture: MealLiveCapture? = nil
    ) {
        self.model = model
        self.submit = submit
        self.operationAction = operationAction
        self.saveEdit = saveEdit
        self.confirm = confirm
        self.cancel = cancel
        self.presentsLocalDemonstration = presentsLocalDemonstration
        self.liveCapture = liveCapture
        // The demonstration pre-fills its sample text; a real account starts
        // empty and types the meal.
        _textDraft = State(initialValue: presentsLocalDemonstration
            ? "Refeição de demonstração" : "")
    }

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
            }
            .accessibilityIdentifier("registration.proposal.confirmed")
        } else {
            captureContent
        }
    }

    @ViewBuilder
    private var captureContent: some View {
        if let liveCapture {
            MealLiveCaptureView(
                model: liveCapture.model,
                stager: liveCapture.stager,
                recorder: liveCapture.recorder,
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
                    presentsLocalDemonstration: presentsLocalDemonstration
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
