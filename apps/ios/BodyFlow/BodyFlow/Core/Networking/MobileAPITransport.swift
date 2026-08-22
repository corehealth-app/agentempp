import Foundation

struct MobileAPITransport: Sendable {
    private let configuration: MobileAPIConfiguration?
    private let sessionTokenProvider: any SessionTokenProviding
    private let session: URLSession
    private let clock: any Clock<Duration>
    private let timeout: Duration
    private let responseBodyLimit: Int
    private let maximumRetryCount: Int

    init(
        configuration: MobileAPIConfiguration?,
        sessionTokenProvider: any SessionTokenProviding,
        session: URLSession,
        clock: any Clock<Duration>,
        timeout: Duration = .seconds(30),
        responseBodyLimit: Int = 64 * 1_024,
        maximumRetryCount: Int = 1
    ) {
        self.configuration = configuration
        self.sessionTokenProvider = sessionTokenProvider
        let sessionConfiguration = session.configuration
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        sessionConfiguration.urlCache = nil
        sessionConfiguration.timeoutIntervalForRequest = Self.seconds(timeout)
        sessionConfiguration.timeoutIntervalForResource = Self.seconds(timeout)
        self.session = URLSession(configuration: sessionConfiguration)
        self.clock = clock
        self.timeout = timeout
        self.responseBodyLimit = responseBodyLimit
        self.maximumRetryCount = maximumRetryCount
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
        var attempt = 0

        while true {
            try Task.checkCancellation()
            let result: NetworkResult
            do {
                result = try await executeAttempt(
                    request,
                    configuration: configuration,
                    requestID: requestID
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as MobileAPITransportError {
                if error == .network,
                   attempt < maximumRetryCount,
                   request.isRetryEligible {
                    attempt += 1
                    continue
                }
                throw error
            }

            if Self.isRetryable(status: result.response.statusCode),
               attempt < maximumRetryCount,
               request.isRetryEligible {
                attempt += 1
                continue
            }

            return try decode(
                Response.self,
                data: result.data,
                response: result.response
            )
        }
    }

    private func executeAttempt<Response: Decodable & Sendable>(
        _ request: MobileAPIRequest<Response>,
        configuration: MobileAPIConfiguration,
        requestID: String
    ) async throws -> NetworkResult {
        let bearer = await sessionTokenProvider.currentBearerToken()
        try Task.checkCancellation()
        guard let bearer,
              !bearer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
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
        urlRequest.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(requestID, forHTTPHeaderField: "X-Request-Id")
        if request.body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if case .required(let key) = request.idempotency {
            urlRequest.setValue(key.value, forHTTPHeaderField: "Idempotency-Key")
        }

        let preparedRequest = urlRequest
        let redirectDelegate = MobileAPIRedirectDelegate(configuration: configuration)
        do {
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
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MobileAPITransportError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            try Task.checkCancellation()
            throw MobileAPITransportError.network
        } catch let error as URLError where error.code == .timedOut {
            throw MobileAPITransportError.timeout
        } catch {
            throw MobileAPITransportError.network
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

    private static func isRetryable(status: Int) -> Bool {
        status == 429 || (500...599).contains(status)
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
