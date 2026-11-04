import SwiftUI

/// Actual source state, never a demo transcript or legacy writer fallback.
@MainActor
struct FlowConversationRootView: View {
  let coordinator: FlowConversationShellCoordinator
  @Environment(\.locale) private var locale
  private var english: Bool { BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates }
  private var capture: FlowConversationCaptureCapability? {
    coordinator.captureStaging.map { .init(stager: .init(staging: $0), camera: .device) }
  }
  var body: some View {
    Group {
      if let model = coordinator.model {
        FlowConversationView(model: model, capture: capture)
      } else {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
          Text(verbatim: "Flow AI").font(BodyFlowTypography.cardTitle)
          if coordinator.phase == .idle || coordinator.phase == .loading {
            ProgressView(english ? "Opening your conversation…" : "Abrindo sua conversa…")
              .accessibilityIdentifier("conversation.runtime.loading")
          } else {
            Text(
              english ? "Flow is unavailable right now." : "O Flow está indisponível no momento."
            )
            .accessibilityIdentifier("conversation.runtime.unavailable")
            Text(
              english
                ? "Pending reports stay protected on this device."
                : "Relatos pendentes continuam protegidos neste dispositivo."
            )
            .foregroundStyle(BodyFlowColor.secondaryText)
            if coordinator.phase != .closed {
              Button(english ? "Try again" : "Tentar novamente") {
                Task { await coordinator.load() }
              }
              .accessibilityIdentifier("conversation.runtime.retry")
            }
          }
          Spacer()
        }.padding(BodyFlowSpacing.md).frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .background(BodyFlowColor.color(.backgroundPrimary))
    .navigationTitle("Flow").navigationBarTitleDisplayMode(.inline)
    .task {
      guard coordinator.phase == .idle else { return }
      await coordinator.load()
    }
  }
}
