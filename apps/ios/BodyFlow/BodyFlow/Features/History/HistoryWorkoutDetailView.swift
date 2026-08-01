import SwiftUI

struct HistoryWorkoutDetailView: View {
    let row: HistoryWorkoutLogRow?

    var body: some View {
        Group {
            if let row {
                ScrollView {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                        Text(row.workoutType ?? "Treino").font(BodyFlowTypography.title)
                        if let duration = row.durationMin { Text("Duração: \(duration) min") }
                        if let kcal = row.estimatedKcal { Text("Energia estimada: \(kcal) kcal") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BodyFlowSpacing.md)
                }
            } else {
                ScreenStateView(state: .unavailable, retryAction: {})
            }
        }
        .navigationTitle("Registro de treino")
    }
}
