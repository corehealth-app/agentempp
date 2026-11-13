import CryptoKit
import Darwin
import Foundation

/// Constructed from an authenticated lease, never from composer text. The
/// stable hash deliberately excludes bearer and local session generation so
/// the same account can recover its ciphertext after logout or process death.
struct ConversationOutboxOwner: Sendable {
    let hash: String
    init(lease: SessionLease) throws {
        guard let id = UUID(uuidString: lease.userID) else { throw ConversationOutboxError.invalidOwner }
        hash = ConversationMealCommand.digest(Data("performe.conversation.outbox.v1\0\(id.uuidString.lowercased())".utf8))
    }
}

enum ConversationOutboxState: String, Codable, Sendable {
    case queued
    case dispatchedUnknown = "dispatched-unknown"
    case waitingReconciliation = "waiting-reconciliation"
}

enum ConversationOutboxHold: String, Codable, Sendable {
    case unknownOutcome, userCancelled, originalEpochUnavailable, originalOwnerUnavailable, notRecorded, staleEpoch, serverChanged, reset

    var priority: Int {
        switch self { case .unknownOutcome: 0; case .userCancelled: 1; case .originalEpochUnavailable, .originalOwnerUnavailable, .notRecorded: 2; case .staleEpoch, .serverChanged: 3; case .reset: 4 }
    }
}

struct ConversationOutboxEntry: Codable, Sendable, CustomStringConvertible, CustomReflectable {
    enum EpochProvenance: String, Codable, Sendable {
        case backendObservation = "backend-observation"
        case legacyV1Missing = "legacy-v1-missing"
    }
    enum OwnerProvenance: String, Codable, Sendable { case backendSession = "backend-session", legacyUnbound = "legacy-unbound" }
    let commandID: UUID
    let wireBody: Data
    let inputHash: String
    let originalServerEpoch: UUID?
    let epochProvenance: EpochProvenance
    let originalPatientOwnerID: UUID?
    let ownerProvenance: OwnerProvenance
    var state: ConversationOutboxState
    var hold: ConversationOutboxHold?

    init(command: ConversationMealCommand, originalServerEpoch: UUID, originalPatientOwnerID: UUID) {
        commandID = command.commandID; wireBody = command.wireBody; inputHash = command.inputHash
        self.originalServerEpoch = originalServerEpoch; epochProvenance = .backendObservation
        self.originalPatientOwnerID = originalPatientOwnerID; ownerProvenance = .backendSession
        state = .queued; hold = nil
    }

    fileprivate init(legacy command: ConversationMealCommand, state: ConversationOutboxState, hold: ConversationOutboxHold?, originalServerEpoch: UUID? = nil, epochProvenance: EpochProvenance = .legacyV1Missing) {
        commandID = command.commandID; wireBody = command.wireBody; inputHash = command.inputHash
        self.originalServerEpoch = originalServerEpoch; self.epochProvenance = epochProvenance
        originalPatientOwnerID = nil; ownerProvenance = .legacyUnbound
        // Preserve the proof of never-dispatched work; unknown work stays
        // undiscardable, even though no usable dispatch ticket can be issued.
        self.state = state == .queued ? .queued : .waitingReconciliation
        self.hold = hold ?? (originalServerEpoch == nil ? .originalEpochUnavailable : .originalOwnerUnavailable)
    }

    private enum CodingKeys: String, CodingKey {
        case commandID, wireBody, inputHash, originalServerEpoch, epochProvenance, originalPatientOwnerID, ownerProvenance, state, hold
    }
    init(from decoder: any Decoder) throws {
        try outboxKeys(decoder, required: ["commandID", "wireBody", "inputHash", "originalServerEpoch", "epochProvenance", "originalPatientOwnerID", "ownerProvenance", "state", "hold"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        commandID = try c.decode(UUID.self, forKey: .commandID)
        wireBody = try c.decode(Data.self, forKey: .wireBody)
        inputHash = try c.decode(String.self, forKey: .inputHash)
        originalServerEpoch = try c.decodeIfPresent(UUID.self, forKey: .originalServerEpoch)
        epochProvenance = try c.decode(EpochProvenance.self, forKey: .epochProvenance)
        originalPatientOwnerID = try c.decodeIfPresent(UUID.self, forKey: .originalPatientOwnerID)
        ownerProvenance = try c.decode(OwnerProvenance.self, forKey: .ownerProvenance)
        state = try c.decode(ConversationOutboxState.self, forKey: .state)
        hold = try c.decodeIfPresent(ConversationOutboxHold.self, forKey: .hold)
        try validate()
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(commandID, forKey: .commandID); try c.encode(wireBody, forKey: .wireBody)
        try c.encode(inputHash, forKey: .inputHash); try c.encode(originalServerEpoch, forKey: .originalServerEpoch)
        try c.encode(epochProvenance, forKey: .epochProvenance)
        try c.encode(originalPatientOwnerID, forKey: .originalPatientOwnerID); try c.encode(ownerProvenance, forKey: .ownerProvenance)
        try c.encode(state, forKey: .state)
        try c.encode(hold, forKey: .hold)
    }
    func validate() throws {
        let command = try ConversationMealCommand(wireBody: wireBody)
        guard command.commandID == commandID, command.wireBody == wireBody, command.inputHash == inputHash else {
            throw ConversationOutboxError.integrityFailure
        }
        guard (originalServerEpoch != nil) == (epochProvenance == .backendObservation),
              (originalPatientOwnerID != nil) == (ownerProvenance == .backendSession),
              ownerProvenance != .backendSession || epochProvenance == .backendObservation else { throw ConversationOutboxError.integrityFailure }
        if originalServerEpoch == nil || originalPatientOwnerID == nil {
            guard hold != nil, state != .dispatchedUnknown else { throw ConversationOutboxError.integrityFailure }
            if state == .queued {
                guard hold == .reset || hold == .originalEpochUnavailable || hold == .originalOwnerUnavailable else { throw ConversationOutboxError.integrityFailure }
            }
        } else {
            guard hold != .originalEpochUnavailable, hold != .originalOwnerUnavailable else { throw ConversationOutboxError.integrityFailure }
            switch state {
            case .queued: guard hold == nil || hold == .reset else { throw ConversationOutboxError.integrityFailure }
            case .dispatchedUnknown: guard hold == nil else { throw ConversationOutboxError.integrityFailure }
            case .waitingReconciliation: guard hold != nil else { throw ConversationOutboxError.integrityFailure }
            }
        }
    }

    var description: String { "ConversationOutboxEntry(redacted)" }
    var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .struct) }
}

/// A typed answer is not a report. Its exact original submission and question
/// stay protected in the same Auth-scoped file and shared capacity budget.
struct ConversationMealReplyOutboxEntry: Codable, Sendable, CustomStringConvertible, CustomReflectable {
    let intent: ConversationMealReplyIntent
    var state: ConversationOutboxState
    var hold: ConversationOutboxHold?
    init(intent: ConversationMealReplyIntent) {
        self.intent = intent; state = .queued; hold = nil
    }
    private enum CodingKeys: String, CodingKey { case intent, state, hold }
    init(from decoder: any Decoder) throws {
        try outboxKeys(decoder, required: ["intent", "state", "hold"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intent = try c.decode(ConversationMealReplyIntent.self, forKey: .intent)
        state = try c.decode(ConversationOutboxState.self, forKey: .state)
        hold = try c.decodeIfPresent(ConversationOutboxHold.self, forKey: .hold)
        try validate()
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(intent, forKey: .intent); try c.encode(state, forKey: .state)
        try c.encode(hold, forKey: .hold)
    }
    func validate() throws {
        if let hold {
            guard [.unknownOutcome, .userCancelled, .staleEpoch, .serverChanged, .reset].contains(hold) else {
                throw ConversationOutboxError.integrityFailure
            }
        }
        switch state {
        case .queued: guard hold == nil || hold == .reset else { throw ConversationOutboxError.integrityFailure }
        case .dispatchedUnknown: guard hold == nil else { throw ConversationOutboxError.integrityFailure }
        case .waitingReconciliation: guard hold != nil else { throw ConversationOutboxError.integrityFailure }
        }
    }
    var description: String { "ConversationMealReplyOutboxEntry(redacted)" }
    var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .struct) }
}

/// A neutral intent remains distinct from every legacy meal and typed reply.
/// Its original owner/epoch and bytes cannot be rebound after a refresh.
struct ConversationNeutralIntakeOutboxEntry: Codable, Sendable, CustomStringConvertible, CustomReflectable {
    let input: FlowNeutralIntakeInput
    let ownerID: UUID
    let epoch: UUID
    var state: ConversationOutboxState = .queued
    var hold: ConversationOutboxHold?
    init(input: FlowNeutralIntakeInput, ownerID: UUID, epoch: UUID) {
        self.input = input; self.ownerID = ownerID; self.epoch = epoch
    }
    private enum CodingKeys: String, CodingKey { case wireBody, inputHash, ownerID, epoch, state, hold }
    init(from decoder: any Decoder) throws {
        try outboxKeys(decoder, required: ["wireBody", "inputHash", "ownerID", "epoch", "state", "hold"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let wire = try c.decode(Data.self, forKey: .wireBody)
        input = try FlowNeutralIntakeInput(wireBody: wire)
        guard input.wireBody == wire, input.inputHash == (try c.decode(String.self, forKey: .inputHash)) else { throw ConversationOutboxError.integrityFailure }
        ownerID = try c.decode(UUID.self, forKey: .ownerID); epoch = try c.decode(UUID.self, forKey: .epoch)
        state = try c.decode(ConversationOutboxState.self, forKey: .state); hold = try c.decodeIfPresent(ConversationOutboxHold.self, forKey: .hold)
        try validate()
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(input.wireBody, forKey: .wireBody); try c.encode(input.inputHash, forKey: .inputHash)
        try c.encode(ownerID, forKey: .ownerID); try c.encode(epoch, forKey: .epoch)
        try c.encode(state, forKey: .state); try c.encode(hold, forKey: .hold)
    }
    func validate() throws {
        guard hold != .originalEpochUnavailable, hold != .originalOwnerUnavailable else { throw ConversationOutboxError.integrityFailure }
        switch state {
        case .queued: guard hold == nil || hold == .reset else { throw ConversationOutboxError.integrityFailure }
        case .dispatchedUnknown: guard hold == nil else { throw ConversationOutboxError.integrityFailure }
        case .waitingReconciliation: guard hold != nil else { throw ConversationOutboxError.integrityFailure }
        }
    }
    var description: String { "ConversationNeutralIntakeOutboxEntry(redacted)" }
    var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .struct) }
}

/// A synchronous disk transaction is called only inside the lifecycle's
/// patient-state gate. flock also excludes another store instance/process.
/// Ciphertext is retained on corruption, missing key, account change or logout.
struct EncryptedConversationOutboxStore: Sendable {
    // Existing Flow history/accepted-cache horizon is 50. Backpressure never
    // silently evicts a command whose server outcome may still be unknown.
    static let capacity = 50
    private static let maxBytes = capacity * 24_576 + 4_096
    private static let header = Data("PCOBX003".utf8)
    private static let mixedHeader = Data("PCOBX004".utf8)
    private static let neutralHeader = Data("PCOBX005".utf8)
    private static let previousHeader = Data("PCOBX002".utf8)
    private static let legacyHeader = Data("PCOBX001".utf8)
    private static let directoryCreationLock = NSLock()
    let root: URL

    init(directory: URL) {
        root = directory.appendingPathComponent("performe-conversation-outbox-v1", isDirectory: true)
    }

    static var device: Self { Self(directory: .applicationSupportDirectory) }

    func fileURL(owner: ConversationOutboxOwner) -> URL {
        root.appendingPathComponent(owner.hash + ".sealed", isDirectory: false)
    }

    func containsCiphertext(owner: ConversationOutboxOwner) throws -> Bool {
        try locked {
            let queue = try readCiphertext(owner: owner)
            let capture = try readCiphertext(at: originalFileURL(owner: owner), maximum: ConversationMediaOriginal.maximumEnvelopeBytes)
            let pending = try readCiphertext(at: originalPendingFileURL(owner: owner), maximum: ConversationMediaOriginal.maximumEnvelopeBytes)
            return queue != nil || capture != nil || pending != nil
        }
    }

    func originalFileURL(owner: ConversationOutboxOwner) -> URL {
        root.appendingPathComponent(owner.hash + ".original-sealed", isDirectory: false)
    }
    func originalPendingFileURL(owner: ConversationOutboxOwner) -> URL {
        root.appendingPathComponent("." + owner.hash + ".original-pending", isDirectory: false)
    }
    func containsOriginalCiphertext(owner: ConversationOutboxOwner) throws -> Bool {
        try locked {
            let canonical = try readCiphertext(at: originalFileURL(owner: owner), maximum: ConversationMediaOriginal.maximumEnvelopeBytes)
            let pending = try readCiphertext(at: originalPendingFileURL(owner: owner), maximum: ConversationMediaOriginal.maximumEnvelopeBytes)
            return canonical != nil || pending != nil
        }
    }
    struct OriginalObservation: Sendable {
        let original: ConversationMediaOriginal?
        let revision: String
    }
    private func originalRevision(_ envelope: OriginalEnvelope?) -> String {
        if let original = envelope?.original { return "original:" + original.captureID.uuidString + ":" + original.intakeID.uuidString }
        if let retired = envelope?.retired { return "retired:" + retired.intakeID.uuidString + ":" + String(retired.cancelled) }
        return "empty"
    }

    func prepareOriginal(_ candidate: ConversationMediaOriginal, expectedRevision: String? = nil, owner: ConversationOutboxOwner, key: SymmetricKey) throws -> ConversationMediaOriginal {
        try locked {
            try candidate.validate()
            let previous = try readOriginalEnvelope(owner: owner, key: key)
            if let expectedRevision, expectedRevision != originalRevision(previous), previous?.original?.matchesUnbound(candidate) != true {
                throw ConversationOutboxError.reconciliationRequired
            }
            if previous?.retired?.intakeID == candidate.intakeID { throw ConversationOutboxError.reconciliationRequired }
            if let old = previous?.original {
                guard old.matchesUnbound(candidate) else { throw ConversationOutboxError.invalidTransition }
                try syncOriginalDirectory()
                return old
            }
            let state = try readState(owner: owner, key: key)
            if let retired = previous?.retired, retired.cancelled,
               state.intakes.contains(where: { $0.input.intakeID == retired.intakeID }) {
                throw ConversationOutboxError.reconciliationRequired
            }
            guard state.entries.count + state.replies.count + state.intakes.count < Self.capacity else { throw ConversationOutboxError.queueFull }
            guard !state.entries.contains(where: { $0.commandID == candidate.intakeID }),
                  !state.replies.contains(where: { $0.intent.replyID == candidate.intakeID }),
                  !state.intakes.contains(where: { $0.input.intakeID == candidate.intakeID }) else { throw ConversationOutboxError.invalidTransition }
            try writeOriginalEnvelope(.init(owner: owner.hash, original: candidate, retired: nil), owner: owner, key: key)
            return candidate
        }
    }

    func bindOriginalAsset(intakeID: UUID, assetID: UUID, owner: ConversationOutboxOwner, key: SymmetricKey) throws -> ConversationMediaOriginal {
        try locked {
            guard var original = try readOriginalEnvelope(owner: owner, key: key)?.original,
                  original.intakeID == intakeID, original.assetID == nil || original.assetID == assetID else { throw ConversationOutboxError.invalidTransition }
            original.assetID = assetID
            try writeOriginalEnvelope(.init(owner: owner.hash, original: original, retired: nil), owner: owner, key: key)
            return original
        }
    }

    /// Reconcile a crash after enqueue but before retiring local capture bytes.
    /// This read never recreates an input or dispatches work.
    func loadOriginal(owner: ConversationOutboxOwner, key: SymmetricKey) throws -> ConversationMediaOriginal? {
        try observeOriginal(owner: owner, key: key).original
    }
    func observeOriginal(owner: ConversationOutboxOwner, key: SymmetricKey) throws -> OriginalObservation {
        try locked {
            guard let envelope = try readOriginalEnvelope(owner: owner, key: key) else { return .init(original: nil, revision: "empty") }
            var state = try readState(owner: owner, key: key)
            if let original = envelope.original {
                if let row = state.intakes.first(where: { $0.input.intakeID == original.intakeID }) {
                    try verifyOriginal(original, row: row)
                    guard row.state == .queued else { throw ConversationOutboxError.reconciliationRequired }
                    try writeOriginalEnvelope(.init(owner: owner.hash, original: nil, retired: .init(original, cancelled: false)), owner: owner, key: key)
                    return .init(original: nil, revision: "retired:" + original.intakeID.uuidString + ":false")
                }
                return .init(original: original, revision: originalRevision(envelope))
            }
            try syncOriginalDirectory()
            if let retired = envelope.retired, retired.cancelled,
               let index = state.intakes.firstIndex(where: { $0.input.intakeID == retired.intakeID }) {
                let row = state.intakes[index]
                guard row.state == .queued, row.ownerID == retired.ownerID, row.epoch == retired.epoch,
                      retired.inputHash == row.input.inputHash else { throw ConversationOutboxError.reconciliationRequired }
                state.intakes.remove(at: index)
                try write(state, owner: owner, key: key)
            }
            return .init(original: nil, revision: originalRevision(envelope))
        }
    }

    func promoteOriginal(_ input: FlowNeutralIntakeInput, ifPresent: Bool = false, owner: ConversationOutboxOwner, key: SymmetricKey) throws {
        try locked {
            guard let envelope = try readOriginalEnvelope(owner: owner, key: key) else {
                if ifPresent { return }
                throw ConversationOutboxError.invalidTransition
            }
            if ifPresent, (envelope.original?.intakeID ?? envelope.retired?.intakeID) != input.intakeID { return }
            if let retired = envelope.retired {
                guard !retired.cancelled, retired.intakeID == input.intakeID, retired.inputHash == input.inputHash else { throw ConversationOutboxError.invalidTransition }
                try syncOriginalDirectory()
                return
            }
            guard let original = envelope.original, try original.input().wireBody == input.wireBody,
                  let row = try readState(owner: owner, key: key).intakes.first(where: { $0.input.intakeID == input.intakeID }) else { throw ConversationOutboxError.invalidTransition }
            try verifyOriginal(original, row: row)
            guard row.state == .queued else { throw ConversationOutboxError.reconciliationRequired }
            try writeOriginalEnvelope(.init(owner: owner.hash, original: nil, retired: .init(original, cancelled: false)), owner: owner, key: key)
        }
    }

    /// Durable cancellation precedes queue removal. A crash between the writes
    /// cannot turn the previously cancelled original into a new registration.
    func discardOriginal(intakeID: UUID, owner: ConversationOutboxOwner, key: SymmetricKey) throws {
        try locked {
            guard let envelope = try readOriginalEnvelope(owner: owner, key: key) else { throw ConversationOutboxError.commandNotFound }
            var state = try readState(owner: owner, key: key)
            if let original = envelope.original {
                guard original.intakeID == intakeID else { throw ConversationOutboxError.commandNotFound }
                if let row = state.intakes.first(where: { $0.input.intakeID == intakeID }) {
                    try verifyOriginal(original, row: row)
                    guard row.state == .queued else { throw ConversationOutboxError.reconciliationRequired }
                }
                try writeOriginalEnvelope(.init(owner: owner.hash, original: nil, retired: .init(original, cancelled: true)), owner: owner, key: key)
            } else {
                guard let retired = envelope.retired, retired.intakeID == intakeID else { throw ConversationOutboxError.commandNotFound }
                guard retired.cancelled else { throw ConversationOutboxError.reconciliationRequired }
                try syncOriginalDirectory()
            }
            if let index = state.intakes.firstIndex(where: { $0.input.intakeID == intakeID }) {
                guard state.intakes[index].state == .queued else { throw ConversationOutboxError.reconciliationRequired }
                state.intakes.remove(at: index)
                try write(state, owner: owner, key: key)
            }
        }
    }

    private func verifyOriginal(_ original: ConversationMediaOriginal, row: ConversationNeutralIntakeOutboxEntry) throws {
        guard try original.input().wireBody == row.input.wireBody,
              original.ownerID == row.ownerID, original.epoch == row.epoch else { throw ConversationOutboxError.integrityFailure }
    }

    private struct OriginalRetirement: Codable {
        let intakeID: UUID, ownerID: UUID, epoch: UUID
        let inputHash: String?
        let cancelled: Bool
        init(_ original: ConversationMediaOriginal, cancelled: Bool) {
            intakeID = original.intakeID; ownerID = original.ownerID; epoch = original.epoch
            inputHash = try? original.input().inputHash; self.cancelled = cancelled
        }
    }
    private struct OriginalEnvelope: Codable {
        var version = 1
        let owner: String
        let original: ConversationMediaOriginal?
        let retired: OriginalRetirement?
        private enum CodingKeys: String, CodingKey { case version, owner, original, retired }
        init(owner: String, original: ConversationMediaOriginal?, retired: OriginalRetirement?) {
            self.owner = owner; self.original = original; self.retired = retired
        }
        init(from decoder: any Decoder) throws {
            try outboxKeys(decoder, required: ["version", "owner"], optional: ["original", "retired"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(Int.self, forKey: .version); owner = try c.decode(String.self, forKey: .owner)
            original = try c.decodeIfPresent(ConversationMediaOriginal.self, forKey: .original)
            retired = try c.decodeIfPresent(OriginalRetirement.self, forKey: .retired)
            guard version == 1, (original == nil) != (retired == nil) else { throw ConversationOutboxError.integrityFailure }
            if let retired {
                guard retired.cancelled || retired.inputHash != nil,
                      retired.inputHash.map({ $0.count == 64 && $0.allSatisfy({ "0123456789abcdef".contains($0) }) }) ?? retired.cancelled else { throw ConversationOutboxError.integrityFailure }
            }
        }
    }
    private func originalAAD(_ owner: ConversationOutboxOwner) -> Data {
        Data("performe.conversation.original\0version=1\0owner=\(owner.hash)".utf8)
    }
    private func decodeOriginalEnvelope(_ data: Data, owner: ConversationOutboxOwner, key: SymmetricKey) throws -> OriginalEnvelope {
        do {
            guard data.starts(with: Data("PCOMG001".utf8)) else { throw ConversationOutboxError.integrityFailure }
            let box = try AES.GCM.SealedBox(combined: data.dropFirst(8))
            let plain = try AES.GCM.open(box, using: key, authenticating: originalAAD(owner))
            let value = try JSONDecoder().decode(OriginalEnvelope.self, from: plain)
            guard value.owner == owner.hash else { throw ConversationOutboxError.integrityFailure }
            return value
        } catch { throw ConversationOutboxError.integrityFailure }
    }
    private func readOriginalEnvelope(owner: ConversationOutboxOwner, key: SymmetricKey) throws -> OriginalEnvelope? {
        let pendingURL = originalPendingFileURL(owner: owner)
        let canonicalURL = originalFileURL(owner: owner)
        let canonical = try readCiphertext(at: canonicalURL, maximum: ConversationMediaOriginal.maximumEnvelopeBytes)
        if let pending = try readCiphertext(at: pendingURL, maximum: ConversationMediaOriginal.maximumEnvelopeBytes) {
            // Only this exact authenticated, attributable uncommitted copy is ours.
            // Unknown/corrupt ciphertext and unrelated temporary files are preserved.
            _ = try decodeOriginalEnvelope(pending, owner: owner, key: key)
            if let canonical {
                _ = try decodeOriginalEnvelope(canonical, owner: owner, key: key)
                guard unlink(pendingURL.path) == 0 else { throw ConversationOutboxError.storageUnavailable }
            } else {
                guard rename(pendingURL.path, canonicalURL.path) == 0 else { throw ConversationOutboxError.storageUnavailable }
            }
            try syncOriginalDirectory()
        }
        guard let data = try readCiphertext(at: canonicalURL, maximum: ConversationMediaOriginal.maximumEnvelopeBytes) else { return nil }
        return try decodeOriginalEnvelope(data, owner: owner, key: key)
    }
    private func writeOriginalEnvelope(_ envelope: OriginalEnvelope, owner: ConversationOutboxOwner, key: SymmetricKey) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let plain = try encoder.encode(envelope)
        guard plain.count <= ConversationMediaOriginal.maximumEnvelopeBytes else { throw ConversationOutboxError.queueFull }
        let box = try AES.GCM.seal(plain, using: key, authenticating: originalAAD(owner))
        guard let data = box.combined else { throw ConversationOutboxError.storageUnavailable }
        try atomicReplace(Data("PCOMG001".utf8) + data, at: originalFileURL(owner: owner), temporaryURL: originalPendingFileURL(owner: owner))
        try syncOriginalDirectory()
    }
    private func syncOriginalDirectory() throws {
        let fd = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ConversationOutboxError.storageUnavailable }
        defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else { throw ConversationOutboxError.storageUnavailable }
    }

    func load(owner: ConversationOutboxOwner, key: SymmetricKey) throws -> [ConversationOutboxEntry] {
        try locked { try readState(owner: owner, key: key).entries }
    }

    func loadIntakes(owner: ConversationOutboxOwner, key: SymmetricKey) throws -> [ConversationNeutralIntakeOutboxEntry] {
        try locked { try readState(owner: owner, key: key).intakes }
    }
    @discardableResult
    func updateIntakes<Value: Sendable>(owner: ConversationOutboxOwner, key: SymmetricKey, _ mutation: (inout [ConversationNeutralIntakeOutboxEntry]) throws -> Value) throws -> Value {
        try locked {
            var state = try readState(owner: owner, key: key)
            let original = state.intakes
            let result = try mutation(&state.intakes)
            try Self.validateIntakeTransitions(from: original, to: state.intakes)
            state.version = 5
            try write(state, owner: owner, key: key)
            return result
        }
    }

    func loadReplies(owner: ConversationOutboxOwner, key: SymmetricKey) throws -> [ConversationMealReplyOutboxEntry] {
        try locked { try readState(owner: owner, key: key).replies }
    }

    @discardableResult
    func update<Value: Sendable>(
        owner: ConversationOutboxOwner, key: SymmetricKey,
        _ mutation: (inout [ConversationOutboxEntry]) throws -> Value
    ) throws -> Value {
        try locked {
            var state = try readState(owner: owner, key: key)
            let original = state.entries
            let result = try mutation(&state.entries)
            try Self.validateTransitions(from: original, to: state.entries)
            try write(state, owner: owner, key: key)
            return result
        }
    }

    @discardableResult
    func updateReplies<Value: Sendable>(
        owner: ConversationOutboxOwner, key: SymmetricKey,
        _ mutation: (inout [ConversationMealReplyOutboxEntry]) throws -> Value
    ) throws -> Value {
        try locked {
            var state = try readState(owner: owner, key: key)
            let original = state.replies
            let result = try mutation(&state.replies)
            try Self.validateReplyTransitions(from: original, to: state.replies)
            state.version = max(state.version, 4)
            try write(state, owner: owner, key: key)
            return result
        }
    }

    private struct State {
        var version: Int
        var entries: [ConversationOutboxEntry]
        var replies: [ConversationMealReplyOutboxEntry]
        var intakes: [ConversationNeutralIntakeOutboxEntry]
    }
    private func write(_ state: State, owner: ConversationOutboxOwner, key: SymmetricKey) throws {
        let capture = try readOriginalEnvelope(owner: owner, key: key)
        var reservation = 0
        if let original = capture?.original {
            guard !state.entries.contains(where: { $0.commandID == original.intakeID }),
                  !state.replies.contains(where: { $0.intent.replyID == original.intakeID }) else { throw ConversationOutboxError.integrityFailure }
            if let row = state.intakes.first(where: { $0.input.intakeID == original.intakeID }) {
                try verifyOriginal(original, row: row)
                guard row.state == .queued else { throw ConversationOutboxError.reconciliationRequired }
            } else { reservation = 1 }
        }
        if let retired = capture?.retired, retired.cancelled,
           let row = state.intakes.first(where: { $0.input.intakeID == retired.intakeID }) {
            guard row.state == .queued else { throw ConversationOutboxError.reconciliationRequired }
        }
        guard state.entries.count + state.replies.count + state.intakes.count + reservation <= Self.capacity else { throw ConversationOutboxError.queueFull }
        try Self.validate(state.entries)
        try Self.validateReplies(state.replies, reports: state.entries)
        try Self.validateIntakes(state.intakes, reports: state.entries, replies: state.replies)
        // Old report-only callers retain their qualified format until the first
        // typed reply. Once v4, closing its last reply never downgrades the file.
        let version = state.version >= 5 ? 5 : (state.version == 4 ? 4 : 3)
        let plain: Data
        if version == 5 {
            plain = try JSONEncoder().encode(NeutralEnvelope(owner: owner.hash, entries: state.entries, replies: state.replies, intakes: state.intakes))
        } else if version == 4 {
            plain = try JSONEncoder().encode(MixedEnvelope(owner: owner.hash, entries: state.entries, replies: state.replies))
        } else {
            plain = try JSONEncoder().encode(Envelope(version: 3, owner: owner.hash, entries: state.entries))
        }
        guard plain.count <= Self.maxBytes else { throw ConversationOutboxError.queueFull }
        let box = try AES.GCM.seal(plain, using: key, authenticating: aad(owner, version: version))
        guard let combined = box.combined else { throw ConversationOutboxError.storageUnavailable }
        try atomicReplace((version == 5 ? Self.neutralHeader : (version == 4 ? Self.mixedHeader : Self.header)) + combined, at: fileURL(owner: owner))
    }
    private struct NeutralEnvelope: Codable {
        let version: Int
        let owner: String
        let entries: [ConversationOutboxEntry]
        let replies: [ConversationMealReplyOutboxEntry]
        let intakes: [ConversationNeutralIntakeOutboxEntry]
        private enum CodingKeys: String, CodingKey { case version, owner, entries, replies, intakes }
        init(owner: String, entries: [ConversationOutboxEntry], replies: [ConversationMealReplyOutboxEntry], intakes: [ConversationNeutralIntakeOutboxEntry]) {
            version = 5; self.owner = owner; self.entries = entries; self.replies = replies; self.intakes = intakes
        }
        init(from decoder: any Decoder) throws {
            try outboxKeys(decoder, required: ["version", "owner", "entries", "replies", "intakes"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(Int.self, forKey: .version); owner = try c.decode(String.self, forKey: .owner)
            entries = try c.decode([ConversationOutboxEntry].self, forKey: .entries)
            replies = try c.decode([ConversationMealReplyOutboxEntry].self, forKey: .replies)
            intakes = try c.decode([ConversationNeutralIntakeOutboxEntry].self, forKey: .intakes)
        }
    }

    private struct MixedEnvelope: Codable {
        let version: Int
        let owner: String
        let entries: [ConversationOutboxEntry]
        let replies: [ConversationMealReplyOutboxEntry]
        private enum CodingKeys: String, CodingKey { case version, owner, entries, replies }
        init(owner: String, entries: [ConversationOutboxEntry], replies: [ConversationMealReplyOutboxEntry]) {
            version = 4; self.owner = owner; self.entries = entries; self.replies = replies
        }
        init(from decoder: any Decoder) throws {
            try outboxKeys(decoder, required: ["version", "owner", "entries", "replies"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(Int.self, forKey: .version); owner = try c.decode(String.self, forKey: .owner)
            entries = try c.decode([ConversationOutboxEntry].self, forKey: .entries)
            replies = try c.decode([ConversationMealReplyOutboxEntry].self, forKey: .replies)
        }
    }

    private struct Envelope: Codable {
        let version: Int
        let owner: String
        let entries: [ConversationOutboxEntry]
        private enum CodingKeys: String, CodingKey { case version, owner, entries }
        init(version: Int, owner: String, entries: [ConversationOutboxEntry]) {
            self.version = version; self.owner = owner; self.entries = entries
        }
        init(from decoder: any Decoder) throws {
            try outboxKeys(decoder, required: ["version", "owner", "entries"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(Int.self, forKey: .version); owner = try c.decode(String.self, forKey: .owner)
            entries = try c.decode([ConversationOutboxEntry].self, forKey: .entries)
        }
    }
    private struct LegacyEnvelope: Decodable {
        let version: Int
        let owner: String
        let entries: [LegacyEntry]
        private enum CodingKeys: String, CodingKey { case version, owner, entries }
        init(from decoder: any Decoder) throws {
            try outboxKeys(decoder, required: ["version", "owner", "entries"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(Int.self, forKey: .version); owner = try c.decode(String.self, forKey: .owner)
            entries = try c.decode([LegacyEntry].self, forKey: .entries)
        }
    }
    private struct PreviousEnvelope: Decodable {
        let version: Int
        let owner: String
        let entries: [PreviousEntry]
        private enum CodingKeys: String, CodingKey { case version, owner, entries }
        init(from decoder: any Decoder) throws {
            try outboxKeys(decoder, required: ["version", "owner", "entries"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(Int.self, forKey: .version); owner = try c.decode(String.self, forKey: .owner)
            entries = try c.decode([PreviousEntry].self, forKey: .entries)
        }
    }
    private struct PreviousEntry: Decodable {
        let value: ConversationOutboxEntry
        private enum CodingKeys: String, CodingKey { case commandID, wireBody, inputHash, originalServerEpoch, epochProvenance, state, hold }
        init(from decoder: any Decoder) throws {
            try outboxKeys(decoder, required: ["commandID", "wireBody", "inputHash", "originalServerEpoch", "epochProvenance", "state", "hold"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let id = try c.decode(UUID.self, forKey: .commandID), wire = try c.decode(Data.self, forKey: .wireBody)
            let hash = try c.decode(String.self, forKey: .inputHash), state = try c.decode(ConversationOutboxState.self, forKey: .state)
            let hold = try c.decodeIfPresent(ConversationOutboxHold.self, forKey: .hold)
            let epoch = try c.decodeIfPresent(UUID.self, forKey: .originalServerEpoch)
            let provenance = try c.decode(ConversationOutboxEntry.EpochProvenance.self, forKey: .epochProvenance)
            let command = try ConversationMealCommand(wireBody: wire)
            guard command.commandID == id, command.wireBody == wire, command.inputHash == hash,
                  hold != .originalOwnerUnavailable, hold != .notRecorded, hold != .serverChanged else { throw ConversationOutboxError.integrityFailure }
            if provenance == .legacyV1Missing {
                guard epoch == nil, hold != nil, state != .dispatchedUnknown else { throw ConversationOutboxError.integrityFailure }
            } else {
                guard epoch != nil, hold != .originalEpochUnavailable else { throw ConversationOutboxError.integrityFailure }
                switch state {
                case .queued: guard hold == nil || hold == .reset else { throw ConversationOutboxError.integrityFailure }
                case .dispatchedUnknown: guard hold == nil else { throw ConversationOutboxError.integrityFailure }
                case .waitingReconciliation: guard hold != nil else { throw ConversationOutboxError.integrityFailure }
                }
            }
            value = ConversationOutboxEntry(legacy: command, state: state, hold: hold, originalServerEpoch: epoch, epochProvenance: provenance)
        }
    }
    private struct LegacyEntry: Decodable {
        let value: ConversationOutboxEntry
        private enum CodingKeys: String, CodingKey { case commandID, wireBody, inputHash, state, hold }
        init(from decoder: any Decoder) throws {
            try outboxKeys(decoder, required: ["commandID", "wireBody", "inputHash", "state"], optional: ["hold"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let id = try c.decode(UUID.self, forKey: .commandID), wire = try c.decode(Data.self, forKey: .wireBody)
            let hash = try c.decode(String.self, forKey: .inputHash), state = try c.decode(ConversationOutboxState.self, forKey: .state)
            let hold = try c.decodeIfPresent(ConversationOutboxHold.self, forKey: .hold)
            let command = try ConversationMealCommand(wireBody: wire)
            guard command.commandID == id, command.wireBody == wire, command.inputHash == hash,
                  hold != .originalEpochUnavailable, hold != .originalOwnerUnavailable, hold != .notRecorded, hold != .serverChanged,
                  ((state == .waitingReconciliation) ? hold != nil : hold == nil) else { throw ConversationOutboxError.integrityFailure }
            value = ConversationOutboxEntry(legacy: command, state: state, hold: hold)
        }
    }
    private func aad(_ owner: ConversationOutboxOwner, version: Int) -> Data {
        Data("performe.conversation.outbox\0version=\(version)\0owner=\(owner.hash)".utf8)
    }

    private func readState(owner: ConversationOutboxOwner, key: SymmetricKey) throws -> State {
        guard let data = try readCiphertext(owner: owner) else { return .init(version: 3, entries: [], replies: [], intakes: []) }
        do {
            let version: Int
            if data.starts(with: Self.neutralHeader) { version = 5 }
            else if data.starts(with: Self.mixedHeader) { version = 4 }
            else if data.starts(with: Self.header) { version = 3 }
            else if data.starts(with: Self.previousHeader) { version = 2 }
            else if data.starts(with: Self.legacyHeader) { version = 1 }
            else { throw ConversationOutboxError.integrityFailure }
            let box = try AES.GCM.SealedBox(combined: data.dropFirst(Self.header.count))
            let plain = try AES.GCM.open(box, using: key, authenticating: aad(owner, version: version))
            let entries: [ConversationOutboxEntry]
            var replies: [ConversationMealReplyOutboxEntry] = []
            var intakes: [ConversationNeutralIntakeOutboxEntry] = []
            if version == 1 {
                let envelope = try JSONDecoder().decode(LegacyEnvelope.self, from: plain)
                guard envelope.version == 1, envelope.owner == owner.hash else { throw ConversationOutboxError.integrityFailure }
                entries = envelope.entries.map(\.value)
            } else if version == 2 {
                let envelope = try JSONDecoder().decode(PreviousEnvelope.self, from: plain)
                guard envelope.version == 2, envelope.owner == owner.hash else { throw ConversationOutboxError.integrityFailure }
                entries = envelope.entries.map(\.value)
            } else if version == 3 {
                let envelope = try JSONDecoder().decode(Envelope.self, from: plain)
                guard envelope.version == 3, envelope.owner == owner.hash else { throw ConversationOutboxError.integrityFailure }
                entries = envelope.entries
            } else if version == 4 {
                let envelope = try JSONDecoder().decode(MixedEnvelope.self, from: plain)
                guard envelope.version == 4, envelope.owner == owner.hash else { throw ConversationOutboxError.integrityFailure }
                entries = envelope.entries; replies = envelope.replies
            } else {
                let envelope = try JSONDecoder().decode(NeutralEnvelope.self, from: plain)
                guard envelope.version == 5, envelope.owner == owner.hash else { throw ConversationOutboxError.integrityFailure }
                entries = envelope.entries; replies = envelope.replies; intakes = envelope.intakes
            }
            try Self.validate(entries)
            try Self.validateReplies(replies, reports: entries)
            try Self.validateIntakes(intakes, reports: entries, replies: replies)
            return .init(version: version, entries: entries, replies: replies, intakes: intakes)
        } catch { throw ConversationOutboxError.integrityFailure }
    }

    private static func validateIntakes(_ intakes: [ConversationNeutralIntakeOutboxEntry], reports: [ConversationOutboxEntry], replies: [ConversationMealReplyOutboxEntry]) throws {
        let ids = intakes.map { $0.input.intakeID }
        guard reports.count + replies.count + intakes.count <= capacity,
              Set(ids).count == ids.count,
              Set(ids).isDisjoint(with: Set(reports.map(\.commandID))),
              Set(ids).isDisjoint(with: Set(replies.map { $0.intent.replyID })) else { throw ConversationOutboxError.integrityFailure }
        for row in intakes { try row.validate() }
    }
    private static func validateIntakeTransitions(from old: [ConversationNeutralIntakeOutboxEntry], to rows: [ConversationNeutralIntakeOutboxEntry]) throws {
        for previous in old {
            guard let next = rows.first(where: { $0.input.intakeID == previous.input.intakeID }) else { continue }
            guard previous.input.wireBody == next.input.wireBody, previous.input.inputHash == next.input.inputHash,
                  previous.ownerID == next.ownerID, previous.epoch == next.epoch else { throw ConversationOutboxError.integrityFailure }
            if previous.state != .queued && next.state == .queued { throw ConversationOutboxError.integrityFailure }
            if previous.state == .waitingReconciliation && next.state != .waitingReconciliation { throw ConversationOutboxError.integrityFailure }
            if let hold = previous.hold {
                guard let nextHold = next.hold, nextHold.priority >= hold.priority else { throw ConversationOutboxError.integrityFailure }
            }
        }
    }

    private static func validateReplies(_ replies: [ConversationMealReplyOutboxEntry], reports: [ConversationOutboxEntry]) throws {
        guard reports.count + replies.count <= Self.capacity,
              Set(replies.map { $0.intent.replyID }).count == replies.count,
              Set(reports.map(\.commandID)).isDisjoint(with: Set(replies.map { $0.intent.replyID })) else {
            throw ConversationOutboxError.integrityFailure
        }
        for reply in replies { try reply.validate() }
    }
    private static func validateReplyTransitions(from original: [ConversationMealReplyOutboxEntry], to replies: [ConversationMealReplyOutboxEntry]) throws {
        for old in original {
            guard let next = replies.first(where: { $0.intent.replyID == old.intent.replyID }) else { continue }
            guard old.intent.wireBody == next.intent.wireBody,
                  old.intent.replyInputHash == next.intent.replyInputHash,
                  old.intent.parentBinding == next.intent.parentBinding,
                  old.intent.parentDecisionHash == next.intent.parentDecisionHash,
                  old.intent.question.encodedData == next.intent.question.encodedData else {
                throw ConversationOutboxError.integrityFailure
            }
            if old.state != .queued && next.state == .queued { throw ConversationOutboxError.integrityFailure }
            if old.state == .waitingReconciliation && next.state != .waitingReconciliation { throw ConversationOutboxError.integrityFailure }
            if let hold = old.hold {
                guard let nextHold = next.hold, nextHold.priority >= hold.priority else { throw ConversationOutboxError.integrityFailure }
            }
        }
    }

    private static func validateTransitions(from original: [ConversationOutboxEntry], to entries: [ConversationOutboxEntry]) throws {
        for old in original {
            guard let new = entries.first(where: { $0.commandID == old.commandID }) else { continue }
            guard old.wireBody == new.wireBody, old.inputHash == new.inputHash,
                  old.originalServerEpoch == new.originalServerEpoch, old.epochProvenance == new.epochProvenance,
                  old.originalPatientOwnerID == new.originalPatientOwnerID, old.ownerProvenance == new.ownerProvenance else {
                // Hold monotonicity is checked explicitly below; identities can
                // never be rebound, including nil legacy epoch becoming current.
                throw ConversationOutboxError.integrityFailure
            }
            if let hold = old.hold {
                guard let next = new.hold, next.priority >= hold.priority else { throw ConversationOutboxError.integrityFailure }
            }
            if old.state != .queued {
                guard new.state != .queued else { throw ConversationOutboxError.integrityFailure }
            }
            if old.state == .waitingReconciliation {
                guard new.state == .waitingReconciliation else { throw ConversationOutboxError.integrityFailure }
            }
        }
    }

    private static func validate(_ entries: [ConversationOutboxEntry]) throws {
        guard entries.count <= capacity, Set(entries.map(\.commandID)).count == entries.count else {
            throw ConversationOutboxError.integrityFailure
        }
        for entry in entries { try entry.validate() }
    }

    private func prepareDirectory() throws {
        // The initial directory must already be private when it becomes
        // visible to another instance. Metadata configuration follows under
        // the process-shared file lock, rather than racing before that lock.
        try Self.directoryCreationLock.withLock {
            try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard mkdir(root.path, 0o700) == 0 || errno == EEXIST else { throw ConversationOutboxError.storageUnavailable }
        }
        var info = stat()
        guard lstat(root.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_mode & 0o077 == 0 else { throw ConversationOutboxError.storageUnavailable }
    }

    private func configureDirectory() throws {
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var directory = root; try directory.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: root.path)
        #endif
    }

    private func locked<Value>(operation: () throws -> Value) throws -> Value {
        do {
            try prepareDirectory()
            // One empty store lock also serializes protection/backup metadata
            // across accounts and processes. Command files remain per account.
            let path = root.appendingPathComponent(".store.lock").path
            let descriptor = open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw ConversationOutboxError.storageUnavailable }
            defer { close(descriptor) }
            while flock(descriptor, LOCK_EX) != 0 {
                guard errno == EINTR else { throw ConversationOutboxError.storageUnavailable }
            }
            defer { flock(descriptor, LOCK_UN) }
            try configureDirectory()
            return try operation()
        } catch let error as ConversationOutboxError { throw error }
        catch { throw ConversationOutboxError.storageUnavailable }
    }

    private func readCiphertext(owner: ConversationOutboxOwner) throws -> Data? {
        try readCiphertext(at: fileURL(owner: owner), maximum: Self.maxBytes)
    }
    private func readCiphertext(at url: URL, maximum: Int) throws -> Data? {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw ConversationOutboxError.storageUnavailable
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size > 0, info.st_size <= maximum + 128 else {
            throw ConversationOutboxError.integrityFailure
        }
        var data = Data(count: Int(info.st_size))
        try data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.read(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw ConversationOutboxError.storageUnavailable }
                offset += count
            }
        }
        return data
    }

    /// Only ciphertext touches the temporary file. No throwing operation is
    /// performed after rename, so a reported failure preserves the old queue.
    private func atomicReplace(_ ciphertext: Data, at destination: URL, temporaryURL: URL? = nil) throws {
        let temporary = temporaryURL ?? root.appendingPathComponent(".\(UUID().uuidString).sealed-tmp")
        let descriptor = open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw ConversationOutboxError.storageUnavailable }
        defer { close(descriptor); unlink(temporary.path) }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: temporary.path)
        #endif
        try ciphertext.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw ConversationOutboxError.storageUnavailable }
                offset += count
            }
        }
        guard fsync(descriptor) == 0, rename(temporary.path, destination.path) == 0 else {
            throw ConversationOutboxError.storageUnavailable
        }
    }
}

private struct OutboxStorageKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
private func outboxKeys(_ decoder: any Decoder, required: Set<String>, optional: Set<String> = []) throws {
    let keys = Set(try decoder.container(keyedBy: OutboxStorageKey.self).allKeys.map(\.stringValue))
    guard required.isSubset(of: keys), keys.isSubset(of: required.union(optional)) else { throw ConversationOutboxError.integrityFailure }
}
