import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum MealLiveCaptureChoice: Equatable {
    case text
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
    let isProposing: Bool
    let submitText: @MainActor (String) -> Void
    let submitMedia: @MainActor (StagedMedia) -> Void
    let retry: @MainActor () -> Void
    let propose: @MainActor (MealProposalRequest) -> Void

    @State private var choice: MealLiveCaptureChoice?
    @State private var textDraft = ""
    @State private var showingCamera = false
    @State private var showingGallery = false
    @State private var showingImporter = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isStaging = false
    @Environment(\.locale) private var locale

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
    }

    static let importableAudioTypes: [UTType] = [.mpeg4Audio, .mp3, .wav]
        + [UTType("public.aac-audio")].compactMap { $0 }

    @ViewBuilder
    private var content: some View {
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
        case .uploading, .processing, .reading:
            progress
        case let .failed(failure):
            failureContent(failure)
        case .idle:
            if isStaging {
                progressLine(copy("registration.live.phase.preparing"))
            } else {
                capture
            }
        }
    }

    @ViewBuilder
    private var capture: some View {
        switch choice {
        case .text:
            textEntry
        case .record:
            MealAudioRecorderView(
                recorder: recorder,
                isBusy: isStaging,
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
                    sourceButton("registration.live.capture.camera", .camera, .secondary, "camera") {
                        openCamera()
                    }
                }
                sourceButton("registration.live.capture.gallery", .photo, .secondary, "gallery") {
                    showingGallery = true
                }
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

    private var progress: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            if let key = MealCaptureCopy.phaseKey(model.phase, channel: model.channel) {
                progressLine(copy(key))
            }
            Button(action: startOver) {
                Text(copy("registration.live.cancel"))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
            }
            .buttonStyle(BodyFlowButtonStyle(role: .secondary))
            .accessibilityIdentifier("registration.meal.capture.cancel")
        }
    }

    private func progressLine(_ message: String) -> some View {
        HStack(spacing: BodyFlowSpacing.sm) {
            ProgressView()
                .tint(BodyFlowColor.accent)
                .accessibilityHidden(true)
            Text(verbatim: message)
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("registration.meal.capture.progress")
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
        isStaging = true
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                isStaging = false
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

    /// Prepares the file off the main actor and hands it to the upload.
    private func stage(
        _ work: @escaping @Sendable (MealMediaStager) async throws -> StagedMedia
    ) {
        isStaging = true
        let stager = stager
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                await Result { try await work(stager) }
            }.value
            isStaging = false
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
