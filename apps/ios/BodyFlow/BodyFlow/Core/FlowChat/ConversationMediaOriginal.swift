import Darwin
import Foundation

/// One frozen Send original. No path, bearer or local session generation is
/// persisted. Recovery still requires the same authenticated patient and epoch.
struct ConversationMediaOriginal: Codable, Equatable, Sendable, CustomStringConvertible,
  CustomReflectable
{
  let captureID: UUID
  let intakeID: UUID
  let ownerID: UUID
  let epoch: UUID
  let kind: MediaUploadKind
  let mimeType: String
  let duration: TimeInterval?
  let channel: MealSourceChannel
  let fileExtension: String
  let caption: String?
  let mealTypeHint: ConversationMealCommand.MealType?
  let bytes: Data
  let bytesHash: String
  var assetID: UUID?

  init(
    staged: StagedMedia, staging: MediaStagingStore, captureID: UUID, intakeID: UUID,
    context: ConversationCommandContext.Identity, caption: String?,
    mealTypeHint: ConversationMealCommand.MealType?
  ) throws {
    let file = staged.fileURL.standardizedFileURL
    guard file.isFileURL,
      file.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        == staging.root.standardizedFileURL.resolvingSymlinksInPath(),
      (1...Self.maximumMediaBytes).contains(staged.sizeBytes)
    else { throw ConversationOutboxError.integrityFailure }
    self.captureID = captureID
    self.intakeID = intakeID
    ownerID = context.ownerID
    epoch = context.epoch
    kind = staged.kind
    mimeType = staged.mimeType
    duration = staged.duration
    channel = staged.channel
    fileExtension = file.pathExtension
    self.caption = caption
    self.mealTypeHint = mealTypeHint
    bytes = try Self.readOwnedBytes(file, count: staged.sizeBytes)
    bytesHash = ConversationMealCommand.digest(bytes)
    assetID = nil
    try validate()
  }

  static let maximumMediaBytes = max(
    MealMediaLimits.maximumPhotoBytes, MealMediaLimits.maximumAudioBytes)
  static let maximumEnvelopeBytes = maximumMediaBytes * 4 / 3 + 16_384

  func validate() throws {
    guard (1...Self.maximumMediaBytes).contains(bytes.count),
      ConversationMealCommand.digest(bytes) == bytesHash
    else { throw ConversationOutboxError.integrityFailure }
    switch kind {
    case .conversationPhoto:
      guard channel.isPhoto, mimeType == "image/jpeg", duration == nil,
        fileExtension == "jpg", bytes.count <= MealMediaLimits.maximumPhotoBytes
      else { throw ConversationOutboxError.integrityFailure }
    case .audioNote:
      guard channel.isAudio, let duration, duration.isFinite, duration > 0,
        duration <= MealMediaLimits.maximumAudioDuration,
        MealAudioInspector.stagedExtension(for: fileExtension) == fileExtension,
        MealAudioInspector.mimeTypesByExtension[fileExtension] == mimeType,
        bytes.count <= MealMediaLimits.maximumAudioBytes
      else { throw ConversationOutboxError.integrityFailure }
    default: throw ConversationOutboxError.integrityFailure
    }
    // Reuse the actual closed neutral wire validation without dispatching it.
    _ = try FlowNeutralIntakeInput(
      intakeID: intakeID, source: .media(assetID: assetID ?? captureID, caption: caption),
      mealTypeHint: mealTypeHint)
  }

  func input() throws -> FlowNeutralIntakeInput {
    guard let assetID else { throw ConversationOutboxError.invalidTransition }
    return try .init(
      intakeID: intakeID, source: .media(assetID: assetID, caption: caption),
      mealTypeHint: mealTypeHint)
  }
  func matchesUnbound(_ other: Self) -> Bool {
    var first = self
    var second = other
    first.assetID = nil
    second.assetID = nil
    return first == second
  }
  func restage(in staging: MediaStagingStore) throws -> StagedMedia {
    try validate()
    return .init(
      fileURL: try staging.stage(bytes, fileExtension: fileExtension), kind: kind,
      mimeType: mimeType, sizeBytes: bytes.count, duration: duration, channel: channel)
  }

  func ensureStaged(_ staged: StagedMedia, in staging: MediaStagingStore) throws {
    try validate()
    guard staged.kind == kind, staged.mimeType == mimeType, staged.duration == duration,
      staged.channel == channel, staged.sizeBytes == bytes.count,
      staged.fileURL.pathExtension == fileExtension,
      staged.fileURL.standardizedFileURL.deletingLastPathComponent().deletingLastPathComponent()
        == staging.root.standardizedFileURL,
      staged.fileURL.resolvingSymlinksInPath().deletingLastPathComponent()
        .deletingLastPathComponent().path
        == staging.root.standardizedFileURL.resolvingSymlinksInPath().path
    else { throw ConversationOutboxError.integrityFailure }
    if let current = try? Self.readOwnedBytes(staged.fileURL, count: bytes.count),
      ConversationMealCommand.digest(current) == bytesHash
    {
      return
    }
    try staging.restoreOriginalBytes(bytes, at: staged.fileURL)
    guard
      try ConversationMealCommand.digest(Self.readOwnedBytes(staged.fileURL, count: bytes.count))
        == bytesHash
    else {
      throw ConversationOutboxError.integrityFailure
    }
  }

  var description: String { "<protected conversation media original>" }
  var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .struct) }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case captureID, intakeID, ownerID, epoch, kind, mimeType, duration, channel, fileExtension,
      caption, mealTypeHint, bytes, bytesHash, assetID
  }
  init(from decoder: any Decoder) throws {
    let required: Set<String> = [
      "captureID", "intakeID", "ownerID", "epoch", "kind", "mimeType",
      "channel", "fileExtension", "bytes", "bytesHash",
    ]
    let keys = Set(
      try decoder.container(keyedBy: MediaOriginalStorageKey.self).allKeys.map(\.stringValue))
    guard required.isSubset(of: keys), keys.isSubset(of: Set(CodingKeys.allCases.map(\.rawValue)))
    else {
      throw ConversationOutboxError.integrityFailure
    }
    let c = try decoder.container(keyedBy: CodingKeys.self)
    captureID = try c.decode(UUID.self, forKey: .captureID)
    intakeID = try c.decode(UUID.self, forKey: .intakeID)
    ownerID = try c.decode(UUID.self, forKey: .ownerID)
    epoch = try c.decode(UUID.self, forKey: .epoch)
    kind = try c.decode(MediaUploadKind.self, forKey: .kind)
    mimeType = try c.decode(String.self, forKey: .mimeType)
    duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration)
    channel = try c.decode(MealSourceChannel.self, forKey: .channel)
    fileExtension = try c.decode(String.self, forKey: .fileExtension)
    caption = try c.decodeIfPresent(String.self, forKey: .caption)
    if let hint = try c.decodeIfPresent(String.self, forKey: .mealTypeHint) {
      guard let value = ConversationMealCommand.MealType(rawValue: hint) else {
        throw ConversationOutboxError.integrityFailure
      }
      mealTypeHint = value
    } else {
      mealTypeHint = nil
    }
    bytes = try c.decode(Data.self, forKey: .bytes)
    bytesHash = try c.decode(String.self, forKey: .bytesHash)
    assetID = try c.decodeIfPresent(UUID.self, forKey: .assetID)
    try validate()
  }

  func encode(to encoder: any Encoder) throws {
    try validate()
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(captureID, forKey: .captureID)
    try c.encode(intakeID, forKey: .intakeID)
    try c.encode(ownerID, forKey: .ownerID)
    try c.encode(epoch, forKey: .epoch)
    try c.encode(kind, forKey: .kind)
    try c.encode(mimeType, forKey: .mimeType)
    try c.encodeIfPresent(duration, forKey: .duration)
    try c.encode(channel, forKey: .channel)
    try c.encode(fileExtension, forKey: .fileExtension)
    try c.encodeIfPresent(caption, forKey: .caption)
    try c.encodeIfPresent(mealTypeHint?.rawValue, forKey: .mealTypeHint)
    try c.encode(bytes, forKey: .bytes)
    try c.encode(bytesHash, forKey: .bytesHash)
    try c.encodeIfPresent(assetID, forKey: .assetID)
  }

  private static func readOwnedBytes(_ url: URL, count: Int) throws -> Data {
    let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw ConversationOutboxError.storageUnavailable }
    defer { Darwin.close(fd) }
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size == count else {
      throw ConversationOutboxError.integrityFailure
    }
    var data = Data(count: count)
    try data.withUnsafeMutableBytes { bytes in
      var offset = 0
      while offset < count {
        let n = Darwin.read(fd, bytes.baseAddress!.advanced(by: offset), count - offset)
        if n < 0 && errno == EINTR { continue }
        guard n > 0 else { throw ConversationOutboxError.storageUnavailable }
        offset += n
      }
    }
    return data
  }
}

private struct MediaOriginalStorageKey: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

/// Serial file work is separate from the observable UI and from persisted identity.
protocol ConversationOriginalFileWorking: Sendable {
  func prepare(
    staged: StagedMedia, staging: MediaStagingStore, captureID: UUID, intakeID: UUID,
    identity: ConversationCommandContext.Identity, caption: String?,
    hint: ConversationMealCommand.MealType?
  ) async throws -> ConversationMediaOriginal
  func ensure(
    _ original: ConversationMediaOriginal, staged: StagedMedia, staging: MediaStagingStore)
    async throws
  func restage(_ original: ConversationMediaOriginal, staging: MediaStagingStore) async throws
    -> StagedMedia
}
actor ConversationOriginalFileWorker: ConversationOriginalFileWorking {
  func prepare(
    staged: StagedMedia, staging: MediaStagingStore, captureID: UUID, intakeID: UUID,
    identity: ConversationCommandContext.Identity, caption: String?,
    hint: ConversationMealCommand.MealType?
  ) throws -> ConversationMediaOriginal {
    try Task.checkCancellation()
    return try .init(
      staged: staged, staging: staging, captureID: captureID, intakeID: intakeID,
      context: identity, caption: caption, mealTypeHint: hint)
  }
  func ensure(
    _ original: ConversationMediaOriginal, staged: StagedMedia, staging: MediaStagingStore
  ) throws {
    try Task.checkCancellation()
    try original.ensureStaged(staged, in: staging)
  }
  func restage(_ original: ConversationMediaOriginal, staging: MediaStagingStore) throws
    -> StagedMedia
  {
    try Task.checkCancellation()
    return try original.restage(in: staging)
  }
}
