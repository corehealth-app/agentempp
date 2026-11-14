import Foundation

struct TrainingExecutionSetDraft: Identifiable {
  let id: UUID, index: Int
  var repetitions = "", load = "", duration = ""
  var completed = false
  private let originalLoad: Double?
  private let originalLoadText: String
  init(index: Int) {
    id = UUID()
    self.index = index
    originalLoad = nil
    originalLoadText = ""
  }
  init(set: TrainingExecutionSet) {
    id = set.id
    index = set.index
    repetitions = set.repetitions.map { String($0) } ?? ""
    load = set.loadKg.map { String($0) } ?? ""
    duration = set.durationSeconds.map { String($0) } ?? ""
    completed = set.completed
    originalLoad = set.loadKg
    originalLoadText = load
  }
  func actual() throws -> TrainingExecutionSet {
    let kg: Double?
    if load == originalLoadText {
      kg = originalLoad
    } else {
      let trimmed = load.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        kg = nil
      } else {
        guard trimmed.utf16.count <= 32,
          trimmed.range(of: "^[0-9]+([.,][0-9]+)?$", options: .regularExpression) != nil,
          let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")), value.isFinite,
          (0...10000).contains(value)
        else { throw TrainingExecutionError.invalidResponse }
        kg = value
      }
    }
    return try .init(
      id: id, index: index, repetitions: integer(repetitions, max: 10000),
      loadKg: kg, durationSeconds: integer(duration, max: 86400), completed: completed)
  }
  private func integer(_ raw: String, max: Int) throws -> Int? {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty { return nil }
    guard value.utf16.count <= 10, value.range(of: "^[0-9]+$", options: .regularExpression) != nil,
      let number = Int(value), (0...max).contains(number)
    else { throw TrainingExecutionError.invalidResponse }
    return number
  }
}
