import Foundation
import Observation
import Testing

@testable import BodyFlow

@Suite("Mobile API Transport", .serialized)
struct MobileAPITransportTests {
    @Test("progress reads official profile weight without querying history or mutating the ledger")
    func profileWeightRead() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        let json = #"{"data":{"weight_kg":80,"weight_measured_at":"2026-10-01T16:15:33.319Z","weight_instant_source":"measured","height_cm":180},"meta":{"api_version":"v1","request_id":"profile-weight-qa-a"}}"#
        await harness.stub.respond(with: StubResponse(
            status: 200, headers: ["Content-Type": "application/json"], body: Data(json.utf8)
        ))
        let response = try await MobileBodyFlowRepository(transport: harness.transport).profileWeight()
        #expect(response?.data?.weightKG == 80)
        #expect(response?.data?.instantSource == "measured")
        #expect(response?.meta.requestID == "profile-weight-qa-a")
        let requests = await harness.stub.requests()
        #expect(requests.count == 1)
        #expect(requests[0].httpMethod == "GET")
        #expect(requests[0].url?.path == "/api/mobile/v1/profile")
        #expect(requests[0].httpBody == nil)
    }

    @Test("same-origin request obtains and sends the current bearer")
    func sendsCurrentBearer() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .success())

        let payload: TransportPayload = try await harness.transport.execute(.getToday())
        let requests = await harness.stub.requests()

        #expect(payload == TransportPayload(value: "ok"))
        #expect(requests.count == 1)
        #expect(requests[0].url?.host == "staging.example.test")
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer session-alpha")
    }

    @Test("a response Date header sets the server clock estimate")
    func recordsTheServerDate() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        let body = Data(
            "{\"data\":{\"value\":\"ok\"},\"meta\":{\"api_version\":\"v1\",\"request_id\":\"request-date-0001\"}}".utf8
        )
        let serverDate = "Tue, 29 Sep 2026 19:03:00 GMT"
        await harness.stub.respond(with: StubResponse(
            status: 200,
            headers: ["Content-Type": "application/json", "Date": serverDate],
            body: body
        ))

        #expect(harness.transport.serverClock.offset == nil)
        let _: TransportPayload = try await harness.transport.execute(.getToday())

        let offset = try #require(harness.transport.serverClock.offset)
        let expected = ServerClockEstimate.parse(serverDate)!.timeIntervalSinceNow
        #expect(abs(offset - expected) < 5)
    }

    @Test("missing token fails closed before network activity")
    func rejectsMissingToken() async throws {
        let harness = try await TransportHarness(tokens: [])

        await #expect(throws: MobileAPITransportError.missingSession) {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
        }
        #expect(await harness.stub.requests().isEmpty)
    }

    @Test("token is fetched again for consecutive requests")
    func fetchesRotatedToken() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha", "session-beta"])
        await harness.stub.respond(with: .success())

        let _: TransportPayload = try await harness.transport.execute(.getToday())
        let _: TransportPayload = try await harness.transport.execute(.getToday())
        let authorization = await harness.stub.requests().map {
            $0.value(forHTTPHeaderField: "Authorization")
        }

        #expect(authorization == ["Bearer session-alpha", "Bearer session-beta"])
    }

    @Test("a cross-origin request cannot be constructed")
    func cannotConstructCrossOriginRequest() {
        #expect(throws: MobileAPIRequestError.self) {
            try MobileAPIRequest<TransportPayload>(
                method: .get,
                path: "https://other.example.test/api/mobile/v1/today"
            )
        }
    }

    @Test("same-origin API redirect follows without losing authorization")
    func followsApprovedRedirect() async throws {
        let harness = try await TransportHarness(
            tokens: ["session-alpha"],
            maximumRetryCount: 0
        )
        await harness.stub.respond { request, call in
            if call == 1 {
                return .redirect(
                    from: request.url!,
                    to: URL(string: "https://staging.example.test/api/mobile/v1/profile")!
                )
            }
            return .success()
        }

        let _: TransportPayload = try await harness.transport.execute(.getToday())
        let requests = await harness.stub.requests()

        #expect(requests.count == 2)
        #expect(requests[1].url?.path == "/api/mobile/v1/profile")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer session-alpha")
    }

    @Test("same-origin redirect cannot rewrite a mutation")
    func blocksMutationRedirect() async throws {
        let harness = try await TransportHarness(
            tokens: ["session-alpha"],
            maximumRetryCount: 0
        )
        await harness.stub.respond { request, _ in
            .redirect(
                from: request.url!,
                to: URL(string: "https://staging.example.test/api/mobile/v1/profile")!
            )
        }
        let request = try MobileAPIRequest<TransportPayload>(
            method: .post,
            path: "/api/mobile/v1/content/item/read",
            body: Data("{\"event\":\"opened\"}".utf8),
            idempotencyKey: try IdempotencyKey(validating: "mobile-redirect-0001")
        )

        await #expect(throws: MobileAPITransportError.redirectNotAllowed) {
            let _: TransportPayload = try await harness.transport.execute(request)
        }
        #expect(await harness.stub.requests().count == 1)
    }

    @Test("cross-origin redirect is blocked before a second request")
    func blocksCrossOriginRedirect() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond { request, _ in
            .redirect(
                from: request.url!,
                to: URL(string: "https://other.example.test/api/mobile/v1/today")!
            )
        }

        await #expect(throws: MobileAPITransportError.redirectNotAllowed) {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
        }
        #expect(await harness.stub.requests().count == 1)
    }

    @Test("explicit timeout maps to a typed error without retry")
    func mapsTimeout() async throws {
        let harness = try await TransportHarness(
            tokens: ["session-alpha"],
            timeout: .milliseconds(30)
        )
        await harness.stub.respond(with: .success(delay: .seconds(1)))

        await #expect(throws: MobileAPITransportError.timeout) {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
        }
        #expect(await harness.stub.requests().count == 1)
    }

    // Staging device gate 2026-09-28: a Flow turn that builds a plan took 77 s
    // and the app gave up at the shared 30 s limit. A request may ask for a
    // longer limit; every other request keeps the transport default.
    @Test("a request with its own longer timeout outlives the default")
    func requestTimeoutOverridesDefault() async throws {
        let harness = try await TransportHarness(
            tokens: ["session-alpha", "session-beta"],
            timeout: .milliseconds(100)
        )
        await harness.stub.respond(with: .success(delay: .milliseconds(400)))

        let slow = try MobileAPIRequest<TransportPayload>(
            method: .get,
            path: "/api/mobile/v1/today",
            timeout: .seconds(3)
        )
        let _: TransportPayload = try await harness.transport.execute(slow)

        await harness.stub.respond(with: .success(delay: .milliseconds(400)))
        await #expect(throws: MobileAPITransportError.timeout) {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
        }
    }

    @Test("task cancellation remains CancellationError")
    func preservesCancellation() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .success(delay: .seconds(1)))
        let transport = harness.transport
        let request = try MobileAPIRequest<TransportPayload>.getToday()
        let task = Task { try await transport.execute(request) }
        await harness.stub.waitForRequests(1)

        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test("late protocol success cannot replace cancellation")
    func suppressesLateSuccess() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .success(delay: .milliseconds(150), ignoresCancellation: true))
        let transport = harness.transport
        let request = try MobileAPIRequest<TransportPayload>.getToday()
        let task = Task { try await transport.execute(request) }
        await harness.stub.waitForRequests(1)

        task.cancel()
        try? await Task.sleep(for: .milliseconds(250))

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test("response body limit is enforced before decoding")
    func rejectsOversizedBody() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"], bodyLimit: 32)
        await harness.stub.respond(with: .init(
            status: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(repeating: 0x61, count: 33)
        ))

        await #expect(throws: MobileAPITransportError.responseTooLarge(limit: 32)) {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
        }
    }

    @Test("default body limit rejects the first byte above 64 KiB")
    func rejectsBodyAboveDefaultLimit() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .init(
            status: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(repeating: 0x61, count: 65_537)
        ))

        await #expect(throws: MobileAPITransportError.responseTooLarge(limit: 65_536)) {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
        }
    }

    @Test("oversized declared content length fails before decode")
    func rejectsOversizedDeclaredContentLength() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .init(
            status: 200,
            headers: [
                "Content-Type": "application/json",
                "Content-Length": "65537",
            ],
            body: Data("not-json".utf8)
        ))

        await #expect(throws: MobileAPITransportError.responseTooLarge(limit: 65_536)) {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
        }
    }

    @Test("invalid JSON maps to a typed decode error")
    func mapsInvalidJSON() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .init(status: 200, body: Data("not-json".utf8)))

        await #expect(throws: MobileAPITransportError.decodingFailure) {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
        }
    }

    @Test("success data and metadata envelope decodes")
    func decodesSuccessEnvelope() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .success(requestID: "request-success-0001"))

        let payload: TransportPayload = try await harness.transport.execute(.getToday())

        #expect(payload.value == "ok")
    }

    @Test("success envelope with another API version fails closed")
    func rejectsIncompatibleAPIVersion() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .init(
            status: 200,
            body: Data(
                "{\"data\":{\"value\":\"ok\"},\"meta\":{\"api_version\":\"v2\",\"request_id\":\"request-version-0001\"}}".utf8
            )
        ))

        await #expect(throws: MobileAPITransportError.invalidResponse) {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
        }
    }

    @Test(
        "error envelope maps stable HTTP categories",
        arguments: [
            ErrorCase(status: 401, code: "invalid_access_token", category: .unauthorized),
            ErrorCase(status: 403, code: "patient_account_inactive", category: .forbidden),
            ErrorCase(status: 409, code: "idempotency_key_conflict", category: .conflict),
            ErrorCase(status: 422, code: "validation_failed", category: .validation),
            ErrorCase(status: 429, code: "rate_limited", category: .rateLimited),
            ErrorCase(status: 503, code: "internal_error", category: .server),
        ]
    )
    func mapsErrorEnvelope(_ errorCase: ErrorCase) async throws {
        let harness = try await TransportHarness(
            tokens: ["session-alpha"],
            maximumRetryCount: 0
        )
        await harness.stub.respond(with: .failure(
            status: errorCase.status,
            code: errorCase.code,
            requestID: "request-error-0001"
        ))

        do {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
            Issue.record("Expected a typed transport error")
        } catch let error as MobileAPITransportError {
            #expect(error.category == errorCase.category)
        }
    }

    /// docs/mobile/api-v1.md, "Erros do pending": the real HTTP answer to an
    /// edit (PATCH) or a cancellation (DELETE) of an already saved record.
    @Test("HTTP 409 registration_already_confirmed on PATCH and DELETE reaches the repository caller as the already-confirmed capability error")
    func alreadyConfirmedConflictThroughTheRegistrationRepository() async throws {
        let harness = try await TransportHarness(
            tokens: ["session-alpha", "session-alpha"],
            maximumRetryCount: 0
        )
        await harness.stub.respond(with: .failure(
            status: 409,
            code: "registration_already_confirmed",
            requestID: "request-conflict-0001"
        ))
        let repository = MobileRegistrationRepository(transport: harness.transport)
        let id = "7c9c0c5e-1f6a-4a1a-9c0b-0f1d2e3a4b5c"

        await #expect(throws: BodyFlowCapabilityError.registrationAlreadyConfirmed) {
            try await repository.edit(MutationAttempt(
                operation: .proposalEdit,
                key: try IdempotencyKey(validating: "mobile-test-edit-409"),
                payload: RegistrationEditCommand(
                    registrationID: id,
                    proposal: .meal(MealProposalRequest(
                        mealType: .lunch,
                        items: [MealProposalItemRequest(foodName: "arroz", quantityG: 100, userKcal: nil)],
                        consumedAt: nil
                    ))
                ),
                createdAt: Date()
            ))
        }
        await #expect(throws: BodyFlowCapabilityError.registrationAlreadyConfirmed) {
            try await repository.cancel(MutationAttempt(
                operation: .proposalCancel,
                key: try IdempotencyKey(validating: "mobile-test-cancel-409"),
                payload: RegistrationIDCommand(registrationID: id),
                createdAt: Date()
            ))
        }

        // One request each: a 409 is an answer, not a failure to send again.
        let requests = await harness.stub.requests()
        #expect(requests.map(\.httpMethod) == ["PATCH", "DELETE"])
        #expect(requests.map { $0.url?.path } == [
            "/api/mobile/v1/registrations/\(id)",
            "/api/mobile/v1/registrations/\(id)",
        ])
        #expect(BodyFlowCapabilityError.registrationAlreadyConfirmed.telemetryValue
            == .registrationNotPending)
        #expect(BodyFlowCapabilityError.registrationAlreadyConfirmed.telemetryValue.rawValue
            == "registration_not_pending")
    }

    /// Reported on 2026-10-10 11:55: a person signs in to the app with an
    /// account that administers the team's panel. The server answers HTTP 403
    /// with this exact code to GET /api/mobile/v1/onboarding
    /// (apps/admin/src/lib/mobile-api/auth.ts; docs/mobile/api-v1.md), in the
    /// envelope `mobileErrorResponse` writes (no `details`).
    @Test("HTTP 403 patient_admin_account_conflict on GET /onboarding reaches the caller as its own failure")
    func teamPanelAccountConflictOnOnboardingReachesTheCallerAsItsOwnFailure() async throws {
        let harness = try await TransportHarness(
            tokens: ["session-alpha"],
            maximumRetryCount: 0
        )
        await harness.stub.respond(with: StubResponse(
            status: 403,
            body: Data(
                #"{"error":{"code":"patient_admin_account_conflict","message":"Patient and administrator accounts must be separate","request_id":"request-admin-0001"}}"#.utf8
            )
        ))
        let repository = MobileOnboardingRepository(transport: harness.transport)

        await #expect(throws: OnboardingRepositoryError.adminAccountConflict) {
            try await repository.loadState(for: "user-team-panel")
        }
        // One request: a 403 is an answer, not a failure to send again.
        let requests = await harness.stub.requests()
        try #require(requests.count == 1)
        #expect(requests[0].httpMethod == "GET")
        #expect(requests[0].url?.path == "/api/mobile/v1/onboarding")

        // Lock: any other refusal on the same route keeps today's meaning.
        let other = try await TransportHarness(
            tokens: ["session-alpha"],
            maximumRetryCount: 0
        )
        await other.stub.respond(with: .failure(
            status: 403,
            code: "patient_account_inactive",
            requestID: "request-inactive-0001"
        ))
        await #expect(throws: OnboardingRepositoryError.serviceUnavailable) {
            try await MobileOnboardingRepository(transport: other.transport)
                .loadState(for: "user-inactive")
        }
    }

    @Test("request ID is safe and attached to every attempt")
    func attachesRequestID() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .success())

        let _: TransportPayload = try await harness.transport.execute(.getToday())
        let requestID = try #require(
            await harness.stub.requests().first?.value(forHTTPHeaderField: "X-Request-Id")
        )

        #expect((8...128).contains(requestID.count))
        #expect(requestID.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._:-".contains($0)) })
    }

    @Test("mutation receives JSON and one stable idempotency key")
    func attachesMutationHeaders() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .success())
        let key = try IdempotencyKey(validating: "mobile-mutation-0001")
        let request = try MobileAPIRequest<TransportPayload>(
            method: .post,
            path: "/api/mobile/v1/content/item/read",
            body: Data("{\"event\":\"opened\"}".utf8),
            idempotencyKey: key
        )

        let _: TransportPayload = try await harness.transport.execute(request)
        let captured = try #require(await harness.stub.requests().first)

        #expect(captured.value(forHTTPHeaderField: "Idempotency-Key") == key.value)
        #expect(captured.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(captured.httpMethod == "POST")
    }

    @Test("transient server failure is never replayed by the session layer")
    func doesNotRetryServerFailure() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond { _, call in
            call == 1 ? .failure(status: 503, code: "internal_error") : .success()
        }

        await #expect(throws: MobileAPITransportError.self) {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
        }

        #expect(await harness.stub.requests().count == 1)
    }

    @Test("one current 401 refreshes and replays with stable logical identifiers")
    func refreshesOnceAfterUnauthorized() async throws {
        let harness = try await LifecycleTransportHarness()
        await harness.stub.respond { _, attempt in
            attempt == 1
                ? .failure(status: 401, code: "expired_token")
                : .success()
        }

        let response: TransportPayload = try await harness.transport.execute(.getToday())
        let requests = await harness.stub.requests()

        #expect(response.value == "ok")
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "X-Request-Id") ==
            requests[1].value(forHTTPHeaderField: "X-Request-Id"))
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") !=
            requests[1].value(forHTTPHeaderField: "Authorization"))
        #expect(await harness.lifecycle.refreshCount == 1)
    }

    @Test("a second 401 ends without another refresh")
    func secondUnauthorizedEnds() async throws {
        let harness = try await LifecycleTransportHarness()
        await harness.stub.respond(with: .failure(status: 401, code: "expired_token"))

        await #expect(throws: MobileAPITransportError.self) {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
        }
        #expect(await harness.stub.requests().count == 2)
        #expect(await harness.lifecycle.refreshCount == 1)
    }

    @Test("a response completed after generation invalidation is suppressed")
    func staleResponseIsSuppressed() async throws {
        let harness = try await LifecycleTransportHarness()
        await harness.stub.respond { _, _ in
            await harness.lifecycle.supersede()
            return .success()
        }

        await #expect(throws: MobileAPITransportError.sessionSuperseded) {
            let _: TransportPayload = try await harness.transport.execute(.getToday())
        }
    }

    @Test("mutation retry preserves the logical idempotency key")
    func preservesKeyAcrossRetry() async throws {
        let harness = try await LifecycleTransportHarness()
        await harness.stub.respond { _, call in
            call == 1 ? .failure(status: 401, code: "expired_token") : .success()
        }
        let key = try IdempotencyKey(validating: "mobile-mutation-retry-0001")
        let request = try MobileAPIRequest<TransportPayload>(
            method: .patch,
            path: "/api/mobile/v1/me",
            body: Data("{}".utf8),
            idempotencyKey: key
        )

        let _: TransportPayload = try await harness.transport.execute(request)
        let keys = await harness.stub.requests().map {
            $0.value(forHTTPHeaderField: "Idempotency-Key")
        }

        #expect(keys == [key.value, key.value])
    }

    @Test("validation and decode failures are never retried")
    func doesNotRetryUnsafeFailures() async throws {
        let validationHarness = try await TransportHarness(tokens: ["session-alpha"])
        await validationHarness.stub.respond(with: .failure(status: 422, code: "validation_failed"))
        await #expect(throws: MobileAPITransportError.self) {
            let _: TransportPayload = try await validationHarness.transport.execute(.getToday())
        }
        #expect(await validationHarness.stub.requests().count == 1)

        let decodeHarness = try await TransportHarness(tokens: ["session-alpha"])
        await decodeHarness.stub.respond(with: .init(status: 200, body: Data("private body".utf8)))
        await #expect(throws: MobileAPITransportError.decodingFailure) {
            let _: TransportPayload = try await decodeHarness.transport.execute(.getToday())
        }
        #expect(await decodeHarness.stub.requests().count == 1)
    }

    @Test("diagnostic descriptions redact bearer body and signed URL shaped input")
    func diagnosticDescriptionsAreRedacted() {
        let sensitive = [
            "Bearer session-alpha",
            "person@example.invalid",
            "{\"name\":\"Private Person\"}",
            "https://storage.example.test/object?token=signed-value",
        ]
        let descriptions = [
            MobileAPITransportError.decodingFailure.description,
            MobileAPITransportError.http(
                status: 400,
                code: sensitive.joined(separator: " "),
                requestID: "unsafe request id \(sensitive[0])"
            ).description,
        ]

        for description in descriptions {
            for value in sensitive {
                #expect(!description.contains(value))
            }
        }
    }

    @Test("private patient requests bypass URL cache")
    func disablesPrivateCaching() async throws {
        let harness = try await TransportHarness(tokens: ["session-alpha"])
        await harness.stub.respond(with: .success())

        let _: TransportPayload = try await harness.transport.execute(.getToday())
        let request = try #require(await harness.stub.requests().first)

        #expect(request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }

    @Test("network cannot start before patient work registration succeeds")
    func registrationPrecedesNetworkStart() async throws {
        let stub = TransportStubStore()
        await stub.respond(with: .success())
        await StubURLProtocol.install(store: stub)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let transport = MobileAPITransport(
            configuration: try MobileAPIConfiguration(
                originString: "https://staging.example.test"
            ),
            sessionLifecycle: RejectingRegistrationLifecycle(),
            session: URLSession(configuration: configuration),
            clock: ContinuousClock(),
            timeout: .seconds(2)
        )

        await #expect(throws: MobileAPITransportError.sessionSuperseded) {
            let _: TransportPayload = try await transport.execute(.getToday())
        }
        #expect(await stub.requests().isEmpty)
    }

    @Test("caller cancellation before registration release sends no request")
    func cancellationBeforeRegistrationReleaseSendsNothing() async throws {
        let stub = TransportStubStore()
        await stub.respond(with: .success())
        await StubURLProtocol.install(store: stub)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let lifecycle = BlockingRegistrationLifecycle()
        let transport = MobileAPITransport(
            configuration: try MobileAPIConfiguration(
                originString: "https://staging.example.test"
            ),
            sessionLifecycle: lifecycle,
            session: URLSession(configuration: configuration),
            clock: ContinuousClock(),
            timeout: .seconds(2)
        )
        let request = Task {
            let _: TransportPayload = try await transport.execute(.getToday())
        }
        await lifecycle.waitForRegistrationStart()

        request.cancel()
        await lifecycle.releaseRegistration()

        await #expect(throws: CancellationError.self) {
            try await request.value
        }
        #expect(await stub.requests().isEmpty)
    }
    // C11 characterization uses this serialized suite's existing HTTP peers.
    // Coordinator/store/transport are real; holds only delay actual boundaries.
    @Test("C11 W02: a scoped GET/PATCH/DELETE cannot adopt B or A2 during lease capture",
          arguments: [HTTPMethod.get, .patch, .delete], [false, true])
    func c11W02LeaseAwaitCannotRebind(method: HTTPMethod, returnToA: Bool) async throws {
        let harness = try await C11RealLifecycleTransportHarness()
        let original = try await harness.lifecycle.leaseForRequest()
        let scoped = harness.transport.scoped(to: original)
        await harness.lifecycle.holdNextLease()
        let request = try C11RealLifecycleTransportHarness.request(method: method)
        let operation = Task { try await scoped.execute(request) }
        await harness.lifecycle.leaseHold.waitUntilEntered()
        try await harness.replaceSession(returnToA: returnToA)
        let current = try await harness.coordinator.leaseForRequest()
        #expect(current.generation != original.generation)
        #expect(current.userID == (returnToA ? "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" : "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"))
        await harness.lifecycle.leaseHold.release()
        await #expect(throws: MobileAPITransportError.sessionSuperseded) {
            _ = try await operation.value
        }
        #expect(await harness.stub.requests().isEmpty)
        #expect(await harness.remote.refreshCount == 0)
        // Re-scoping an already-bound transport cannot renew it for A2/B.
        await #expect(throws: MobileAPITransportError.sessionSuperseded) {
            _ = try await scoped.scoped(to: current).execute(request)
        }
        #expect(await harness.stub.requests().isEmpty)
    }

    @Test("C11 W03: a completed HTTP success pending validation cannot publish after B/A2",
          arguments: [HTTPMethod.get, .patch, .delete], [false, true])
    func c11W03SuccessPendingValidation(method: HTTPMethod, returnToA: Bool) async throws {
        let harness = try await C11RealLifecycleTransportHarness()
        let original = try await harness.lifecycle.leaseForRequest()
        let request = try C11RealLifecycleTransportHarness.request(method: method)
        await harness.lifecycle.holdNextFinish()
        let operation = Task { try await harness.transport.scoped(to: original).execute(request) }
        await harness.lifecycle.finishHold.waitUntilEntered()
        let sent = await harness.stub.requests()
        #expect(sent.count == 1)
        #expect(sent.first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(original.bearer)")
        try await harness.replaceSession(returnToA: returnToA)
        await harness.lifecycle.finishHold.release()
        await #expect(throws: MobileAPITransportError.sessionSuperseded) {
            _ = try await operation.value
        }
        #expect(await harness.stub.requests().count == 1)
        #expect(await harness.remote.refreshCount == 0)
        // The HTTP request already left. This oracle does not imply server rollback.
    }

    @Test("C11 W04: a completed 401 pending validation cannot refresh another generation",
          arguments: [HTTPMethod.get, .patch, .delete], [false, true])
    func c11W04UnauthorizedPendingValidation(method: HTTPMethod, returnToA: Bool) async throws {
        let harness = try await C11RealLifecycleTransportHarness()
        let original = try await harness.lifecycle.leaseForRequest()
        await harness.stub.respond(with: .failure(status: 401, code: "expired_token"))
        await harness.lifecycle.holdNextFinish()
        let request = try C11RealLifecycleTransportHarness.request(method: method)
        let operation = Task { try await harness.transport.scoped(to: original).execute(request) }
        await harness.lifecycle.finishHold.waitUntilEntered()
        #expect(await harness.stub.requests().count == 1)
        try await harness.replaceSession(returnToA: returnToA)
        await harness.lifecycle.finishHold.release()
        await #expect(throws: MobileAPITransportError.sessionSuperseded) {
            _ = try await operation.value
        }
        #expect(await harness.remote.refreshCount == 0)
        #expect(await harness.stub.requests().count == 1)
    }

    @Test("C11 W05: same-generation refresh preserves the exact logical request",
          arguments: [HTTPMethod.get, .patch, .delete])
    func c11W05RefreshPreservesScopeAndCommand(method: HTTPMethod) async throws {
        let harness = try await C11RealLifecycleTransportHarness()
        let original = try await harness.lifecycle.leaseForRequest()
        let bodyCapture = C11RequestBodyCapture()
        await harness.stub.respond { request, call in
            try await bodyCapture.capture(request)
            return call == 1 ? .failure(status: 401, code: "expired_token") : .success()
        }
        let request = try C11RealLifecycleTransportHarness.request(method: method)
        let response = try await harness.transport.scoped(to: original).execute(request)
        #expect(response == TransportPayload(value: "ok"))
        let current = try await harness.coordinator.leaseForRequest()
        #expect(current.userID == original.userID)
        #expect(current.generation == original.generation)
        let sent = await harness.stub.requests()
        #expect(sent.count == 2)
        let first = try #require(sent.first)
        let second = try #require(sent.last)
        #expect(first.httpMethod == second.httpMethod)
        #expect(first.url == second.url)
        let bodies = await bodyCapture.bodies()
        #expect(bodies.count == 2)
        #expect(bodies.allSatisfy { $0 == request.body })
        #expect(first.value(forHTTPHeaderField: "Idempotency-Key") == second.value(forHTTPHeaderField: "Idempotency-Key"))
        #expect(first.value(forHTTPHeaderField: "X-Request-Id") == second.value(forHTTPHeaderField: "X-Request-Id"))
        #expect(first.value(forHTTPHeaderField: "Authorization") != second.value(forHTTPHeaderField: "Authorization"))
        #expect((method == .get) == (first.value(forHTTPHeaderField: "Idempotency-Key") == nil))
        #expect(await harness.remote.refreshCount == 1)
    }

    @Test("C11 W06: close before a reserved child attaches sends nothing and releases once")
    func c11W06CloseBeforeStartAndRelease() async throws {
        let harness = try await C11RealLifecycleTransportHarness()
        let lease = try await harness.lifecycle.leaseForRequest()
        let startHold = C11BoundaryHold()
        let gate = Prompt14SessionOperationGate(operationStartBoundary: {
            await startHold.enterAndWait()
        })
        let capability = MealRecordSessionCapability(
            provider: MobileMealRecordRepository(transport: harness.transport.scoped(to: lease)), gate: gate
        )
        let retained = capability
        let operation = Task { try await capability.mealRecord(id: C11RealLifecycleTransportHarness.recordID) }
        await startHold.waitUntilEntered()
        gate.close()
        #expect(gate.isClosed)
        try await harness.replaceSession(returnToA: true)
        await startHold.release()
        await #expect(throws: CancellationError.self) { _ = try await operation.value }
        await gate.drain()
        capability.release()
        capability.release()
        #expect(!capability.hasRetainedCapability)
        await #expect(throws: CancellationError.self) {
            _ = try await retained.mealRecord(id: C11RealLifecycleTransportHarness.recordID)
        }
        #expect(await harness.stub.requests().isEmpty)
        #expect(await harness.remote.refreshCount == 0)
    }

    @MainActor
    @Test("C11 W03 model: finished GET/PATCH/DELETE cannot restore state or invalidate A2",
          arguments: [HTTPMethod.get, .patch, .delete])
    func c11W03ModelPublicationAndInvalidation(method: HTTPMethod) async throws {
        let harness = try await C11RealLifecycleTransportHarness()
        let lease = try await harness.lifecycle.leaseForRequest()
        let gate = Prompt14SessionOperationGate()
        let capability = MealRecordSessionCapability(
            provider: MobileMealRecordRepository(transport: harness.transport.scoped(to: lease)), gate: gate
        )
        let center = FeatureInvalidationCenter()
        let keys = C11OwnerFixtureKeys()
        let model = MealRecordModel(
            recordID: C11RealLifecycleTransportHarness.recordID, provider: capability,
            time: C11OwnerFixtureTime(), keys: keys, invalidation: center,
            isSessionActive: { !gate.isClosed }
        )
        try await harness.respondWithMealDetail()
        if method != .get {
            await model.load()
            #expect(model.detail != nil)
            #expect(model.canStartMutation)
            if method == .patch { model.draft?.items[0].quantityText = "25" }
            try await harness.respondWithMealReceipt(method: method)
        }
        await harness.lifecycle.holdNextFinish()
        let operation = Task { @MainActor in
            switch method {
            case .get: await model.load()
            case .patch: await model.save(language: .englishUnitedStates)
            case .delete: await model.delete()
            case .post: Issue.record("POST is outside this C11 test matrix")
            }
        }
        await harness.lifecycle.finishHold.waitUntilEntered()
        let retained = model.retainedAttempt
        #expect((method == .get) == (retained == nil))
        #expect(keys.count == (method == .get ? 0 : 1))
        let expectedRequests = method == .get ? 1 : 2
        #expect(await harness.stub.requests().count == expectedRequests)
        gate.close() // synchronous auth boundary, BEFORE transition await
        model.endSession()
        try await harness.replaceSession(returnToA: true)
        await harness.lifecycle.finishHold.release()
        await operation.value
        await gate.drain()
        capability.release()
        #expect(model.detail == nil)
        #expect(model.draft == nil)
        #expect(model.retainedAttempt == nil)
        #expect(model.confirmedReceipt == nil)
        #expect(model.completedMutations.isEmpty)
        #expect(center.revision(for: .today) == 0)
        #expect(center.revision(for: .history) == 0)
        await model.retry()
        await model.save(language: .englishUnitedStates)
        await model.delete()
        #expect(await harness.stub.requests().count == expectedRequests)
        #expect(keys.count == (method == .get ? 0 : 1))
        #expect(await harness.remote.refreshCount == 0)
    }

    @MainActor
    @Test("C11 W01: owner reservation before await rejects a valid A2 lease",
          arguments: [false, true])
    func c11W01OwnerReservationBeforeAwait(closeLeafToo: Bool) async throws {
        let harness = try await C11RealLifecycleTransportHarness()
        let ownerA1 = Prompt14SessionOwner(userID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            dependencies: C11BindingTestDependencies.make(), enablesMealRecordBinding: true)
        await ownerA1.awaitPatientTimeZoneResolution()
        let bindingA1 = try #require(ownerA1.mealRecordBinding)
        #expect(bindingA1.isOpen)
        let originalLease = try await harness.coordinator.leaseForRequest()
        #expect(originalLease.userID == ownerA1.userID)
        await harness.lifecycle.holdNextLease(completeEvenIfCancelled: true)
        let oldBind = Task {
            try await bindingA1.bind(transport: harness.transport, lifecycle: harness.lifecycle)
        }
        await harness.lifecycle.leaseHold.waitUntilEntered()
        #expect(bindingA1.capability == nil)
        ownerA1.invalidateSynchronously()
        if closeLeafToo { bindingA1.invalidateSynchronously() }
        try await harness.replaceSession(returnToA: true)
        let current = try await harness.coordinator.leaseForRequest()
        try await harness.coordinator.validate(current)
        #expect(current.userID == ownerA1.userID)
        #expect(current.generation != originalLease.generation)
        await harness.lifecycle.leaseHold.release()
        await #expect(throws: CancellationError.self) { _ = try await oldBind.value }
        #expect(await harness.lifecycle.lastReturnedGeneration == current.generation)
        #expect(bindingA1.capability == nil)
        #expect(bindingA1.capturedLease == nil)
        #expect(!bindingA1.isOpen)
        #expect(await harness.stub.requests().isEmpty)
        let ownerA2 = Prompt14SessionOwner(userID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            dependencies: C11BindingTestDependencies.make(), enablesMealRecordBinding: true)
        await ownerA2.awaitPatientTimeZoneResolution()
        let bindingA2 = try #require(ownerA2.mealRecordBinding)
        try await harness.respondWithMealDetail()
        let currentCapability = try await bindingA2.bind(
            transport: harness.transport, lifecycle: harness.lifecycle)
        #expect(bindingA2.capturedLease?.generation == current.generation)
        let detail = try await currentCapability.mealRecord(id: C11RealLifecycleTransportHarness.recordID)
        #expect(detail.data.recordID == C11RealLifecycleTransportHarness.recordID)
        #expect(await harness.stub.requests().count == 1)
        await ownerA1.endSession()
        await ownerA2.endSession()
        #expect(!currentCapability.hasRetainedCapability)
    }

    @MainActor
    @Test("C11 BIND-F1: original owner close after bind blocks a retained grant before auth changes")
    func c11BindingOriginalOwnerCloseAfterBind() async throws {
        let harness = try await C11RealLifecycleTransportHarness()
        let owner = Prompt14SessionOwner(userID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            dependencies: C11BindingTestDependencies.make(), enablesMealRecordBinding: true)
        await owner.awaitPatientTimeZoneResolution()
        let binding = try #require(owner.mealRecordBinding)
        let lease = try await harness.coordinator.leaseForRequest()
        try await harness.respondWithMealDetail()
        let retained = try await binding.bind(transport: harness.transport, lifecycle: harness.lifecycle)
        #expect(binding.isOpen)
        #expect(retained.hasRetainedCapability)
        #expect(binding.capability === retained)
        #expect(await harness.stub.requests().isEmpty)
        owner.invalidateSynchronously() // ONLY original owner; lifecycle is still A1.
        try await harness.coordinator.validate(lease)
        #expect(owner.isInvalidated)
        #expect(!binding.isOpen)
        await #expect(throws: CancellationError.self) {
            _ = try await retained.mealRecord(id: C11RealLifecycleTransportHarness.recordID)
        }
        #expect(await harness.stub.requests().isEmpty)
        #expect(!retained.hasRetainedCapability)
        #expect(binding.capability == nil)
        #expect(binding.capturedLease == nil)
        await owner.endSession()
    }

    @MainActor
    @Test("C11 BIND-F2: cancel/owner-close/leaf-close after real visible commit leaves no orphan grant",
          arguments: [C11BindingTerminalBoundary.callerCancellation, .originalOwnerClose, .leafClose])
    func c11BindingTerminalBetweenCommitAndReturn(boundary: C11BindingTerminalBoundary) async throws {
        let harness = try await C11RealLifecycleTransportHarness()
        let owner = Prompt14SessionOwner(userID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            dependencies: C11BindingTestDependencies.make(), enablesMealRecordBinding: true)
        await owner.awaitPatientTimeZoneResolution()
        let binding = try #require(owner.mealRecordBinding)
        let lease = try await harness.coordinator.leaseForRequest()
        try await harness.respondWithMealDetail()
        await harness.lifecycle.holdNextVisibleReturn()
        let pending = Task { try await binding.bind(transport: harness.transport, lifecycle: harness.lifecycle) }
        await harness.lifecycle.visibleReturnHold.waitUntilEntered()
        // The delegate executed the REAL atomic commit before this hold.
        let installed = try #require(binding.capability)
        #expect(installed.hasRetainedCapability)
        #expect(binding.capturedLease?.generation == lease.generation)
        #expect(binding.capturedLease?.userID == lease.userID)
        #expect(binding.isOpen)
        #expect(await harness.stub.requests().isEmpty)
        switch boundary {
        case .callerCancellation: pending.cancel()
        case .originalOwnerClose: owner.invalidateSynchronously()
        case .leafClose: binding.invalidateSynchronously()
        }
        try await harness.coordinator.validate(lease) // no lifecycle transition hiding this gap
        await #expect(throws: CancellationError.self) {
            _ = try await installed.mealRecord(id: C11RealLifecycleTransportHarness.recordID)
        }
        #expect(await harness.stub.requests().isEmpty)
        // Closing a borrowed leaf must not close other original-owner capabilities.
        if boundary != .originalOwnerClose {
            #expect(!owner.isInvalidated)
            let neighbor = try await owner.progress.progress()
            #expect(!neighbor.meta.requestID.isEmpty)
        } else {
            #expect(owner.isInvalidated)
            await #expect(throws: CancellationError.self) { _ = try await owner.progress.progress() }
        }
        await harness.lifecycle.visibleReturnHold.release()
        await #expect(throws: CancellationError.self) { _ = try await pending.value }
        #expect(binding.capability == nil)
        #expect(binding.capturedLease == nil)
        #expect(!binding.isOpen)
        #expect(!installed.hasRetainedCapability)
        #expect(await harness.stub.requests().isEmpty)
        await owner.endSession()
    }

    @MainActor
    @Test("C11 BIND-F3: two concurrent owner ends join a held committed bind and release its grant")
    func c11BindingConcurrentEndJoinsHeldCommit() async throws {
        let harness = try await C11RealLifecycleTransportHarness()
        let owner = Prompt14SessionOwner(userID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            dependencies: C11BindingTestDependencies.make(), enablesMealRecordBinding: true)
        await owner.awaitPatientTimeZoneResolution()
        let binding = try #require(owner.mealRecordBinding)
        await harness.lifecycle.holdNextVisibleReturn()
        let pending = Task { try await binding.bind(transport: harness.transport, lifecycle: harness.lifecycle) }
        await harness.lifecycle.visibleReturnHold.waitUntilEntered()
        let installed = try #require(binding.capability)
        #expect(installed.hasRetainedCapability)
        let probe = C11ConcurrentEndProbe()
        let first = Task { @MainActor in
            probe.didStart()
            await owner.endSession()
            probe.didFinish()
        }
        let second = Task { @MainActor in
            probe.didStart()
            await owner.endSession()
            probe.didFinish()
        }
        await probe.waitForBothStarts()
        #expect(probe.finishedCount == 0)
        #expect(owner.isInvalidated)
        #expect(!binding.isOpen)
        #expect(binding.capability == nil)
        #expect(!installed.hasRetainedCapability)
        await harness.lifecycle.visibleReturnHold.release()
        await #expect(throws: CancellationError.self) { _ = try await pending.value }
        await first.value
        await second.value
        #expect(probe.finishedCount == 2)
        #expect(owner.mealRecordBinding == nil)
        #expect(binding.capability == nil)
        #expect(binding.capturedLease == nil)
        #expect(!owner.hasRetainedCapabilities)
        #expect(!installed.hasRetainedCapability)
        #expect(await harness.stub.requests().isEmpty)
        await owner.endSession()
        await binding.endSession()
    }

    @MainActor
    @Test("C11 H01: all five admitted auth entries withdraw the original grant before auth suspension",
          arguments: [C11AuthenticationEntry.start, .signIn, .signUp, .confirmDevelopment, .signOut])
    func c11H01FivePreAwaitAuthHooks(entry: C11AuthenticationEntry) async throws {
        let wire = try await C11RealLifecycleTransportHarness()
        let peer = C11AuthenticationEntryPeer(coordinator: wire.coordinator)
        let onboarding = C11AuthenticationOnboardingPeer(completed: true)
        let telemetry = InMemoryTelemetryClient()
        let tickets = C11AuthenticationTicketFactorySpy()
        let lifetime = MealRecordAuthenticationLifetime(ticketFactory: { tickets.next() })
        let model = C11AuthenticationFixtures.model(peer: peer, onboarding: onboarding,
            lifetime: lifetime, telemetry: telemetry, initialState: .authenticated(userID: C11AuthenticationFixtures.a))
        let grant = try await C11AuthenticationOwnedGrant.prepare(lifetime: lifetime, wire: wire)
        #expect(model.mealRecordActivation == grant.activation)
        #expect(tickets.issued.count == 1)
        let observation = C11ActivationObservationSignal()
        withObservationTracking { _ = model.mealRecordActivation } onChange: { observation.signal() }
        await peer.holdNextEntry(entry)
        let work = Task { await C11AuthenticationFixtures.invoke(entry, model: model) }
        do {
            await peer.entryHold.waitUntilEntered()
            // Auth has not switched/revoked the real A1 session yet.
            try await wire.coordinator.validate(grant.lease)
            #expect(!grant.binding.isOpen)
            #expect(!grant.retained.hasRetainedCapability)
            #expect(grant.binding.capability == nil)
            #expect(grant.binding.capturedLease == nil)
            #expect(model.mealRecordActivation == nil)
            #expect(lifetime.currentActivation == nil)
            #expect(observation.didChange)
            #expect(model.state == .authenticated(userID: C11AuthenticationFixtures.a))
            #expect(tickets.issued.count == 2)
            #expect(await peer.entries == [entry])
            await #expect(throws: CancellationError.self) {
                _ = try await grant.retained.mealRecord(id: C11RealLifecycleTransportHarness.recordID)
            }
            #expect(await wire.stub.requests().isEmpty)
            let heldCore = C11AuthenticationCoreSnapshot(model)
            await peer.entryHold.release()
            await work.value
            let resultingCore = C11AuthenticationCoreSnapshot(model)
            let resultingTelemetry = await telemetry.snapshot()
            #expect(await peer.entries == [entry])
            #expect(tickets.issued.count == 2)
            #expect(await wire.stub.requests().isEmpty)
            await lifetime.endSession()
            await grant.owner.endSession()
            // Default-nil reference follows the exact same existing core/telemetry.
            let referenceWire = try await C11RealLifecycleTransportHarness()
            let referencePeer = C11AuthenticationEntryPeer(coordinator: referenceWire.coordinator)
            let referenceTelemetry = InMemoryTelemetryClient()
            let reference = C11AuthenticationFixtures.model(peer: referencePeer,
                onboarding: C11AuthenticationOnboardingPeer(completed: true), telemetry: referenceTelemetry,
                initialState: .authenticated(userID: C11AuthenticationFixtures.a))
            await referencePeer.holdNextEntry(entry)
            let referenceWork = Task { await C11AuthenticationFixtures.invoke(entry, model: reference) }
            await referencePeer.entryHold.waitUntilEntered()
            #expect(C11AuthenticationCoreSnapshot(reference) == heldCore)
            #expect(reference.mealRecordActivation == nil)
            await referencePeer.entryHold.release()
            await referenceWork.value
            #expect(C11AuthenticationCoreSnapshot(reference) == resultingCore)
            #expect(await referenceTelemetry.snapshot() == resultingTelemetry)
            #expect(await referencePeer.entries == [entry])
        } catch {
            await peer.entryHold.release()
            await work.value
            await lifetime.endSession()
            await grant.owner.endSession()
            throw error
        }
    }

    @MainActor
    @Test("C11 auth guards do not retire a grant or reserve another ticket",
          arguments: [C11AuthenticationEntry.signIn, .signUp, .confirmDevelopment])
    func c11H01RejectedAuthGuardPreservesOriginal(entry: C11AuthenticationEntry) async throws {
        let wire = try await C11RealLifecycleTransportHarness()
        let peer = C11AuthenticationEntryPeer(coordinator: wire.coordinator)
        let tickets = C11AuthenticationTicketFactorySpy()
        let lifetime = MealRecordAuthenticationLifetime(ticketFactory: { tickets.next() })
        let telemetry = InMemoryTelemetryClient()
        let model = C11AuthenticationFixtures.model(peer: peer,
            onboarding: C11AuthenticationOnboardingPeer(completed: true), lifetime: lifetime,
            telemetry: telemetry, initialState: .authenticated(userID: C11AuthenticationFixtures.a),
            initialAuthOperationState: .submitting)
        let grant = try await C11AuthenticationOwnedGrant.prepare(lifetime: lifetime, wire: wire)
        let before = C11AuthenticationCoreSnapshot(model)
        await C11AuthenticationFixtures.invoke(entry, model: model)
        #expect(C11AuthenticationCoreSnapshot(model) == before)
        #expect(tickets.issued.count == 1)
        #expect(model.mealRecordActivation == grant.activation)
        #expect(grant.binding.isOpen)
        #expect(grant.retained.hasRetainedCapability)
        #expect(await peer.entries.isEmpty)
        #expect(await telemetry.snapshot().isEmpty)
        #expect(await wire.stub.requests().isEmpty)
        await lifetime.endSession()
        await grant.owner.endSession()
    }

    @MainActor
    @Test("C11 password recovery does not cross an authentication replacement boundary")
    func c11PasswordRecoveryPreservesOriginalGrant() async throws {
        let wire = try await C11RealLifecycleTransportHarness()
        let peer = C11AuthenticationEntryPeer(coordinator: wire.coordinator)
        let tickets = C11AuthenticationTicketFactorySpy()
        let lifetime = MealRecordAuthenticationLifetime(ticketFactory: { tickets.next() })
        let telemetry = InMemoryTelemetryClient()
        let model = C11AuthenticationFixtures.model(peer: peer,
            onboarding: C11AuthenticationOnboardingPeer(completed: true), lifetime: lifetime,
            telemetry: telemetry, initialState: .authenticated(userID: C11AuthenticationFixtures.a))
        let grant = try await C11AuthenticationOwnedGrant.prepare(lifetime: lifetime, wire: wire)
        await model.requestPasswordRecovery(email: C11AuthenticationFixtures.email)
        #expect(tickets.issued.count == 1)
        #expect(model.mealRecordActivation == grant.activation)
        #expect(grant.binding.isOpen)
        #expect(grant.retained.hasRetainedCapability)
        #expect(model.state == .authenticated(userID: C11AuthenticationFixtures.a))
        #expect(model.authOperationState == .recoveryConfirmation)
        #expect(await peer.entries == [.passwordRecovery])
        #expect(await telemetry.snapshot() == [
            .authOperationCompleted(screen: .passwordRecovery, outcome: .success)
        ])
        #expect(await wire.stub.requests().isEmpty)
        await lifetime.endSession()
        await grant.owner.endSession()
    }

    @MainActor
    @Test("C11 H03: an old completed/nil/unconfirmed/failed auth return cannot withdraw A2",
          arguments: [C11OldAuthenticationReturn.completed, .missing, .unconfirmed, .failed])
    func c11H03OldAuthenticationTerminalIsScoped(oldReturn: C11OldAuthenticationReturn) async throws {
        let wire = try await C11RealLifecycleTransportHarness()
        let peer = C11AuthenticationEntryPeer(coordinator: wire.coordinator)
        let tickets = C11AuthenticationTicketFactorySpy()
        let lifetime = MealRecordAuthenticationLifetime(ticketFactory: { tickets.next() })
        let model = C11AuthenticationFixtures.model(peer: peer,
            onboarding: C11AuthenticationOnboardingPeer(completed: true), lifetime: lifetime,
            telemetry: InMemoryTelemetryClient())
        await peer.holdNextEntry(.start, forcedRestore: C11AuthenticationFixtures.lateReturn(oldReturn))
        let first = Task { await model.start() }
        do {
            await peer.entryHold.waitUntilEntered()
            #expect(tickets.issued.count == 1)
            let originalTicket = try #require(tickets.issued.first)
            await C11AuthenticationFixtures.cycleThroughBAndBackToA(model: model, peer: peer)
            let current = try #require(lifetime.currentActivation)
            #expect(current.ticket != originalTicket)
            #expect(tickets.issued.count == 5)
            #expect(current.ticket == tickets.issued.last)
            #expect(model.mealRecordActivation == current)
            await peer.entryHold.release()
            await first.value
            #expect(lifetime.currentActivation == current)
            #expect(lifetime.isCurrent(current.ticket))
            #expect(tickets.issued.count == 5)
            #expect(await peer.entries == [.start, .signOut, .signIn, .signOut, .signIn])
            switch oldReturn {
            case .completed:
                #expect(model.state == .authenticated(userID: C11AuthenticationFixtures.a))
                #expect(model.mealRecordActivation == current)
            case .missing:
                #expect(model.state == .signedOut(.signIn))
                #expect(model.mealRecordActivation == nil)
            case .unconfirmed:
                #expect(model.state == .awaitingEmailConfirmation(email: C11AuthenticationFixtures.email))
                #expect(model.mealRecordActivation == nil)
            case .failed:
                #expect(model.state == .signedOut(.signIn))
                #expect(model.presentationError == .serviceUnavailable)
                #expect(model.mealRecordActivation == nil)
            }
            #expect(await wire.stub.requests().isEmpty)
            await lifetime.endSession()
        } catch {
            await peer.entryHold.release()
            await first.value
            await lifetime.endSession()
            throw error
        }
    }

    @MainActor
    @Test("C11 H03: a held onboarding return from A1 cannot replace A2 authority")
    func c11H03OldOnboardingReturnIsScoped() async throws {
        let wire = try await C11RealLifecycleTransportHarness()
        let peer = C11AuthenticationEntryPeer(coordinator: wire.coordinator)
        let onboarding = C11AuthenticationOnboardingPeer(completed: true)
        await onboarding.holdLoad(1)
        let tickets = C11AuthenticationTicketFactorySpy()
        let lifetime = MealRecordAuthenticationLifetime(ticketFactory: { tickets.next() })
        let model = C11AuthenticationFixtures.model(peer: peer, onboarding: onboarding,
            lifetime: lifetime, telemetry: InMemoryTelemetryClient())
        let first = Task { await model.start() }
        do {
            await onboarding.loadHold.waitUntilEntered()
            let firstTicket = try #require(tickets.issued.first)
            await C11AuthenticationFixtures.cycleThroughBAndBackToA(model: model, peer: peer)
            let current = try #require(lifetime.currentActivation)
            #expect(current.ticket != firstTicket)
            let core = C11AuthenticationCoreSnapshot(model)
            await onboarding.loadHold.release()
            await first.value
            #expect(lifetime.currentActivation == current)
            #expect(model.mealRecordActivation == current)
            #expect(C11AuthenticationCoreSnapshot(model) == core)
            #expect(tickets.issued.count == 5)
            #expect(await wire.stub.requests().isEmpty)
            await lifetime.endSession()
        } catch {
            await onboarding.loadHold.release()
            await first.value
            await lifetime.endSession()
            throw error
        }
    }

    @MainActor
    @Test("C11 H06: only an official completed restore publishes an activation",
          arguments: [C11ActivationSource.completed, .incomplete, .confirmationRequired])
    func c11H06LegitimateActivationSources(source: C11ActivationSource) async throws {
        let wire = try await C11RealLifecycleTransportHarness()
        let peer = C11AuthenticationEntryPeer(coordinator: wire.coordinator)
        let tickets = C11AuthenticationTicketFactorySpy()
        let lifetime = MealRecordAuthenticationLifetime(ticketFactory: { tickets.next() })
        let model = C11AuthenticationFixtures.model(peer: peer,
            onboarding: C11AuthenticationOnboardingPeer(completed: source == .completed),
            lifetime: lifetime, telemetry: InMemoryTelemetryClient())
        if source == .confirmationRequired {
            await peer.requireSignUpConfirmation()
            await model.signUp(email: C11AuthenticationFixtures.email, password: C11AuthenticationFixtures.syntheticPassword)
            #expect(model.state == .awaitingEmailConfirmation(email: C11AuthenticationFixtures.email))
        } else {
            await model.start()
        }
        #expect(tickets.issued.count == 1)
        if source == .completed {
            let activation = try #require(model.mealRecordActivation)
            #expect(activation.ticket == tickets.issued.first)
            let repeated = lifetime.publishAuthenticated(userID: activation.userID, ticket: activation.ticket)
            #expect(repeated == activation)
            #expect(tickets.issued.count == 1)
        } else {
            #expect(model.mealRecordActivation == nil)
            #expect(lifetime.currentActivation == nil)
        }
        #expect(await peer.entries.count == 1)
        #expect(await wire.stub.requests().isEmpty)
        await lifetime.endSession()
    }

    @MainActor
    @Test("C11 H06: onboarding retry and completion retain the auth ticket from before await")
    func c11H06RetryAndCompletionRetainOriginalTicket() async throws {
        let wire = try await C11RealLifecycleTransportHarness()
        let peer = C11AuthenticationEntryPeer(coordinator: wire.coordinator)
        let onboarding = C11AuthenticationOnboardingPeer(completed: false)
        await onboarding.failNextRead()
        let tickets = C11AuthenticationTicketFactorySpy()
        let lifetime = MealRecordAuthenticationLifetime(ticketFactory: { tickets.next() })
        let model = C11AuthenticationFixtures.model(peer: peer, onboarding: onboarding,
            lifetime: lifetime, telemetry: InMemoryTelemetryClient())
        await model.start()
        #expect(tickets.issued.count == 1)
        let original = try #require(tickets.issued.first)
        #expect(model.mealRecordActivation == nil)
        #expect(model.presentationError == .serviceUnavailable)
        await model.retryOnboardingRestore()
        #expect(tickets.issued.count == 1)
        #expect(await peer.entries == [.start])
        #expect(await onboarding.loads == 2)
        let owner = try #require(model.onboardingOwnerToken)
        model.completeOnboarding(ownerToken: owner)
        let activation = try #require(model.mealRecordActivation)
        #expect(activation.ticket == original)
        model.completeOnboarding(ownerToken: owner)
        #expect(model.mealRecordActivation == activation)
        #expect(tickets.issued.count == 1)
        #expect(await wire.stub.requests().isEmpty)
        await lifetime.endSession()
    }

    @MainActor
    @Test("C11 H06: late A1 incomplete form cannot spend A2's continuation through retry/completion",
          arguments: [C11OldIncompleteAction.retry, .complete])
    func c11H06OldIncompleteVisibleFormCannotUseCurrentTicket(action: C11OldIncompleteAction) async throws {
        let wire = try await C11RealLifecycleTransportHarness()
        let peer = C11AuthenticationEntryPeer(coordinator: wire.coordinator)
        let onboarding = C11AuthenticationOnboardingPeer(completed: false)
        let tickets = C11AuthenticationTicketFactorySpy()
        let lifetime = MealRecordAuthenticationLifetime(ticketFactory: { tickets.next() })
        let model = C11AuthenticationFixtures.model(peer: peer, onboarding: onboarding,
            lifetime: lifetime, telemetry: InMemoryTelemetryClient())
        await peer.holdNextEntry(.start, forcedRestore: C11AuthenticationFixtures.lateReturn(.completed))
        let first = Task { await model.start() }
        do {
            await peer.entryHold.waitUntilEntered()
            let oldTicket = try #require(tickets.issued.first)
            await C11AuthenticationFixtures.cycleThroughBAndBackToA(model: model, peer: peer)
            #expect(tickets.issued.count == 5)
            let currentTicket = try #require(tickets.issued.last)
            #expect(currentTicket != oldTicket)
            #expect(lifetime.isCurrent(currentTicket))
            let currentGeneration = model.onboardingRestoreGeneration
            let a2Owner = try #require(model.onboardingOwnerToken)
            #expect(lifetime.currentActivation == nil)
            await peer.entryHold.release()
            await first.value
            // Preserve the existing core's late visible-form publication.
            #expect(model.onboardingRestoreGeneration > currentGeneration)
            #expect(model.currentSession?.userID == C11AuthenticationFixtures.a)
            #expect(model.currentSession?.isOnboardingCompleted == false)
            #expect(lifetime.isCurrent(currentTicket))
            model.completeOnboarding(ownerToken: a2Owner)
            #expect(model.currentSession?.isOnboardingCompleted == false)
            if action == .retry { await model.retryOnboardingRestore() }
            model.completeOnboarding(for: C11AuthenticationFixtures.a)
            #expect(model.state == .authenticated(userID: C11AuthenticationFixtures.a))
            #expect(lifetime.currentActivation == nil)
            #expect(model.mealRecordActivation == nil)
            #expect(lifetime.isCurrent(currentTicket))
            #expect(tickets.issued.count == 5)
            #expect(await peer.entries == [.start, .signOut, .signIn, .signOut, .signIn])
            #expect(await wire.stub.requests().isEmpty)
            await lifetime.endSession()
        } catch {
            await peer.entryHold.release()
            await first.value
            await lifetime.endSession()
            throw error
        }
    }

    @MainActor
    @Test("C11 lifetime remains absent by default through actual restore and sign out")
    func c11DefaultNilRemainsOff() async throws {
        let wire = try await C11RealLifecycleTransportHarness()
        let peer = C11AuthenticationEntryPeer(coordinator: wire.coordinator)
        let telemetry = InMemoryTelemetryClient()
        let model = C11AuthenticationFixtures.model(peer: peer,
            onboarding: C11AuthenticationOnboardingPeer(completed: true), telemetry: telemetry)
        await model.start()
        #expect(model.state == .authenticated(userID: C11AuthenticationFixtures.a))
        #expect(model.mealRecordActivation == nil)
        await model.signOut()
        #expect(model.state == .signedOut(.signIn))
        #expect(model.mealRecordActivation == nil)
        #expect(await peer.entries == [.start, .signOut])
        #expect(await wire.stub.requests().isEmpty)
    }

    @MainActor
    @Test("C11 register rejects B for activation A and rejects A borrowed to register B's reservation",
          arguments: [C11WrongBindingOwnerArgument.actualB, .borrowedA])
    func c11RegistrationRequiresOriginalOwnerAndBinding(argument: C11WrongBindingOwnerArgument) async throws {
        let wire = try await C11RealLifecycleTransportHarness()
        let lifetime = MealRecordAuthenticationLifetime()
        let ticket = lifetime.beginAuthenticationBoundary()
        let activation = try #require(lifetime.publishAuthenticated(userID: C11AuthenticationFixtures.a, ticket: ticket))
        let ownerA = Prompt14SessionOwner(userID: C11AuthenticationFixtures.a,
            dependencies: C11BindingTestDependencies.make(), enablesMealRecordBinding: true)
        let ownerB = Prompt14SessionOwner(userID: C11AuthenticationFixtures.b,
            dependencies: C11BindingTestDependencies.make(), enablesMealRecordBinding: true)
        do {
            await ownerA.awaitPatientTimeZoneResolution()
            await ownerB.awaitPatientTimeZoneResolution()
            let bindingA = try #require(ownerA.mealRecordBinding)
            let bindingB = try #require(ownerB.mealRecordBinding)
            #expect(bindingA.isOpen)
            #expect(bindingB.isOpen)
            let suppliedOwner = argument == .actualB ? ownerB : ownerA
            #expect(!lifetime.register(binding: bindingB, owner: suppliedOwner, activation: activation))
            #expect(!bindingB.isOpen)
            #expect(bindingB.capability == nil)
            #expect(bindingB.capturedLease == nil)
            #expect(!ownerA.isInvalidated)
            #expect(!ownerB.isInvalidated)
            #expect(lifetime.currentActivation == activation)
            #expect(lifetime.isCurrent(ticket))
            #expect(bindingA.isOpen)
            #expect(lifetime.register(binding: bindingA, owner: ownerA, activation: activation))
            #expect(await wire.stub.requests().isEmpty)
            await lifetime.endSession()
            await ownerA.endSession()
            await ownerB.endSession()
        } catch {
            await lifetime.endSession()
            await ownerA.endSession()
            await ownerB.endSession()
            throw error
        }
    }

}

private actor RejectingRegistrationLifecycle: SessionLifecycleProviding {
    func currentBearerToken() -> String? { "bearer-old" }
    func leaseForRequest() -> SessionLease {
        SessionLease(userID: "user-old", generation: 1, bearer: "bearer-old")
    }
    func refreshAfterUnauthorized(lease: SessionLease) throws -> SessionLease {
        throw SessionLifecycleError.sessionSuperseded
    }
    func validate(_ lease: SessionLease) throws {}
    func signOut() -> RemoteRevocationOutcome { .confirmed }
    func beginPatientWork(
        lease: SessionLease,
        cancel: @escaping @Sendable () -> Void
    ) async throws -> UUID {
        try await Task.sleep(for: .milliseconds(100))
        cancel()
        throw SessionLifecycleError.sessionSuperseded
    }
    func finishPatientWork(_ id: UUID) {}
}

private actor BlockingRegistrationLifecycle: SessionLifecycleProviding {
    private var registrationStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var registrationRelease: CheckedContinuation<Void, Never>?

    func currentBearerToken() -> String? { "bearer-old" }
    func leaseForRequest() -> SessionLease {
        SessionLease(userID: "user-old", generation: 1, bearer: "bearer-old")
    }
    func refreshAfterUnauthorized(lease: SessionLease) throws -> SessionLease {
        throw SessionLifecycleError.refreshFailed
    }
    func validate(_ lease: SessionLease) throws {}
    func signOut() -> RemoteRevocationOutcome { .confirmed }
    func beginPatientWork(
        lease: SessionLease,
        cancel: @escaping @Sendable () -> Void
    ) async -> UUID {
        registrationStarted = true
        let waiters = startWaiters
        startWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { registrationRelease = $0 }
        return UUID()
    }
    func finishPatientWork(_ id: UUID) {}
    func waitForRegistrationStart() async {
        guard !registrationStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }
    func releaseRegistration() {
        registrationRelease?.resume()
        registrationRelease = nil
    }
}

private struct TransportPayload: Codable, Equatable, Sendable {
    let value: String
}

private extension MobileAPIRequest where Response == TransportPayload {
    static func getToday() throws -> Self {
        try MobileAPIRequest(method: .get, path: "/api/mobile/v1/today")
    }
}

struct ErrorCase: Sendable {
    let status: Int
    let code: String
    let category: TransportErrorCategory
}

enum TransportErrorCategory: Sendable {
    case unauthorized
    case forbidden
    case conflict
    case validation
    case rateLimited
    case server
    case other
}

private extension MobileAPITransportError {
    var category: TransportErrorCategory {
        switch self {
        case .unauthorized: .unauthorized
        case .forbidden: .forbidden
        case .conflict: .conflict
        case .validation: .validation
        case .rateLimited: .rateLimited
        case .server: .server
        default: .other
        }
    }
}

private struct TransportHarness: Sendable {
    let stub: TransportStubStore
    let transport: MobileAPITransport

    init(
        tokens: [String],
        timeout: Duration = .seconds(2),
        bodyLimit: Int = 64 * 1_024,
        maximumRetryCount: Int = 1
    ) async throws {
        let stub = TransportStubStore()
        let protocolClass = StubURLProtocol.self
        await protocolClass.install(store: stub)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolClass]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: configuration)
        let tokenProvider = RotatingTokenProvider(tokens: tokens)

        self.stub = stub
        self.transport = MobileAPITransport(
            configuration: try MobileAPIConfiguration(
                originString: "https://staging.example.test"
            ),
            sessionTokenProvider: tokenProvider,
            session: session,
            clock: ContinuousClock(),
            timeout: timeout,
            responseBodyLimit: bodyLimit,
            maximumRetryCount: maximumRetryCount
        )
    }
}

private struct LifecycleTransportHarness: Sendable {
    let stub: TransportStubStore
    let lifecycle: TransportLifecycleStub
    let transport: MobileAPITransport

    init() async throws {
        let stub = TransportStubStore()
        await StubURLProtocol.install(store: stub)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let lifecycle = TransportLifecycleStub()
        self.stub = stub
        self.lifecycle = lifecycle
        transport = MobileAPITransport(
            configuration: try MobileAPIConfiguration(
                originString: "https://staging.example.test"
            ),
            sessionLifecycle: lifecycle,
            session: session,
            clock: ContinuousClock(),
            timeout: .seconds(2),
            responseBodyLimit: 64 * 1_024
        )
    }
}

private actor TransportLifecycleStub: SessionLifecycleProviding {
    private var generation: UInt64 = 1
    private var bearer = "bearer-initial"
    private(set) var refreshCount = 0

    func currentBearerToken() -> String? { bearer }
    func leaseForRequest() -> SessionLease {
        SessionLease(userID: "user-a", generation: generation, bearer: bearer)
    }
    func refreshAfterUnauthorized(lease: SessionLease) throws -> SessionLease {
        try validate(lease)
        refreshCount += 1
        bearer = "bearer-rotated"
        return SessionLease(
            userID: lease.userID,
            generation: generation,
            bearer: bearer
        )
    }
    func validate(_ lease: SessionLease) throws {
        guard lease.generation == generation else {
            throw SessionLifecycleError.sessionSuperseded
        }
    }
    func signOut() -> RemoteRevocationOutcome { .confirmed }
    func beginPatientWork(
        lease: SessionLease,
        cancel: @escaping @Sendable () -> Void
    ) throws -> UUID {
        try validate(lease)
        return UUID()
    }
    func finishPatientWork(_ id: UUID) {}
    func supersede() { generation &+= 1 }
}

private actor RotatingTokenProvider: SessionTokenProviding {
    private var tokens: [String]

    init(tokens: [String]) {
        self.tokens = tokens
    }

    func currentBearerToken() -> String? {
        guard !tokens.isEmpty else { return nil }
        return tokens.removeFirst()
    }
}

private struct StubResponse: Sendable {
    let status: Int
    let headers: [String: String]
    let body: Data
    let delay: Duration
    let ignoresCancellation: Bool
    let redirectURL: URL?

    init(
        status: Int,
        headers: [String: String] = ["Content-Type": "application/json"],
        body: Data = Data(),
        delay: Duration = .zero,
        ignoresCancellation: Bool = false,
        redirectURL: URL? = nil
    ) {
        self.status = status
        self.headers = headers
        self.body = body
        self.delay = delay
        self.ignoresCancellation = ignoresCancellation
        self.redirectURL = redirectURL
    }

    static func success(
        requestID: String = "request-success-0001",
        delay: Duration = .zero,
        ignoresCancellation: Bool = false
    ) -> StubResponse {
        let body = Data(
            "{\"data\":{\"value\":\"ok\"},\"meta\":{\"api_version\":\"v1\",\"request_id\":\"\(requestID)\"}}".utf8
        )
        return StubResponse(
            status: 200,
            body: body,
            delay: delay,
            ignoresCancellation: ignoresCancellation
        )
    }

    static func failure(
        status: Int,
        code: String,
        requestID: String = "request-error-0001"
    ) -> StubResponse {
        StubResponse(
            status: status,
            body: Data(
                "{\"error\":{\"code\":\"\(code)\",\"message\":\"Synthetic failure\",\"request_id\":\"\(requestID)\",\"details\":{}}}".utf8
            )
        )
    }

    static func redirect(from: URL, to: URL) -> StubResponse {
        StubResponse(
            status: 302,
            headers: ["Location": to.absoluteString],
            redirectURL: to
        )
    }
}

private actor TransportStubStore {
    typealias Handler = @Sendable (URLRequest, Int) async throws -> StubResponse

    private var capturedRequests: [URLRequest] = []
    private var handler: Handler = { _, _ in .success() }

    func respond(with response: StubResponse) {
        handler = { _, _ in response }
    }

    func respond(_ handler: @escaping Handler) {
        self.handler = handler
    }

    func response(for request: URLRequest) async throws -> StubResponse {
        capturedRequests.append(request)
        return try await handler(request, capturedRequests.count)
    }

    func requests() -> [URLRequest] {
        capturedRequests
    }

    func waitForRequests(_ count: Int) async {
        while capturedRequests.count < count {
            await Task.yield()
        }
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let registry = StubRegistry()
    private var loadingContext: StubLoadingContext?

    static func install(store: TransportStubStore) async {
        await registry.install(store)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let context = StubLoadingContext(
            protocolInstance: self,
            request: request,
            registry: Self.registry
        )
        loadingContext = context
        context.start()
    }

    override func stopLoading() {
        loadingContext?.cancel()
    }
}

private final class StubLoadingContext: @unchecked Sendable {
    private let protocolInstance: StubURLProtocol
    private let request: URLRequest
    private let registry: StubRegistry
    private let lock = NSLock()
    private var cancelled = false

    init(
        protocolInstance: StubURLProtocol,
        request: URLRequest,
        registry: StubRegistry
    ) {
        self.protocolInstance = protocolInstance
        self.request = request
        self.registry = registry
    }

    func start() {
        Task { await run() }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }

    private func run() async {
        guard let store = await registry.current() else { return }
        do {
            let stub = try await store.response(for: request)
            try? await Task.sleep(for: stub.delay)
            guard stub.ignoresCancellation || !isCancelled else {
                throw CancellationError()
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: stub.status,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
            )!
            if let redirectURL = stub.redirectURL {
                var redirected = request
                redirected.url = redirectURL
                protocolInstance.client?.urlProtocol(
                    protocolInstance,
                    wasRedirectedTo: redirected,
                    redirectResponse: response
                )
                return
            }
            protocolInstance.client?.urlProtocol(
                protocolInstance,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            protocolInstance.client?.urlProtocol(protocolInstance, didLoad: stub.body)
            protocolInstance.client?.urlProtocolDidFinishLoading(protocolInstance)
        } catch is CancellationError {
            protocolInstance.client?.urlProtocol(
                protocolInstance,
                didFailWithError: URLError(.cancelled)
            )
        } catch {
            protocolInstance.client?.urlProtocol(
                protocolInstance,
                didFailWithError: error
            )
        }
    }

    private var isCancelled: Bool {
        lock.withLock { cancelled }
    }
}

private actor StubRegistry {
    private var store: TransportStubStore?

    func install(_ store: TransportStubStore) {
        self.store = store
    }

    func current() -> TransportStubStore? {
        store
    }
}

// C11 test boundaries delay the real session lifecycle, without replacing it.
// No separate transport/session engine: all actual behavior delegates to the
// existing SessionLifecycleCoordinator, PatientWorkRegistry and MobileAPITransport.
private actor C11BoundaryHold {
    private var entered = false
    private var opened = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func enterAndWait() async {
        entered = true
        let enteredWaiters = enteredWaiters
        self.enteredWaiters.removeAll()
        enteredWaiters.forEach { $0.resume() }
        guard !opened else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }
    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }
    func release() {
        opened = true
        let releaseWaiters = releaseWaiters
        self.releaseWaiters.removeAll()
        releaseWaiters.forEach { $0.resume() }
    }
}

private actor C11HoldingLifecycle: SessionLifecycleProviding {
    let base: SessionLifecycleCoordinator
    let leaseHold = C11BoundaryHold()
    let finishHold = C11BoundaryHold()
    let visibleReturnHold = C11BoundaryHold()
    private var nextLeaseIsHeld = false
    private var completeHeldLeaseEvenIfCancelled = false
    private var nextFinishIsHeld = false
    private var nextVisibleReturnIsHeld = false
    private(set) var lastReturnedGeneration: UInt64?

    init(base: SessionLifecycleCoordinator) { self.base = base }
    func holdNextLease(completeEvenIfCancelled: Bool = false) {
        nextLeaseIsHeld = true
        completeHeldLeaseEvenIfCancelled = completeEvenIfCancelled
    }
    func holdNextFinish() { nextFinishIsHeld = true }
    func holdNextVisibleReturn() { nextVisibleReturnIsHeld = true }
    func currentBearerToken() async -> String? { await base.currentBearerToken() }
    func restorePublicSession() async throws -> AuthSession? { try await base.restorePublicSession() }
    func `switch`(to record: AuthenticationSessionRecord) async throws { try await base.switch(to: record) }
    func leaseForRequest() async throws -> SessionLease {
        let held = nextLeaseIsHeld
        let completesIfCancelled = completeHeldLeaseEvenIfCancelled
        nextLeaseIsHeld = false
        completeHeldLeaseEvenIfCancelled = false
        if held { await leaseHold.enterAndWait() }
        let lease: SessionLease
        if held && completesIfCancelled {
            // Test one resolver that completes despite caller cancellation.
            // It still obtains the REAL current lease; no generation/token is fabricated.
            let completion = Task { try await base.leaseForRequest() }
            lease = try await completion.value
        } else {
            lease = try await base.leaseForRequest()
        }
        lastReturnedGeneration = lease.generation
        return lease
    }
    func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease {
        try await base.refreshAfterUnauthorized(lease: lease)
    }
    func validate(_ lease: SessionLease) async throws { try await base.validate(lease) }
    func signOut() async -> RemoteRevocationOutcome { await base.signOut() }
    func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws -> UUID {
        try await base.beginPatientWork(lease: lease, cancel: cancel)
    }
    func finishPatientWork(_ id: UUID) async {
        let held = nextFinishIsHeld
        nextFinishIsHeld = false
        if held { await finishHold.enterAndWait() }
        await base.finishPatientWork(id)
    }
    func performPatientStateOperation<Value: Sendable>(
        lease: SessionLease, operation: @Sendable () throws -> Value
    ) async throws -> Value {
        try await base.performPatientStateOperation(lease: lease, operation: operation)
    }
    func performVisiblePatientStateOperation<Value: Sendable>(
        lease: SessionLease, operation: @MainActor @Sendable () throws -> Value
    ) async throws -> Value {
        let held = nextVisibleReturnIsHeld
        nextVisibleReturnIsHeld = false
        let value = try await base.performVisiblePatientStateOperation(lease: lease, operation: operation)
        if held { await visibleReturnHold.enterAndWait() }
        return value
    }
}

private actor C11OwnerRemote: SupabaseAuthRemoteOperating {
    private(set) var refreshCount = 0
    func signIn(email: String, password: String) throws -> AuthenticationSessionRecord {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func signUp(email: String, password: String) throws -> SupabaseRemoteSignUpResult {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func requestPasswordRecovery(email: String) throws {}
    func refresh(record: AuthenticationSessionRecord) -> AuthenticationSessionRecord {
        refreshCount += 1
        return C11RealLifecycleTransportHarness.record(userID: record.userID, ordinal: 10)
    }
    func revokeCurrentSession(accessToken: String) -> RemoteRevocationOutcome { .confirmed }
}

private struct C11RealLifecycleTransportHarness: Sendable {
    static let recordID = "11111111-1111-4111-8111-111111111111"
    let stub: TransportStubStore
    let remote: C11OwnerRemote
    let coordinator: SessionLifecycleCoordinator
    let lifecycle: C11HoldingLifecycle
    let transport: MobileAPITransport

    init() async throws {
        let store = AuthenticationSessionStore(
            secureStore: InMemorySecureStore(), now: { Date(timeIntervalSince1970: 1000) }
        )
        try await store.replace(with: Self.record(userID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", ordinal: 1))
        let remote = C11OwnerRemote()
        let coordinator = SessionLifecycleCoordinator(
            store: store, remote: remote,
            refreshPolicy: SessionRefreshPolicy(now: { Date(timeIntervalSince1970: 1000) }, leeway: 60)
        )
        let lifecycle = C11HoldingLifecycle(base: coordinator)
        let stub = TransportStubStore()
        await StubURLProtocol.install(store: stub)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        self.stub = stub
        self.remote = remote
        self.coordinator = coordinator
        self.lifecycle = lifecycle
        self.transport = MobileAPITransport(
            configuration: try MobileAPIConfiguration(originString: "https://staging.example.test"),
            sessionLifecycle: lifecycle, session: URLSession(configuration: configuration),
            clock: ContinuousClock(), timeout: .seconds(2)
        )
        _ = try await coordinator.leaseForRequest() // bootstrap before hold; generation is real
    }

    func replaceSession(returnToA: Bool) async throws {
        try await coordinator.switch(to: Self.record(userID: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", ordinal: 2))
        if returnToA {
            try await coordinator.switch(to: Self.record(userID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", ordinal: 3))
        }
    }

    static func record(userID: String, ordinal: Int) -> AuthenticationSessionRecord {
        AuthenticationSessionRecord(
            userID: userID, email: "c11-owner@example.invalid", isEmailConfirmed: true,
            isOnboardingCompleted: true, accessToken: c11OwnerToken(subject: userID, marker: "\(ordinal)"),
            refreshToken: "c11-synthetic-refresh-\(ordinal)", expiresAt: Date(timeIntervalSince1970: 2000)
        )
    }

    static func request(method: HTTPMethod) throws -> MobileAPIRequest<TransportPayload> {
        try MobileAPIRequest(
            method: method, path: "/api/mobile/v1/meal-records/\(recordID)",
            body: method == .get ? nil : Data("{}".utf8),
            idempotencyKey: method == .get ? nil : IdempotencyKey(validating: "c11-owner-command-0001")
        )
    }

    func respondWithMealDetail() async throws {
        let value = Self.detail()
        // DTO uses its real Codable implementation, not a second wire schema.
        let data = try JSONEncoder().encode(value)
        await stub.respond(with: StubResponse(status: 200, body: data))
    }

    static func detail() -> MealRecordResponse {
        let item = MealRecordItemSnapshot(
            id: recordID, foodName: "Synthetic owner fixture", quantityG: 50, kcal: 100,
            proteinG: 1, carbsG: 2, fatG: 3, source: "canonical_exact",
            consumedAt: APITimestamp(value: Date(timeIntervalSince1970: 1790000000)), mealType: nil
        )
        return MealRecordResponse(data: MealRecordSnapshot(
            recordID: recordID, scope: .item, expectedVersion: "opaque-owner-fixture-version",
            itemIDs: [recordID], items: [item], editable: true, dayClosed: false,
            localDate: "2026-10-13", timezone: "America/Sao_Paulo", editBlockReason: nil
        ), meta: MobileResponseMetadata(apiVersion: "v1", requestID: "c11-owner-fixture"))
    }
}

private extension C11RealLifecycleTransportHarness {
    func respondWithMealReceipt(method: HTTPMethod) async throws {
        let next = "22222222-2222-4222-8222-222222222222"
        let updated = method == .patch
        let value = MealRecordMutationResponse(data: MealRecordMutationSnapshot(
            recordID: Self.recordID, operation: updated ? .updated : .deleted,
            newItemIDs: updated ? [next] : [], removedItemIDs: [Self.recordID],
            nextRecordID: updated ? next : nil,
            snapshot: MealRecordPersistedSnapshot(id: "c11-owner-snapshot", date: "2026-10-13",
                caloriesConsumed: updated ? 123 : 0, proteinG: 0, carbsG: 0, fatG: 0, dailyBalance: 0)
        ), meta: MobileResponseMetadata(apiVersion: "v1", requestID: "c11-owner-mutation-fixture"))
        await stub.respond(with: StubResponse(status: 200, body: try JSONEncoder().encode(value)))
    }
}

private struct C11OwnerFixtureTime: TimeProviding {
    var now: Date { Date(timeIntervalSince1970: 1790000000) }
}

private final class C11OwnerFixtureKeys: IdempotencyKeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var issued = 0
    var count: Int { lock.withLock { issued } }
    func nextKey() throws -> IdempotencyKey {
        let ordinal = lock.withLock { issued += 1; return issued }
        return try IdempotencyKey(validating: "c11-owner-model-command-\(ordinal)")
    }
}

// URLProtocol can receive a body stream instead of httpBody. Capture it at
// the handler boundary so body equality cannot pass as nil == nil.
private actor C11RequestBodyCapture {
    private var values: [Data?] = []
    func capture(_ request: URLRequest) throws {
        if let body = request.httpBody { values.append(body); return }
        guard let stream = request.httpBodyStream else { values.append(nil); return }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 256)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw C11BodyCaptureError.readFailed }
            if count == 0 { break }
            guard result.count + count <= 8192 else { throw C11BodyCaptureError.tooLarge }
            result.append(contentsOf: buffer.prefix(count))
        }
        values.append(result)
    }
    func bodies() -> [Data?] { values }
}
private enum C11BodyCaptureError: Error { case readFailed, tooLarge }

// Same synthetic subject-bearing token shape as SessionLifecycleCoordinatorTests.
// No real signature, session, auth provider or credential is used.
private func c11OwnerToken(subject: String, marker: String) -> String {
    let header = Data(#"{"alg":"none"}"#.utf8).c11OwnerBase64URL
    let payload = Data(#"{"sub":"\#(subject)","marker":"\#(marker)"}"#.utf8)
        .c11OwnerBase64URL
    return "\(header).\(payload).synthetic"
}

private extension Data {
    var c11OwnerBase64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum C11BindingTerminalBoundary: Equatable, Sendable {
    case callerCancellation
    case originalOwnerClose
    case leafClose
}

@MainActor
private final class C11ConcurrentEndProbe {
    private var startedCount = 0
    private(set) var finishedCount = 0
    private var startsWaiter: CheckedContinuation<Void, Never>?
    func didStart() {
        startedCount += 1
        if startedCount == 2 {
            startsWaiter?.resume()
            startsWaiter = nil
        }
    }
    func didFinish() { finishedCount += 1 }
    func waitForBothStarts() async {
        guard startedCount < 2 else { return }
        await withCheckedContinuation { startsWaiter = $0 }
    }
}

private enum C11BindingTestDependencies {
    static func make() -> AppDependencies {
        let base = AppDependencies.scaffold()
        return AppDependencies(
            apiClient: base.apiClient, authentication: base.authentication,
            onboarding: base.onboarding, coachPersona: base.coachPersona,
            secureStore: base.secureStore, telemetry: base.telemetry,
            today: base.today, history: base.history, plan: base.plan,
            progress: C11BindingNeighborProgress(), mealDetection: base.mealDetection,
            registration: base.registration, hydration: base.hydration, weight: base.weight,
            routine: base.routine, me: base.me,
            publishedContentSessions: base.publishedContentSessions,
            coachExperienceSessions: base.coachExperienceSessions,
            contentCoverSessions: base.contentCoverSessions,
            timeProvider: base.timeProvider, idempotencyKeyProvider: base.idempotencyKeyProvider,
            patientTimeZoneStore: base.patientTimeZoneStore, flowChat: base.flowChat
        )
    }
}
private struct C11BindingNeighborProgress: ProgressProviding {
    func progress() async throws -> ProgressResponse { BodyFlowTestFixtures.progressResponse }
    func profileWeight() async throws -> ProfileWeightResponse? { nil }
}

// These parameter types are internal because the existing suite's @Test methods
// are internal (private enum parameters would be a compiler/setup failure).
enum C11AuthenticationEntry: CaseIterable, Equatable, Sendable {
    case start, signIn, signUp, confirmDevelopment, signOut, passwordRecovery
}
enum C11OldAuthenticationReturn: Equatable, Sendable { case completed, missing, unconfirmed, failed }
enum C11ActivationSource: Equatable, Sendable { case completed, incomplete, confirmationRequired }
enum C11OldIncompleteAction: Equatable, Sendable { case retry, complete }

@MainActor
private final class C11AuthenticationTicketFactorySpy {
    private(set) var issued: [MealRecordAuthenticationTicket] = []
    func next() -> MealRecordAuthenticationTicket {
        let value = MealRecordAuthenticationTicket()
        issued.append(value)
        return value
    }
}

private final class C11ActivationObservationSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false
    func signal() { lock.withLock { changed = true } }
    var didChange: Bool { lock.withLock { changed } }
}

private actor C11AuthenticationEntryPeer: AuthenticationService {
    let coordinator: SessionLifecycleCoordinator
    let entryHold = C11BoundaryHold()
    private var heldEntry: C11AuthenticationEntry?
    private var forcedHeldRestore: Result<AuthSession?, AuthenticationError>?
    private var signInRecords: [AuthenticationSessionRecord] = []
    private var signUpNeedsConfirmation = false
    private(set) var entries: [C11AuthenticationEntry] = []

    init(coordinator: SessionLifecycleCoordinator) { self.coordinator = coordinator }
    func holdNextEntry(_ entry: C11AuthenticationEntry,
        forcedRestore: Result<AuthSession?, AuthenticationError>? = nil) {
        heldEntry = entry
        forcedHeldRestore = forcedRestore
    }
    func setSignInRecords(_ values: [AuthenticationSessionRecord]) { signInRecords = values }
    func requireSignUpConfirmation() { signUpNeedsConfirmation = true }

    private func enter(_ entry: C11AuthenticationEntry) async -> Bool {
        entries.append(entry)
        guard heldEntry == entry else { return false }
        heldEntry = nil
        await entryHold.enterAndWait()
        return true
    }

    func restoreSession() async throws -> AuthSession? {
        let forced = forcedHeldRestore
        let held = await enter(.start)
        if held, let forced { return try forced.get() }
        return try await coordinator.restorePublicSession()
    }
    func signIn(email: String, password: String) async throws -> AuthSession {
        _ = await enter(.signIn)
        let record = signInRecords.isEmpty
            ? C11RealLifecycleTransportHarness.record(userID: C11AuthenticationFixtures.a, ordinal: 4)
            : signInRecords.removeFirst()
        try await coordinator.switch(to: record)
        return record.publicSession
    }
    func signUp(email: String, password: String) async throws -> AuthSignUpResult {
        _ = await enter(.signUp)
        if signUpNeedsConfirmation { return .confirmationRequired(email: C11AuthenticationFixtures.email) }
        let record = C11RealLifecycleTransportHarness.record(userID: C11AuthenticationFixtures.a, ordinal: 4)
        try await coordinator.switch(to: record)
        return .authenticated(record.publicSession)
    }
    func confirmEmailForDevelopment() async throws -> AuthSession {
        _ = await enter(.confirmDevelopment)
        let record = C11RealLifecycleTransportHarness.record(userID: C11AuthenticationFixtures.a, ordinal: 4)
        try await coordinator.switch(to: record)
        return record.publicSession
    }
    func requestPasswordRecovery(email: String) async throws { _ = await enter(.passwordRecovery) }
    func signOut() async throws {
        _ = await enter(.signOut)
        if await coordinator.signOut() == .localInvalidationFailed {
            throw AuthenticationError.storageUnavailable
        }
    }
}

private actor C11AuthenticationOnboardingPeer: OnboardingRepository {
    let loadHold = C11BoundaryHold()
    private var heldLoad: Int?
    private let completed: Bool
    private var failNext = false
    private(set) var loads = 0

    init(completed: Bool) { self.completed = completed }
    func holdLoad(_ ordinal: Int) { heldLoad = ordinal }
    func failNextRead() { failNext = true }
    func loadDraft(for userID: String) -> OnboardingDraft? {
        completed ? nil : BodyFlowTestFixtures.onboardingDraft(currentStep: .objective)
    }
    func loadState(for userID: String) async throws -> OnboardingServerState {
        loads += 1
        let value = OnboardingServerState(
            locale: "pt-BR",
            completion: OnboardingCompletionState(completed: completed,
                completedAt: completed ? "2026-10-13T00:00:00.000Z" : nil),
            requirements: .unavailable, acceptedActions: [],
            draft: completed ? nil : BodyFlowTestFixtures.onboardingDraft(currentStep: .objective)
        )
        if heldLoad == loads { await loadHold.enterAndWait() }
        if failNext { failNext = false; throw OnboardingRepositoryError.serviceUnavailable }
        return value
    }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}
    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}
    func clear(for userID: String) async throws {}
}

private enum C11AuthenticationFixtures {
    static let a = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    static let b = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    static let email = "c11-owner@example.invalid"
    static let syntheticPassword = "synthetic-local-only"

    @MainActor
    static func model(peer: C11AuthenticationEntryPeer,
        onboarding: C11AuthenticationOnboardingPeer,
        lifetime: MealRecordAuthenticationLifetime? = nil,
        telemetry: InMemoryTelemetryClient,
        initialState: AppFlowState = .launching,
        initialAuthOperationState: AuthOperationState = .idle) -> AppFlowModel {
        AppFlowModel(authentication: peer, onboarding: onboarding,
            persona: AppDependencies.scaffold().coachPersona, telemetry: telemetry,
            mealRecordAuthenticationLifetime: lifetime, initialState: initialState,
            initialAuthOperationState: initialAuthOperationState,
            developmentConsentAvailability: .syntheticDevelopment,
            now: { Date(timeIntervalSince1970: 1790000000) })
    }

    @MainActor
    static func invoke(_ entry: C11AuthenticationEntry, model: AppFlowModel) async {
        switch entry {
        case .start: await model.start()
        case .signIn: await model.signIn(email: email, password: syntheticPassword)
        case .signUp: await model.signUp(email: email, password: syntheticPassword)
        case .confirmDevelopment: await model.confirmEmailForDevelopment()
        case .signOut: await model.signOut()
        case .passwordRecovery: await model.requestPasswordRecovery(email: email)
        }
    }

    @MainActor
    static func cycleThroughBAndBackToA(model: AppFlowModel,
        peer: C11AuthenticationEntryPeer) async {
        await peer.setSignInRecords([
            C11RealLifecycleTransportHarness.record(userID: b, ordinal: 2),
            C11RealLifecycleTransportHarness.record(userID: a, ordinal: 3)
        ])
        await model.signOut()
        await model.signIn(email: email, password: syntheticPassword)
        await model.signOut()
        await model.signIn(email: email, password: syntheticPassword)
    }

    static func lateReturn(_ value: C11OldAuthenticationReturn) -> Result<AuthSession?, AuthenticationError> {
        switch value {
        case .completed: .success(C11RealLifecycleTransportHarness.record(userID: a, ordinal: 1).publicSession)
        case .missing: .success(nil)
        case .unconfirmed: .success(AuthSession(userID: a, email: email,
            isEmailConfirmed: false, isOnboardingCompleted: false))
        case .failed: .failure(.serviceUnavailable)
        }
    }
}

@MainActor
private struct C11AuthenticationOwnedGrant {
    let owner: Prompt14SessionOwner
    let binding: MealRecordSessionBinding
    let retained: MealRecordSessionCapability
    let activation: MealRecordAuthenticatedActivation
    let lease: SessionLease

    static func prepare(lifetime: MealRecordAuthenticationLifetime,
        wire: C11RealLifecycleTransportHarness) async throws -> Self {
        var preparedOwner: Prompt14SessionOwner?
        do {
            let ticket = lifetime.beginAuthenticationBoundary()
            let activation = try #require(lifetime.publishAuthenticated(
                userID: C11AuthenticationFixtures.a, ticket: ticket))
            let owner = Prompt14SessionOwner(userID: C11AuthenticationFixtures.a,
                dependencies: C11BindingTestDependencies.make(), enablesMealRecordBinding: true)
            preparedOwner = owner
            await owner.awaitPatientTimeZoneResolution()
            let binding = try #require(owner.mealRecordBinding)
            #expect(lifetime.register(binding: binding, owner: owner, activation: activation))
            let lease = try await wire.coordinator.leaseForRequest()
            try await wire.coordinator.validate(lease)
            try await wire.respondWithMealDetail() // a permitted GET has a valid real DTO, not a decode/setup failure
            let retained = try await binding.bind(transport: wire.transport, lifecycle: wire.lifecycle)
            #expect(retained.hasRetainedCapability)
            #expect(binding.isOpen)
            #expect(await wire.stub.requests().isEmpty)
            return Self(owner: owner, binding: binding, retained: retained, activation: activation, lease: lease)
        } catch {
            await lifetime.endSession()
            await preparedOwner?.endSession()
            throw error
        }
    }
}

private struct C11AuthenticationCoreSnapshot: Equatable, Sendable {
    let state: AppFlowState
    let session: AuthSession?
    let error: AppPresentationError?
    let operation: AuthOperationState
    let draft: OnboardingDraft?
    let requirements: OnboardingRequirements
    let restoreGeneration: Int
    let completedAt: String?
    let loadFailure: OnboardingLoadFailure?
    @MainActor init(_ model: AppFlowModel) {
        state = model.state; session = model.currentSession; error = model.presentationError
        operation = model.authOperationState; draft = model.restoredOnboardingDraft
        requirements = model.restoredOnboardingRequirements
        restoreGeneration = model.onboardingRestoreGeneration
        completedAt = model.restoredHistoricalCompletedAt; loadFailure = model.onboardingLoadFailure
    }
}

enum C11WrongBindingOwnerArgument: Equatable, Sendable { case actualB, borrowedA }
