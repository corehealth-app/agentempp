protocol SessionTokenProviding: Sendable {
    func currentBearerToken() async -> String?
}
