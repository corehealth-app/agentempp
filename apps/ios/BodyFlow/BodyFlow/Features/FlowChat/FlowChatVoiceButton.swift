import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

@MainActor
struct FlowChatVoiceButton: View {
  let stager: MealMediaStager
  let english: Bool
  @Binding var recordingCaption: String?
  let dismissKeyboard: () -> Void
  let availableTarget: () -> FlowVoiceCaptureTarget?
  let retainedTarget: () -> FlowVoiceCaptureTarget?
  let send: (StagedMedia, FlowVoiceCaptureTarget) async throws -> Void
  let accessibilityID: String
  @State private var recorder: MealAudioRecorder
  @State private var owner: FlowVoiceCaptureTarget?
  @State private var work: Task<Void, Never>?
  @State private var released = false
  @State private var notice: String?
  @Environment(\.scenePhase) private var scenePhase

  init(model: FlowNeutralIntakeModel, stager: MealMediaStager, english: Bool,
    recordingCaption: Binding<String?>, dismissKeyboard: @escaping () -> Void
  ) {
    self.init(stager: stager, english: english, recordingCaption: recordingCaption,
      dismissKeyboard: dismissKeyboard,
      availableTarget: { model.inlineVoiceContext.map { .init(identity: $0, destination: .composer) } },
      retainedTarget: { model.captureSelectionIdentity.map { .init(identity: $0, destination: .composer) } },
      accessibilityID: "conversation.neutral.record-audio") { staged, target in
      try model.attach(staged, expectedContext: target.identity)
      await model.submit()
    }
  }

  init(stager: MealMediaStager, english: Bool, recordingCaption: Binding<String?>,
    dismissKeyboard: @escaping () -> Void, availableTarget: @escaping () -> FlowVoiceCaptureTarget?,
    retainedTarget: @escaping () -> FlowVoiceCaptureTarget?, accessibilityID: String,
    send: @escaping (StagedMedia, FlowVoiceCaptureTarget) async throws -> Void
  ) {
    self.stager = stager
    self.english = english
    self._recordingCaption = recordingCaption
    self.dismissKeyboard = dismissKeyboard
    self.availableTarget = availableTarget
    self.retainedTarget = retainedTarget
    self.accessibilityID = accessibilityID
    self.send = send
    self._recorder = State(initialValue: MealAudioRecorder(
      staging: stager.staging, captureFormat: .linearPCM))
  }

  private var available: Bool { availableTarget() != nil }

  var body: some View {
    Image(systemName: owner == nil ? "mic" : "mic.fill")
      .foregroundStyle(available || owner != nil ? BodyFlowColor.accent : BodyFlowColor.secondaryText)
      .frame(width: 44, height: 44)
      .overlay {
        FlowChatVoicePress(
          enabled: available || owner != nil,
          begin: begin, release: finish, cancel: cancel, interrupt: interrupt)
          .accessibilityHidden(true)
      }
      .accessibilityLabel(owner == nil
        ? (english ? "Record audio" : "Gravar áudio")
        : (english ? "Send audio" : "Enviar áudio"))
      .accessibilityHint(english ? "Activate to start recording or send" : "Ative para começar a gravar ou enviar")
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { if owner == nil { begin() } else { finish() } }
      .accessibilityAction(named: Text(english ? "Cancel recording" : "Cancelar gravação")) { cancel() }
      .accessibilityIdentifier(accessibilityID)
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
          switch error {
          case .permissionDenied:
            notice = english ? "Allow microphone access in Settings." : "Permita o microfone nos Ajustes."
          case .nothingRecognized:
            notice = english ? "I couldn't hear your voice. Check your microphone and try again."
              : "Não consegui captar sua voz. Confira o microfone e tente novamente."
          default:
            notice = english ? "Could not record audio." : "Não foi possível gravar o áudio."
          }
        default: break
        }
      }
      .onChange(of: retainedTarget()) { _, target in
        if let owner, target != owner { cancel() }
      }
      .onChange(of: scenePhase) { _, phase in if phase == .background { cancel() } }
      .onDisappear { cancel() }
  }

  private func begin() {
    guard owner == nil, let target = availableTarget() else { return }
    owner = target
    released = false
    dismissKeyboard()
    recordingCaption = "0:00"
    work = Task {
      guard !Task.isCancelled, owner == target else { return }
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
      notice = english
        ? "Hold the microphone until recording starts."
        : "Segure o microfone até começar a gravar."
    case .failed: break
    }
  }

  private func stageAndSend() {
    guard let target = owner, let url = recorder.takeRecording() else { return }
    work = Task {
      do {
        let staged = try await stager.stageRecording(at: url)
        guard !Task.isCancelled, owner == target else {
          stager.staging.remove(staged.fileURL)
          return
        }
        guard availableTarget() == target else {
          stager.staging.remove(staged.fileURL)
          interrupt()
          return
        }
        guard (staged.duration ?? 0) >= 0.25 else {
          stager.staging.remove(staged.fileURL)
          cancel()
          notice = english
            ? "Hold the microphone while speaking."
            : "Segure o microfone enquanto fala."
          return
        }
        owner = nil
        recordingCaption = nil
        do { try await send(staged, target) }
        catch {
          stager.staging.remove(staged.fileURL)
          throw error
        }
      } catch {
        if Task.isCancelled || error is CancellationError { return }
        cancel()
        if target.destination == .composer {
          notice = english ? "Could not attach the audio." : "Não foi possível anexar o áudio."
        } else if retainedTarget() == target {
          notice = english ? "I couldn't use that answer. Try recording again or type it here."
            : "Não consegui usar essa resposta. Você pode gravar de novo ou escrever aqui."
        }
      }
    }
  }

  private func interrupt() {
    guard owner != nil else { return }
    cancel()
    if scenePhase == .active {
      notice = english
        ? "Recording was interrupted. Hold the microphone to try again."
        : "A gravação foi interrompida. Segure o microfone para tentar novamente."
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
  let enabled: Bool
  let begin: () -> Void
  let release: () -> Void
  let cancel: () -> Void
  let interrupt: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(actions: self) }

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    let press = FlowMicrophonePressRecognizer(
      target: context.coordinator, action: #selector(Coordinator.track))
    press.minimumPressDuration = 0
    press.allowableMovement = .greatestFiniteMagnitude
    press.isEnabled = enabled
    view.addGestureRecognizer(press)
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.actions = self
    uiView.gestureRecognizers?.first?.isEnabled = enabled
  }

  @MainActor final class Coordinator: NSObject {
    var actions: FlowChatVoicePress
    private var startX: CGFloat?
    init(actions: FlowChatVoicePress) { self.actions = actions }

    @objc func track(_ press: FlowMicrophonePressRecognizer) {
      // The composer can resize while the keyboard closes or the timer appears.
      let x = press.location(in: nil).x
      switch press.state {
      case .began:
        startX = x
        actions.begin()
      case .changed where startX.map({ x < $0 - 64 }) == true:
        startX = nil
        actions.cancel()
      case .ended:
        guard let origin = startX else { return }
        startX = nil
        if let releaseX = press.releaseX, releaseX < origin - 64 {
          actions.cancel()
        } else {
          actions.release()
        }
      case .cancelled, .failed:
        guard startX != nil else { return }
        startX = nil
        actions.interrupt()
      default: break
      }
    }
  }
}

/// A hold on the microphone owns its touch. Scrolls starting anywhere else
/// are outside the recognizer's hit region.
final class FlowMicrophonePressRecognizer: UILongPressGestureRecognizer {
  private(set) var releaseX: CGFloat?

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    releaseX = touches.first?.location(in: nil).x
    super.touchesEnded(touches, with: event)
  }

  override func reset() {
    super.reset()
    releaseX = nil
  }

  override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
    if let scroll = preventingGestureRecognizer.view as? UIScrollView,
      preventingGestureRecognizer === scroll.panGestureRecognizer,
      view?.isDescendant(of: scroll) == true
    {
      return false
    }
    return super.canBePrevented(by: preventingGestureRecognizer)
  }
}
