import Foundation
import Observation

/// A real authenticated shell owns one concrete Flow session. No factory is
/// invoked before load, and a withdrawn shell cannot publish late completion.
@MainActor @Observable
final class FlowConversationShellCoordinator {
  enum Phase: Equatable { case idle, loading, ready, unavailable, closed }
  private let userID: String
  private var source: FlowConversationSessionSource?
  private var session: FlowConversationBoundSession?
  private var work: Task<Void, Never>?
  private var workID: UUID?
  private var retirement: Task<Void, Never>?
  private(set) var phase = Phase.idle
  var model: FlowConversationModel? {
    guard phase != .closed, let model = session?.model, !model.isClosed else { return nil }
    return model
  }
  var captureStaging: MediaStagingStore? { model != nil ? source?.captureStaging : nil }
  init(userID: String, source: FlowConversationSessionSource) {
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
      var opened: FlowConversationBoundSession?
      do {
        let value = try await source.open(expectedUserID: self.userID)
        opened = value
        try Task.checkCancellation()
        try await value.publishIfCurrent { [weak self] binding in
          guard let self, self.phase != .closed, self.workID == id else { return }
          self.session = binding
          self.phase = .ready
        }
        guard self.phase == .ready, self.session === value else {
          await value.close()
          return
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
    work?.cancel()
    session?.invalidateSynchronously()
    source = nil
    if newlyClosed {
      // Start retirement immediately, independent of other shell readers
      // draining. Explicit close joins this same task instead of starting it.
      retirement = Task { @MainActor [weak self] in
        guard let self else { return }
        await self.work?.value
        await self.session?.close()
        self.session = nil
        self.work = nil
        self.workID = nil
      }
    }
  }
  func close() async {
    invalidateSynchronously()
    await retirement?.value
    retirement = nil
  }
}
