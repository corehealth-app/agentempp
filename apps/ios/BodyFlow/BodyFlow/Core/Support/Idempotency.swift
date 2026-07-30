import Foundation

struct IdempotencyKey: Hashable, Sendable {
    let value: String

    init(validating value: String) throws {
        guard (8...128).contains(value.count),
              value.unicodeScalars.allSatisfy(Self.isAllowed)
        else {
            throw BodyFlowCapabilityError.invalidIdempotencyKey
        }

        self.value = value
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122, 45...46, 58, 95:
            true
        default:
            false
        }
    }
}

protocol IdempotencyKeyProviding: Sendable {
    func nextKey() throws -> IdempotencyKey
}

struct UnavailableIdempotencyKeyProvider: IdempotencyKeyProviding {
    func nextKey() throws -> IdempotencyKey {
        throw BodyFlowCapabilityError.operationUnavailable
    }
}

enum MutationOperation: Hashable, Sendable {
    case proposalCreate
    case proposalEdit
    case proposalConfirm
    case proposalCancel
    case hydration
    case weight
    case routineAction
}

struct MutationAttempt<Payload: Hashable & Sendable>: Hashable, Sendable {
    let operation: MutationOperation
    let key: IdempotencyKey
    let payload: Payload
    let createdAt: Date
}
