import SwiftUI

/// Day/week consumes one complete server window; plans never count as consumed.
@MainActor
struct NutritionWindowRootView: View {
  @Bindable var model: NutritionWindowModel
  let revision: Int
  let isSelected: Bool
  @Environment(\.locale) private var locale
  @Environment(\.scenePhase) private var scenePhase
  private var portuguese: Bool { BodyFlowPresentationLanguage.resolve(locale) == .portugueseBrazil }
  private func text(_ pt: String, _ en: String) -> String { portuguese ? pt : en }
  private struct LoadKey: Hashable {
    let revision: Int
    let selected: Bool
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Picker(text("Período", "Period"), selection: $model.period) {
          Text(text("Dia", "Day")).tag(NutritionWindowModel.Period.day)
          Text(text("Semana", "Week")).tag(NutritionWindowModel.Period.week)
        }.pickerStyle(.segmented).accessibilityIdentifier("nutrition.period")
        if let snapshot = model.snapshot {
          windowHeader(snapshot)
          if model.period == .day {
            dayPicker(snapshot)
            if let day = model.selectedDay { dayContent(day, snapshot: snapshot) }
          } else {
            ForEach(snapshot.days) { day in
              dayContent(day, snapshot: snapshot)
              if day.localDate != snapshot.weekEnd { Divider() }
            }
          }
          Text(
            text(
              "Somente registros confirmados aparecem como realizados.",
              "Only confirmed records appear as consumed.")
          )
          .font(.footnote).foregroundStyle(.secondary)
        } else if model.phase == .loading {
          ProgressView(text("Consultando alimentação…", "Loading nutrition…"))
            .frame(maxWidth: .infinity, minHeight: 160)
        } else {
          ContentUnavailableView {
            Label(
              text("Alimentação indisponível", "Nutrition unavailable"), systemImage: "fork.knife")
          } description: {
            Text(
              model.failure == .changed
                ? text(
                  "Os registros mudaram durante a consulta. Atualize para ver os valores atuais.",
                  "Records changed during the read. Refresh to see current values.")
                : text(
                  "Não foi possível confirmar os registros e o plano. Tente novamente.",
                  "The records and plan could not be confirmed. Try again."))
          } actions: {
            Button(text("Tentar novamente", "Try again")) {
              Task { await model.load(revision: revision) }
            }
          }
        }
      }.padding()
    }
    .background(BodyFlowColor.background)
    .navigationTitle(text("Alimentação", "Nutrition"))
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("screen.alimentacao")
    .task(id: LoadKey(revision: revision, selected: isSelected)) {
      guard isSelected else { return }
      await model.load(revision: revision)
    }
    .refreshable {
      guard isSelected else { return }
      await model.load(revision: revision)
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active, isSelected else { return }
      Task { await model.load(revision: revision) }
    }
  }
  private func windowHeader(_ snapshot: NutritionWindowSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Button {
          Task { await model.shiftWeek(-1, revision: revision) }
        } label: {
          Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
        }.accessibilityLabel(text("Semana anterior", "Previous week"))
        Spacer()
        Text(
          "\(dateLabel(snapshot.weekStart, year: true)) – \(dateLabel(snapshot.weekEnd, year: true))"
        ).font(.headline)
        Spacer()
        Button {
          Task { await model.shiftWeek(1, revision: revision) }
        } label: {
          Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
        }.accessibilityLabel(text("Próxima semana", "Next week"))
      }
      HStack {
        Text(snapshot.timezone).font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button(text("Hoje", "Today")) { Task { await model.showToday(revision: revision) } }
      }
    }
  }
  private func dayPicker(_ snapshot: NutritionWindowSnapshot) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(snapshot.days) { day in
          Button {
            model.selectDay(day.localDate)
          } label: {
            Text(dateLabel(day.localDate, weekday: true)).font(.subheadline)
              .padding(10).background(
                model.selectedDay?.id == day.id
                  ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12))
          }
          .accessibilityAddTraits(model.selectedDay?.id == day.id ? [.isSelected] : [])
          .accessibilityIdentifier("nutrition.day.\(day.localDate)")
        }
      }
    }
  }
  private func dayContent(_ day: NutritionWindowDay, snapshot: NutritionWindowSnapshot) -> some View
  {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text(dateLabel(day.localDate, weekday: true)).font(.title3.bold())
        if day.localDate == snapshot.currentLocalDate {
          Text(text("Hoje", "Today")).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        if day.dayClosed == true {
          Text(text("Dia encerrado", "Day closed")).font(.caption).foregroundStyle(.secondary)
        }
      }
      VStack(alignment: .leading, spacing: 10) {
        Label(text("Realizado", "Consumed"), systemImage: "checkmark.circle").font(.headline)
        totals(day)
        if day.meals.isEmpty {
          Text(text("Nenhuma refeição confirmada neste dia.", "No confirmed meals on this day."))
            .foregroundStyle(.secondary)
        } else {
          ForEach(registrations(day)) { group in
            VStack(alignment: .leading, spacing: 8) {
              if let first = group.meals.first {
                Text(mealLabel(first.mealType)).font(.subheadline.bold())
                Text(timeLabel(first.consumedAt, zone: snapshot.timezone)).font(.caption)
                  .foregroundStyle(.secondary)
              }
              ForEach(group.meals) { meal in
                NutritionMealFactView(meal: meal, english: !portuguese)
              }
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
          }
        }
      }
      VStack(alignment: .leading, spacing: 10) {
        Label(text("Planejado", "Planned"), systemImage: "calendar").font(.headline)
        plannedNotice(day.planned)
        ForEach(day.planned.meals) { meal in
          VStack(alignment: .leading, spacing: 6) {
            Text(mealLabel(meal.mealType)).font(.subheadline.bold())
            if let time = meal.timeSuggestion {
              Text(time).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(meal.items.enumerated()), id: \.offset) { _, item in
              let quantity = NutritionQuantityPresentation.planned(
                item, locale: locale, english: !portuguese)
              Text("\(item.foodName) · \(quantity.text)")
            }
            if meal.totalKcal != nil || meal.totalProteinG != nil {
              Text(
                "\(amount(meal.totalKcal)) kcal · \(text("Proteína", "Protein")) \(amount(meal.totalProteinG)) g"
              )
              .font(.caption).foregroundStyle(.secondary)
            }
            if let notes = meal.notes, !notes.isEmpty {
              Text(notes).font(.footnote).foregroundStyle(.secondary)
            }
            Text(
              "\(text("Prescrição", "Prescription")) · \(instantDateLabel(meal.generatedAt, zone: snapshot.timezone))"
            )
            .font(.caption2).foregroundStyle(.secondary)
          }.padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("nutrition.planned.\(meal.id)")
        }
      }
    }.accessibilityElement(children: .contain)
  }
  private func totals(_ day: NutritionWindowDay) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      if day.totals.source == .unavailable {
        Text(text("Totais do dia indisponíveis", "Day totals unavailable")).foregroundStyle(
          .secondary)
      } else {
        Text(
          "\(amount(day.totals.kcal)) kcal · \(text("Proteína", "Protein")) \(amount(day.totals.proteinG)) g"
        ).font(.headline)
        Text(
          "\(text("Carboidratos", "Carbs")) \(amount(day.totals.carbsG)) g · \(text("Gorduras", "Fat")) \(amount(day.totals.fatG)) g"
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      if day.targets.caloriesKcal != nil || day.targets.proteinG != nil {
        Text(
          "\(text("Metas registradas para o dia", "Stored day targets")): \(amount(day.targets.caloriesKcal)) kcal · \(amount(day.targets.proteinG)) g \(text("de proteína", "protein"))"
        )
        .font(.caption).foregroundStyle(.secondary)
      } else {
        Text(text("Metas do dia indisponíveis", "Day targets unavailable")).font(.caption)
          .foregroundStyle(.secondary)
      }
    }.accessibilityElement(children: .combine)
      .accessibilityIdentifier("nutrition.totals.\(day.localDate)")
  }
  private func plannedNotice(_ plan: NutritionWindowPlanned) -> some View {
    let message: String =
      switch plan.status {
      case .none:
        text(
          "Nenhuma prescrição disponível para este dia.",
          "No prescription is available for this day.")
      case .protected:
        text(
          "O plano alimentar requer avaliação profissional antes de ser exibido.",
          "The nutrition plan requires professional assessment before it can be shown.")
      case .unavailable:
        text(
          "Não foi possível apresentar a prescrição deste dia.",
          "The prescription for this day could not be displayed.")
      case .partial:
        text("Parte das prescrições está indisponível.", "Some prescriptions are unavailable.")
      case .available:
        plan.meals.isEmpty
          ? text("Nenhuma refeição planejada para este dia.", "No meals are planned for this day.")
          : ""
      }
    return Text(message).font(.footnote).foregroundStyle(.secondary)
  }
  private struct Registration: Identifiable {
    let id: String
    var meals: [NutritionWindowMeal]
  }
  private func registrations(_ day: NutritionWindowDay) -> [Registration] {
    var groups: [Registration] = []
    for meal in day.meals {
      if let index = groups.firstIndex(where: { $0.id == meal.registrationKey }) {
        groups[index].meals.append(meal)
      } else {
        groups.append(.init(id: meal.registrationKey, meals: [meal]))
      }
    }
    return groups
  }
  private func mealLabel(_ key: String?) -> String {
    switch key {
    case "cafe": text("Café da manhã", "Breakfast")
    case "lanche_manha": text("Lanche da manhã", "Morning snack")
    case "almoco": text("Almoço", "Lunch")
    case "lanche_tarde": text("Lanche da tarde", "Afternoon snack")
    case "jantar": text("Jantar", "Dinner")
    case "ceia": text("Ceia", "Evening snack")
    default: text("Refeição", "Meal")
    }
  }
  private func amount(_ value: Decimal?) -> String {
    guard let value else { return "—" }
    return value.formatted(.number.locale(locale).precision(.fractionLength(0...2)))
  }
  private func dateLabel(_ civil: String, weekday: Bool = false, year: Bool = false) -> String {
    guard let date = NutritionCivilDate.date(civil) else { return civil }
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.setLocalizedDateFormatFromTemplate(weekday ? "EEE d MMM" : year ? "d MMM y" : "d MMM")
    return formatter.string(from: date)
  }
  private func instantDateLabel(_ raw: String, zone: String) -> String {
    guard let clock = ConversationProtocolInstant(raw), let timezone = TimeZone(identifier: zone)
    else { return "—" }
    return dateLabel(
      NutritionCivilDate.string(Date(timeIntervalSince1970: Double(clock.seconds)), zone: timezone))
  }
  private func timeLabel(_ raw: String, zone: String) -> String {
    guard let clock = ConversationProtocolInstant(raw), let timezone = TimeZone(identifier: zone)
    else { return "—" }
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = timezone
    formatter.timeStyle = .short
    return formatter.string(from: Date(timeIntervalSince1970: Double(clock.seconds)))
  }
}
