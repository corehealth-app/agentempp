import SwiftUI

struct TrainingExecutionCompletionFactsView: View {
  let completion: TrainingExecutionCompletionSnapshot
  let english: Bool
  private func text(_ pt: String, _ en: String) -> String { english ? en : pt }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      switch completion.status {
      case .reserved:
        Text(text("Conferindo a conclusão…", "Checking completion…"))
        Text(
          text(
            "Aguarde a confirmação antes de alterar as séries.",
            "Wait for confirmation before changing the sets."))
      case .cancelled:
        Text(text("Tentativa de conclusão cancelada", "Completion attempt cancelled"))
        if let decision = completion.decision { Text(verbatim: decision.text) }
      case .completed:
        Text(
          completion.workoutState == .removed
            ? text("Registro da atividade removido", "Activity record removed")
            : text("Treino registrado", "Training recorded")
        ).font(.headline)
        if let workout = completion.workout {
          Text(verbatim: workout.workoutType)
          Text("\(workout.durationMin) min")
          if let intensity = workout.intensity {
            Text(text("Intensidade: ", "Intensity: ") + intensity)
          }
          if let kcal = workout.estimatedKcal {
            Text(text("Gasto estimado: \(kcal) kcal", "Estimated expenditure: \(kcal) kcal"))
          }
        }
        if let feedback = completion.feedback {
          Text(verbatim: "Flow AI").font(.headline)
          Text(
            text(
              "Resumo do registro em \(feedback.original.localDate)",
              "Registration summary on \(feedback.original.localDate)"))
          ForEach(feedback.sections, id: \.key) { section in
            Text(verbatim: section.text).accessibilityIdentifier(
              "training.completion.feedback.\(section.key.rawValue)")
          }
        } else {
          Text(
            text(
              "O comentário está indisponível. Seu registro foi preservado.",
              "The commentary is unavailable. Your record is preserved."))
        }
      }
    }.font(.subheadline).accessibilityElement(children: .contain)
      .accessibilityIdentifier("training.completion.facts")
  }
}

@MainActor struct TrainingExecutionFinishEditor: View {
  @Bindable var model: TrainingExecutionModel
  @State private var report = ""
  @Environment(\.dismiss) private var dismiss
  @Environment(\.locale) private var locale
  private var english: Bool { BodyFlowPresentationLanguage.resolve(locale) != .portugueseBrazil }
  private func text(_ pt: String, _ en: String) -> String { english ? en : pt }
  private var valid: Bool {
    !report.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && report.utf16.count <= 2000
  }
  var body: some View {
    NavigationStack {
      Form {
        if model.isClosed {
          Text(text("Treino indisponível", "Training unavailable"))
        } else {
          Section(text("Atividade realizada", "Performed activity")) {
            Text(
              text(
                "Conte qual atividade fez e por quantos minutos. Inclua a intensidade, se souber.",
                "Describe the activity you did and for how many minutes. Include intensity if known."
              ))
            TextField(
              text(
                "Ex.: fiz musculação por 30 minutos, intensidade moderada",
                "E.g. I did strength training for 30 minutes, moderate intensity"), text: $report,
              axis: .vertical
            )
            .lineLimit(3...7).disabled(!model.canEdit).accessibilityIdentifier(
              "training.execution.finish.report")
          }
          Text(
            text(
              "As séries já anotadas serão preservadas. A conclusão registra uma única atividade.",
              "Your recorded sets will be preserved. Completion records one activity."))
          if let question = model.completion?.decision { Text(verbatim: question.text) }
          if model.pending != nil {
            Text(
              text(
                "A conclusão está protegida. Feche esta tela e use Tentar novamente para conferir o resultado.",
                "Completion is protected. Close this screen and use Try again to check the outcome."
              ))
          } else if model.failure != nil {
            Text(
              text(
                "Confira o estado atualizado antes de tentar novamente.",
                "Review the updated state before trying again."))
          }
        }
      }
      .navigationTitle(text("Concluir treino", "Complete training"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(text("Fechar", "Close")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(text("Registrar", "Record")) {
            Task { if await model.finish(report: report) { dismiss() } }
          }
          .disabled(!model.canEdit || !valid).accessibilityIdentifier(
            "training.execution.finish.submit")
        }
      }
    }
  }
}
