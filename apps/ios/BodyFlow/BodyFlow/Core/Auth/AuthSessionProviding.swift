enum AuthSessionState: Equatable, Sendable {
    case unauthenticated
    case authenticated(userID: String)
}

protocol AuthSessionProviding: Sendable {
    var state: AuthSessionState { get }
}

struct MockAuthSessionProvider: AuthSessionProviding {
    let state: AuthSessionState
}
