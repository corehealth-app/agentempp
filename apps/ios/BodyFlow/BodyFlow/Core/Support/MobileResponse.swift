struct MobileResponseMetadata: Codable, Equatable, Sendable {
    let apiVersion: String
    let requestID: String

    private enum CodingKeys: String, CodingKey {
        case apiVersion = "api_version"
        case requestID = "request_id"
    }
}

struct MobileResponse<Payload: Codable & Sendable>: Codable, Sendable {
    let data: Payload
    let meta: MobileResponseMetadata

    private enum CodingKeys: String, CodingKey {
        case data
        case meta
    }
}

extension MobileResponse: Equatable where Payload: Equatable {}
