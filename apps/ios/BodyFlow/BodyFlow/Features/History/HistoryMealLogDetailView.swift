import SwiftUI

struct HistoryMealLogDetailView: View {
    let row: HistoryMealLogRow?

    var body: some View {
        Group {
            if let row {
                ScrollView {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                        Text(row.foodName).font(BodyFlowTypography.title)
                        if let mealType = row.mealType { Text(mealType) }
                        if let quantity = row.quantityG { Text("Quantidade: \(quantity.description) g") }
                        if let kcal = row.kcal { Text("Energia: \(kcal.description) kcal") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BodyFlowSpacing.md)
                }
            } else {
                ScreenStateView(state: .unavailable, retryAction: {})
            }
        }
        .navigationTitle("Registro de alimento")
    }
}
