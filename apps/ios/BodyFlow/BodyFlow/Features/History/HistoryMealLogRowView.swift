import SwiftUI

struct HistoryMealLogRowView: View {
    let row: HistoryMealLogRow

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Text(row.foodName).font(BodyFlowTypography.headline)
            if let mealType = row.mealType { Text(mealType) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BodyFlowSpacing.md)
    }
}
