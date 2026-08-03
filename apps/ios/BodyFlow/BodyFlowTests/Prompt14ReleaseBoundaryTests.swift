import Foundation
import Testing

@testable import BodyFlow

@Suite("Prompt 14 Release Boundary")
struct Prompt14ReleaseBoundaryTests {
    @Test("Release published-content session capabilities fail closed")
    func releasePublishedContentCapabilitiesFailClosed() async throws {
        let session = releaseDependencies().publishedContentSessions.makeSession(
            userID: "release-user"
        )
        let query = try ContentFeedQuery(
            surface: .library,
            category: nil,
            limit: 20,
            cursor: nil
        )

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await session.listing.content(query)
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await session.detail.contentDetail(publicationID: "publication-1")
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await session.state.recordRead(try contentReadAttempt())
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await session.state.setSaved(try contentSaveAttempt())
        }

        await session.lifetime.endSession()
    }

    @Test("Release coach-experience capability fails closed")
    func releaseCoachExperienceFailsClosed() async {
        let provider = releaseDependencies()
            .coachExperienceSessions
            .makeCoachExperience(userID: "release-user")

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await provider.coachExperience()
        }
    }

    @Test("Unavailable cover factory fails before request construction or streaming")
    func unavailableCoverFactoryPerformsNoTransport() async {
        let stream = Prompt14UnavailableStreamSpy()
        let loader = UnavailableContentCoverSessionFactory(stream: stream)
            .makeLoader(userID: "release-user")

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await loader.image(
                publicationID: "publication-1",
                version: 4,
                cover: PublishedContentCover(
                    url: "not-even-a-valid-cover-path",
                    expiresAt: APITimestamp(value: .distantFuture)
                ),
                target: ContentCoverTargetSize(
                    widthPixels: 240,
                    heightPixels: 160
                )
            )
        }

        #expect(await stream.streamCallCount == 0)
        #expect(await stream.cancelAllCallCount == 0)
    }

    @Test("Unavailable cover stream rejects an already-resolved request")
    func unavailableCoverStreamFailsClosedWhenCalledDirectly() async throws {
        let origin = try ContentCoverTrustedOrigin(
            validating: #require(URL(string: "https://mobile.bodyflow.test"))
        )
        let path = try ContentCoverPath(
            validating: "/api/mobile/v1/content/covers/AbC_123-xyz"
        )
        let request = try ContentCoverRequestResolver(trustedOrigin: origin)
            .resolve(path)
        let stream: any ContentCoverByteStreaming = UnavailableContentCoverByteStream()

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await stream.stream(request)
        }
    }

    private func contentReadAttempt() throws -> MutationAttempt<ContentReadCommand> {
        MutationAttempt(
            operation: .contentRead,
            key: try IdempotencyKey(validating: "release-content-read-0001"),
            payload: ContentReadCommand(
                publicationID: "publication-1",
                body: ContentReadBody(
                    event: .opened,
                    origin: .library,
                    version: 4
                )
            ),
            createdAt: Date(timeIntervalSince1970: 1_784_589_300)
        )
    }

    private func contentSaveAttempt() throws -> MutationAttempt<ContentSaveCommand> {
        MutationAttempt(
            operation: .contentSave,
            key: try IdempotencyKey(validating: "release-content-save-0001"),
            payload: ContentSaveCommand(
                publicationID: "publication-1",
                body: ContentSaveBody(saved: true, version: 4)
            ),
            createdAt: Date(timeIntervalSince1970: 1_784_589_300)
        )
    }
}

private actor Prompt14UnavailableStreamSpy: ContentCoverByteStreaming {
    private(set) var streamCallCount = 0
    private(set) var cancelAllCallCount = 0

    func stream(
        _ request: ContentCoverTransportRequest
    ) async throws -> ContentCoverByteStream {
        streamCallCount += 1
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func cancelAll() async {
        cancelAllCallCount += 1
    }
}

private func releaseDependencies() -> AppDependencies {
    AppDependencies.make(
        configuration: .resolve(
            arguments: ["--ui-testing"],
            buildFlavor: .release
        )
    )
}
