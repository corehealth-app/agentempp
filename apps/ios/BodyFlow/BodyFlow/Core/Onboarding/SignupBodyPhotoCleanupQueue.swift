import Foundation

/// Technical owner/G ledger. Last ACK does not erase a known scope or an uncertain create.
struct SignupBodyPhotoCleanupRepairRecord: Codable, Equatable, Sendable {
    let key: String
    let createdAt: Date
}

struct SignupBodyPhotoCleanupKnownScope: Codable, Equatable, Sendable {
    let generation: String
    var revision: UUID
    var operationID: UUID?
    var pending: Bool
    var repair: SignupBodyPhotoCleanupRepairRecord?
}

struct SignupBodyPhotoCleanupTicket: Codable, Equatable, Sendable {
    let userHash: String
    let generation: String
    let revision: UUID
    let operationID: UUID
    let repair: SignupBodyPhotoCleanupRepairRecord

    func mutationAttempt() throws -> MutationAttempt<SignupBodyPhotoRepairCommand> {
        MutationAttempt(operation: .mediaDelete,
            key: try IdempotencyKey(validating: repair.key),
            payload: SignupBodyPhotoRepairCommand(generation: generation),
            createdAt: repair.createdAt)
    }
}

struct SignupBodyPhotoCleanupQueue: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var version: Int
    let userHash: String
    var knownScopes: [SignupBodyPhotoCleanupKnownScope]
    var unboundCreates: [UUID]

    init(userHash: String, version: Int = currentVersion,
         knownScopes: [SignupBodyPhotoCleanupKnownScope] = [], unboundCreates: [UUID] = []) {
        self.userHash = userHash; self.version = version
        self.knownScopes = knownScopes; self.unboundCreates = unboundCreates
    }

    func scope(_ generation: String) -> SignupBodyPhotoCleanupKnownScope? {
        knownScopes.first { $0.generation == generation }
    }

    @discardableResult
    mutating func observePending(_ generation: String, newRevision: UUID) throws -> Bool {
        try validate()
        guard Self.validGeneration(generation) else { throw SignupBodyPhotoCleanupStoreError.invalidFormat }
        if let index = knownScopes.firstIndex(where: { $0.generation == generation }) {
            guard knownScopes[index].revision != newRevision else { throw SignupBodyPhotoCleanupStoreError.invalidFormat }
            knownScopes[index].revision = newRevision
            knownScopes[index].operationID = nil
            knownScopes[index].pending = true
        } else {
            knownScopes.append(SignupBodyPhotoCleanupKnownScope(generation: generation,
                revision: newRevision, operationID: nil, pending: true, repair: nil))
        }
        return true
    }

    mutating func prepareRepair(_ generation: String, expectedRevision: UUID,
        newRevision: UUID, operationID: UUID,
        takeKey: @Sendable () throws -> IdempotencyKey,
        takeDate: @Sendable () -> Date) throws -> SignupBodyPhotoCleanupTicket? {
        try validate()
        guard let index = knownScopes.firstIndex(where: { $0.generation == generation }),
              knownScopes[index].revision == expectedRevision else { return nil }
        guard newRevision != expectedRevision else { throw SignupBodyPhotoCleanupStoreError.invalidFormat }
        let repair: SignupBodyPhotoCleanupRepairRecord
        if let retained = knownScopes[index].repair { repair = retained }
        else { repair = SignupBodyPhotoCleanupRepairRecord(key: try takeKey().value, createdAt: takeDate()) }
        guard repair.createdAt.timeIntervalSince1970.isFinite else { throw SignupBodyPhotoCleanupStoreError.invalidFormat }
        knownScopes[index].revision = newRevision
        knownScopes[index].operationID = operationID
        knownScopes[index].pending = true
        knownScopes[index].repair = repair
        return SignupBodyPhotoCleanupTicket(userHash: userHash, generation: generation,
            revision: newRevision, operationID: operationID, repair: repair)
    }

    @discardableResult
    mutating func acknowledge(_ ticket: SignupBodyPhotoCleanupTicket,
        newRevision: UUID) throws -> Bool {
        try validate()
        guard ticket.userHash == userHash,
              let index = knownScopes.firstIndex(where: { $0.generation == ticket.generation }),
              knownScopes[index].revision == ticket.revision,
              knownScopes[index].operationID == ticket.operationID,
              knownScopes[index].repair == ticket.repair,
              knownScopes[index].pending else { return false }
        guard newRevision != ticket.revision else { throw SignupBodyPhotoCleanupStoreError.invalidFormat }
        knownScopes[index].revision = newRevision
        knownScopes[index].operationID = nil
        knownScopes[index].pending = false
        return true
    }

    @discardableResult
    mutating func resolveNotRequired(_ generation: String, expectedRevision: UUID) -> Bool {
        guard let index = knownScopes.firstIndex(where: { $0.generation == generation }),
              knownScopes[index].revision == expectedRevision else { return false }
        knownScopes.remove(at: index)
        return true
    }

    @discardableResult
    mutating func rememberUnbound(_ operationID: UUID) -> Bool {
        guard !unboundCreates.contains(operationID) else { return false }
        unboundCreates.append(operationID)
        return true
    }

    func validate() throws {
        guard version == Self.currentVersion else { throw SignupBodyPhotoCleanupStoreError.unsupportedVersion }
        guard userHash.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              Set(knownScopes.map(\.generation)).count == knownScopes.count,
              Set(unboundCreates).count == unboundCreates.count else { throw SignupBodyPhotoCleanupStoreError.invalidFormat }
        for scope in knownScopes {
            guard Self.validGeneration(scope.generation),
                  scope.operationID == nil || (scope.pending && scope.repair != nil) else { throw SignupBodyPhotoCleanupStoreError.invalidFormat }
            if let repair = scope.repair {
                guard (try? IdempotencyKey(validating: repair.key)) != nil,
                      repair.createdAt.timeIntervalSince1970.isFinite else { throw SignupBodyPhotoCleanupStoreError.invalidFormat }
            }
        }
    }

    private static func validGeneration(_ value: String) -> Bool {
        value.count <= 35 && value.range(of: #"^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,6})?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$"#, options: .regularExpression) != nil
            && (try? JSONDecoder().decode(APITimestamp.self, from: JSONEncoder().encode(value))) != nil
    }
}

enum SignupBodyPhotoCleanupStoreError: Error, Equatable, Sendable {
    case invalidFormat
    case unsupportedVersion
    case ownerMismatch
}

