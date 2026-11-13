import Foundation
import Observation

@MainActor @Observable
final class TrainingWindowModel {
  enum Phase { case idle, loading, loaded, unavailable }
  enum Failure { case changed, unavailable }
  enum Period: String, CaseIterable, Hashable { case day, week }
  var period: Period = .day
  private let provider: any TrainingWindowProviding
  private let expectedAuthUserID: UUID?
  private let isCurrent: @MainActor () -> Bool
  private var value: TrainingWindowSnapshot?
  private var lastObservation: TrainingWindowSnapshot?
  private var pendingRebind: TrainingWindowReadReference?
  private var state: Phase = .idle
  private(set) var failure: Failure?
  private var sequence = 0
  private var highestRevision = -1
  private var requestedDate: String?
  private var selectedDate: String?
  var snapshot: TrainingWindowSnapshot? { isCurrent() ? value : nil }
  var phase: Phase { isCurrent() ? state : .unavailable }
  var selectedDay: TrainingWindowDay? { snapshot?.days.first { $0.localDate == selectedDate } }
  init(
    provider: any TrainingWindowProviding, expectedAuthUserID: UUID?,
    isCurrent: @escaping @MainActor () -> Bool = { true }
  ) {
    self.provider = provider
    self.expectedAuthUserID = expectedAuthUserID
    self.isCurrent = isCurrent
  }
  func selectDay(_ date: String) {
    guard snapshot?.days.contains(where: { $0.localDate == date }) == true else { return }
    selectedDate = date
  }
  func load(revision: Int) async {
    guard revision >= highestRevision else { return }
    highestRevision = revision
    sequence += 1
    let ticket = sequence
    value = nil
    failure = nil
    state = .loading
    guard isCurrent(), expectedAuthUserID != nil else {
      state = .unavailable
      return
    }
    do {
      let date = requestedDate
      let rebinding = pendingRebind
      let next: TrainingWindowSnapshot
      if let rebinding {
        next = try await provider.rebindTrainingWindow(rebinding, date: date)
      } else {
        next = try await provider.trainingWindow(date: date)
      }
      try Task.checkCancellation()
      guard ticket == sequence, revision == highestRevision, isCurrent() else { return }
      guard next.authUserID == expectedAuthUserID,
        next.selectedLocalDate == (date ?? next.currentLocalDate)
      else {
        throw MobileAPITransportError.invalidResponse
      }
      if let previous = lastObservation {
        guard previous.ownerID == next.ownerID,
          let oldTime = ConversationProtocolInstant(previous.observedAt),
          let newTime = ConversationProtocolInstant(next.observedAt),
          newTime >= oldTime,
          newTime != oldTime || previous.weekStart != next.weekStart
            || previous.sourceVersion == next.sourceVersion
        else {
          failure = .changed
          state = .unavailable
          return
        }
        let scopeChanged = previous.epoch != next.epoch || previous.timezone != next.timezone
        if scopeChanged && rebinding == nil {
          pendingRebind = .init(next)
          failure = .changed
          state = .unavailable
          return
        }
      }
      if let rebinding, !rebinding.matches(next) { throw MobileAPITransportError.invalidResponse }
      pendingRebind = nil
      lastObservation = next
      value = next
      state = .loaded
      if !next.days.contains(where: { $0.localDate == selectedDate }) {
        selectedDate = next.selectedLocalDate
      }
    } catch {
      guard ticket == sequence else { return }
      pendingRebind = nil
      value = nil
      failure = .unavailable
      state = .unavailable
    }
  }
  func showToday(revision: Int) async {
    requestedDate = nil
    selectedDate = nil
    await load(revision: revision)
  }
  func shiftWeek(_ offset: Int, revision: Int) async {
    guard let start = snapshot?.weekStart,
      let date = NutritionCivilDate.add(start, days: offset * 7)
    else { return }
    requestedDate = date
    selectedDate = nil
    await load(revision: revision)
  }
}
