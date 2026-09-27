import Foundation

/// Server-issued identifiers travel back into request paths, so only the
/// UUID alphabet is accepted there; anything else fails closed as invalid
/// input before a request exists.
enum MobileAPIPathSegment {
    static func identifier(_ value: String) throws -> String {
        guard (1...64).contains(value.count),
              value.unicodeScalars.allSatisfy({ scalar in
                  ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
                      || ("0"..."9").contains(scalar) || scalar == "-"
              })
        else {
            throw BodyFlowCapabilityError.invalidInput
        }
        return value
    }

    /// Opaque pagination cursors are base64url tokens from the server;
    /// anything else would only earn a 422, so it fails closed here.
    static func cursor(_ value: String) throws -> String {
        guard (1...512).contains(value.count),
              value.unicodeScalars.allSatisfy({ scalar in
                  ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
                      || ("0"..."9").contains(scalar) || scalar == "_" || scalar == "-"
              })
        else {
            throw BodyFlowCapabilityError.invalidInput
        }
        return value
    }
}

extension MobileAPIEnvelopeExecuting {
    /// Runs one request and translates transport failures into the
    /// capability states the screens already render. Cancellation and
    /// capability errors pass through untouched; a request that cannot be
    /// formed is invalid input, never a fabricated success.
    func executeCapability<Payload: Codable & Sendable>(
        _ request: () throws -> MobileAPIRequest<Payload>
    ) async throws -> MobileResponse<Payload> {
        do {
            return try await executeEnvelope(try request())
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as BodyFlowCapabilityError {
            throw error
        } catch let error as MobileAPITransportError {
            throw error.capabilityError
        } catch is MobileAPIRequestError {
            throw BodyFlowCapabilityError.invalidInput
        } catch {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
    }
}
