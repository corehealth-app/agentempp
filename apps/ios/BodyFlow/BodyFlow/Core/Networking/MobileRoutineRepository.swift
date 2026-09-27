import Foundation

/// Supplements and medications over the mobile BFF. The server derives each
/// occurrence, its status and the allowed transitions; the client sends the
/// patient's action with the attempt's idempotency key and shows the result.
struct MobileRoutineRepository: RoutineProviding {
    let transport: any MobileAPIEnvelopeExecuting

    static let historyLimitRange = 1...50

    func list(
        kind: RoutineItemKind,
        includeArchived: Bool
    ) async throws -> RoutineListResponse {
        try await transport.executeCapability {
            try MobileAPIRequest(
                method: .get,
                path: Self.collectionPath(kind),
                queryItems: [URLQueryItem(
                    name: "include_archived",
                    value: includeArchived ? "true" : "false"
                )]
            )
        }
    }

    func record(
        _ attempt: MutationAttempt<RoutineActionCommand>
    ) async throws -> RoutineActionResponse {
        let command = attempt.payload
        let path = try Self.itemPath(command.kind, itemID: command.itemID, suffix: "/log")
        let body: Data
        do {
            body = try JSONEncoder().encode(command)
        } catch {
            throw BodyFlowCapabilityError.invalidInput
        }
        return try await transport.executeCapability {
            try MobileAPIRequest(
                method: .post,
                path: path,
                body: body,
                idempotencyKey: attempt.key
            )
        }
    }

    func history(
        kind: RoutineItemKind,
        itemID: String,
        cursor: String?,
        limit: Int
    ) async throws -> RoutineHistoryPage {
        guard Self.historyLimitRange.contains(limit) else {
            throw BodyFlowCapabilityError.invalidInput
        }
        let path = try Self.itemPath(kind, itemID: itemID, suffix: "/history")
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor {
            queryItems.append(URLQueryItem(
                name: "cursor",
                value: try MobileAPIPathSegment.cursor(cursor)
            ))
        }
        return try await transport.executeCapability {
            try MobileAPIRequest(method: .get, path: path, queryItems: queryItems)
        }
    }

    static func collectionPath(_ kind: RoutineItemKind) -> String {
        switch kind {
        case .supplement: "/api/mobile/v1/supplements"
        case .medication: "/api/mobile/v1/medications"
        }
    }

    static func itemPath(
        _ kind: RoutineItemKind,
        itemID: String,
        suffix: String = ""
    ) throws -> String {
        "\(collectionPath(kind))/\(try MobileAPIPathSegment.identifier(itemID))\(suffix)"
    }
}
