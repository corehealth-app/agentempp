import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum MealLiveCaptureChoice: Equatable {
    case text
    /// Take or choose a photo: the step the "Foto" way of the meal card
    /// opens on.
    case photo
    case record
}

/// The meal capture of a real account: write, photograph, pick a photo,
/// record or import audio — then review what the server read. Each step says
/// what is happening; nothing is calculated before the review is sent.
@MainActor
struct MealLiveCaptureView: View {
    let model: MealDraftModel
    let stager: MealMediaStager
    let recorder: MealAudioRecorder
    /// The sheet has finished arriving: only then is the keyboard asked for.
    let sheetSettled: Bool
    /// The stage of the analysis being waited for, decided by the sheet
    /// (`RegistrationSheet.mealAnalysisStage`); `nil` when nothing is.
    let analysisStage: MealAnalysisStage?
    let isProposing: Bool
    let submitText: @MainActor (String) -> Void
    let submitMedia: @MainActor (StagedMedia) -> Void
    let retry: @MainActor () -> Void
    let propose: @MainActor (MealProposalRequest) -> Void

    @State private var choice: MealLiveCaptureChoice?
    @FocusState private var textFocused: Bool
    @State private var textDraft = ""
    @State private var showingCamera = false
    @State private var showingGallery = false
    @State private var showingImporter = false
    @State private var pickedPhoto: PhotosPickerItem?
    @AccessibilityFocusState private var analysisFocused: Bool
    @Environment(\.locale) private var locale

    /// `entry` is the way already chosen on the Register screen: the capture
    /// opens on its step and the choice is not asked again.
    init(
        model: MealDraftModel,
        stager: MealMediaStager,
        recorder: MealAudioRecorder,
        entry: MealCaptureEntry?,
        sheetSettled: Bool,
        analysisStage: MealAnalysisStage?,
        isProposing: Bool,
        submitText: @escaping @MainActor (String) -> Void,
        submitMedia: @escaping @MainActor (StagedMedia) -> Void,
        retry: @escaping @MainActor () -> Void,
        propose: @escaping @MainActor (MealProposalRequest) -> Void
    ) {
        self.model = model
        self.stager = stager
        self.recorder = recorder
        self.sheetSettled = sheetSettled
        self.analysisStage = analysisStage
        self.isProposing = isProposing
        self.submitText = submitText
        self.submitMedia = submitMedia
        self.retry = retry
        self.propose = propose
        _choice = State(initialValue: MealCaptureStart.liveChoice(
            entry: entry,
            supportsMedia: model.supportsMedia
        ))
    }

    var body: some View {
        content
            .fullScreenCover(isPresented: $showingCamera) {
                MealCameraPicker { data in
                    showingCamera = false
                    if let data { stagePhoto(data, channel: .camera) }
                }
                .ignoresSafeArea()
            }
            .photosPicker(
                isPresented: $showingGallery,
                selection: $pickedPhoto,
                matching: .images,
                preferredItemEncoding: .compatible
            )
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                pickedPhoto = nil
                loadPickedPhoto(item)
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: Self.importableAudioTypes
            ) { result in
                switch result {
                case let .success(url): stageImportedAudio(url)
                case .failure: model.reportCaptureFailure(.unreadableMedia)
                }
            }
            // VoiceOver follows the wait: the block takes the focus once,
            // when it appears; a change of stage is read as its new value.
            .onChange(of: analysisStage) { previous, current in
                if MealAnalysisFocus.takesFocus(from: previous, to: current) {
                    analysisFocused = true
                }
            }
    }

    static let importableAudioTypes: [UTType] = [.mpeg4Audio, .mp3, .wav]
        + [UTType("public.aac-audio")].compactMap { $0 }

    @ViewBuilder
    private var content: some View {
        if let analysisStage {
            // One block for the whole wait, whatever its stage.
            analysisLoader(analysisStage)
        } else {
            switch model.phase {
            case .review:
                if model.review != nil {
                    MealDraftReviewView(
                        review: Binding(
                            get: { model.review ?? Self.emptyReview },
                            set: { model.review = $0 }
                        ),
                        isSubmitting: isProposing,
                        submit: {
                            if let request = model.reviewedRequest(language: language) {
                                propose(request)
                            }
                        },
                        startOver: startOver
                    )
                }
            case let .failed(failure):
                failureContent(failure)
            case .idle, .preparing, .uploading, .processing, .reading:
                capture
            }
        }
    }

    @ViewBuilder
    private var capture: some View {
        switch choice {
        case .text:
            textEntry
        case .photo:
            photoStep
        case .record:
            MealAudioRecorderView(
                recorder: recorder,
                isBusy: model.isAnalysing,
                use: stageRecording,
                fail: { failure in
                    choice = nil
                    model.reportCaptureFailure(failure)
                }
            )
            backButton
        case nil:
            sources
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Text(copy("registration.capture.title"))
                .font(BodyFlowTypography.cardTitle)
                .foregroundStyle(BodyFlowColor.primaryText)
                .accessibilityAddTraits(.isHeader)
            BodyFlowStatusLine(copy("registration.live.capture.notice"), kind: .info)

            sourceButton("registration.live.capture.text", .compose, .primary, "text") {
                choice = .text
            }
            if model.supportsMedia {
                if MealCameraPicker.isCameraAvailable {
                    cameraButton(.secondary)
                }
                galleryButton(.secondary)
                sourceButton("registration.live.capture.record", .microphone, .secondary, "record") {
                    choice = .record
                }
                sourceButton(
                    "registration.live.capture.import-audio", .importFile, .secondary, "audio-import"
                ) {
                    showingImporter = true
                }
            } else {
                BodyFlowStatusLine(copy("registration.capture.media-unavailable"), kind: .unavailable)
            }
        }
    }

    /// The step "Foto" opens on: the same two actions the full choice
    /// offers (the very same buttons — the two steps are never on screen
    /// together), and the way back to it.
    private var photoStep: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Text(copy("registration.live.photo.title"))
                .font(BodyFlowTypography.headline)
                .foregroundStyle(BodyFlowColor.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("registration.meal.photo-step")
            if MealCameraPicker.isCameraAvailable {
                cameraButton(.primary)
                galleryButton(.secondary)
            } else {
                galleryButton(.primary)
            }
            backButton
        }
    }

    private func cameraButton(_ role: BodyFlowButtonRole) -> some View {
        sourceButton("registration.live.capture.camera", .camera, role, "camera") {
            openCamera()
        }
    }

    private func galleryButton(_ role: BodyFlowButtonRole) -> some View {
        sourceButton("registration.live.capture.gallery", .photo, role, "gallery") {
            showingGallery = true
        }
    }

    private var textEntry: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(copy("registration.live.text.title"))
                .font(BodyFlowTypography.headline)
                .accessibilityAddTraits(.isHeader)
            TextField(
                copy("registration.live.text.placeholder"),
                text: $textDraft,
                axis: .vertical
            )
            .lineLimit(3...8)
            .textInputAutocapitalization(.sentences)
            .focused($textFocused)
            .bodyFlowField()
            .accessibilityIdentifier("registration.meal.text")

            Button {
                submitText(textDraft)
            } label: {
                Text(copy("registration.live.text.submit"))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
            }
            .buttonStyle(BodyFlowButtonStyle(role: .primary))
            .disabled(
                textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || textDraft.count > MealMediaLimits.maximumTextLength
            )
            .accessibilityIdentifier("registration.meal.detect")

            backButton
        }
        // The keyboard comes with the field — on the direct entry and after
        // "Escrever" alike — once the sheet has stopped moving.
        .onChange(of: sheetSettled, initial: true) { _, settled in
            if MealCaptureStart.focusesText(isTextStep: true, sheetSettled: settled) {
                textFocused = true
            }
        }
    }

    private var backButton: some View {
        Button {
            recorder.discard()
            choice = nil
        } label: {
            Text(copy("registration.live.back"))
                .frame(maxWidth: .infinity)
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
        }
        .buttonStyle(BodyFlowButtonStyle(role: .tertiary))
        .accessibilityIdentifier("registration.meal.source.back")
    }

    /// The one loading block of the analysis: the same title from the first
    /// instant to the review, one line for the stage the work is really in,
    /// and the cancel action always in its place.
    private func analysisLoader(_ stage: MealAnalysisStage) -> some View {
        BodyFlowStagedLoader(
            title: copy("registration.live.analysis.title"),
            stage: copy(stage.lineKey),
            reservedStages: stage.reservedLines.map { copy($0.lineKey) },
            cancel: stage.offersCancel
                ? BodyFlowStagedLoader.CancelAction(
                    title: copy("registration.live.cancel"),
                    isEnabled: stage.isCancelEnabled,
                    identifier: "registration.meal.capture.cancel",
                    perform: startOver
                )
                : nil,
            statusIdentifier: "registration.meal.capture.progress",
            statusFocus: $analysisFocused
        )
    }

    private func failureContent(_ failure: MealCaptureFailure) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            BodyFlowStatusLine(
                MealCaptureCopy.message(for: failure, language: language),
                kind: .error
            )
            .accessibilityIdentifier("registration.meal.capture.failure")
            if model.canRetry {
                Button(action: retry) {
                    Text(copy("state.retry"))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
                }
                .buttonStyle(BodyFlowButtonStyle(role: .primary))
                .accessibilityIdentifier("registration.meal.capture.retry")
            }
            Button(action: startOver) {
                Text(copy("registration.live.start-over"))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
            }
            .buttonStyle(BodyFlowButtonStyle(role: .secondary))
            .accessibilityIdentifier("registration.meal.capture.start-over")
        }
    }

    private func sourceButton(
        _ key: String.LocalizationValue,
        _ symbol: BodyFlowSymbol,
        _ role: BodyFlowButtonRole,
        _ identifier: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Label(verbatim: copy(key), symbol: symbol)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
        }
        .buttonStyle(BodyFlowButtonStyle(role: role))
        .accessibilityIdentifier("registration.meal.source.\(identifier)")
    }

    private func startOver() {
        recorder.discard()
        choice = nil
        model.startOver()
    }

    private func openCamera() {
        Task {
            if await MealCameraPicker.requestAccess() {
                showingCamera = true
            } else {
                model.reportCaptureFailure(.permissionDenied)
            }
        }
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem) {
        model.beginPreparing()
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                model.reportCaptureFailure(.unreadableMedia)
                return
            }
            stagePhoto(data, channel: .gallery)
        }
    }

    private func stagePhoto(_ data: Data, channel: MealSourceChannel) {
        stage { stager in try stager.stagePhoto(data, channel: channel) }
    }

    private func stageRecording(_ url: URL) {
        stage { stager in try await stager.stageRecording(at: url) }
    }

    private func stageImportedAudio(_ url: URL) {
        stage { stager in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try await stager.stageImportedAudio(from: url)
        }
    }

    /// Prepares the file off the main actor and hands it to the upload. The
    /// wait belongs to the model from here on (`beginPreparing`), and ends
    /// in `submitMedia` or in a reported failure.
    private func stage(
        _ work: @escaping @Sendable (MealMediaStager) async throws -> StagedMedia
    ) {
        model.beginPreparing()
        let stager = stager
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                await Result { try await work(stager) }
            }.value
            choice = nil
            switch result {
            case let .success(staged): submitMedia(staged)
            case let .failure(error): model.reportCaptureFailure(MealCaptureFailure(error))
            }
        }
    }

    private static let emptyReview = MealDraftReview(
        draft: MealDraftSnapshot(
            source: "text",
            mediaAssetID: nil,
            transcript: nil,
            contextNote: nil,
            items: [],
            nutritionLabel: nil
        ),
        source: MealProposalSource(channel: .text, mediaAssetID: nil)!,
        mealType: .other
    )

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(key, language: language)
    }
}

private extension Result where Failure == any Error {
    init(_ work: () async throws -> Success) async {
        do {
            self = .success(try await work())
        } catch {
            self = .failure(error)
        }
    }
}
