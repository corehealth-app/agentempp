import SwiftUI

@MainActor
struct TrainingExecutionRootView: View {
  let coordinator: TrainingExecutionShellCoordinator
  let plan: PlanViewModel
  @Environment(\.locale) private var locale
  private var english: Bool { BodyFlowPresentationLanguage.resolve(locale) != .portugueseBrazil }
  var body: some View {
    VStack(spacing: 0) {
      NavigationLink {
        PlanReadContent(model: plan, scope: .training)
          .navigationTitle(english ? "Full plan" : "Plano completo")
          .task { await plan.load() }
      } label: {
        Label(english ? "Full plan" : "Plano completo", systemImage: "list.bullet.rectangle")
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal).padding(.vertical, 8)
      }
      .accessibilityIdentifier("training.execution.full-plan")
      .disabled(coordinator.phase == .closed)
      if let model = coordinator.model {
        if model.home != nil || model.pending != nil || model.isWorking || model.failure == nil {
          TrainingExecutionView(model: model)
        } else {
          readOnlyPlan { Task { await model.load() } }
        }
      } else if coordinator.phase == .idle || coordinator.phase == .loading {
        ProgressView(english ? "Opening your training…" : "Abrindo seu treino…")
      } else {
        readOnlyPlan { Task { await coordinator.load() } }
      }
    }
    .task { if coordinator.phase == .idle { await coordinator.load() } }
  }
  private func readOnlyPlan(retry: @escaping () -> Void) -> some View {
    VStack(spacing: 8) {
      HStack {
        Text(
          english
            ? "Recording is unavailable right now." : "O registro está indisponível no momento.")
        Button(english ? "Try again" : "Tentar novamente", action: retry)
          .accessibilityIdentifier("training.execution.retry-bind")
      }.font(.footnote).padding(.horizontal)
      PlanReadContent(model: plan, scope: .training).task { await plan.load() }
    }
  }
}

@MainActor
struct TrainingExecutionView: View {
  @Bindable var model: TrainingExecutionModel
  @State private var editor: Editor?
  @State private var asksAbandon = false
  @Environment(\.locale) private var locale
  private var english: Bool { BodyFlowPresentationLanguage.resolve(locale) != .portugueseBrazil }
  private func text(_ pt: String, _ en: String) -> String { english ? en : pt }
  private struct Editor: Identifiable {
    let exercise: Int
    var draft: TrainingExecutionSetDraft
    var id: UUID { draft.id }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        if model.isClosed {
          Text(text("Treino indisponível", "Training unavailable"))
        } else {
          if let held = model.pending {
            pendingNotice(held)
          } else if let failure = model.failure {
            Text(
              failure == .changed
                ? text(
                  "O treino mudou. Confira os dados atualizados antes de editar.",
                  "Training changed. Review the updated values before editing.")
                : text(
                  "Não foi possível atualizar agora. Seus registros salvos são preservados.",
                  "Unable to update right now. Saved records are preserved.")
            )
            .accessibilityIdentifier("training.execution.failure")
          }
          if model.isWorking { ProgressView(text("Atualizando treino…", "Updating training…")) }
          if let session = model.session {
            execution(session)
          } else if let home = model.home {
            plans(home)
          } else if !model.isWorking {
            Button(text("Consultar treino", "Load training")) { Task { await model.load() } }
          }
        }
      }.padding()
    }
    .accessibilityIdentifier("training.execution.root")
    .task { if model.home == nil && !model.isClosed { await model.load() } }
    .refreshable { await model.load() }
    .sheet(item: Binding(get: { model.isClosed ? nil : editor }, set: { editor = $0 })) { context in
      TrainingExecutionSetEditor(model: model, exercise: context.exercise, draft: context.draft)
    }
    .confirmationDialog(
      text("Abandonar esta execução?", "Abandon this execution?"), isPresented: $asksAbandon
    ) {
      Button(text("Abandonar execução", "Abandon execution"), role: .destructive) {
        Task { _ = await model.abandon() }
      }
    } message: {
      Text(
        text(
          "As séries anotadas ficam no histórico da execução. Nenhuma atividade será registrada por esta ação.",
          "Recorded sets remain in the execution history. This action does not register an activity."
        ))
    }
  }
  private func pendingNotice(_ held: TrainingExecutionOperation) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(text("Há uma alteração pendente de confirmação.", "An update is awaiting confirmation."))
      if let home = model.home, held.binding.matches(home.scope) {
        Text(
          text(
            "Tentar novamente recupera a mesma alteração, sem criar outra série.",
            "Retry recovers the same update without creating another set."))
        Button(text("Tentar novamente", "Try again")) { Task { _ = await model.retryPending() } }
          .disabled(model.isWorking).accessibilityIdentifier("training.execution.retry-pending")
      } else {
        Text(
          text(
            "O estado da conta mudou. Atualize para verificar a alteração protegida neste aparelho.",
            "The account state changed. Refresh to check the protected update on this device."))
      }
    }.font(.footnote).accessibilityIdentifier("training.execution.pending")
  }
  private func plans(_ home: TrainingExecutionHomeSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      if !model.resumableSessions.isEmpty {
        Text(text("Em andamento", "In progress")).font(.headline)
        ForEach(model.resumableSessions) { item in
          Button {
            Task { await model.select(item.id) }
          } label: {
            VStack(alignment: .leading) {
              Text(item.dayLabel)
              Text("\(item.localDate) · \(item.completedExercises)/\(item.totalExercises)")
            }
          }.disabled(model.isWorking).accessibilityIdentifier(
            "training.execution.resume.\(item.id.uuidString.lowercased())")
        }
      }
      if model.nextCursor != nil {
        Button(text("Mais execuções", "More executions")) { Task { await model.loadMore() } }
          .disabled(model.isWorking)
      }
      if let plan = home.plan {
        Text(text("Seu plano", "Your plan")).font(.headline)
        ForEach(plan.days) { day in
          VStack(alignment: .leading, spacing: 10) {
            Text(day.label).font(.headline)
            if let focus = day.focus { Text(focus) }
            ForEach(day.exercises) { prescription in
              Text(prescription.name).font(.subheadline)
            }
            if day.startable {
              Button(text("Começar treino", "Start training")) {
                Task { _ = await model.start(dayIndex: day.index) }
              }
              .buttonStyle(.borderedProminent)
              .disabled(
                model.isWorking || model.pending != nil || !home.scope.recordingAllowed
                  || home.scope.openLocalDate != home.scope.currentLocalDate
              )
              .accessibilityIdentifier("training.execution.start.\(day.index)")
            } else {
              Text(text("Sem exercícios neste dia.", "No exercises on this day."))
            }
          }.frame(maxWidth: .infinity, alignment: .leading).padding().background(
            BodyFlowColor.surface, in: RoundedRectangle(cornerRadius: 16))
        }
      } else {
        Text(text("Nenhum plano de treino disponível.", "No training plan available."))
      }
    }
  }
  private func execution(_ session: TrainingExecutionSession) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(session.definition.dayLabel).font(.title2)
      Text(session.localDate).font(.caption)
      Text(
        session.phase == .abandoned
          ? text("Execução abandonada", "Abandoned execution")
          : text("Execução em andamento", "Execution in progress")
      )
      .accessibilityIdentifier("training.execution.phase")
      ForEach(session.definition.exercises) { prescription in
        let actual = session.exercises[prescription.index]
        VStack(alignment: .leading, spacing: 12) {
          TrainingExecutionPrescriptionFactsView(
            prescription: prescription, actual: actual, english: english)
          ForEach(actual.sets.sorted { $0.index < $1.index }) { set in
            VStack(alignment: .leading, spacing: 8) {
              TrainingExecutionActualSetView(set: set, english: english)
              HStack {
                Button(text("Editar série", "Edit set")) {
                  editor = .init(exercise: prescription.index, draft: .init(set: set))
                }
                Button(text("Remover série", "Remove set"), role: .destructive) {
                  Task { _ = await model.removeSet(exercise: prescription.index, setID: set.id) }
                }
              }.disabled(!model.canEdit)
            }
          }
          if let index = (0..<100).first(where: { i in !actual.sets.contains { $0.index == i } }) {
            Button(text("Anotar série", "Record set")) {
              editor = .init(exercise: prescription.index, draft: .init(index: index))
            }
            .disabled(!model.canEdit).accessibilityIdentifier(
              "training.execution.add-set.\(prescription.index)")
          }
          Button(
            actual.completed
              ? text("Desmarcar exercício", "Unmark exercise")
              : text("Marcar exercício realizado", "Mark exercise performed")
          ) {
            Task { _ = await model.markExercise(prescription.index, completed: !actual.completed) }
          }.disabled(!model.canEdit).accessibilityIdentifier(
            "training.execution.mark.\(prescription.index)")
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(
          BodyFlowColor.surface, in: RoundedRectangle(cornerRadius: 16))
      }
      Text(
        text(
          "Anotar séries não conclui nem duplica o registro de uma atividade.",
          "Recording sets does not complete or duplicate an activity record.")
      )
      .font(.footnote).foregroundStyle(.secondary)
      Button(text("Ver plano", "View plan")) { Task { await model.showPlan() } }.disabled(
        model.isWorking)
      if session.phase == .inProgress {
        Button(text("Abandonar execução", "Abandon execution"), role: .destructive) {
          asksAbandon = true
        }.disabled(!model.canEdit)
      }
    }
  }
}

struct TrainingExecutionPrescriptionFactsView: View {
  let prescription: TrainingExecutionPrescription
  let actual: TrainingExecutionExercise
  let english: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(prescription.name).font(.headline)
      if let sets = prescription.recommendedSets {
        Text(english ? "Recommended: \(sets) sets" : "Recomendado: \(sets) séries")
      }
      if let reps = prescription.repsReference {
        Text(english ? "Reference repetitions: \(reps)" : "Repetições de referência: \(reps)")
      }
      if let rest = prescription.restSeconds {
        Text(english ? "Reference rest: \(rest) s" : "Descanso de referência: \(rest) s")
      }
      Text(
        actual.sets.isEmpty
          ? (english ? "No sets recorded" : "Nenhuma série anotada")
          : (english
            ? "Recorded: \(actual.sets.count) sets" : "Anotado: \(actual.sets.count) séries"))
      if actual.completed {
        Text(english ? "Exercise marked as performed" : "Exercício marcado como realizado")
      }
    }.accessibilityElement(children: .combine).accessibilityIdentifier(
      "training.execution.exercise.\(prescription.index)")
  }
}
struct TrainingExecutionActualSetView: View {
  let set: TrainingExecutionSet
  let english: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(english ? "Set \(set.index + 1)" : "Série \(set.index + 1)")
      Text(
        set.repetitions.map { english ? "\($0) repetitions" : "\($0) repetições" }
          ?? (english ? "Repetitions not provided" : "Repetições não informadas"))
      Text(
        set.loadKg.map { value in
          let raw = String(value)
          let trimmed = raw.hasSuffix(".0") ? String(raw.dropLast(2)) : raw
          return (english ? trimmed : trimmed.replacingOccurrences(of: ".", with: ",")) + " kg"
        } ?? (english ? "Load not provided" : "Carga não informada"))
      if let duration = set.durationSeconds { Text("\(duration) s") }
      Text(
        set.completed
          ? (english ? "Set marked as performed" : "Série marcada como realizada")
          : (english ? "Not marked as performed" : "Não marcada como realizada"))
    }.font(.subheadline).accessibilityElement(children: .combine)
      .accessibilityIdentifier("training.execution.actual.\(set.id.uuidString.lowercased())")
  }
}

@MainActor
struct TrainingExecutionSetEditor: View {
  @Bindable var model: TrainingExecutionModel
  let exercise: Int
  @State var draft: TrainingExecutionSetDraft
  @Environment(\.dismiss) private var dismiss
  @Environment(\.locale) private var locale
  private var english: Bool { BodyFlowPresentationLanguage.resolve(locale) != .portugueseBrazil }
  private func text(_ pt: String, _ en: String) -> String { english ? en : pt }
  var body: some View {
    NavigationStack {
      Group {
        if model.isClosed {
          Text(text("Treino indisponível", "Training unavailable"))
        } else {
          Form {
            Section(text("Valores anotados", "Recorded values")) {
              TextField(
                text("Repetições (opcional)", "Repetitions (optional)"), text: $draft.repetitions
              ).keyboardType(.numberPad)
                .accessibilityIdentifier("training.execution.editor.reps")
              TextField(text("Carga em kg (opcional)", "Load in kg (optional)"), text: $draft.load)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("training.execution.editor.load")
              TextField(
                text("Tempo em segundos (opcional)", "Duration in seconds (optional)"),
                text: $draft.duration
              ).keyboardType(.numberPad)
                .accessibilityIdentifier("training.execution.editor.duration")
              Toggle(text("Realizei esta série", "I performed this set"), isOn: $draft.completed)
                .accessibilityIdentifier("training.execution.editor.completed")
            }
            if !model.isWorking && model.pending == nil && !model.canEdit {
              Text(
                text(
                  "Esta execução não pode mais ser alterada. Feche a revisão para consultar os dados atuais.",
                  "This execution can no longer be changed. Close the editor to review its current values."
                )
              )
              .accessibilityIdentifier("training.execution.editor.readonly")
            }
            if (try? draft.actual()) == nil {
              Text(
                text(
                  "Confira os números. Use vírgula ou ponto apenas para a carga.",
                  "Check the numbers. Use a comma or dot only for load."))
            }
            if model.pending != nil {
              Text(
                text(
                  "A alteração está protegida. Feche esta revisão e use Tentar novamente para confirmar o resultado.",
                  "The update is protected. Close this editor and use Try again to confirm the outcome."
                ))
            } else if model.failure != nil {
              Text(
                text(
                  "Confira os dados atualizados antes de tentar salvar novamente.",
                  "Review the updated data before saving again."))
            }
          }.disabled(!model.canEdit)
        }
      }
      .navigationTitle(text("Registro de série", "Set record")).navigationBarTitleDisplayMode(
        .inline
      )
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(text("Fechar", "Close")) { dismiss() }
            .accessibilityIdentifier("training.execution.editor.close")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(text("Salvar", "Save")) {
            guard let actual = try? draft.actual() else { return }
            Task { if await model.saveSet(exercise: exercise, set: actual) { dismiss() } }
          }.disabled(
            !model.canEdit || (try? draft.actual()) == nil
          )
          .accessibilityIdentifier("training.execution.editor.save")
        }
      }
    }
  }
}
