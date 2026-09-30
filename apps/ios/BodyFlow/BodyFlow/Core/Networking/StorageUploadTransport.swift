import Foundation

/// Sends one staged file to storage with the ticket the BFF issued.
///
/// The ticket is a capability, so the address is checked before any byte
/// leaves: https, the app's own Supabase host, the signed-upload path and
/// nothing else. Only the headers the ticket lists are sent — the BFF bearer
/// never travels here — redirects are refused, and neither the address nor
/// its token is ever logged or reported.
struct StorageUploadTransport: StorageUploading {
    static let signedUploadPathPrefix = "/storage/v1/object/upload/sign/"
    static let allowedHeaders: Set<String> = ["content-type", "x-upsert"]

    private let storageOrigin: URL
    /// One session per upload: a fresh connection each time. Staging
    /// 2026-09-30 showed a PUT reusing a QUIC connection idle for 162 s,
    /// stalling until the 60 s limit ("Sem conexão") while the network was
    /// fine; an upload body is never retried by URLSession, so a stale
    /// pooled connection must not carry it.
    private let makeSession: @Sendable () -> URLSession
    private let now: @Sendable () -> Date

    init(
        storageOrigin: URL,
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = { Date() },
        makeSession: (@Sendable (URLSessionConfiguration) -> URLSession)? = nil
    ) {
        self.storageOrigin = storageOrigin
        let configuration = session.configuration
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpAdditionalHeaders = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 180
        let factory = makeSession ?? { URLSession(configuration: $0) }
        let base = UploadSessionConfiguration(configuration)
        self.makeSession = { factory(base.fresh()) }
        self.now = now
    }

    func upload(_ media: StagedMedia, with ticket: MediaUploadTicket) async throws {
        let request = try Self.request(
            for: media,
            ticket: ticket,
            storageOrigin: storageOrigin,
            now: now()
        )
        let delegate = RefusingRedirectDelegate()
        let session = makeSession()
        defer { session.finishTasksAndInvalidate() }
        let response: URLResponse
        do {
            (_, response) = try await session.upload(
                for: request,
                fromFile: media.fileURL,
                delegate: delegate
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            if Task.isCancelled { throw CancellationError() }
            throw delegate.wasRedirected
                ? MealCaptureFailure.uploadRejected : MealCaptureFailure.offline
        } catch is URLError {
            throw MealCaptureFailure.offline
        } catch {
            throw MealCaptureFailure.unavailable
        }
        guard !delegate.wasRedirected,
              let http = response as? HTTPURLResponse
        else {
            throw MealCaptureFailure.uploadRejected
        }
        switch http.statusCode {
        case 200...299:
            return
        case 500...599:
            throw MealCaptureFailure.unavailable
        default:
            throw MealCaptureFailure.uploadRejected
        }
    }

    /// Builds the upload request or refuses. Every refusal is
    /// `.uploadRejected`, with nothing of the ticket in it.
    static func request(
        for media: StagedMedia,
        ticket: MediaUploadTicket,
        storageOrigin: URL,
        now: Date
    ) throws -> URLRequest {
        guard ticket.method == "PUT",
              ticket.expiresAt.value > now,
              let components = URLComponents(string: ticket.signedURL),
              components.scheme == "https",
              let host = components.host?.lowercased(),
              storageOrigin.scheme == "https",
              host == storageOrigin.host?.lowercased(),
              effectivePort(components.port) == effectivePort(storageOrigin.port),
              components.user == nil,
              components.password == nil,
              components.fragment == nil,
              isSignedUploadPath(components.percentEncodedPath),
              components.queryItems?.contains(where: {
                  $0.name == "token" && !($0.value ?? "").isEmpty
              }) == true,
              let url = components.url
        else {
            throw MealCaptureFailure.uploadRejected
        }

        var headers: [String: String] = [:]
        for (name, value) in ticket.headers {
            let lowered = name.lowercased()
            guard allowedHeaders.contains(lowered),
                  headers[lowered] == nil,
                  !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else {
                throw MealCaptureFailure.uploadRejected
            }
            headers[lowered] = value
        }
        // The file goes as what the asset was declared to be, or not at all.
        guard headers["content-type"] == media.mimeType else {
            throw MealCaptureFailure.uploadRejected
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData
        )
        request.httpMethod = "PUT"
        request.httpShouldHandleCookies = false
        for (name, value) in ticket.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    private static func isSignedUploadPath(_ path: String) -> Bool {
        guard path.hasPrefix(signedUploadPathPrefix),
              !path.contains("\\"),
              let decoded = path.removingPercentEncoding,
              decoded.hasPrefix(signedUploadPathPrefix),
              !decoded.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            return false
        }
        let segments = decoded.dropFirst(signedUploadPathPrefix.count)
            .split(separator: "/", omittingEmptySubsequences: false)
        return segments.count >= 2
            && !segments.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    private static func effectivePort(_ port: Int?) -> Int { port ?? 443 }
}

private final class RefusingRedirectDelegate: NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable {
    private let lock = NSLock()
    private var redirected = false

    var wasRedirected: Bool { lock.withLock { redirected } }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        lock.withLock { redirected = true }
        completionHandler(nil)
        task.cancel()
    }
}

/// The upload session settings, copied for each new session (the
/// configuration class is not Sendable; it is only ever copied, never
/// mutated after init).
private final class UploadSessionConfiguration: @unchecked Sendable {
    private let configuration: URLSessionConfiguration

    init(_ configuration: URLSessionConfiguration) {
        self.configuration = configuration
    }

    func fresh() -> URLSessionConfiguration {
        (configuration.copy() as? URLSessionConfiguration) ?? configuration
    }
}
