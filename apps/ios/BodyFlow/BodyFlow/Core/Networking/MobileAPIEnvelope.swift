import Foundation

struct MobileAPISuccessEnvelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    let data: Payload
    let meta: MobileResponseMetadata
}

struct MobileAPIErrorEnvelope: Decodable, Equatable, Sendable {
    let error: MobileAPIErrorPayload
}

struct MobileAPIErrorPayload: Decodable, Equatable, Sendable {
    let code: String
    let message: String
    let requestID: String

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case requestID = "request_id"
    }
}
