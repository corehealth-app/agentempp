import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Sends the photo or PDF of a plan the patient already has. What comes out
/// is a draft to review, never a plan.
@MainActor
struct PlanImportView: View {
    @State private var model: PlanImportModel
    let stager: MealMediaStager
    let openDraft: @MainActor (String) -> Void

    @State private var showingCamera = false
    @State private var showingGallery = false
    @State private var showingImporter = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isStaging = false
    @Environment(\.locale) private var locale

    init(
        model: PlanImportModel,
        stager: MealMediaStager,
        openDraft: @escaping @MainActor (String) -> Void
    ) {
        _model = State(initialValue: model)
        self.stager = stager
        self.openDraft = openDraft
    }

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                    content
                }
                .padding(BodyFlowSpacing.md)
            }
        }
        .bodyFlowScreenChrome(title: copy("plan.import.navigation.title"))
        .accessibilityIdentifier("screen.plan.import")
        .onDisappear { model.screenClosed() }
        .onChange(of: model.phase) { _, phase in
            if case let .started(draftID) = phase { openDraft(draftID) }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            MealCameraPicker { data in
                showingCamera = false
                if let data { stage { try $0.stagePlanPhoto(data, channel: .camera) } }
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
            isStaging = true
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    isStaging = false
                    model.reportCaptureFailure(.unreadableMedia)
                    return
                }
                stage { try $0.stagePlanPhoto(data, channel: .gallery) }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf]) { result in
            switch result {
            case let .success(url):
                stage { stager in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    return try stager.stagePlanPDF(from: url)
                }
            case .failure:
                model.reportCaptureFailure(.unreadableMedia)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .started:
            if isStaging {
                progress(copy("registration.live.phase.preparing"))
            } else {
                sources
            }
        case .uploading:
            progress(copy("registration.live.phase.uploading"))
            cancelButton
        case .starting:
            progress(copy("plan.import.phase.starting"))
            cancelButton
        case let .failed(failure):
            BodyFlowStatusLine(copy(PlanDraftCopy.importFailureKey(failure)), kind: .error)
                .accessibilityIdentifier("plan.import.failure")
            if model.canRetry {
                button("state.retry", .primary, "plan.import.retry") {
                    Task { await model.retry() }
                }
            }
            button("registration.live.start-over", .secondary, "plan.import.start-over") {
                model.startOver()
            }
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Text(copy("plan.import.title"))
                .font(BodyFlowTypography.screenTitle)
                .foregroundStyle(BodyFlowColor.primaryText)
                .accessibilityAddTraits(.isHeader)
            BodyFlowStatusLine(copy("plan.import.notice.draft"), kind: .info)
            BodyFlowStatusLine(copy("plan.draft.notice.medications"), kind: .info)

            Picker(copy("plan.import.domain"), selection: $model.domain) {
                ForEach(PlanDraftDomain.allCases, id: \.self) { domain in
                    Text(PlanDraftCopy.domainTitle(domain, language: language)).tag(domain)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("plan.import.domain")

            if model.isAvailable {
                button("plan.import.source.pdf", .primary, "plan.import.source.pdf") {
                    showingImporter = true
                }
                if MealCameraPicker.isCameraAvailable {
                    button("plan.import.source.camera", .secondary, "plan.import.source.camera") {
                        Task {
                            if await MealCameraPicker.requestAccess() {
                                showingCamera = true
                            } else {
                                model.reportCaptureFailure(.permissionDenied)
                            }
                        }
                    }
                }
                button("plan.import.source.gallery", .secondary, "plan.import.source.gallery") {
                    showingGallery = true
                }
                BodyFlowStatusLine(copy("plan.import.notice.scanned"), kind: .info)
            } else {
                BodyFlowStatusLine(copy("state.unavailable.title"), kind: .unavailable)
            }
        }
    }

    private var cancelButton: some View {
        button("registration.live.cancel", .secondary, "plan.import.cancel") {
            model.startOver()
        }
    }

    private func stage(
        _ work: @escaping @Sendable (MealMediaStager) throws -> StagedMedia
    ) {
        isStaging = true
        let stager = stager
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try work(stager) }
            }.value
            isStaging = false
            switch result {
            case let .success(staged): await model.submit(staged)
            case let .failure(error): model.reportCaptureFailure(MealCaptureFailure(error))
            }
        }
    }

    private func progress(_ message: String) -> some View {
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
        .accessibilityIdentifier("plan.import.progress")
    }

    private func button(
        _ key: String.LocalizationValue,
        _ role: BodyFlowButtonRole,
        _ id: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Text(copy(key))
                .frame(maxWidth: .infinity)
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
        }
        .buttonStyle(BodyFlowButtonStyle(role: role))
        .accessibilityIdentifier(id)
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        PlanDraftCopy.string(key, language: language)
    }
}
