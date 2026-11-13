import SwiftUI

/// Current recorded facts. No editable calories, completion command or reward.
struct TrainingActivityFactView: View {
  let activity: TrainingWindowActivity
  let timezone: String
  let english: Bool
  @Environment(\.locale) private var locale
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(activity.workoutType ?? (english ? "Recorded activity" : "Atividade registrada"))
        .font(.body.weight(.semibold))
      if let duration = activity.durationMin {
        Text("\(amount(duration)) min")
      } else {
        Text(english ? "Duration not provided" : "Duração não informada")
      }
      if let energy = activity.estimatedKcal {
        Text("\(english ? "Estimated expenditure" : "Gasto estimado"): \(amount(energy)) kcal")
      } else {
        Text(english ? "Expenditure not provided" : "Gasto não informado")
      }
      if let intensity = activity.intensity {
        Text("\(english ? "Intensity" : "Intensidade"): \(intensity)")
      }
      if let clock = clockText {
        Text(clock).font(.caption).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .background(BodyFlowColor.surface, in: RoundedRectangle(cornerRadius: 16))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("training.recorded.\(activity.id.uuidString.lowercased())")
  }
  private func amount(_ value: Decimal) -> String {
    value.formatted(.number.locale(locale).precision(.fractionLength(0...2)))
  }
  private var clockText: String? {
    guard let instant = ConversationProtocolInstant(activity.performedAt),
      let zone = TimeZone(identifier: timezone)
    else { return nil }
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = zone
    formatter.timeStyle = .short
    return formatter.string(from: Date(timeIntervalSince1970: Double(instant.seconds)))
  }
}
