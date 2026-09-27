import Foundation

/// Cover bytes from the mobile BFF proxy: the same origin, bearer and
/// no-redirect policy as the JSON transport, streamed instead of buffered
/// because covers exceed the transport's JSON body cap. Each download is
/// registered as patient work, so sign-out or a user switch aborts it, and
/// the loader's `endSession` cancels whatever is still in flight.
actor MobileContentCoverByteStream: ContentCoverByteStreaming {
    private struct Flight {
        let relay: CoverTaskRelay
        let workID: UUID
        var reader: Task<Void, Never>?
    }

    private let configuration: MobileAPIConfiguration
    private let sessionLifecycle: any SessionLifecycleProviding
    private let session: URLSession
    private let timeout: TimeInterval
    private var flights: [UUID: Flight] = [:]

    init(
        configuration: MobileAPIConfiguration,
        sessionLifecycle: any SessionLifecycleProviding,
        session: URLSession = .shared,
        timeout: TimeInterval = 30
    ) {
        self.configuration = configuration
        self.sessionLifecycle = sessionLifecycle
        let sessionConfiguration = session.configuration
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        sessionConfiguration.urlCache = nil
        sessionConfiguration.httpShouldSetCookies = false
        sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.urlCredentialStorage = nil
        sessionConfiguration.timeoutIntervalForRequest = timeout
        sessionConfiguration.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: sessionConfiguration)
        self.timeout = timeout
    }

    func stream(
        _ request: ContentCoverTransportRequest
    ) async throws -> ContentCoverByteStream {
        // The resolver already pinned the URL to the trusted origin; the
        // transport's own approval is the second lock before a bearer goes out.
        guard configuration.approves(request.url) else {
            throw BodyFlowCapabilityError.invalidContentCover
        }

        let lease: SessionLease
        do {
            lease = try await sessionLifecycle.leaseForRequest()
        } catch is CancellationError {
            throw CancellationError()
        } catch SessionLifecycleError.sessionSuperseded {
            throw CancellationError()
        } catch {
            throw BodyFlowCapabilityError.operationUnavailable
        }
        guard !lease.bearer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BodyFlowCapabilityError.operationUnavailable
        }

        var urlRequest = URLRequest(
            url: request.url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: timeout
        )
        urlRequest.httpMethod = HTTPMethod.get.rawValue
        urlRequest.setValue("image/jpeg, image/png, image/webp", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(lease.bearer)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "X-Request-Id")

        let relay = CoverTaskRelay()
        let workID: UUID
        do {
            workID = try await sessionLifecycle.beginPatientWork(
                lease: lease,
                cancel: { relay.cancel() }
            )
        } catch {
            throw CancellationError()
        }
        // Tracked from here, so a session that ends during the request
        // still closes the patient work and cancels the task once it exists.
        let flightID = UUID()
        flights[flightID] = Flight(relay: relay, workID: workID, reader: nil)

        let redirectDelegate = CoverRedirectDelegate()
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            try Task.checkCancellation()
            (bytes, response) = try await session.bytes(for: urlRequest, delegate: redirectDelegate)
        } catch {
            await finish(flightID)
            if redirectDelegate.wasRejected {
                throw BodyFlowCapabilityError.contentCoverNotFound
            }
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw BodyFlowCapabilityError.offline
        }
        relay.install(bytes.task)

        guard !relay.isCancelled else {
            await finish(flightID)
            throw CancellationError()
        }
        // A refused redirect can still surface as the 3xx response itself.
        guard !redirectDelegate.wasRejected else {
            relay.cancel()
            await finish(flightID)
            throw BodyFlowCapabilityError.contentCoverNotFound
        }
        guard let http = response as? HTTPURLResponse else {
            relay.cancel()
            await finish(flightID)
            throw BodyFlowCapabilityError.invalidContentCover
        }

        // The reader closes the patient work before it finishes the stream,
        // so a consumer that drained the bytes observes the work as done.
        let (chunks, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        let chunkSize = Self.chunkSize
        let reader = Task.detached {
            var buffer = Data()
            buffer.reserveCapacity(chunkSize)
            do {
                for try await byte in bytes {
                    buffer.append(byte)
                    if buffer.count >= chunkSize {
                        try Task.checkCancellation()
                        continuation.yield(buffer)
                        buffer.removeAll(keepingCapacity: true)
                    }
                }
                try Task.checkCancellation()
                if !buffer.isEmpty {
                    continuation.yield(buffer)
                }
                await self.finish(flightID)
                continuation.finish()
            } catch {
                await self.finish(flightID)
                continuation.finish(throwing: error)
            }
        }
        flights[flightID]?.reader = reader
        continuation.onTermination = { _ in
            reader.cancel()
            relay.cancel()
            Task { await self.finish(flightID) }
        }

        return ContentCoverByteStream(
            statusCode: http.statusCode,
            declaredLength: http.expectedContentLength >= 0 ? http.expectedContentLength : nil,
            mimeType: http.mimeType,
            cacheMaxAgeSeconds: Self.maxAge(fromCacheControl: http.value(forHTTPHeaderField: "Cache-Control")),
            redirectLocation: nil,
            chunks: chunks,
            cancel: {
                reader.cancel()
                relay.cancel()
            }
        )
    }

    func cancelAll() async {
        let active = flights
        flights.removeAll()
        for flight in active.values {
            flight.reader?.cancel()
            flight.relay.cancel()
            await sessionLifecycle.finishPatientWork(flight.workID)
        }
    }

    private static let chunkSize = 16 * 1_024

    /// `Cache-Control: private, max-age=<seconds>`; anything else yields nil
    /// and the loader falls back to the capability's own expiry.
    static func maxAge(fromCacheControl header: String?) -> Int? {
        guard let header else { return nil }
        for directive in header.split(separator: ",") {
            let trimmed = directive.trimmingCharacters(in: .whitespaces).lowercased()
            guard trimmed.hasPrefix("max-age=") else { continue }
            let digits = trimmed.dropFirst("max-age=".count)
            guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let value = Int(digits) else {
                return nil
            }
            return value
        }
        return nil
    }

    private func finish(_ flightID: UUID) async {
        guard let flight = flights.removeValue(forKey: flightID) else { return }
        await sessionLifecycle.finishPatientWork(flight.workID)
    }
}

/// One byte stream and one cache per signed-in session: the loader's
/// `endSession` cancels that session's downloads and drops its covers.
struct MobileContentCoverSessionFactory: ContentCoverSessionCreating {
    let transport: MobileAPITransport
    let timeProvider: any TimeProviding

    func makeLoader(userID: String) -> any ContentCoverLoading {
        _ = userID
        return ContentCoverLoader(
            stream: transport.makeContentCoverByteStream() ?? UnavailableContentCoverByteStream(),
            origin: transport.contentCoverTrustedOrigin,
            decoder: ContentCoverDecoder(),
            cache: SessionCoverCache(),
            timeProvider: timeProvider
        )
    }
}

/// Holds the data task once `bytes(for:)` hands it over, so a cancel that
/// arrives earlier (sign-out during the lease) still lands.
private final class CoverTaskRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func install(_ task: URLSessionTask) {
        let shouldCancel: Bool = lock.withLock {
            self.task = task
            return cancelled
        }
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        let task: URLSessionTask? = lock.withLock {
            cancelled = true
            return self.task
        }
        task?.cancel()
    }
}

/// Covers never redirect: the capability URL is final, so any redirect is
/// treated as the opaque not-found the proxy itself returns.
private final class CoverRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var rejected = false

    var wasRejected: Bool {
        lock.withLock { rejected }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        lock.withLock { rejected = true }
        completionHandler(nil)
        task.cancel()
    }
}
