#if DEBUG
import Foundation

actor DemoContentCoverByteStream: ContentCoverByteStreaming {
    private let scenario: DemoPrompt14ScenarioSelection
    private var streamCallCount = 0
    private var nextStreamID: UInt64 = 0
    private var pendingStreams: [
        UInt64: AsyncThrowingStream<Data, any Error>.Continuation
    ] = [:]

    init(scenario: DemoPrompt14Scenario) {
        self.scenario = DemoPrompt14ScenarioSelection(
            legacyScenario: scenario
        )
    }

    init(selection: DemoPrompt14ScenarioSelection) {
        scenario = selection
    }

    func stream(
        _ request: ContentCoverTransportRequest
    ) async throws -> ContentCoverByteStream {
        _ = request
        streamCallCount += 1
        switch scenario {
        case .offline:
            throw BodyFlowCapabilityError.offline
        case .error:
            throw BodyFlowCapabilityError.serviceUnavailable
        case .unavailable:
            throw BodyFlowCapabilityError.operationUnavailable
        default:
            break
        }

        let statusCode = scenario == .contentNotFound ? 404 : 200
        let bytes: Data = switch scenario {
        case .coverInvalid:
            DemoPrompt14Fixtures.invalidCoverBytes
        case .coverAbusiveDimensions:
            DemoPrompt14Fixtures.abusiveDimensionPNG
        default:
            DemoPrompt14Fixtures.neutralPNG
        }
        let declaredLength: Int64 = scenario == .coverTooLarge
            ? 10_485_761
            : Int64(bytes.count)
        let mimeType = scenario == .coverMIMEMismatch
            ? "image/jpeg"
            : "image/png"

        if scenario == .loading {
            return pendingStream(statusCode: statusCode)
        }

        let chunks = AsyncThrowingStream<Data, any Error> { continuation in
            continuation.yield(bytes)
            continuation.finish()
        }
        return ContentCoverByteStream(
            statusCode: statusCode,
            declaredLength: declaredLength,
            mimeType: mimeType,
            cacheMaxAgeSeconds: 300,
            redirectLocation: nil,
            chunks: chunks,
            cancel: {}
        )
    }

    func cancelAll() async {
        let continuations = Array(pendingStreams.values)
        pendingStreams.removeAll(keepingCapacity: false)
        streamCallCount = 0
        for continuation in continuations {
            continuation.finish(throwing: CancellationError())
        }
    }

    func streamCallCountForTesting() -> Int {
        streamCallCount
    }

    private func pendingStream(statusCode: Int) -> ContentCoverByteStream {
        nextStreamID &+= 1
        let streamID = nextStreamID
        let (chunks, continuation) = AsyncThrowingStream<Data, any Error>
            .makeStream()
        pendingStreams[streamID] = continuation
        return ContentCoverByteStream(
            statusCode: statusCode,
            declaredLength: nil,
            mimeType: "image/png",
            cacheMaxAgeSeconds: 300,
            redirectLocation: nil,
            chunks: chunks,
            cancel: {
                await self.cancel(streamID: streamID)
            }
        )
    }

    private func cancel(streamID: UInt64) {
        pendingStreams.removeValue(forKey: streamID)?
            .finish(throwing: CancellationError())
    }
}
#endif
