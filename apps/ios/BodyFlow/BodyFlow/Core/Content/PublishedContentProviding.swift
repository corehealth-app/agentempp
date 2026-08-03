protocol PublishedContentListing: Sendable {
    func content(
        _ query: ContentFeedQuery
    ) async throws -> PublishedContentFeedResponse
}

protocol PublishedContentDetailProviding: Sendable {
    func contentDetail(
        publicationID: String
    ) async throws -> PublishedContentDetailResponse
}

protocol PublishedContentStateRecording: Sendable {
    func recordRead(
        _ attempt: MutationAttempt<ContentReadCommand>
    ) async throws -> PublishedContentStateResponse

    func setSaved(
        _ attempt: MutationAttempt<ContentSaveCommand>
    ) async throws -> PublishedContentStateResponse
}

struct PublishedContentSession: Sendable {
    let listing: any PublishedContentListing
    let detail: any PublishedContentDetailProviding
    let state: any PublishedContentStateRecording
    let lifetime: any PublishedContentSessionLifetime
}

protocol PublishedContentSessionCreating: Sendable {
    func makeSession(userID: String) -> PublishedContentSession
}

protocol PublishedContentSessionLifetime: Sendable {
    func endSession() async
}
