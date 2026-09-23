import SwiftUI

struct HistoryMealLogRowView: View {
    let row: HistoryMealLogRow

    var body: some View {
        BodyFlowCard {
            HStack(alignment: .center, spacing: BodyFlowSpacing.sm) {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text(row.foodName)
                        .font(BodyFlowTypography.headline)
                        .foregroundStyle(BodyFlowColor.primaryText)
                    if let mealType = row.mealType {
                        Text(mealType)
                            .font(BodyFlowTypography.callout)
                            .foregroundStyle(BodyFlowColor.secondaryText)
                    }
                }
                Spacer(minLength: BodyFlowSpacing.xs)
                HistoryRowChevron()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Decorative disclosure glyph shared by the history rows.
struct HistoryRowChevron: View {
    var body: some View {
        Image(symbol: .chevron)
            .font(BodyFlowTypography.caption)
            .foregroundStyle(BodyFlowColor.secondaryText)
            .accessibilityHidden(true)
    }
}
