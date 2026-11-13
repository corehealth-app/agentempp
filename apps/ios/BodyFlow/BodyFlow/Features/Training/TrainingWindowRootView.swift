import SwiftUI

@MainActor
struct TrainingWindowRootView: View {
  @Bindable var model: TrainingWindowModel
  let plan: PlanViewModel
  let revision: Int
  let isSelected: Bool
  @State private var section: Section = .recorded
  @Environment(\.locale) private var locale
  @Environment(\.scenePhase) private var scenePhase
  private enum Section: Hashable { case recorded, plan }
  private struct LoadKey: Hashable {
    let revision: Int
    let selected: Bool
    let section: Section
  }
  private var english: Bool { BodyFlowPresentationLanguage.resolve(locale) != .portugueseBrazil }
  private func text(_ pt: String, _ en: String) -> String { english ? en : pt }

  var body: some View {
    VStack(spacing: 0) {
      Picker(text("Treino", "Training"), selection: $section) {
        Text(text("Realizado", "Recorded")).tag(Section.recorded)
        Text(text("Plano", "Plan")).tag(Section.plan)
      }.pickerStyle(.segmented).padding().accessibilityIdentifier("training.section")
      if section == .plan {
        PlanReadContent(model: plan, scope: .training)
      } else {
        ScrollView { TrainingWindowContentView(model: model, revision: revision) }
      }
    }
    .background(BodyFlowColor.background)
    .navigationTitle(text("Treino", "Training"))
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("screen.treino")
    .task(id: LoadKey(revision: revision, selected: isSelected, section: section)) {
      guard isSelected else { return }
      if section == .recorded { await model.load(revision: revision) } else { await plan.load() }
    }
    .refreshable {
      guard isSelected else { return }
      if section == .recorded { await model.load(revision: revision) } else { await plan.retry() }
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active, isSelected, section == .recorded else { return }
      Task { await model.load(revision: revision) }
    }
  }
}

@MainActor
struct TrainingWindowContentView: View {
  @Bindable var model: TrainingWindowModel
  let revision: Int
  @Environment(\.locale) private var locale
  private var english: Bool { BodyFlowPresentationLanguage.resolve(locale) != .portugueseBrazil }
  private func text(_ pt: String, _ en: String) -> String { english ? en : pt }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Picker(text("Período", "Period"), selection: $model.period) {
        Text(text("Dia", "Day")).tag(TrainingWindowModel.Period.day)
        Text(text("Semana", "Week")).tag(TrainingWindowModel.Period.week)
      }.pickerStyle(.segmented).accessibilityIdentifier("training.period")
      if let snapshot = model.snapshot {
        Text("\(snapshot.weekStart) – \(snapshot.weekEnd)").font(.headline)
        Text("\(text("Fuso dos registros", "Records time zone")): \(snapshot.timezone)")
          .font(.caption).foregroundStyle(.secondary)
        HStack {
          Button {
            Task { await model.shiftWeek(-1, revision: revision) }
          } label: {
            Text(text("Anterior", "Previous")).frame(minWidth: 44, minHeight: 44)
          }.accessibilityLabel(text("Semana anterior", "Previous week"))
            .accessibilityIdentifier("training.previous-week")
          Spacer()
          Button {
            Task { await model.showToday(revision: revision) }
          } label: {
            Text(text("Hoje", "Today")).frame(minWidth: 44, minHeight: 44)
          }.accessibilityLabel(text("Hoje", "Today"))
            .accessibilityIdentifier("training.today")
          Spacer()
          Button {
            Task { await model.shiftWeek(1, revision: revision) }
          } label: {
            Text(text("Próxima", "Next")).frame(minWidth: 44, minHeight: 44)
          }.accessibilityLabel(text("Próxima semana", "Next week"))
            .accessibilityIdentifier("training.next-week")
        }.buttonStyle(.bordered).font(.caption)
        if model.period == .day {
          Picker(
            text("Data", "Date"),
            selection: Binding(
              get: { model.selectedDay?.localDate ?? snapshot.selectedLocalDate },
              set: { model.selectDay($0) }
            )
          ) {
            ForEach(snapshot.days) { day in Text(day.localDate).tag(day.localDate) }
          }.pickerStyle(.menu).accessibilityIdentifier("training.day")
        }
        LazyVStack(alignment: .leading, spacing: 18) {
          ForEach(model.period == .week ? snapshot.days : model.selectedDay.map { [$0] } ?? []) {
            day in
            Section {
              if day.workouts.isEmpty {
                Text(
                  text(
                    "Nenhuma atividade registrada neste dia.", "No activity recorded on this day.")
                )
                .foregroundStyle(.secondary).accessibilityIdentifier(
                  "training.empty.\(day.localDate)")
              }
              ForEach(day.workouts) { activity in
                TrainingActivityFactView(
                  activity: activity, timezone: snapshot.timezone, english: english)
              }
            } header: {
              Text(day.localDate).font(.headline)
            }
          }
        }
        Text(
          text(
            "Somente atividades registradas aparecem como realizadas. Exercício não aumenta o saldo disponível para comida.",
            "Only saved activities appear as recorded. Exercise does not increase the available food budget."
          )
        )
        .font(.footnote).foregroundStyle(.secondary)
      } else if model.phase == .loading {
        ProgressView(text("Consultando treinos…", "Loading training…"))
          .frame(maxWidth: .infinity, minHeight: 160)
      } else {
        VStack(alignment: .leading, spacing: 12) {
          Text(text("Registros de treino indisponíveis", "Training records unavailable")).font(
            .headline)
          Text(
            model.failure == .changed
              ? text(
                "Os registros ou a conta mudaram durante a consulta. Atualize para continuar.",
                "Records or account changed during the read. Refresh to continue.")
              : text(
                "Não foi possível confirmar as atividades. O plano continua disponível na opção Plano.",
                "The recorded activities could not be confirmed. Your plan remains available under Plan."
              ))
          Button(text("Tentar novamente", "Try again")) {
            Task { await model.load(revision: revision) }
          }
          .buttonStyle(.bordered).accessibilityIdentifier("training.retry")
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
    }.padding()
  }
}
