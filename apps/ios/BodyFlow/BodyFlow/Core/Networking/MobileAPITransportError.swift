import Foundation

enum MobileAPIConfigurationError: Error, Equatable, Sendable {
    case missingOrigin
    case invalidOrigin
}

enum MobileAPIRequestError: Error, Equatable, Sendable {
    case invalidPath
    case invalidQuery
    case unexpectedIdempotencyKey
}

enum MobileAPITransportError: Error, Equatable, Sendable {
    case unavailableConfiguration
    case missingSession
    case sessionSuperseded
    case redirectNotAllowed
    case timeout
    case responseTooLarge(limit: Int)
    case invalidResponse
    case decodingFailure
    case unauthorized(code: String, requestID: String?)
    case forbidden(code: String, requestID: String?)
    case conflict(code: String, requestID: String?)
    case validation(code: String, requestID: String?)
    case rateLimited(code: String, requestID: String?)
    case server(status: Int, code: String, requestID: String?)
    case http(status: Int, code: String, requestID: String?)
    case network
}

extension MobileAPITransportError: CustomStringConvertible {
    var description: String {
        switch self {
        case .unavailableConfiguration: "mobile_api_unavailable_configuration"
        case .missingSession: "mobile_api_missing_session"
        case .sessionSuperseded: "mobile_api_session_superseded"
        case .redirectNotAllowed: "mobile_api_redirect_not_allowed"
        case .timeout: "mobile_api_timeout"
        case .responseTooLarge: "mobile_api_response_too_large"
        case .invalidResponse: "mobile_api_invalid_response"
        case .decodingFailure: "mobile_api_decoding_failure"
        case .unauthorized(let code, let requestID),
             .forbidden(let code, let requestID),
             .conflict(let code, let requestID),
             .validation(let code, let requestID),
             .rateLimited(let code, let requestID),
             .http(_, let code, let requestID),
             .server(_, let code, let requestID):
            Self.redacted(code: code, requestID: requestID)
        case .network: "mobile_api_network_failure"
        }
    }

    private static func redacted(code: String, requestID: String?) -> String {
        let safeCode = safeValue(code) ?? "http_error"
        if let requestID = requestID.flatMap(safeValue) {
            return "mobile_api_\(safeCode) request_id=\(requestID)"
        }
        return "mobile_api_\(safeCode)"
    }

    private static func safeValue(_ value: String) -> String? {
        guard (1...128).contains(value.count),
              value.unicodeScalars.allSatisfy({ scalar in
                  switch scalar.value {
                  case 45...46, 48...58, 65...90, 95, 97...122:
                      true
                  default:
                      false
                  }
              })
        else { return nil }
        return value
    }
}
