import Foundation

/// Independent of signup completion. No historical completion date is created.
struct OnboardingLegacyReconsentCapability: Codable, Equatable, Sendable {
    enum ProtocolVersion: String, Codable, Sendable { case documentsOnly = "documents_only_v1" }
    let protocolVersion: ProtocolVersion
    static let documentsOnly = Self(protocolVersion: .documentsOnly)
    private enum CodingKeys: String, CodingKey { case protocolVersion = "protocol" }
}

struct OnboardingLegacyDocumentInput: Encodable, Equatable, Sendable {
    let version = 1
    let locale: String
    let documentActions: [OnboardingDocumentAction]
    init(locale: String, actions: [OnboardingDocumentAction]) throws {
        guard OnboardingLocalePolicy.isSupported(locale), (1...16).contains(actions.count),
              Set(actions.map(\.documentKey)).count == actions.count,
              actions.allSatisfy({ action in
                  action.locale == locale && !action.documentKey.hasPrefix("dev_")
                    && action.documentKey.range(of: "^[a-z][a-z0-9_]{0,99}$", options: .regularExpression) != nil
                    && action.version.range(of: "^[A-Za-z0-9._-]{1,64}$", options: .regularExpression) != nil
                    && action.contentHash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
              }) else { throw OnboardingRepositoryError.invalidDraft }
        self.locale = locale
        documentActions = actions.sorted { $0.documentKey < $1.documentKey }
    }
    private enum CodingKeys: String, CodingKey { case version, locale; case documentActions = "document_actions" }
}

/// An original legal ACK is historical. Only a subsequent official GET may
/// decide that this session can enter the app after reset or new publication.
struct OnboardingLegacyDocumentAcknowledgement: Decodable, Sendable {
    struct Receipt: Decodable, Sendable {
        let id: UUID
        let locale: String
        let acceptedAt: APITimestamp
        let documentActions: [OnboardingAcceptedAction]
        private enum CodingKeys: String, CodingKey {
            case id, locale
            case acceptedAt = "accepted_at", documentActions = "document_actions"
        }
    }
    let version: Int
    let operationKey: UUID
    let receipt: Receipt
    private enum CodingKeys: String, CodingKey { case version, receipt; case operationKey = "operation_key" }
    func matches(_ input: OnboardingLegacyDocumentInput, key: IdempotencyKey) -> Bool {
        guard version == 1, operationKey.uuidString.lowercased() == key.value.lowercased(), receipt.locale == input.locale,
              Set(receipt.documentActions.map(\.documentKey)).count == receipt.documentActions.count else { return false }
        let identities = receipt.documentActions.map {
            OnboardingDocumentAction(documentKey: $0.documentKey, version: $0.version, locale: $0.locale, contentHash: $0.contentHash, action: $0.action)
        }.sorted { $0.documentKey < $1.documentKey }
        guard identities == input.documentActions else { return false }
        return receipt.documentActions.allSatisfy { action in
            guard !action.purpose.isEmpty,
                  let bytes = try? JSONEncoder().encode(action.actedAt),
                  let acted = try? JSONDecoder().decode(APITimestamp.self, from: bytes) else { return false }
            return acted.value <= receipt.acceptedAt.value
        }
    }
}
