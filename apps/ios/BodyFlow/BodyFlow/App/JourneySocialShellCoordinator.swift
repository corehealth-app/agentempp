import Foundation
import Observation

@MainActor @Observable
final class JourneySocialShellCoordinator {
  enum Phase: Equatable { case idle, loading, ready, unavailable, closed }
  private let userID: String
  private var source: JourneySocialSessionSource?
  private var value: JourneySocialModel?
  private var work: Task<Void, Never>?
  private var workID: UUID?
  private var retirement: Task<Void, Never>?
  private(set) var phase = Phase.idle
  var model: JourneySocialModel? {
    guard phase != .closed, let value, !value.isClosed else { return nil }
    return value
  }
  var hasRetainedCapabilities: Bool { source != nil || value != nil || work != nil }
  init(userID: String, source: JourneySocialSessionSource) {
    self.userID = userID
    self.source = source
  }
  func load() async {
    guard phase != .closed, model == nil, !Task.isCancelled else { return }
    if let work {
      await work.value
      return
    }
    guard let source else { return }
    let id = UUID()
    workID = id
    phase = .loading
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      defer {
        if self.workID == id {
          self.work = nil
          self.workID = nil
        }
      }
      var opened: JourneySocialModel?
      do {
        await self.value?.close()
        self.value = nil
        let next = try await source.open(expectedUserID: self.userID)
        opened = next
        try Task.checkCancellation()
        try await next.publishIfCurrent {
          guard self.phase != .closed, self.workID == id else { throw CancellationError() }
          self.value = next
          self.phase = .ready
        }
      } catch {
        await opened?.close()
        guard self.phase != .closed, self.workID == id else { return }
        self.phase = .unavailable
      }
    }
    work = task
    await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
  }
  func invalidateSynchronously() {
    let newlyClosed = phase != .closed
    phase = .closed
    source = nil
    work?.cancel()
    value?.invalidateSynchronously()
    if newlyClosed {
      retirement = Task { @MainActor [self] in
        await work?.value
        await value?.close()
        value = nil
        work = nil
        workID = nil
      }
    }
  }
  func close() async {
    invalidateSynchronously()
    await retirement?.value
    retirement = nil
  }
}
