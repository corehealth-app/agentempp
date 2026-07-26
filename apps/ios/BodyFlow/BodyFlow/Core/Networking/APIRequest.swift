enum HTTPMethod: String, Hashable, Sendable {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
}

struct APIRequestKey: Hashable, Sendable {
    let method: HTTPMethod
    let path: String
}

struct APIRequest<Response: Decodable & Sendable>: Sendable {
    let method: HTTPMethod
    let path: String

    var key: APIRequestKey {
        APIRequestKey(method: method, path: path)
    }
}
