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
