import Foundation

/// Upload and processing only: no draft extractor, nutrition calculation,
/// registration or success publication. Callers persist the exact command
/// before process(); protected/uncertain queued assets survive close.
actor ConversationMealMediaService {
  private struct Capture: Sendable {
    let staged: StagedMedia
    let identity: ConversationCommandContext.Identity
    var assetID: UUID?
    var completed = false
    var retained = false
  }
  private let transport: MobileAPITransport
  private let lifecycle: any SessionLifecycleProviding
  private var lease: SessionLease?
  private let uploader: any StorageUploading
  private let staging: MediaStagingStore
  private let clock: any Clock<Duration>
  private let pollInterval: Duration
  private let maximumPolls: Int
  private let cancellation = ConversationMediaCancellation()
  private var workID: UUID?
  private var captures: [UUID: Capture] = [:]
  private var activeCaptures: Set<UUID> = []
  private var discarded: Set<UUID> = []

  private init(
    transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding, lease: SessionLease,
    uploader: any StorageUploading, staging: MediaStagingStore, clock: any Clock<Duration>,
    pollInterval: Duration, maximumPolls: Int
  ) {
    self.transport = transport
    self.lifecycle = lifecycle
    self.lease = lease
    self.uploader = uploader
    self.staging = staging
    self.clock = clock
    self.pollInterval = pollInterval
    self.maximumPolls = maximumPolls
  }
  static func open(
    transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding, lease: SessionLease,
    uploader: any StorageUploading, staging: MediaStagingStore,
    clock: any Clock<Duration> = ContinuousClock(),
    // Reuse MealDraftModel's existing processing read budget.
    pollInterval: Duration = .milliseconds(1_500), maximumPolls: Int = 80
  ) async throws -> Self {
    let scoped = transport.scoped(to: lease)
    try await scoped.validateOriginalSession(lease)
    let service = Self(
      transport: scoped, lifecycle: lifecycle, lease: lease, uploader: uploader,
      staging: staging, clock: clock, pollInterval: pollInterval, maximumPolls: maximumPolls)
    let cancellation = service.cancellation
    do {
      let id = try await lifecycle.beginPatientWork(lease: lease) { [weak service] in
        cancellation.close()
        Task { await service?.close() }
      }
      try await service.install(id)
      try await lifecycle.validate(lease)
      try Task.checkCancellation()
      return service
    } catch {
      await service.close()
      throw error
    }
  }
  private func install(_ id: UUID) async throws {
    do {
      try cancellation.check()
      workID = id
    } catch {
      await lifecycle.finishPatientWork(id)
      throw error
    }
  }

  func upload(_ staged: StagedMedia, captureID: UUID, context: ConversationCommandContext)
    async throws -> UUID
  {
    try cancellation.check()
    guard !discarded.contains(captureID), !activeCaptures.contains(captureID) else {
      throw MealCaptureFailure.unavailable
    }
    try validateStaged(staged, completed: captures[captureID]?.completed == true)
    if let old = captures[captureID] {
      guard old.staged == staged, old.identity == context.identity else {
        throw ConversationOutboxError.invalidServerObservation
      }
    } else {
      captures[captureID] = .init(staged: staged, identity: context.identity)
    }
    activeCaptures.insert(captureID)
    defer { activeCaptures.remove(captureID) }
    return try await run(context: context) {
      try await self.performUpload(captureID: captureID, context: context)
    }
  }
  private func performUpload(captureID: UUID, context: ConversationCommandContext) async throws
    -> UUID
  {
    var capture = try currentCapture(captureID, context: context)
    if capture.completed, let id = capture.assetID { return id }
    let media = try await repository(context)
    let created = try await media.create(
      attempt(.mediaCreate, capture.staged.uploadRequest, id: captureID, suffix: "create"))
    try cancellation.check()
    capture = try currentCapture(captureID, context: context)
    let assetID = try asset(created.asset, expected: capture.assetID, kind: capture.staged.kind)
    capture.assetID = assetID
    captures[captureID] = capture
    switch created.asset.state {
    case .pendingUpload:
      guard let ticket = created.upload else { throw MealCaptureFailure.uploadRejected }
      try await uploader.upload(capture.staged, with: ticket)
      try cancellation.check()
      _ = try currentCapture(captureID, context: context)
    case .uploaded, .processing, .processed: break
    default: throw MealCaptureFailure.uploadRejected
    }
    let completed = try await media.complete(
      attempt(
        .mediaComplete, .init(assetID: assetID.uuidString.lowercased()), id: captureID,
        suffix: "complete"))
    try cancellation.check()
    capture = try currentCapture(captureID, context: context)
    _ = try asset(completed, expected: assetID, kind: capture.staged.kind)
    guard [.uploaded, .processing, .processed].contains(completed.state) else {
      throw MealCaptureFailure.uploadRejected
    }
    capture.completed = true
    captures[captureID] = capture
    staging.remove(capture.staged.fileURL)
    return assetID
  }

  /// Mark before the persistence attempt: a response/cancellation may be lost
  /// after the encrypted write. Such uncertainty never licenses blob deletion.
  func retainForEnqueue(
    captureID: UUID, command: ConversationMealCommand,
    expectedContext: ConversationCommandContext.Identity
  ) throws {
    try cancellation.check()
    guard var capture = captures[captureID], capture.completed, capture.identity == expectedContext,
      case .media(let assetID, _) = command.source, capture.assetID == assetID
    else { throw ConversationOutboxError.invalidTransition }
    capture.retained = true
    captures[captureID] = capture
  }

  /// Explicit resume first reads the existing asset. A currently processing
  /// asset only gets reads; an unknown POST never repeats inside this call.
  func process(
    command: ConversationMealCommand, expectedContext: ConversationCommandContext.Identity,
    context: ConversationCommandContext
  ) async throws {
    guard expectedContext == context.identity, case .media(let assetID, _) = command.source else {
      throw ConversationOutboxError.invalidServerObservation
    }
    try await run(context: context) {
      let media = try await self.repository(context)
      let initial = try await media.asset(id: assetID.uuidString.lowercased())
      _ = try self.asset(initial, expected: assetID)
      switch initial.state {
      case .processed: return
      case .uploaded:
        let response = try await media.requestProcessing(
          self.attempt(
            .mediaProcess, .init(assetID: assetID.uuidString.lowercased()), id: command.commandID,
            suffix: "process"))
        _ = try self.asset(response, expected: assetID)
        if response.state == .processed { return }
        if case .failed = response.state { throw MealCaptureFailure.processingFailed }
      case .processing: break
      case .failed: throw MealCaptureFailure.processingFailed
      default: throw MealCaptureFailure.uploadRejected
      }
      try await self.poll(media, assetID: assetID)
    }
  }
  private func poll(_ media: MobileConversationMediaRepository, assetID: UUID) async throws {
    for index in 0..<maximumPolls {
      if index > 0 { try await clock.sleep(for: pollInterval) }
      try cancellation.check()
      try Task.checkCancellation()
      let value = try await media.asset(id: assetID.uuidString.lowercased())
      _ = try asset(value, expected: assetID)
      switch value.state {
      case .processed: return
      case .failed: throw MealCaptureFailure.processingFailed
      case .processing, .uploaded: continue
      default: throw MealCaptureFailure.uploadRejected
      }
    }
    throw MealCaptureFailure.processingTimedOut
  }

  func discard(captureID: UUID, context: ConversationCommandContext) async throws {
    guard let capture = captures[captureID] else { return }
    staging.remove(capture.staged.fileURL)
    guard !capture.retained else { return }
    guard capture.identity == context.identity else {
      throw ConversationOutboxError.invalidServerObservation
    }
    discarded.insert(captureID)
    if let id = capture.assetID {
      try await run(context: context) {
        let media = try await self.repository(context)
        try await media.delete(
          self.attempt(
            .mediaDelete, .init(assetID: id.uuidString.lowercased()), id: captureID,
            suffix: "delete"))
      }
    }
    captures.removeValue(forKey: captureID)
  }
  func close() async {
    cancellation.close()
    lease = nil
    for capture in captures.values { staging.remove(capture.staged.fileURL) }
    captures.removeAll()
    activeCaptures.removeAll()
    discarded.removeAll()
    // No remote DELETE on logout, unknown enqueue or protected command.
    if let id = workID {
      workID = nil
      await lifecycle.finishPatientWork(id)
    }
  }

  private func currentCapture(_ id: UUID, context: ConversationCommandContext) throws -> Capture {
    try cancellation.check()
    try Task.checkCancellation()
    try context.withCurrentAuthority {}
    guard !discarded.contains(id), let capture = captures[id], capture.identity == context.identity
    else { throw CancellationError() }
    return capture
  }
  private func validateStaged(_ media: StagedMedia, completed: Bool) throws {
    let file = media.fileURL.standardizedFileURL.resolvingSymlinksInPath()
    let root = staging.root.standardizedFileURL.resolvingSymlinksInPath()
    guard media.fileURL.isFileURL,
      file.deletingLastPathComponent().deletingLastPathComponent() == root
    else { throw MealCaptureFailure.invalidInput }
    switch media.kind {
    case .mealPhoto:
      guard media.channel.isPhoto, media.mimeType == "image/jpeg", media.duration == nil,
        (1...MealMediaLimits.maximumPhotoBytes).contains(media.sizeBytes)
      else { throw MealCaptureFailure.invalidInput }
    case .audioNote:
      guard media.channel.isAudio, media.mimeType.hasPrefix("audio/"),
        let duration = media.duration,
        duration.isFinite, duration > 0, duration <= MealMediaLimits.maximumAudioDuration,
        (1...MealMediaLimits.maximumAudioBytes).contains(media.sizeBytes)
      else { throw MealCaptureFailure.invalidInput }
    default: throw MealCaptureFailure.invalidInput
    }
    // A completed upload intentionally no longer has a local staged file.
    if !completed {
      guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
        attributes[.type] as? FileAttributeType == .typeRegular,
        (attributes[.size] as? NSNumber)?.intValue == media.sizeBytes
      else { throw MealCaptureFailure.unreadableMedia }
    }
  }
  private func repository(_ context: ConversationCommandContext) async throws
    -> MobileConversationMediaRepository
  {
    guard let lease else { throw ConversationOutboxError.sessionClosed }
    return try await .scoped(
      transport: transport, lifecycle: lifecycle, lease: lease, context: context)
  }
  private nonisolated func asset(
    _ value: MediaAssetSnapshot, expected: UUID?, kind: MediaUploadKind? = nil
  ) throws -> UUID {
    guard let id = UUID(uuidString: value.id), value.id == id.uuidString.lowercased(),
      expected == nil || id == expected,
      kind.map({ $0.rawValue == value.kind })
        ?? [MediaUploadKind.mealPhoto.rawValue, MediaUploadKind.audioNote.rawValue].contains(
          value.kind)
    else { throw MealCaptureFailure.uploadRejected }
    return id
  }
  private nonisolated func attempt<P>(
    _ operation: MutationOperation, _ payload: P, id: UUID, suffix: String
  ) throws -> MutationAttempt<P> {
    .init(
      operation: operation,
      key: try IdempotencyKey(validating: "cmedia1:\(id.uuidString.lowercased()):\(suffix)"),
      payload: payload, createdAt: Date())
  }
  private func run<Value: Sendable>(
    context: ConversationCommandContext, _ operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    try cancellation.check()
    try Task.checkCancellation()
    guard let lease, !context.observation.isEnqueueOnly,
      context.authUserID == UUID(uuidString: lease.userID),
      context.sessionGeneration == lease.generation
    else { throw ConversationOutboxError.invalidServerObservation }
    let lifecycle = lifecycle
    let cancellation = cancellation
    let task = Task {
      try await lifecycle.validate(lease)
      try Task.checkCancellation()
      try context.withCurrentAuthority {}
      let value = try await operation()
      try await lifecycle.validate(lease)
      try Task.checkCancellation()
      try context.withCurrentAuthority {}
      try cancellation.check()
      return value
    }
    let id = cancellation.install { task.cancel() }
    defer { cancellation.remove(id) }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }
}

private final class ConversationMediaCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var closed = false
  private var cancellations: [UUID: @Sendable () -> Void] = [:]
  func check() throws {
    try lock.withLock { if closed { throw ConversationOutboxError.sessionClosed } }
  }
  func install(_ cancel: @escaping @Sendable () -> Void) -> UUID {
    let id = UUID()
    let now = lock.withLock {
      if closed { return true }
      cancellations[id] = cancel
      return false
    }
    if now { cancel() }
    return id
  }
  func remove(_ id: UUID) { lock.withLock { _ = cancellations.removeValue(forKey: id) } }
  func close() {
    let values = lock.withLock {
      closed = true
      let values = Array(cancellations.values)
      cancellations.removeAll()
      return values
    }
    for cancel in values { cancel() }
  }
}
