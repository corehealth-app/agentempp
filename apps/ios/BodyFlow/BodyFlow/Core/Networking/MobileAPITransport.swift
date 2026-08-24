import Foundation

struct MobileAPITransport: Sendable {
    private let configuration: MobileAPIConfiguration?
    private let sessionLifecycle: any SessionLifecycleProviding
    private let session: URLSession
    private let clock: any Clock<Duration>
    private let timeout: Duration
    private let responseBodyLimit: Int

    init(
        configuration: MobileAPIConfiguration?,
        sessionTokenProvider: any SessionTokenProviding,
        session: URLSession,
        clock: any Clock<Duration>,
        timeout: Duration = .seconds(30),
        responseBodyLimit: Int = 64 * 1_024,
        maximumRetryCount: Int = 1
    ) {
        let lifecycle = LegacySessionLifecycleAdapter(provider: sessionTokenProvider)
        self.init(
            configuration: configuration,
            sessionLifecycle: lifecycle,
            session: session,
            clock: clock,
            timeout: timeout,
            responseBodyLimit: responseBodyLimit
        )
        _ = maximumRetryCount
    }

    init(
        configuration: MobileAPIConfiguration?,
        sessionLifecycle: any SessionLifecycleProviding,
        session: URLSession,
        clock: any Clock<Duration>,
        timeout: Duration = .seconds(30),
        responseBodyLimit: Int = 64 * 1_024
    ) {
        self.configuration = configuration
        self.sessionLifecycle = sessionLifecycle
        let sessionConfiguration = session.configuration
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        sessionConfiguration.urlCache = nil
        sessionConfiguration.httpShouldSetCookies = false
        sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.urlCredentialStorage = nil
        sessionConfiguration.timeoutIntervalForRequest = Self.seconds(timeout)
        sessionConfiguration.timeoutIntervalForResource = Self.seconds(timeout)
        self.session = URLSession(configuration: sessionConfiguration)
        self.clock = clock
        self.timeout = timeout
        self.responseBodyLimit = responseBodyLimit
    }

    init(
        configuration: MobileAPIConfiguration?,
        sessionTokenProvider: any SessionTokenProviding,
        session: URLSession = .shared
    ) {
        self.init(
            configuration: configuration,
            sessionTokenProvider: sessionTokenProvider,
            session: session,
            clock: ContinuousClock()
        )
    }

    func execute<Response: Decodable & Sendable>(
        _ request: MobileAPIRequest<Response>
    ) async throws -> Response {
        guard let configuration else {
            throw MobileAPITransportError.unavailableConfiguration
        }
        let requestID = UUID().uuidString.lowercased()
        let lease: SessionLease
        do {
            lease = try await sessionLifecycle.leaseForRequest()
        } catch is CancellationError {
            throw CancellationError()
        } catch SessionLifecycleError.sessionSuperseded {
            throw MobileAPITransportError.sessionSuperseded
        } catch {
            throw MobileAPITransportError.missingSession
        }

        try Task.checkCancellation()
        let firstResult = try await executeAttempt(
            request,
            configuration: configuration,
            requestID: requestID,
            lease: lease
        )
        guard firstResult.response.statusCode == 401,
              request.isRetryEligible
        else {
            return try await validatedDecode(
                Response.self,
                result: firstResult,
                lease: lease
            )
        }

        let refreshedLease: SessionLease
        do {
            refreshedLease = try await sessionLifecycle
                .refreshAfterUnauthorized(lease: lease)
        } catch is CancellationError {
            throw CancellationError()
        } catch SessionLifecycleError.sessionSuperseded {
            throw MobileAPITransportError.sessionSuperseded
        } catch {
            return try decode(
                Response.self,
                data: firstResult.data,
                response: firstResult.response
            )
        }

        let secondResult = try await executeAttempt(
            request,
            configuration: configuration,
            requestID: requestID,
            lease: refreshedLease
        )
        return try await validatedDecode(
            Response.self,
            result: secondResult,
            lease: refreshedLease
        )
    }

    private func validatedDecode<Response: Decodable & Sendable>(
        _ type: Response.Type,
        result: NetworkResult,
        lease: SessionLease
    ) async throws -> Response {
        do {
            try await sessionLifecycle.validate(lease)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MobileAPITransportError.sessionSuperseded
        }
        return try decode(
            type,
            data: result.data,
            response: result.response
        )
    }

    private func executeAttempt<Response: Decodable & Sendable>(
        _ request: MobileAPIRequest<Response>,
        configuration: MobileAPIConfiguration,
        requestID: String,
        lease: SessionLease
    ) async throws -> NetworkResult {
        guard !lease.bearer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MobileAPITransportError.missingSession
        }

        let url = try request.url(using: configuration)
        guard configuration.approves(url) else {
            throw MobileAPIRequestError.invalidPath
        }

        var urlRequest = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: Self.seconds(timeout)
        )
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(lease.bearer)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(requestID, forHTTPHeaderField: "X-Request-Id")
        if request.body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if case .required(let key) = request.idempotency {
            urlRequest.setValue(key.value, forHTTPHeaderField: "Idempotency-Key")
        }

        let preparedRequest = urlRequest
        let redirectDelegate = MobileAPIRedirectDelegate(configuration: configuration)
        let cancellationRelay = NetworkTaskCancellationRelay()
        return try await withTaskCancellationHandler {
            let workID: UUID
            do {
                workID = try await sessionLifecycle.beginPatientWork(
                    lease: lease,
                    cancel: cancellationRelay.cancel
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw MobileAPITransportError.sessionSuperseded
            }

            let startGate = NetworkTaskStartGate()
            let networkTask = Task {
                await startGate.waitUntilOpen()
                try Task.checkCancellation()
                return try await withThrowingTaskGroup(of: NetworkResult.self) { group in
                    group.addTask {
                        try await readBounded(
                            preparedRequest,
                            redirectDelegate: redirectDelegate
                        )
                    }
                    group.addTask {
                        try await clock.sleep(for: timeout)
                        throw MobileAPITransportError.timeout
                    }

                    guard let first = try await group.next() else {
                        throw MobileAPITransportError.network
                    }
                    group.cancelAll()
                    return first
                }
            }
            cancellationRelay.install(networkTask)
            await startGate.open()
            do {
                let result = try await networkTask.value
                await sessionLifecycle.finishPatientWork(workID)
                do {
                    try await sessionLifecycle.validate(lease)
                } catch {
                    throw MobileAPITransportError.sessionSuperseded
                }
                return result
            } catch is CancellationError {
                await sessionLifecycle.finishPatientWork(workID)
                if Task.isCancelled { throw CancellationError() }
                do {
                    try await sessionLifecycle.validate(lease)
                } catch {
                    throw MobileAPITransportError.sessionSuperseded
                }
                throw MobileAPITransportError.network
            } catch let error as MobileAPITransportError {
                await sessionLifecycle.finishPatientWork(workID)
                throw error
            } catch let error as URLError where error.code == .cancelled {
                await sessionLifecycle.finishPatientWork(workID)
                if Task.isCancelled { throw CancellationError() }
                do {
                    try await sessionLifecycle.validate(lease)
                } catch {
                    throw MobileAPITransportError.sessionSuperseded
                }
                throw MobileAPITransportError.network
            } catch let error as URLError where error.code == .timedOut {
                await sessionLifecycle.finishPatientWork(workID)
                throw MobileAPITransportError.timeout
            } catch {
                await sessionLifecycle.finishPatientWork(workID)
                throw MobileAPITransportError.network
            }
        } onCancel: {
            cancellationRelay.cancel()
        }
    }

    private func readBounded(
        _ request: URLRequest,
        redirectDelegate: MobileAPIRedirectDelegate
    ) async throws -> NetworkResult {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(
                for: request,
                delegate: redirectDelegate
            )
        } catch {
            if redirectDelegate.wasRejected {
                throw MobileAPITransportError.redirectNotAllowed
            }
            throw error
        }
        if redirectDelegate.wasRejected {
            throw MobileAPITransportError.redirectNotAllowed
        }
        guard let response = response as? HTTPURLResponse else {
            throw MobileAPITransportError.invalidResponse
        }
        if response.expectedContentLength > Int64(responseBodyLimit) {
            throw MobileAPITransportError.responseTooLarge(limit: responseBodyLimit)
        }

        var data = Data()
        data.reserveCapacity(
            min(max(Int(response.expectedContentLength), 0), responseBodyLimit)
        )
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < responseBodyLimit else {
                throw MobileAPITransportError.responseTooLarge(limit: responseBodyLimit)
            }
            data.append(byte)
        }
        try Task.checkCancellation()
        if redirectDelegate.wasRejected {
            throw MobileAPITransportError.redirectNotAllowed
        }
        return NetworkResult(data: data, response: response)
    }

    private func decode<Response: Decodable & Sendable>(
        _ type: Response.Type,
        data: Data,
        response: HTTPURLResponse
    ) throws -> Response {
        let decoder = JSONDecoder()
        if (200...299).contains(response.statusCode) {
            do {
                let envelope = try decoder.decode(
                    MobileAPISuccessEnvelope<Response>.self,
                    from: data
                )
                guard envelope.meta.apiVersion == "v1",
                      Self.isValidRequestID(envelope.meta.requestID)
                else {
                    throw MobileAPITransportError.invalidResponse
                }
                return envelope.data
            } catch let error as MobileAPITransportError {
                throw error
            } catch {
                throw MobileAPITransportError.decodingFailure
            }
        }

        let payload = try? decoder.decode(MobileAPIErrorEnvelope.self, from: data).error
        let code = Self.safeDiagnosticValue(payload?.code) ?? "http_error"
        let requestID = Self.safeRequestID(payload?.requestID)
            ?? Self.safeRequestID(response.value(forHTTPHeaderField: "X-Request-Id"))
        switch response.statusCode {
        case 401:
            throw MobileAPITransportError.unauthorized(code: code, requestID: requestID)
        case 403:
            throw MobileAPITransportError.forbidden(code: code, requestID: requestID)
        case 409:
            throw MobileAPITransportError.conflict(code: code, requestID: requestID)
        case 422:
            throw MobileAPITransportError.validation(code: code, requestID: requestID)
        case 429:
            throw MobileAPITransportError.rateLimited(code: code, requestID: requestID)
        case 500...599:
            throw MobileAPITransportError.server(
                status: response.statusCode,
                code: code,
                requestID: requestID
            )
        default:
            throw MobileAPITransportError.http(
                status: response.statusCode,
                code: code,
                requestID: requestID
            )
        }
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return max(
            Double(components.seconds)
                + Double(components.attoseconds) / 1_000_000_000_000_000_000,
            0.001
        )
    }

    private static func safeRequestID(_ value: String?) -> String? {
        guard let value, isValidRequestID(value) else { return nil }
        return value
    }

    private static func isValidRequestID(_ value: String) -> Bool {
        (8...128).contains(value.count)
            && value.unicodeScalars.allSatisfy { scalar in
                switch scalar.value {
                case 45...46, 48...58, 65...90, 95, 97...122:
                    true
                default:
                    false
                }
            }
    }

    private static func safeDiagnosticValue(_ value: String?) -> String? {
        guard let value,
              (1...96).contains(value.count),
              value.unicodeScalars.allSatisfy({ scalar in
                  switch scalar.value {
                  case 48...57, 65...90, 95, 97...122:
                      true
                  default:
                      false
                  }
              })
        else { return nil }
        return value
    }
}

private struct LegacySessionLifecycleAdapter: SessionLifecycleProviding {
    let provider: any SessionTokenProviding

    func currentBearerToken() async -> String? {
        await provider.currentBearerToken()
    }

    func leaseForRequest() async throws -> SessionLease {
        guard let bearer = await provider.currentBearerToken(),
              !bearer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw SessionLifecycleError.missingSession }
        return SessionLease(userID: "legacy", generation: 0, bearer: bearer)
    }

    func refreshAfterUnauthorized(lease: SessionLease) async throws
        -> SessionLease {
        throw SessionLifecycleError.refreshFailed
    }

    func validate(_ lease: SessionLease) async throws {}
    func signOut() async -> RemoteRevocationOutcome { .unconfirmed }
    func beginPatientWork(
        lease: SessionLease,
        cancel: @escaping @Sendable () -> Void
    ) async throws -> UUID { UUID() }
    func finishPatientWork(_ id: UUID) async {}
}

extension MobileAPITransport: APIClient {
    func send<Response: Decodable & Sendable>(
        _ request: APIRequest<Response>
    ) async throws -> Response {
        let mobileRequest = try MobileAPIRequest<Response>(
            method: request.method,
            path: request.path
        )
        return try await execute(mobileRequest)
    }
}

private struct NetworkResult: Sendable {
    let data: Data
    let response: HTTPURLResponse
}

private actor NetworkTaskStartGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilOpen() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll(keepingCapacity: false)
        pending.forEach { $0.resume() }
    }
}

private final class NetworkTaskCancellationRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<NetworkResult, Error>?
    private var isCancelled = false

    func install(_ task: Task<NetworkResult, Error>) {
        let cancelImmediately = lock.withLock {
            self.task = task
            return isCancelled
        }
        if cancelImmediately { task.cancel() }
    }

    func cancel() {
        let task = lock.withLock {
            isCancelled = true
            return self.task
        }
        task?.cancel()
    }
}

private extension MobileAPIRequest {
    var isRetryEligible: Bool {
        if method == .get { return true }
        if case .required = idempotency { return true }
        return false
    }
}

private final class MobileAPIRedirectDelegate: NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable {
    private let configuration: MobileAPIConfiguration
    private let lock = NSLock()
    private var rejected = false

    init(configuration: MobileAPIConfiguration) {
        self.configuration = configuration
    }

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
        let allowedStatusCodes = [301, 302, 303, 307, 308]
        guard allowedStatusCodes.contains(response.statusCode),
              task.originalRequest?.httpMethod == HTTPMethod.get.rawValue,
              request.httpMethod == HTTPMethod.get.rawValue,
              request.value(forHTTPHeaderField: "Idempotency-Key") == nil,
              let url = request.url,
              configuration.approves(url),
              request.value(forHTTPHeaderField: "Authorization") != nil
        else {
            lock.withLock { rejected = true }
            completionHandler(nil)
            task.cancel()
            return
        }
        completionHandler(request)
    }
}
