import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct FlowConversationCaptureCapability {
  let stager: MealMediaStager
  let camera: MealCameraAccess
}
struct FlowConversationCapturePresentation: Identifiable {
  enum Choice: Equatable { case camera, gallery, recording, audioFile }
  let id = UUID()
  let choice: Choice
  let context: ConversationCommandContext.Identity
  var neutral = false
}

/// Captures bytes only. The immutable scope is captured when the picker opens;
/// a later account/epoch change cannot attach its result to another report.
@MainActor
struct FlowConversationCaptureView: View {
  let capability: FlowConversationCaptureCapability
  let presentation: FlowConversationCapturePresentation
  let model: FlowConversationModel
  @State private var recorder: MealAudioRecorder
  @State private var pickedPhoto: PhotosPickerItem?
  @State private var gallery = false
  @State private var importer = false
  @State private var cameraID: CameraPresentation?
  @State private var preparing = false
  @State private var failure = false
  @State private var started = false
  @State private var operation: Task<Void, Never>?
  @Environment(\.dismiss) private var dismiss
  @Environment(\.locale) private var locale
  private var english: Bool { BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates }

  init(
    capability: FlowConversationCaptureCapability,
    presentation: FlowConversationCapturePresentation, model: FlowConversationModel
  ) {
    self.capability = capability
    self.presentation = presentation
    self.model = model
    _recorder = State(initialValue: MealAudioRecorder(staging: capability.stager.staging))
  }
  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
        Text(
          presentation.neutral
            ? (english ? "Attach to Flow" : "Anexar ao Flow")
            : (english ? "Attach a meal report" : "Anexar relato de refeição")
        )
        .font(BodyFlowTypography.cardTitle)
        Text(
          english
            ? "Review your message and send when ready. Only a clear report with enough information can be recorded."
            : "Revise sua mensagem e envie quando estiver pronta. Somente um relato claro e com as informações necessárias pode ser registrado."
        )
        .foregroundStyle(BodyFlowColor.secondaryText)
        if presentation.choice == .recording {
          MealAudioRecorderView(
            recorder: recorder, isBusy: preparing,
            use: { url in stage { try await $0.stageRecording(at: url) } },
            fail: { _ in failure = true })
        }
        if preparing { ProgressView(english ? "Preparing attachment…" : "Preparando anexo…") }
        if failure {
          Text(
            english
              ? "Could not prepare this attachment. Close and choose it again."
              : "Não foi possível preparar este anexo. Feche e selecione novamente."
          )
          .foregroundStyle(BodyFlowColor.secondaryText)
        }
        Spacer(minLength: 0)
      }
      .padding(BodyFlowSpacing.md)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(english ? "Close" : "Fechar") { dismiss() }
        }
      }
    }
    .task { await start() }
    .photosPicker(
      isPresented: $gallery, selection: $pickedPhoto, matching: .images,
      preferredItemEncoding: .compatible
    )
    .onChange(of: pickedPhoto) { _, item in
      guard let item else { return }
      pickedPhoto = nil
      stage { stager in
        guard let data = try await item.loadTransferable(type: Data.self) else {
          throw MealCaptureFailure.unreadableMedia
        }
        return try stager.stagePhoto(data, channel: .gallery)
      }
    }
    .fileImporter(
      isPresented: $importer, allowedContentTypes: MealLiveCaptureView.importableAudioTypes
    ) { result in
      switch result {
      case .success(let url):
        stage { stager in
          let scoped = url.startAccessingSecurityScopedResource()
          defer { if scoped { url.stopAccessingSecurityScopedResource() } }
          return try await stager.stageImportedAudio(from: url)
        }
      case .failure: failure = true
      }
    }
    .fullScreenCover(item: $cameraID) { value in
      MealCameraCover(camera: capability.camera, presentation: value.id) { data in
        cameraID = nil
        if let data { stage { try $0.stagePhoto(data, channel: .camera) } }
      }
    }
    .onDisappear {
      operation?.cancel()
      operation = nil
      recorder.discard()
    }
    .onChange(of: model.captureContext) { _, identity in
      if identity != presentation.context { dismiss() }
    }
  }
  private func start() async {
    guard !started, model.captureContext == presentation.context else { return }
    started = true
    switch presentation.choice {
    case .camera:
      let allowed = await capability.camera.requestAccess()
      guard !Task.isCancelled, model.captureContext == presentation.context else { return }
      if allowed && capability.camera.isAvailable() {
        cameraID = .init(id: 1)
      } else {
        failure = true
      }
    case .gallery: gallery = true
    case .audioFile: importer = true
    case .recording: break
    }
  }
  private func stage(_ work: @escaping @Sendable (MealMediaStager) async throws -> StagedMedia) {
    guard !preparing, model.captureContext == presentation.context else { return }
    preparing = true
    failure = false
    let stager =
      presentation.neutral
      ? MealMediaStager(staging: capability.stager.staging, photoPurpose: .conversation)
      : capability.stager
    operation = Task {
      do {
        let staged = try await Task.detached(priority: .userInitiated) { try await work(stager) }
          .value
        guard !Task.isCancelled else {
          stager.staging.remove(staged.fileURL)
          return
        }
        try model.attach(staged, expectedContext: presentation.context)
        dismiss()
      } catch is CancellationError {} catch { failure = true }
      preparing = false
    }
  }
  private struct CameraPresentation: Identifiable { let id: Int }
}
