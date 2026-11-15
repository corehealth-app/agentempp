import Foundation

/// User-initiated export of owned recorded facts only. No prescription, account
/// identifier, day budget, clinical target, XP or educational policy is exported.
struct TrainingExecutionShareContent: Sendable {
  let text: String
  init?(completion: TrainingExecutionCompletionSnapshot, english: Bool) {
    guard completion.status == .completed, completion.workoutState == .present,
      let session = completion.session, let workout = completion.workout
    else { return nil }
    var lines = [
      english ? "My training · Performe AI" : "Meu treino · Performe AI", workout.localDate,
      "\(workout.workoutType) · \(workout.durationMin) min",
    ]
    if let intensity = workout.intensity {
      lines.append((english ? "Intensity: " : "Intensidade: ") + intensity)
    }
    if let kcal = workout.estimatedKcal {
      lines.append(english ? "Estimated expenditure: \(kcal) kcal" : "Gasto estimado: \(kcal) kcal")
    }
    for actual in session.exercises {
      let performed = actual.sets.filter(\.completed).sorted { $0.index < $1.index }
      guard actual.completed || !performed.isEmpty else { continue }
      lines.append(session.definition.exercises[actual.index].name)
      for set in performed {
        var facts = [english ? "Set \(set.index+1) performed" : "Série \(set.index+1) realizada"]
        if let reps = set.repetitions {
          facts.append(english ? "\(reps) repetitions" : "\(reps) repetições")
        }
        if let load = set.loadKg {
          let value = String(load)
          let trimmed = value.hasSuffix(".0") ? String(value.dropLast(2)) : value
          facts.append(
            (english ? trimmed : trimmed.replacingOccurrences(of: ".", with: ",")) + " kg")
        }
        if let seconds = set.durationSeconds { facts.append("\(seconds) s") }
        lines.append(facts.joined(separator: " · "))
      }
      if actual.completed && performed.isEmpty {
        lines.append(english ? "Marked as performed" : "Marcado como realizado")
      }
    }
    text = lines.joined(separator: "\n")
  }
}
