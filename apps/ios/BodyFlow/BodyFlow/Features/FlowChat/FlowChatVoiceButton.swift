import SwiftUI
import UIKit

@MainActor
struct FlowChatVoiceButton: View {
  let model: FlowNeutralIntakeModel
  let stager: MealMediaStager
  let english: Bool
  @Binding var recordingCaption: String?
  let dismissKeyboard: () -> Void
  @State private var recorder: MealAudioRecorder
  @State private var owner: ConversationCommandContext.Identity?
  @State private var work: Task<Void, Never>?
  @State private var released = false
  @State private var notice: String?
  @Environment(\.scenePhase) private var scenePhase

  init(model: FlowNeutralIntakeModel, stager: MealMediaStager, english: Bool,
    recordingCaption: Binding<String?>, dismissKeyboard: @escaping () -> Void
  ) {
    self.model = model
    self.stager = stager
    self.english = english
    self._recordingCaption = recordingCaption
    self.dismissKeyboard = dismissKeyboard
    self._recorder = State(initialValue: MealAudioRecorder(staging: stager.staging))
  }

  private var available: Bool { model.inlineVoiceContext != nil }

  var body: some View {
    Image(systemName: owner == nil ? "mic" : "mic.fill")
      .foregroundStyle(available || owner != nil ? BodyFlowColor.accent : BodyFlowColor.secondaryText)
      .frame(width: 44, height: 44)
      .overlay {
        FlowChatVoicePress(begin: begin, release: finish, cancel: cancel)
          .accessibilityHidden(true)
      }
      .accessibilityLabel(owner == nil
        ? (english ? "Record audio" : "Gravar áudio")
        : (english ? "Send audio" : "Enviar áudio"))
      .accessibilityHint(english ? "Activate to start recording or send" : "Ative para começar a gravar ou enviar")
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { if owner == nil { begin() } else { finish() } }
      .accessibilityAction(named: Text(english ? "Cancel recording" : "Cancelar gravação")) { cancel() }
      .accessibilityIdentifier("conversation.neutral.record-audio")
      .alert(english ? "Audio" : "Áudio", isPresented: Binding(
        get: { notice != nil }, set: { if !$0 { notice = nil } }
      )) {
        Button("OK", role: .cancel) { notice = nil }
      } message: {
        Text(verbatim: notice ?? "")
      }
      .onChange(of: recorder.elapsed) { _, elapsed in
        if owner != nil, !released { recordingCaption = MealCaptureCopy.clock(elapsed) }
      }
      .onChange(of: recorder.state) { _, state in
        switch state {
        case .finished:
          if released { stageAndSend() }
        case .failed(let error):
          guard owner != nil else { return }
          cancel()
          notice = error == .permissionDenied
            ? (english ? "Allow microphone access in Settings." : "Permita o microfone nos Ajustes.")
            : (english ? "Could not record audio." : "Não foi possível gravar o áudio.")
        default: break
        }
      }
      .onChange(of: model.captureSelectionIdentity) { _, identity in
        if let owner, identity != owner { cancel() }
      }
      .onChange(of: scenePhase) { _, phase in if phase == .background { cancel() } }
      .onDisappear { cancel() }
  }

  private func begin() {
    guard owner == nil, let identity = model.inlineVoiceContext else { return }
    owner = identity
    released = false
    dismissKeyboard()
    recordingCaption = "0:00"
    work = Task {
      guard !Task.isCancelled, owner == identity else { return }
      await recorder.start()
    }
  }

  private func finish() {
    guard owner != nil, !released else { return }
    released = true
    switch recorder.state {
    case .recording: recorder.stop()
    case .finished: stageAndSend()
    case .idle:
      cancel()
    case .failed: break
    }
  }

  private func stageAndSend() {
    guard let identity = owner, let url = recorder.takeRecording() else { return }
    work = Task {
      do {
        let staged = try await stager.stageRecording(at: url)
        guard !Task.isCancelled, owner == identity, model.inlineVoiceContext == identity else {
          stager.staging.remove(staged.fileURL)
          if !Task.isCancelled { cancel() }
          return
        }
        guard (staged.duration ?? 0) >= 0.25 else {
          stager.staging.remove(staged.fileURL)
          cancel()
          return
        }
        do { try model.attach(staged, expectedContext: identity) }
        catch {
          stager.staging.remove(staged.fileURL)
          throw error
        }
        owner = nil
        recordingCaption = nil
        await model.submit()
      } catch {
        if Task.isCancelled { return }
        cancel()
        notice = english ? "Could not attach the audio." : "Não foi possível anexar o áudio."
      }
    }
  }

  private func cancel() {
    guard owner != nil else { return }
    work?.cancel()
    work = nil
    recorder.discard()
    owner = nil
    recordingCaption = nil
  }
}

/// A touch-down, release or cancellation maps to exactly one recording gesture.
private struct FlowChatVoicePress: UIViewRepresentable {
  let begin: () -> Void
  let release: () -> Void
  let cancel: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(actions: self) }

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.track))
    press.minimumPressDuration = 0
    press.allowableMovement = .greatestFiniteMagnitude
    view.addGestureRecognizer(press)
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.actions = self }

  @MainActor final class Coordinator: NSObject {
    var actions: FlowChatVoicePress
    private var startX: CGFloat?
    init(actions: FlowChatVoicePress) { self.actions = actions }

    @objc func track(_ press: UILongPressGestureRecognizer) {
      let x = press.location(in: press.view).x
      switch press.state {
      case .began:
        startX = x
        actions.begin()
      case .changed where startX.map({ x < $0 - 64 }) == true:
        startX = nil
        actions.cancel()
      case .ended where startX != nil:
        let didCancel = startX.map { x < $0 - 64 } ?? false
        startX = nil
        if didCancel { actions.cancel() } else { actions.release() }
      case .cancelled, .failed:
        startX = nil
        actions.cancel()
      default: break
      }
    }
  }
}
