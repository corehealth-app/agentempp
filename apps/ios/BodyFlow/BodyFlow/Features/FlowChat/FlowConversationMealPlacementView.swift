import SwiftUI

@MainActor
struct FlowConversationMealPlacementView: View {
  let group: ConversationMealGroupSnapshot
  let editing: FlowConversationMealEditActions?
  let english: Bool
  @State private var selectedDate: Date?
  @State private var selectedMeal: ConversationMealCommand.MealType = .outro

  var body: some View {
    if let current = group.current,
      group.actions.changePlacement != nil,
      let day = NutritionCivilDate.date(current.localDate),
      let timezone = current.timezone.flatMap(TimeZone.init(identifier:))
    {
      let meal = current.items.first?.mealType
      let latest = NutritionCivilDate.date(NutritionCivilDate.string(Date(), zone: timezone)) ?? day
      VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
        let format = Date.FormatStyle(date: .abbreviated, time: .omitted,
          locale: Locale(identifier: english ? "en-US" : "pt-BR"),
          calendar: NutritionCivilDate.calendar, timeZone: .gmt)
        Text(verbatim: [meal.map(label), day.formatted(format)].compactMap { $0 }.joined(separator: " · "))
          .font(BodyFlowTypography.caption)
          .foregroundStyle(BodyFlowColor.secondaryText)
          .accessibilityIdentifier("conversation.meal.placement.current")
        if let editing, let save = editing.changePlacement, group.actions.changePlacement?.allowed == true {
          if let selectedDate {
            DatePicker(english ? "Date" : "Data", selection: Binding(
              get: { selectedDate }, set: { self.selectedDate = $0 }),
              in: ...latest, displayedComponents: .date)
              .environment(\.timeZone, .gmt)
              .environment(\.calendar, NutritionCivilDate.calendar)
              .accessibilityIdentifier("conversation.meal.placement.date")
            Picker(english ? "Meal" : "Refeição", selection: $selectedMeal) {
              ForEach(ConversationMealCommand.MealType.allCases, id: \.self) {
                Text(verbatim: label($0)).tag($0)
              }
            }
            .accessibilityIdentifier("conversation.meal.placement.type")
            HStack {
              Button(english ? "Save" : "Salvar") {
                save(group, NutritionCivilDate.string(selectedDate), selectedMeal)
                self.selectedDate = nil
              }
              .buttonStyle(.borderedProminent)
              .disabled(editing.isWorking || (selectedDate == day && selectedMeal == meal))
              .accessibilityIdentifier("conversation.meal.placement.save")
              Button(english ? "Cancel" : "Cancelar") { self.selectedDate = nil }
            }
          } else {
            Button(english ? "Change date or meal type" : "Alterar data ou tipo de refeição") {
              selectedDate = min(day, latest)
              selectedMeal = meal ?? .outro
            }
            .disabled(editing.isWorking)
            .accessibilityIdentifier("conversation.meal.placement.change")
          }
        }
        if let editing, let undo = editing.undoPlacement, group.actions.undoPlacement?.allowed == true {
          Button(english ? "Undo meal change" : "Desfazer mudança de refeição") { undo(group) }
            .disabled(editing.isWorking)
            .accessibilityIdentifier("conversation.meal.placement.undo")
        }
      }
      .onChange(of: group.revision) { selectedDate = nil }
    }
  }

  private func label(_ type: ConversationMealCommand.MealType) -> String {
    switch type {
    case .cafe: english ? "Breakfast" : "Café da manhã"
    case .almoco: english ? "Lunch" : "Almoço"
    case .lanche: english ? "Snack" : "Lanche"
    case .jantar: english ? "Dinner" : "Jantar"
    case .ceia: english ? "Supper" : "Ceia"
    case .outro: english ? "Other" : "Outra"
    }
  }
}
