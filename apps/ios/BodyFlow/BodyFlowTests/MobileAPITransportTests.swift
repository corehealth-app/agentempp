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
            case .get: _ = await model.load()
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
    @Test("C11 I5 binding: real terminal invalidation withdraws an idle retained capability",
          arguments: [C11I5BindingTerminal.invalidGrant, .signOut, .otherUser])
    func c11I5BindingRealTerminalWithdrawsIdleCapability(terminal: C11I5BindingTerminal) async throws {
        try await c11WithI5Binding { fixture in
            let runtime = fixture.runtime
            let capability = try await fixture.bind()
            try #require(capability.hasRetainedCapability)
            try #require(fixture.binding.capability === capability)
            try #require(await runtime.store.currentRecord() == runtime.original)
            try #require(await runtime.stub.requests().isEmpty)
            switch terminal {
            case .invalidGrant:
                await #expect(throws: SessionLifecycleError.missingSession) {
                    _ = try await runtime.session.refreshAfterUnauthorized(lease: runtime.originalLease)
                }
                try #require(await runtime.store.currentRecord() == nil)
                try #require(await runtime.remote.refreshCount == 1)
                try #require(await runtime.remote.revokeCount == 1)
            case .signOut:
                try #require(await runtime.session.signOut() == .confirmed)
                try #require(await runtime.store.currentRecord() == nil)
                try #require(await runtime.remote.revokeCount == 1)
            case .otherUser:
                let next = C11RealLifecycleTransportHarness.record(userID: C11AuthenticationFixtures.b, ordinal: 2)
                try await runtime.session.switch(to: next)
                try #require(await runtime.store.currentRecord() == next)
                await #expect(throws: SessionLifecycleError.sessionSuperseded) {
                    try await runtime.session.validate(runtime.originalLease)
                }
                try #require(await runtime.remote.revokeCount == 0)
            }
            // Causal product oracle comes before prospective registration/count oracles.
            #expect(!capability.hasRetainedCapability, "I5_BINDING_IDLE_REAL_INVALIDATION_WITHDRAWS_AUTHORITY")
            await #expect(throws: CancellationError.self) {
                _ = try await capability.mealRecord(id: C11RealLifecycleTransportHarness.recordID)
            }
            #expect(await runtime.stub.requests().isEmpty)
            let admitted = await runtime.probe.admittedIDs
            #expect(admitted.count == 1)
            #expect(runtime.cancellations.count == 1)
            #expect(await runtime.registry.activeCount == 0)
            await fixture.owner.endSession()
            #expect(await runtime.probe.finishedIDs == admitted)
            #expect(fixture.binding.capability == nil && fixture.binding.capturedLease == nil)
            #expect(await runtime.registry.activeCount == 0)
        }
    }

    @MainActor
    @Test("C11 I5 binding: transient, failed marker and same-user credentials preserve the real grant",
          arguments: [C11I5BindingPreserved.transient, .markerFailure, .sameUserCredentials])
    func c11I5BindingNonterminalPreservesAuthority(boundary: C11I5BindingPreserved) async throws {
        try await c11WithI5Binding { fixture in
            let runtime = fixture.runtime
            let capability = try await fixture.bind()
            try #require(capability.hasRetainedCapability)
            switch boundary {
            case .transient:
                await runtime.remote.failRefresh(with: .rateLimited)
                await #expect(throws: SessionLifecycleError.refreshFailed) {
                    _ = try await runtime.session.refreshAfterUnauthorized(lease: runtime.originalLease)
                }
                try #require(await runtime.remote.refreshCount == 1)
                try #require(await runtime.store.currentRecord() == runtime.original)
            case .markerFailure:
                await runtime.secure.rejectMarker()
                try #require(await runtime.session.signOut() == .localInvalidationFailed)
                try #require(await runtime.store.currentRecord() == runtime.original)
            case .sameUserCredentials:
                let next = C11RealLifecycleTransportHarness.record(userID: runtime.original.userID, ordinal: 2)
                try await runtime.session.switch(to: next)
                try #require(await runtime.store.currentRecord() == next)
                let current = try await runtime.session.leaseForRequest()
                try #require(current.generation == runtime.originalLease.generation)
            }
            try await runtime.session.validate(runtime.originalLease)
            #expect(capability.hasRetainedCapability)
            #expect(fixture.binding.capability === capability)
            #expect(runtime.cancellations.count == 0)
            #expect(await runtime.remote.revokeCount == 0)
            #expect(await runtime.registry.activeCount == 1)
            try await runtime.respond()
            let detail = try await capability.mealRecord(id: C11RealLifecycleTransportHarness.recordID)
            #expect(detail.data.recordID == C11RealLifecycleTransportHarness.recordID)
            #expect(await runtime.stub.requests().count == 1)
            #expect(await runtime.registry.activeCount == 1)
            let admitted = await runtime.probe.admittedIDs
            #expect(admitted.count == 1)
            await fixture.owner.endSession()
            #expect(!capability.hasRetainedCapability)
            #expect(await runtime.registry.activeCount == 0)
            #expect(await runtime.probe.finishedIDs == admitted)
        }
    }

    @MainActor
    @Test("C11 I5 binding: invalidation after the real visible commit cannot escape as a live grant")
    func c11I5BindingInvalidationBeforeRegistrationReturn() async throws {
        try await c11WithI5Binding { fixture in
            let runtime = fixture.runtime
            await runtime.held.holdNextVisibleReturn()
            let pending = Task { try await fixture.bind() }
            do {
                await runtime.held.visibleReturnHold.waitUntilEntered()
                let installed = try #require(fixture.binding.capability)
                try #require(installed.hasRetainedCapability)
                try #require(fixture.binding.capturedLease?.generation == runtime.originalLease.generation)
                try #require(await runtime.session.signOut() == .confirmed)
                try #require(await runtime.store.currentRecord() == nil)
                try #require(await runtime.remote.revokeCount == 1)
                await runtime.held.visibleReturnHold.release()
                let result = await pending.result
                if case .success = result {
                    Issue.record("I5_BINDING_INVALIDATED_COMMIT_MUST_NOT_RETURN_SUCCESS")
                }
                #expect(!installed.hasRetainedCapability)
                #expect(fixture.binding.capability == nil && fixture.binding.capturedLease == nil)
                #expect(await runtime.registry.activeCount == 0)
                #expect(await runtime.stub.requests().isEmpty)
            } catch {
                await runtime.releaseAll()
                _ = await pending.result
                throw error
            }
        }
    }

    @MainActor
    @Test("C11 I5 binding: cancellation or invalidation after actual work admission cleans its own UUID",
          arguments: [C11I5BindingAdmissionTerminal.invalidation, .callerCancellation, .leafClose])
    func c11I5BindingTerminalAfterActualAdmission(terminal: C11I5BindingAdmissionTerminal) async throws {
        try await c11WithI5Binding { fixture in
            let runtime = fixture.runtime
            await runtime.probe.holdNextBeginReturn()
            let pending = Task {
                do {
                    let capability = try await fixture.bind()
                    await runtime.probe.beginReturn.noteCompletion()
                    return capability
                } catch {
                    await runtime.probe.beginReturn.noteCompletion()
                    throw error
                }
            }
            do {
                let entered = await runtime.probe.beginReturn.waitUntilEnteredOrCompleted()
                // A missing future subscription is a structural contract failure, never a setup hang/product RED.
                guard entered else {
                    Issue.record("I5_BINDING_SUBSCRIPTION_CONTRACT_NOT_YET_PRESENT")
                    _ = await pending.result
                    return
                }
                let installed = try #require(fixture.binding.capability)
                let admitted = await runtime.probe.admittedIDs
                try #require(admitted.count == 1)
                try #require(await runtime.registry.activeCount == 1)
                switch terminal {
                case .invalidation:
                    try #require(await runtime.session.signOut() == .confirmed)
                    try #require(await runtime.store.currentRecord() == nil)
                case .callerCancellation: pending.cancel()
                case .leafClose: fixture.binding.invalidateSynchronously()
                }
                await runtime.probe.beginReturn.release()
                let result = await pending.result
                if case .success = result {
                    Issue.record("I5_BINDING_TERMINAL_ADMISSION_MUST_NOT_RETURN_SUCCESS")
                }
                #expect(!installed.hasRetainedCapability)
                #expect(await runtime.registry.activeCount == 0)
                #expect(await runtime.probe.finishedIDs == admitted)
                #expect(runtime.cancellations.count == (terminal == .invalidation ? 1 : 0))
                #expect(await runtime.stub.requests().isEmpty)
                if terminal != .invalidation {
                    try await runtime.session.validate(runtime.originalLease)
                    #expect(!fixture.owner.isInvalidated)
                    let neighbor = try await fixture.owner.progress.progress()
                    #expect(neighbor.meta.requestID == "progress-presentation-0001")
                }
                await fixture.binding.endSession()
                #expect(await runtime.probe.finishedIDs == admitted)
            } catch {
                await runtime.releaseAll()
                _ = await pending.result
                throw error
            }
        }
    }

    @MainActor
    @Test("C11 I5 binding: old delayed cleanup finishes only its UUID while same-generation A2 stays usable")
    func c11I5BindingOldCleanupCannotFinishA2() async throws {
        try await c11WithI5Binding { fixture in
            let runtime = fixture.runtime
            let oldCapability = try await fixture.bind()
            try #require(oldCapability.hasRetainedCapability)
            await runtime.probe.holdNextFinish()
            let oldEnd = Task { @MainActor in
                await fixture.binding.endSession()
                await runtime.probe.finishReturn.noteCompletion()
            }
            do {
                let entered = await runtime.probe.finishReturn.waitUntilEnteredOrCompleted()
                guard entered else {
                    Issue.record("I5_BINDING_OWNED_FINISH_CONTRACT_NOT_YET_PRESENT")
                    await oldEnd.value
                    return
                }
                try #require(!oldCapability.hasRetainedCapability)
                try #require(await runtime.registry.activeCount == 1)
                let fresh = try #require(fixture.owner.reserveNewMealRecordBinding())
                try #require(fresh !== fixture.binding)
                let current = try await fresh.bind(transport: runtime.transport, lifecycle: runtime.probe)
                try #require(current.hasRetainedCapability)
                try #require(fresh.capturedLease?.generation == runtime.originalLease.generation)
                let admitted = await runtime.probe.admittedIDs
                try #require(admitted.count == 2 && admitted[0] != admitted[1])
                try #require(await runtime.registry.activeCount == 2)
                await runtime.probe.finishReturn.release()
                await oldEnd.value
                #expect(await runtime.probe.finishedIDs == [admitted[0]])
                #expect(await runtime.registry.activeCount == 1)
                #expect(current.hasRetainedCapability)
                #expect(fixture.owner.mealRecordBinding === fresh)
                try await runtime.respond()
                let response = try await current.mealRecord(id: C11RealLifecycleTransportHarness.recordID)
                #expect(response.data.recordID == C11RealLifecycleTransportHarness.recordID)
                #expect(await runtime.stub.requests().count == 1)
                await fixture.binding.endSession()
                #expect(await runtime.probe.finishedIDs == [admitted[0]])
                #expect(await runtime.registry.activeCount == 1)
                await fixture.owner.endSession()
                #expect(await runtime.probe.finishedIDs == admitted)
                #expect(await runtime.registry.activeCount == 0)
                #expect(!current.hasRetainedCapability)
                #expect(runtime.cancellations.count == 0)
            } catch {
                await runtime.releaseAll()
                await oldEnd.value
                throw error
            }
        }
    }

    @MainActor
    @Test("C11 I5 binding: default and explicit source OFF leave the real registry unchanged",
          arguments: [false, true])
    func c11I5BindingSourceOffHasNoSubscription(explicitOwnerOff: Bool) async throws {
        let runtime = try await C11I5BindingRuntime()
        let dependencies = C11BindingTestDependencies.make()
        let owner = explicitOwnerOff
            ? Prompt14SessionOwner(userID: runtime.original.userID, dependencies: dependencies,
                                   enablesMealRecordBinding: false)
            : Prompt14SessionOwner(userID: runtime.original.userID, dependencies: dependencies)
        await owner.awaitPatientTimeZoneResolution()
        let source = AppDependencies.makeMealRecordBindingSource(enabled: false,
            mode: .releaseUnavailable, client: runtime.transport, lifecycle: runtime.probe)
        #expect(source == nil)
        #expect(owner.reserveNewMealRecordBinding() == nil)
        #expect(await runtime.registry.activeCount == 0)
        #expect(await runtime.probe.admittedIDs.isEmpty)
        #expect(await runtime.stub.requests().isEmpty)
        try await runtime.session.validate(runtime.originalLease)
        await owner.endSession()
        await owner.endSession()
        #expect(await runtime.registry.activeCount == 0)
        #expect(await runtime.probe.finishedIDs.isEmpty)
        #expect(runtime.cancellations.count == 0)
        #expect(await runtime.remote.refreshCount == 0)
        #expect(await runtime.remote.revokeCount == 0)
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

    @MainActor
    @Test("C11 H07 OFF: default and explicit-off owners never admit a meal leaf")
    func c11OwnerRenewalPermissionOffCannotActivate() async throws {
        let harness = try await C11RealLifecycleTransportHarness()
        let original = try await harness.coordinator.leaseForRequest()
        for explicitOff in [false, true] {
            let dependencies = C11BindingTestDependencies.make()
            let owner = explicitOff
                ? Prompt14SessionOwner(userID: original.userID, dependencies: dependencies,
                                       enablesMealRecordBinding: false)
                : Prompt14SessionOwner(userID: original.userID, dependencies: dependencies)
            await owner.awaitPatientTimeZoneResolution()
            try await harness.respondWithMealDetail()
            let reservation = owner.reserveNewMealRecordBinding()
            #expect(reservation == nil)
            // Exercise a bad accidental admission rather than only inspecting nil.
            if let reservation {
                let grant = try await reservation.bind(transport: harness.transport,
                                                       lifecycle: harness.lifecycle)
                _ = try await grant.mealRecord(id: C11RealLifecycleTransportHarness.recordID)
            }
            #expect(await harness.stub.requests().isEmpty)
            let neighbor = try await owner.progress.progress()
            #expect(neighbor.meta.requestID == "progress-presentation-0001")
            try await harness.coordinator.validate(original)
            await owner.endSession()
            #expect(owner.reserveNewMealRecordBinding() == nil)
            #expect(!owner.hasRetainedCapabilities)
        }
        #expect(await harness.remote.refreshCount == 0)
    }

    @MainActor
    @Test("C11 H07 closed: renewal cannot reactivate an invalidated or ended owner")
    func c11OwnerRenewalCannotReactivateClosedOwner() async throws {
        let harness = try await C11RealLifecycleTransportHarness()
        let original = try await harness.coordinator.leaseForRequest()
        let owner = Prompt14SessionOwner(userID: original.userID,
            dependencies: C11BindingTestDependencies.make(), enablesMealRecordBinding: true)
        await owner.awaitPatientTimeZoneResolution()
        let first = try #require(owner.mealRecordBinding)
        let retained = try await first.bind(transport: harness.transport, lifecycle: harness.lifecycle)
        owner.invalidateSynchronously() // Lifecycle A stays valid; only the original owner closes.
        try await harness.coordinator.validate(original)
        let rejected = owner.reserveNewMealRecordBinding()
        #expect(rejected == nil)
        if let rejected {
            await #expect(throws: CancellationError.self) {
                _ = try await rejected.bind(transport: harness.transport, lifecycle: harness.lifecycle)
            }
        }
        await #expect(throws: CancellationError.self) {
            _ = try await retained.mealRecord(id: C11RealLifecycleTransportHarness.recordID)
        }
        #expect(await harness.stub.requests().isEmpty)
        await owner.endSession()
        #expect(owner.reserveNewMealRecordBinding() == nil)
        #expect(owner.mealRecordBinding == nil)
        #expect(!owner.hasRetainedCapabilities)
        #expect(!retained.hasRetainedCapability)
    }

    @MainActor
    @Test("C11 H07 renewal: the same live owner denies its old grant and admits a fresh same-generation leaf")
    func c11OwnerRenewalOldGrantDeniedNewSameGenerationGETWorks() async throws {
        let harness = try await C11RealLifecycleTransportHarness()
        let original = try await harness.coordinator.leaseForRequest()
        let owner = Prompt14SessionOwner(userID: original.userID,
            dependencies: C11BindingTestDependencies.make(), enablesMealRecordBinding: true)
        await owner.awaitPatientTimeZoneResolution()
        let first = try #require(owner.mealRecordBinding)
        let oldGrant = try await first.bind(transport: harness.transport, lifecycle: harness.lifecycle)
        #expect(await harness.stub.requests().isEmpty)
        try await harness.respondWithMealDetail()
        let fresh = try #require(owner.reserveNewMealRecordBinding())
        #expect(fresh !== first)
        #expect(owner.mealRecordBinding === fresh)
        #expect(!first.isOpen)
        #expect(first.capability == nil && first.capturedLease == nil)
        #expect(!owner.isInvalidated)
        // The real lifecycle deliberately did NOT switch users or generation.
        try await harness.coordinator.validate(original)
        await #expect(throws: CancellationError.self) {
            _ = try await oldGrant.mealRecord(id: C11RealLifecycleTransportHarness.recordID)
        }
        #expect(await harness.stub.requests().isEmpty,
                "Renewal must deny the retained old endpoint before it reaches URLProtocol")
        let current = await c11OwnerRenewalBindMustSucceed(fresh, harness: harness)
        if let current {
            #expect(fresh.capturedLease?.generation == original.generation)
            #expect(fresh.capturedLease?.userID == original.userID)
            let detail = try await current.mealRecord(id: C11RealLifecycleTransportHarness.recordID)
            #expect(detail.data.recordID == "11111111-1111-4111-8111-111111111111")
            #expect(detail.meta.requestID == "c11-owner-fixture")
            let requests = await harness.stub.requests()
            #expect(requests.count == 1)
            #expect(requests.first?.httpMethod == "GET")
            #expect(requests.first?.url?.path == "/api/mobile/v1/meal-records/11111111-1111-4111-8111-111111111111")
        }
        let neighbor = try await owner.progress.progress()
        #expect(neighbor.meta.requestID == "progress-presentation-0001")
        #expect(!owner.isInvalidated)
        await owner.endSession()
        #expect(owner.mealRecordBinding == nil)
        #expect(!owner.hasRetainedCapabilities)
        if let current {
            await #expect(throws: CancellationError.self) {
                _ = try await current.mealRecord(id: C11RealLifecycleTransportHarness.recordID)
            }
            #expect(!current.hasRetainedCapability)
        }
        #expect(await harness.remote.refreshCount == 0)
    }

    @MainActor
    @Test("C11 H07 held: replacement works before its predecessor settles and concurrent owner ends join the hold",
          arguments: [C11OwnerRenewalHoldBoundary.beforeLease, .afterVisibleCommit])
    func c11OwnerRenewalHeldPredecessorAndConcurrentEnd(boundary: C11OwnerRenewalHoldBoundary) async throws {
        let harness = try await C11RealLifecycleTransportHarness()
        let original = try await harness.coordinator.leaseForRequest()
        let owner = Prompt14SessionOwner(userID: original.userID,
            dependencies: C11BindingTestDependencies.make(), enablesMealRecordBinding: true)
        await owner.awaitPatientTimeZoneResolution()
        let first = try #require(owner.mealRecordBinding)
        switch boundary {
        case .beforeLease: await harness.lifecycle.holdNextLease(completeEvenIfCancelled: true)
        case .afterVisibleCommit: await harness.lifecycle.holdNextVisibleReturn()
        }
        let oldBind = Task { try await first.bind(transport: harness.transport, lifecycle: harness.lifecycle) }
        do {
            switch boundary {
            case .beforeLease: await harness.lifecycle.leaseHold.waitUntilEntered()
            case .afterVisibleCommit: await harness.lifecycle.visibleReturnHold.waitUntilEntered()
            }
            let installed = first.capability
            if boundary == .afterVisibleCommit {
                _ = try #require(installed, "The REAL visible commit must exist before testing withdrawal")
            } else {
                #expect(installed == nil)
            }
            try await harness.respondWithMealDetail()
            let fresh = try #require(owner.reserveNewMealRecordBinding())
            #expect(fresh !== first)
            #expect(!first.isOpen)
            #expect(first.capability == nil && first.capturedLease == nil)
            #expect(!owner.isInvalidated)
            try await harness.coordinator.validate(original)
            if let installed {
                await #expect(throws: CancellationError.self) {
                    _ = try await installed.mealRecord(id: C11RealLifecycleTransportHarness.recordID)
                }
                #expect(!installed.hasRetainedCapability)
            }
            #expect(await harness.stub.requests().isEmpty)
            let current = await c11OwnerRenewalBindMustSucceed(fresh, harness: harness)
            if let current {
                let response = try await current.mealRecord(id: C11RealLifecycleTransportHarness.recordID)
                #expect(response.data.recordID == "11111111-1111-4111-8111-111111111111")
                #expect(await harness.stub.requests().count == 1)
            }
            let neighbor = try await owner.progress.progress()
            #expect(neighbor.meta.requestID == "progress-presentation-0001")
            let ends = C11ConcurrentEndProbe()
            let firstEnd = Task { @MainActor in
                ends.didStart(); await owner.endSession(); ends.didFinish()
            }
            let secondEnd = Task { @MainActor in
                ends.didStart(); await owner.endSession(); ends.didFinish()
            }
            await ends.waitForBothStarts()
            #expect(ends.finishedCount == 0,
                    "Owner teardown cannot finish while the retired bind is still in its actual lifecycle hold")
            #expect(owner.isInvalidated)
            #expect(owner.reserveNewMealRecordBinding() == nil)
            await c11OwnerRenewalReleaseHolds(harness)
            await #expect(throws: CancellationError.self) { _ = try await oldBind.value }
            await firstEnd.value
            await secondEnd.value
            #expect(ends.finishedCount == 2)
            #expect(owner.mealRecordBinding == nil)
            #expect(!owner.hasRetainedCapabilities)
            #expect(!first.isOpen && !fresh.isOpen)
            #expect(first.capability == nil && first.capturedLease == nil)
            #expect(fresh.capability == nil && fresh.capturedLease == nil)
            await owner.endSession() // Reentrant completed teardown remains terminal.
        } catch {
            owner.invalidateSynchronously()
            await c11OwnerRenewalReleaseHolds(harness)
            _ = try? await oldBind.value
            await owner.endSession()
            throw error
        }
    }

    @MainActor
    @Test("C11 H07 chain: ending the owner joins two outstanding predecessors, not only the newest retirement")
    func c11OwnerRenewalTwoOutstandingPredecessorsAreJoined() async throws {
        let harness = try await C11RealLifecycleTransportHarness()
        let original = try await harness.coordinator.leaseForRequest()
        let owner = Prompt14SessionOwner(userID: original.userID,
            dependencies: C11BindingTestDependencies.make(), enablesMealRecordBinding: true)
        await owner.awaitPatientTimeZoneResolution()
        let first = try #require(owner.mealRecordBinding)
        await harness.lifecycle.holdNextLease(completeEvenIfCancelled: true)
        let firstBind = Task { try await first.bind(transport: harness.transport, lifecycle: harness.lifecycle) }
        var middleBind: Task<MealRecordSessionCapability, any Error>?
        do {
            await harness.lifecycle.leaseHold.waitUntilEntered()
            let middle = try #require(owner.reserveNewMealRecordBinding())
            // This is a causal missing-renewal requirement, NOT a setup/type error.
            // It prevents waiting forever on a second hold if the baseline returned first.
            try #require(middle !== first,
                         "H07 causal: a second activation cannot reuse the already-started predecessor")
            await harness.lifecycle.holdNextVisibleReturn()
            let task = Task { try await middle.bind(transport: harness.transport, lifecycle: harness.lifecycle) }
            middleBind = task
            await harness.lifecycle.visibleReturnHold.waitUntilEntered()
            let installed = try #require(middle.capability)
            let newest = try #require(owner.reserveNewMealRecordBinding())
            try #require(newest !== middle)
            #expect(!first.isOpen && !middle.isOpen)
            #expect(!installed.hasRetainedCapability)
            #expect(owner.mealRecordBinding === newest && newest.isOpen)
            let neighbor = try await owner.progress.progress()
            #expect(neighbor.meta.requestID == "progress-presentation-0001")
            let ends = C11ConcurrentEndProbe()
            let end1 = Task { @MainActor in ends.didStart(); await owner.endSession(); ends.didFinish() }
            let end2 = Task { @MainActor in ends.didStart(); await owner.endSession(); ends.didFinish() }
            await ends.waitForBothStarts()
            #expect(ends.finishedCount == 0)
            #expect(owner.reserveNewMealRecordBinding() == nil)
            // The newer predecessor completes; the older resolver still ignores cancellation.
            await harness.lifecycle.visibleReturnHold.release()
            await #expect(throws: CancellationError.self) { _ = try await task.value }
            #expect(ends.finishedCount == 0)
            await harness.lifecycle.leaseHold.release()
            await #expect(throws: CancellationError.self) { _ = try await firstBind.value }
            await end1.value
            await end2.value
            #expect(ends.finishedCount == 2)
            #expect(!owner.hasRetainedCapabilities)
            #expect(owner.mealRecordBinding == nil)
            #expect(first.capability == nil && middle.capability == nil && newest.capability == nil)
            #expect(first.capturedLease == nil && middle.capturedLease == nil && newest.capturedLease == nil)
            #expect(await harness.stub.requests().isEmpty)
        } catch {
            owner.invalidateSynchronously()
            await c11OwnerRenewalReleaseHolds(harness)
            _ = try? await firstBind.value
            if let middleBind { _ = try? await middleBind.value }
            await owner.endSession()
            throw error
        }
    }


    @MainActor
    @Test("C11 H02: original pending A1 cannot publish or remove A2 after A-B-A",
          arguments: [C11RootOldCompletion.normal, .cancelledCaller])
    func c11H02OriginalPendingBindingCannotEraseA2(boundary: C11RootOldCompletion) async throws {
        let fixture = try await C11RootBindingFixture.make()
        await fixture.wire.lifecycle.holdNextLease(completeEvenIfCancelled: true)
        var first: Task<MealRecordReadyContext?, any Error>? = nil
        do {
            let original = try #require(fixture.coordinator.beginBinding(
                activation: fixture.activation, owner: fixture.owner))
            let completion = Task { try await fixture.coordinator.completeBinding(original) }
            first = completion
            let originalBinding = try #require(fixture.owner.mealRecordBinding)
            await fixture.wire.lifecycle.leaseHold.waitUntilEntered()
            #expect(fixture.coordinator.readyContext == nil)
            #expect(originalBinding.capability == nil)
            #expect(await fixture.countedLifecycle.leaseCalls == 1)
            #expect(await fixture.wire.stub.requests().isEmpty)
            await C11AuthenticationFixtures.cycleThroughBAndBackToA(
                model: fixture.model, peer: fixture.authentication)
            let current = try #require(fixture.model.mealRecordActivation)
            #expect(current.ticket != fixture.activation.ticket)
            #expect(!originalBinding.isOpen)
            #expect(originalBinding.capability == nil)
            #expect(originalBinding.capturedLease == nil)
            #expect(!fixture.owner.isInvalidated)
            let second = try #require(fixture.coordinator.beginBinding(
                activation: current, owner: fixture.owner))
            let currentBinding = try #require(fixture.owner.mealRecordBinding)
            #expect(currentBinding !== originalBinding)
            let ready = try #require(try await fixture.coordinator.completeBinding(second))
            #expect(ready.activation == current)
            #expect(ready.isActive)
            #expect(fixture.coordinator.readyContext === ready)
            #expect(await fixture.countedLifecycle.leaseCalls == 2)
            #expect(await fixture.wire.stub.requests().isEmpty)
            #expect(fixture.coordinator.beginBinding(activation: fixture.activation, owner: fixture.owner) == nil)
            #expect(fixture.coordinator.readyContext === ready)
            #expect(await fixture.countedLifecycle.leaseCalls == 2)
            if boundary == .cancelledCaller { completion.cancel() }
            await fixture.wire.lifecycle.leaseHold.release()
            let oldResult = await completion.result
            switch oldResult {
            case .success: Issue.record("Original A1 completion must be terminal")
            case .failure(let error): #expect(error is CancellationError)
            }
            #expect(fixture.coordinator.readyContext === ready)
            #expect(ready.isActive)
            #expect(fixture.lifetime.currentActivation == current)
            #expect(originalBinding.capability == nil)
            #expect(originalBinding.capturedLease == nil)
            #expect(await fixture.wire.stub.requests().isEmpty)
            let detail = try await ready.capability.mealRecord(id: C11RealLifecycleTransportHarness.recordID)
            #expect(detail.data.recordID == C11RealLifecycleTransportHarness.recordID)
            #expect(await fixture.wire.stub.requests().count == 1)
            #expect(await fixture.countedLifecycle.leaseCalls == 2)
            #expect(try await fixture.owner.progress.progress() == BodyFlowTestFixtures.progressResponse)
            await fixture.end()
        } catch {
            await fixture.wire.lifecycle.leaseHold.release()
            _ = await first?.result
            await fixture.end()
            throw error
        }
    }

    @MainActor
    @Test("C11 H02: duplicate pending and ready admission share one operation, lease and context")
    func c11H02DuplicateAdmissionCoalescesOneLease() async throws {
        let fixture = try await C11RootBindingFixture.make()
        await fixture.wire.lifecycle.holdNextLease(completeEvenIfCancelled: true)
        do {
            let first = try #require(fixture.coordinator.beginBinding(
                activation: fixture.activation, owner: fixture.owner))
            await fixture.wire.lifecycle.leaseHold.waitUntilEntered()
            let duplicate = try #require(fixture.coordinator.beginBinding(
                activation: fixture.activation, owner: fixture.owner))
            #expect(duplicate === first)
            #expect(fixture.coordinator.readyContext == nil)
            #expect(await fixture.countedLifecycle.leaseCalls == 1)
            let completion1 = Task { try await fixture.coordinator.completeBinding(first) }
            let completion2 = Task { try await fixture.coordinator.completeBinding(duplicate) }
            await fixture.wire.lifecycle.leaseHold.release()
            let result1 = await completion1.result
            let result2 = await completion2.result
            let ready1 = try #require(try result1.get())
            let ready2 = try #require(try result2.get())
            #expect(ready1 === ready2)
            #expect(ready1.isActive)
            #expect(fixture.coordinator.readyContext === ready1)
            let alreadyReady = try #require(fixture.coordinator.beginBinding(
                activation: fixture.activation, owner: fixture.owner))
            #expect(alreadyReady === first)
            #expect(try await fixture.coordinator.completeBinding(alreadyReady) === ready1)
            #expect(await fixture.countedLifecycle.leaseCalls == 1)
            #expect(await fixture.wire.stub.requests().isEmpty)
            await fixture.end()
        } catch {
            await fixture.wire.lifecycle.leaseHold.release()
            await fixture.end()
            throw error
        }
    }

    @MainActor
    @Test("C11 Root source/owner OFF stays neutral without a lease or meal request",
          arguments: [C11RootOffSource.source, .owner])
    func c11H02OffAndConstructionDoNotStartMeals(off: C11RootOffSource) async throws {
        let fixture = try await C11RootBindingFixture.make(
            sourceEnabled: off != .source, ownerEnabled: off != .owner)
        #expect(await fixture.countedLifecycle.leaseCalls == 0)
        #expect(await fixture.wire.stub.requests().isEmpty)
        let originalBinding = fixture.owner.mealRecordBinding
        #expect(fixture.coordinator.readyContext == nil)
        #expect(fixture.coordinator.beginBinding(activation: fixture.activation, owner: fixture.owner) == nil)
        #expect(fixture.coordinator.readyContext == nil)
        #expect(fixture.owner.mealRecordBinding === originalBinding)
        #expect(await fixture.countedLifecycle.leaseCalls == 0)
        #expect(await fixture.wire.stub.requests().isEmpty)
        #expect(!fixture.owner.isInvalidated)
        await fixture.end()
    }

    @MainActor
    @Test("C11 context denies access at pre-auth close while model and Root have not redrawn")
    func c11H02ContextClosesBeforeRootRedraw() async throws {
        let fixture = try await C11RootBindingFixture.make()
        var signOut: Task<Void, Never>? = nil
        do {
            let operation = try #require(fixture.coordinator.beginBinding(
                activation: fixture.activation, owner: fixture.owner))
            let ready = try #require(try await fixture.coordinator.completeBinding(operation))
            let binding = try #require(fixture.owner.mealRecordBinding)
            let lease = try #require(binding.capturedLease)
            #expect(ready.isActive)
            await fixture.authentication.holdNextEntry(.signOut)
            signOut = Task { await fixture.model.signOut() }
            await fixture.authentication.entryHold.waitUntilEntered()
            #expect(fixture.model.state == .authenticated(userID: C11AuthenticationFixtures.a))
            #expect(!fixture.owner.isInvalidated)
            #expect(!ready.isActive)
            #expect(fixture.coordinator.readyContext == nil)
            #expect(fixture.model.mealRecordActivation == nil)
            // Parent A1 is still a real valid session: denial comes from C11 pre-close.
            try await fixture.wire.coordinator.validate(lease)
            await #expect(throws: CancellationError.self) {
                _ = try await ready.capability.mealRecord(id: C11RealLifecycleTransportHarness.recordID)
            }
            #expect(await fixture.wire.stub.requests().isEmpty)
            #expect(await fixture.countedLifecycle.leaseCalls == 1)
            await fixture.authentication.entryHold.release()
            await signOut?.value
            await fixture.end()
        } catch {
            await fixture.authentication.entryHold.release()
            await signOut?.value
            await fixture.end()
            throw error
        }
    }

    @MainActor
    @Test("C11 Root rejects stale projection, owner and closed owner before lease",
          arguments: [C11RootRejectedAdmission.staleTicket, .wrongOwner, .closedOwner, .missingProjection])
    func c11H02RejectedAdmissionHasNoLease(reason: C11RootRejectedAdmission) async throws {
        let fixture = try await C11RootBindingFixture.make()
        let wrongOwner = Prompt14SessionOwner(userID: C11AuthenticationFixtures.b,
            dependencies: C11BindingTestDependencies.make(), enablesMealRecordBinding: true)
        await wrongOwner.awaitPatientTimeZoneResolution()
        switch reason {
        case .staleTicket:
            _ = fixture.lifetime.beginAuthenticationBoundary()
        case .wrongOwner: break
        case .closedOwner: fixture.owner.invalidateSynchronously()
        case .missingProjection:
            fixture.lifetime.withdrawVisibleActivation(ticket: fixture.activation.ticket)
        }
        let owner = reason == .wrongOwner ? wrongOwner : fixture.owner
        #expect(fixture.coordinator.beginBinding(activation: fixture.activation, owner: owner) == nil)
        #expect(fixture.coordinator.readyContext == nil)
        #expect(await fixture.countedLifecycle.leaseCalls == 0)
        #expect(await fixture.wire.stub.requests().isEmpty)
        await fixture.end()
        await wrongOwner.endSession()
    }

    @MainActor
    @Test("C11 Root never accepts missing or mismatched actual lease",
          arguments: [C11RootLeaseFailure.missing, .wrongUser])
    func c11H02ActualLeaseFailureStaysNeutral(failure: C11RootLeaseFailure) async throws {
        let fixture = try await C11RootBindingFixture.make()
        do {
            if failure == .missing {
                _ = await fixture.wire.coordinator.signOut()
            } else {
                try await fixture.wire.coordinator.switch(to:
                    C11RealLifecycleTransportHarness.record(userID: C11AuthenticationFixtures.b, ordinal: 2))
            }
            // The visible model still presents A; only real lease validation rejects this.
            #expect(fixture.model.mealRecordActivation == fixture.activation)
            let operation = try #require(fixture.coordinator.beginBinding(
                activation: fixture.activation, owner: fixture.owner))
            let expected: SessionLifecycleError = failure == .missing ? .missingSession : .sessionSuperseded
            await #expect(throws: expected) { _ = try await fixture.coordinator.completeBinding(operation) }
            #expect(fixture.coordinator.readyContext == nil)
            #expect(fixture.owner.mealRecordBinding?.capability == nil)
            #expect(fixture.owner.mealRecordBinding?.capturedLease == nil)
            #expect(fixture.owner.mealRecordBinding?.isOpen == false)
            #expect(await fixture.countedLifecycle.leaseCalls == 1)
            #expect(await fixture.wire.stub.requests().isEmpty)
            await fixture.end()
        } catch {
            await fixture.end()
            throw error
        }
    }

    @MainActor
    @Test("C11 Root: cancellation before complete closes the already-started original reservation")
    func c11H02CancellationBeforeCompleteClosesOriginal() async throws {
        let fixture = try await C11RootBindingFixture.make()
        do {
            let originalLease = try await fixture.wire.coordinator.leaseForRequest()
            await fixture.wire.lifecycle.holdNextLease(completeEvenIfCancelled: true)
            let operation = try #require(fixture.coordinator.beginBinding(
                activation: fixture.activation, owner: fixture.owner))
            await fixture.wire.lifecycle.leaseHold.waitUntilEntered()
            let binding = try #require(fixture.owner.mealRecordBinding)
            #expect(binding.isOpen)
            let completion = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await fixture.coordinator.completeBinding(operation)
            }
            let result = await completion.result
            switch result {
            case .success: Issue.record("A caller cancelled before entry must not receive a context")
            case .failure(let error): #expect(error is CancellationError)
            }
            // Resolver is still held and original A1 remains valid; cleanup is synchronous.
            try await fixture.wire.coordinator.validate(originalLease)
            #expect(fixture.lifetime.currentActivation == fixture.activation)
            #expect(!fixture.owner.isInvalidated)
            #expect(!binding.isOpen)
            #expect(binding.capability == nil)
            #expect(binding.capturedLease == nil)
            #expect(fixture.coordinator.readyContext == nil)
            #expect(await fixture.wire.stub.requests().isEmpty)
            await fixture.wire.lifecycle.leaseHold.release()
            await fixture.end()
            #expect(binding.capability == nil)
            #expect(binding.capturedLease == nil)
            #expect(await fixture.countedLifecycle.leaseCalls == 1)
            #expect(await fixture.wire.stub.requests().isEmpty)
        } catch {
            await fixture.wire.lifecycle.leaseHold.release()
            await fixture.end()
            throw error
        }
    }

    @MainActor
    @Test("C11 Root projection closes context for late core signed-out while A2 authority stays valid")
    func c11H02ActualModelProjectionGuardsContextWithoutRedraw() async throws {
        let fixture = try await C11RootBindingFixture.make()
        await fixture.authentication.holdNextEntry(.start,
            forcedRestore: C11AuthenticationFixtures.lateReturn(.missing))
        let oldRestore = Task { await fixture.model.start() }
        do {
            await fixture.authentication.entryHold.waitUntilEntered()
            await C11AuthenticationFixtures.cycleThroughBAndBackToA(
                model: fixture.model, peer: fixture.authentication)
            let current = try #require(fixture.model.mealRecordActivation)
            let operation = try #require(fixture.coordinator.beginBinding(
                activation: current, owner: fixture.owner))
            let ready = try #require(try await fixture.coordinator.completeBinding(operation))
            let binding = try #require(fixture.owner.mealRecordBinding)
            let lease = try #require(binding.capturedLease)
            #expect(ready.isActive)
            await fixture.authentication.entryHold.release()
            await oldRestore.value
            #expect(fixture.model.state == .signedOut(.signIn))
            #expect(fixture.model.mealRecordActivation == nil)
            #expect(fixture.lifetime.currentActivation == current)
            #expect(fixture.lifetime.isCurrent(current.ticket))
            #expect(!fixture.owner.isInvalidated)
            #expect(binding.isOpen)
            #expect(binding.capability === ready.capability)
            #expect(ready.capability.hasRetainedCapability)
            try await fixture.wire.coordinator.validate(lease)
            // No Root transition or redraw has happened since the old terminal.
            #expect(!ready.isActive)
            #expect(fixture.coordinator.readyContext == nil)
            #expect(fixture.coordinator.beginBinding(activation: current, owner: fixture.owner) == nil)
            #expect(await fixture.countedLifecycle.leaseCalls == 1)
            #expect(await fixture.wire.stub.requests().isEmpty)
            await fixture.end()
        } catch {
            await fixture.authentication.entryHold.release()
            await oldRestore.value
            await fixture.end()
            throw error
        }
    }

    @MainActor
    @Test("C11 Root rejects another live owner of the same user before retiring the current grant")
    func c11H02ForeignSameUserOwnerPreservesCurrentGrant() async throws {
        let fixture = try await C11RootBindingFixture.make()
        let foreignOwner = Prompt14SessionOwner(userID: C11AuthenticationFixtures.a,
            dependencies: C11BindingTestDependencies.make(), enablesMealRecordBinding: true)
        await foreignOwner.awaitPatientTimeZoneResolution()
        do {
            let operation = try #require(fixture.coordinator.beginBinding(
                activation: fixture.activation, owner: fixture.owner))
            let ready = try #require(try await fixture.coordinator.completeBinding(operation))
            let binding = try #require(fixture.owner.mealRecordBinding)
            let lease = try #require(binding.capturedLease)
            #expect(ready.isActive)
            #expect(fixture.coordinator.readyContext === ready)
            #expect(foreignOwner !== fixture.owner)
            #expect(foreignOwner.userID == fixture.activation.userID)
            #expect(!foreignOwner.isInvalidated)
            #expect(await fixture.countedLifecycle.leaseCalls == 1)
            #expect(await fixture.wire.stub.requests().isEmpty)
            let foreignBinding = foreignOwner.mealRecordBinding
            #expect(fixture.coordinator.beginBinding(activation: fixture.activation, owner: foreignOwner) == nil)
            #expect(foreignOwner.mealRecordBinding === foreignBinding)
            #expect(fixture.owner.mealRecordBinding === binding)
            #expect(binding.isOpen)
            #expect(binding.capability === ready.capability)
            #expect(binding.capturedLease == lease)
            #expect(ready.capability.hasRetainedCapability)
            #expect(ready.isActive)
            #expect(fixture.coordinator.readyContext === ready)
            #expect(fixture.lifetime.currentActivation == fixture.activation)
            #expect(!fixture.owner.isInvalidated)
            #expect(!foreignOwner.isInvalidated)
            #expect(await fixture.countedLifecycle.leaseCalls == 1)
            #expect(await fixture.wire.stub.requests().isEmpty)
            try await fixture.wire.coordinator.validate(lease)
            let detail = try await ready.capability.mealRecord(id: C11RealLifecycleTransportHarness.recordID)
            #expect(detail.data.recordID == C11RealLifecycleTransportHarness.recordID)
            #expect(await fixture.wire.stub.requests().count == 1)
            #expect(await fixture.countedLifecycle.leaseCalls == 1)
            // The single request is the accepted original grant; foreign admission made none.
            #expect(fixture.coordinator.beginBinding(activation: fixture.activation, owner: fixture.owner) === operation)
            #expect(await fixture.countedLifecycle.leaseCalls == 1)
            await foreignOwner.endSession()
            await fixture.end()
        } catch {
            await foreignOwner.endSession()
            await fixture.end()
            throw error
        }
    }



    @MainActor
    @Test("C11 H05: real local marker failure preserves authentication and closes only the original meal grant")
    func c11H05RealMarkerFailureClosesOldGrant() async throws {
        let f = try await C11H05Fixture.make()
        do {
            let session = f.model.currentSession
            let original = f.originalContext.activation
            let calls = await f.runtime.counted.leaseCalls
            await f.failLogout()
            #expect(f.model.state == .authenticated(userID: original.userID))
            #expect(f.model.currentSession == session)
            #expect(f.model.presentationError == .storageUnavailable)
            #expect(f.model.authOperationState == .failed(.storageUnavailable))
            #expect(await f.runtime.store.currentRecord() == f.runtime.original)
            try await f.runtime.session.validate(f.runtime.originalLease)
            #expect(!f.originalContext.isActive)
            #expect(!f.originalContext.capability.hasRetainedCapability)
            #expect(f.model.mealRecordActivation == nil)
            #expect(!f.model.isMealRecordAuthenticationBusy)
            let offer = try #require(f.model.availableMealRecordRecoveryOffer)
            #expect(offer.session == session)
            #expect(offer.anchorTicket != original.ticket)
            #expect(f.tickets.issued.count == 2)
            #expect(await f.runtime.counted.leaseCalls == calls)
            #expect(await f.runtime.remote.counts() == [0, 0, 0, 0, 0])
            #expect(await f.runtime.stub.requests().isEmpty)
            let neighbor = try await f.owner.progress.progress()
            #expect(neighbor.meta.requestID == "progress-presentation-0001")
            await f.end()
        } catch { await f.end(); throw error }
    }

    @MainActor
    @Test("C11 H05: remote-unconfirmed with local success is signed out and never offers recovery")
    func c11H05RemoteUnconfirmedCannotRecover() async throws {
        let f = try await C11H05Fixture.make()
        await f.runtime.remote.setRevocation(.unconfirmed)
        await f.model.signOut()
        #expect(f.model.state == .signedOut(.signIn))
        #expect(f.model.currentSession == nil)
        #expect(f.model.availableMealRecordRecoveryOffer == nil)
        #expect(f.model.mealRecordActivation == nil)
        #expect(!f.model.isMealRecordAuthenticationBusy)
        #expect(await f.runtime.remote.counts() == [0, 0, 0, 0, 1])
        await #expect(throws: SessionLifecycleError.missingSession) {
            try await f.runtime.session.validate(f.runtime.originalLease)
        }
        #expect(await f.runtime.stub.requests().isEmpty)
        await f.end()
    }

    @MainActor
    @Test("C11 H05: one explicit action grants a new ticket and leaf, double tap adds no lease or auth")
    func c11H05ExplicitRecoveryAndDoubleTap() async throws {
        let f = try await C11H05Fixture.make()
        do {
            await f.failLogout()
            let offer = try #require(f.model.availableMealRecordRecoveryOffer)
            let core = C11AuthenticationCoreSnapshot(f.model)
            let telemetry = await f.telemetry.snapshot()
            let calls = await f.runtime.counted.leaseCalls
            let oldBinding = try #require(f.owner.mealRecordBinding)
            let recovery = try #require(f.model.beginMealRecordRecovery(offer: offer))
            #expect(recovery.ticket != offer.anchorTicket)
            #expect(f.model.isMealRecordRecoveryInProgress)
            #expect(f.model.beginMealRecordRecovery(offer: offer) == nil)
            #expect(f.tickets.issued.count == 3)
            let operation = try #require(f.root.beginBinding(activation: recovery, owner: f.owner))
            #expect(f.owner.mealRecordBinding !== oldBinding)
            let current = try #require(try await f.root.completeBinding(operation))
            f.model.finishMealRecordRecovery(recovery, succeeded: true)
            #expect(!f.model.isMealRecordRecoveryInProgress)
            #expect(f.model.availableMealRecordRecoveryOffer == nil)
            #expect(current.isActive)
            #expect(f.root.readyContext === current)
            #expect(await f.runtime.counted.leaseCalls == calls + 1)
            #expect(await f.runtime.stub.requests().isEmpty)
            await #expect(throws: CancellationError.self) {
                _ = try await f.originalContext.capability.mealRecord(id: C11RealLifecycleTransportHarness.recordID)
            }
            #expect(await f.runtime.stub.requests().isEmpty)
            let detail = try await current.capability.mealRecord(id: C11RealLifecycleTransportHarness.recordID)
            #expect(detail.meta.requestID == "c11-owner-fixture")
            #expect(detail.data.recordID == C11RealLifecycleTransportHarness.recordID)
            #expect(await f.runtime.stub.requests().count == 1)
            #expect(C11AuthenticationCoreSnapshot(f.model) == core)
            #expect(await f.telemetry.snapshot() == telemetry)
            #expect(await f.runtime.authentication.entries == [.start, .signOut])
            #expect(await f.runtime.remote.counts() == [0, 0, 0, 0, 0])
            await f.end()
        } catch { await f.end(); throw error }
    }

    @MainActor
    @Test("C11 H05: each admitted auth boundary blocks recovery while it is actually held",
          arguments: [C11AuthenticationEntry.start, .signOut, .signIn, .signUp, .confirmDevelopment])
    func c11H05AcceptedAuthIsBusy(entry: C11AuthenticationEntry) async throws {
        let f = try await C11H05Fixture.make()
        await f.failLogout()
        let held = C11BoundaryHold()
        await f.runtime.authentication.hold(entry, using: held)
        let work = Task { await C11AuthenticationFixtures.invoke(entry, model: f.model) }
        do {
            await held.waitUntilEntered()
            #expect(f.model.isMealRecordAuthenticationBusy)
            #expect(f.model.availableMealRecordRecoveryOffer == nil)
            let tickets = f.tickets.issued.count
            let calls = await f.runtime.counted.leaseCalls
            let session = try #require(f.model.currentSession)
            let fabricated = MealRecordRecoveryOffer(anchorTicket: try #require(f.tickets.issued.last), session: session)
            #expect(f.model.beginMealRecordRecovery(offer: fabricated) == nil)
            #expect(f.tickets.issued.count == tickets)
            #expect(await f.runtime.counted.leaseCalls == calls)
            await held.release()
            await work.value
            #expect(!f.model.isMealRecordAuthenticationBusy)
            #expect(await f.runtime.stub.requests().isEmpty)
            await f.end()
        } catch {
            await held.release(); await work.value; await f.end(); throw error
        }
    }

    @MainActor
    @Test("C11 H05: overlapping start/logout release only their own pending identities",
          arguments: [C11H05ReleaseOrder.olderFirst, .newerFirst])
    func c11H05OverlappingAuthIsScoped(order: C11H05ReleaseOrder) async throws {
        let f = try await C11H05Fixture.make()
        await f.failLogout()
        let older = C11BoundaryHold(), newer = C11BoundaryHold()
        await f.runtime.authentication.hold(.start, using: older)
        let first = Task { await f.model.start() }
        await older.waitUntilEntered()
        await f.runtime.authentication.hold(.signOut, using: newer)
        let second = Task { await f.model.signOut() }
        do {
            await newer.waitUntilEntered()
            #expect(f.model.isMealRecordAuthenticationBusy)
            if order == .olderFirst { await older.release(); await first.value }
            else { await newer.release(); await second.value }
            #expect(f.model.isMealRecordAuthenticationBusy)
            #expect(f.model.availableMealRecordRecoveryOffer == nil)
            let count = f.tickets.issued.count
            let candidate = MealRecordRecoveryOffer(anchorTicket: try #require(f.tickets.issued.last),
                session: try #require(f.model.currentSession))
            #expect(f.model.beginMealRecordRecovery(offer: candidate) == nil)
            #expect(f.tickets.issued.count == count)
            await older.release(); await newer.release()
            await first.value; await second.value
            #expect(!f.model.isMealRecordAuthenticationBusy)
            let offer = try #require(f.model.availableMealRecordRecoveryOffer)
            #expect(offer.anchorTicket == f.tickets.issued.last)
            #expect(f.tickets.issued.count == 4)
            #expect(await f.runtime.counted.leaseCalls == 1)
            #expect(await f.runtime.stub.requests().isEmpty)
            await f.end()
        } catch {
            await older.release(); await newer.release()
            await first.value; await second.value; await f.end(); throw error
        }
    }

    @MainActor
    @Test("C11 H05: password recovery is busy-only and remains scoped after a late start/logout")
    func c11H05PasswordRecoveryHasNoAuthority() async throws {
        let f = try await C11H05Fixture.make()
        let firstPW = C11BoundaryHold()
        await f.runtime.authentication.hold(.passwordRecovery, using: firstPW)
        let initial = Task { await f.model.requestPasswordRecovery(email: C11AuthenticationFixtures.email) }
        do {
            await firstPW.waitUntilEntered()
            #expect(f.model.isMealRecordAuthenticationBusy)
            #expect(f.originalContext.isActive)
            #expect(f.originalContext.capability.hasRetainedCapability)
            #expect(f.tickets.issued.count == 1)
            await firstPW.release(); await initial.value
            #expect(!f.model.isMealRecordAuthenticationBusy)
            #expect(f.model.authOperationState == .recoveryConfirmation)
            await f.failLogout()
            let authHold = C11BoundaryHold(), pwHold = C11BoundaryHold()
            await f.runtime.authentication.hold(.start, using: authHold)
            let auth = Task { await f.model.start() }
            await authHold.waitUntilEntered()
            await f.runtime.authentication.hold(.passwordRecovery, using: pwHold)
            let pw = Task { await f.model.requestPasswordRecovery(email: C11AuthenticationFixtures.email) }
            do {
                await pwHold.waitUntilEntered()
                await f.model.signOut() // Real marker failure sets .failed while PW is still held.
                await authHold.release(); await auth.value
                #expect(f.model.authOperationState == .failed(.storageUnavailable))
                #expect(f.model.isMealRecordAuthenticationBusy)
                #expect(f.model.availableMealRecordRecoveryOffer == nil)
                let count = f.tickets.issued.count
                #expect(count == 4)
                let candidate = MealRecordRecoveryOffer(anchorTicket: try #require(f.tickets.issued.last),
                    session: try #require(f.model.currentSession))
                #expect(f.model.beginMealRecordRecovery(offer: candidate) == nil)
                #expect(f.tickets.issued.count == count)
                await pwHold.release(); await pw.value
                #expect(!f.model.isMealRecordAuthenticationBusy)
                #expect(f.model.authOperationState == .recoveryConfirmation)
                #expect(f.model.availableMealRecordRecoveryOffer != nil)
                #expect(f.tickets.issued.count == count)
                #expect(await f.runtime.remote.counts() == [0, 0, 2, 0, 0])
                #expect(await f.runtime.stub.requests().isEmpty)
            } catch {
                await authHold.release(); await pwHold.release()
                await auth.value; await pw.value; throw error
            }
            await f.end()
        } catch { await firstPW.release(); await initial.value; await f.end(); throw error }
    }

    @MainActor
    @Test("C11 H05: a real missing/wrong-account lease never installs recovery",
          arguments: [C11RootLeaseFailure.missing, .wrongUser])
    func c11H05RealLeaseFailureStaysNeutral(reason: C11RootLeaseFailure) async throws {
        let f = try await C11H05Fixture.make()
        do {
            await f.failLogout()
            let offer = try #require(f.model.availableMealRecordRecoveryOffer)
            let core = C11AuthenticationCoreSnapshot(f.model)
            if reason == .missing {
                await f.runtime.secure.rejectMarker(false)
                #expect(await f.runtime.session.signOut() == .confirmed)
            } else {
                try await f.runtime.session.switch(to: C11RealLifecycleTransportHarness.record(
                    userID: C11AuthenticationFixtures.b, ordinal: 2))
            }
            let activation = try #require(f.model.beginMealRecordRecovery(offer: offer))
            let operation = try #require(f.root.beginBinding(activation: activation, owner: f.owner))
            let expected = reason == .missing ? SessionLifecycleError.missingSession : .sessionSuperseded
            await #expect(throws: expected) { _ = try await f.root.completeBinding(operation) }
            f.model.finishMealRecordRecovery(activation, succeeded: false)
            #expect(f.root.readyContext == nil)
            #expect(f.model.mealRecordActivation == nil)
            #expect(!f.model.isMealRecordRecoveryInProgress)
            #expect(f.owner.mealRecordBinding?.isOpen == false)
            #expect(await f.runtime.counted.leaseCalls == 2)
            #expect(await f.runtime.stub.requests().isEmpty)
            #expect(C11AuthenticationCoreSnapshot(f.model) == core)
            await f.end()
        } catch { await f.end(); throw error }
    }

    @MainActor
    @Test("C11 H05: cancellation/late ABA finishes only the original recovery",
          arguments: [C11H05RecoveryTerminal.callerCancelled, .lateABA])
    func c11H05RecoveryTerminalIsScoped(terminal: C11H05RecoveryTerminal) async throws {
        let f = try await C11H05Fixture.make()
        await f.failLogout()
        var oldCaller: Task<MealRecordReadyContext?, any Error>?
        var newCaller: Task<MealRecordReadyContext?, any Error>?
        do {
            let offer = try #require(f.model.availableMealRecordRecoveryOffer)
            let old = try #require(f.model.beginMealRecordRecovery(offer: offer))
            await f.runtime.lifecycle.holdNextLease(completeEvenIfCancelled: true)
            let operation = try #require(f.root.beginBinding(activation: old, owner: f.owner))
            await f.runtime.lifecycle.leaseHold.waitUntilEntered()
            if terminal == .callerCancelled {
                let caller = Task {
                    withUnsafeCurrentTask { $0?.cancel() }
                    return try await f.root.completeBinding(operation)
                }
                oldCaller = caller
                await #expect(throws: CancellationError.self) { _ = try await caller.value }
                f.model.finishMealRecordRecovery(old, succeeded: false)
                #expect(!f.model.isMealRecordRecoveryInProgress)
                #expect(f.model.mealRecordActivation == nil)
                #expect(f.owner.mealRecordBinding?.isOpen == false)
                #expect(f.model.availableMealRecordRecoveryOffer != nil)
                #expect(f.tickets.issued.count == 3)
                try await f.runtime.session.validate(f.runtime.originalLease)
                await f.runtime.lifecycle.leaseHold.release()
            } else {
                let caller = Task { try await f.root.completeBinding(operation) }
                oldCaller = caller
                await f.runtime.remote.setSignIns([
                    C11RealLifecycleTransportHarness.record(userID: C11AuthenticationFixtures.b, ordinal: 2),
                    C11RealLifecycleTransportHarness.record(userID: C11AuthenticationFixtures.a, ordinal: 3)
                ])
                await f.model.signIn(email: C11AuthenticationFixtures.email, password: C11AuthenticationFixtures.syntheticPassword)
                await f.model.signIn(email: C11AuthenticationFixtures.email, password: C11AuthenticationFixtures.syntheticPassword)
                await f.model.signOut() // Actual marker failure under A2.
                let nextOffer = try #require(f.model.availableMealRecordRecoveryOffer)
                let next = try #require(f.model.beginMealRecordRecovery(offer: nextOffer))
                #expect(next.ticket != old.ticket)
                await f.runtime.lifecycle.holdNextVisibleReturn()
                let nextOperation = try #require(f.root.beginBinding(activation: next, owner: f.owner))
                let nextCaller = Task { try await f.root.completeBinding(nextOperation) }
                newCaller = nextCaller
                await f.runtime.lifecycle.visibleReturnHold.waitUntilEntered()
                await f.runtime.lifecycle.leaseHold.release()
                await #expect(throws: CancellationError.self) { _ = try await caller.value }
                f.model.finishMealRecordRecovery(old, succeeded: false)
                #expect(f.model.isMealRecordRecoveryInProgress)
                #expect(f.model.mealRecordActivation == next)
                #expect(f.lifetime.currentActivation == next)
                #expect(f.model.beginMealRecordRecovery(offer: offer) == nil)
                await f.runtime.lifecycle.visibleReturnHold.release()
                let ready = try #require(try await nextCaller.value)
                f.model.finishMealRecordRecovery(next, succeeded: true)
                #expect(ready.isActive)
                #expect(f.root.readyContext === ready)
                #expect(!f.model.isMealRecordRecoveryInProgress)
                #expect(f.model.availableMealRecordRecoveryOffer == nil)
                #expect(await f.runtime.counted.leaseCalls == 3)
                #expect(await f.runtime.remote.counts() == [2, 0, 0, 0, 0])
            }
            #expect(await f.runtime.stub.requests().isEmpty)
            await f.end()
        } catch {
            await f.runtime.releaseAll()
            if let oldCaller { _ = try? await oldCaller.value }
            if let newCaller { _ = try? await newCaller.value }
            await f.end(); throw error
        }
    }

    @MainActor
    @Test("C11 H05: nonlocal errors, absent lifetime and incomplete onboarding cannot offer recovery",
          arguments: [C11H05NoOffer.serviceUnavailable, .defaultNil, .incomplete])
    func c11H05IneligibleSessionHasNoOffer(reason: C11H05NoOffer) async throws {
        let runtime = try await C11H05Runtime()
        let tickets = C11AuthenticationTicketFactorySpy()
        let lifetime = MealRecordAuthenticationLifetime(ticketFactory: { tickets.next() })
        let model = AppFlowModel(authentication: runtime.authentication,
            onboarding: C11AuthenticationOnboardingPeer(completed: reason != .incomplete),
            persona: AppDependencies.scaffold().coachPersona, telemetry: InMemoryTelemetryClient(),
            mealRecordAuthenticationLifetime: reason == .defaultNil ? nil : lifetime)
        await model.start()
        if reason == .serviceUnavailable { await runtime.authentication.forceNextLogoutError(.serviceUnavailable) }
        else { await runtime.secure.rejectMarker() }
        await model.signOut()
        #expect(model.availableMealRecordRecoveryOffer == nil)
        #expect(model.mealRecordActivation == nil)
        #expect(!model.isMealRecordAuthenticationBusy)
        #expect(!model.isMealRecordRecoveryInProgress)
        #expect(await runtime.counted.leaseCalls == 0)
        #expect(await runtime.stub.requests().isEmpty)
        #expect(await runtime.remote.counts() == [0, 0, 0, 0, 0])
        #expect(tickets.issued.count == (reason == .defaultNil ? 0 : 2))
        await lifetime.endSession()
    }

    @MainActor
    @Test("C11 H05: rejected sign-in/sign-up/confirm/password operations add no activity",
          arguments: [C11AuthenticationEntry.signIn, .signUp, .confirmDevelopment, .passwordRecovery])
    func c11H05RejectedAuthAddsNoActivity(entry: C11AuthenticationEntry) async throws {
        let f = try await C11H05Fixture.make()
        let hold = C11BoundaryHold()
        await f.runtime.authentication.hold(.passwordRecovery, using: hold)
        let pw = Task { await f.model.requestPasswordRecovery(email: C11AuthenticationFixtures.email) }
        await hold.waitUntilEntered()
        #expect(f.model.isMealRecordAuthenticationBusy)
        await C11AuthenticationFixtures.invoke(entry, model: f.model)
        #expect(f.originalContext.isActive)
        #expect(f.tickets.issued.count == 1)
        #expect(await f.runtime.authentication.entries == [.start, .passwordRecovery])
        await hold.release(); await pw.value
        #expect(!f.model.isMealRecordAuthenticationBusy)
        #expect(f.model.authOperationState == .recoveryConfirmation)
        #expect(await f.runtime.counted.leaseCalls == 1)
        #expect(await f.runtime.stub.requests().isEmpty)
        await f.end()
    }

    @MainActor
    @Test("C11 H05: a public late same-user session snapshot cannot spend the newer logout offer")
    func c11H05LateSameUserSnapshotRejectsOffer() async throws {
        let f = try await C11H05Fixture.make()
        await f.failLogout()
        let hold = C11BoundaryHold()
        await f.runtime.authentication.holdNextRestoredSession(using: hold)
        let old = Task { await f.model.start() }
        do {
            await hold.waitUntilEntered() // The real adapter has already captured old A.
            let record = C11RealLifecycleTransportHarness.record(userID: C11AuthenticationFixtures.a, ordinal: 2)
            let different = AuthenticationSessionRecord(userID: record.userID,
                email: "same-user-new-snapshot@example.invalid", isEmailConfirmed: true,
                isOnboardingCompleted: true, accessToken: record.accessToken,
                refreshToken: record.refreshToken, expiresAt: record.expiresAt)
            await f.runtime.remote.setSignIns([different])
            await f.model.signIn(email: C11AuthenticationFixtures.email,
                password: C11AuthenticationFixtures.syntheticPassword)
            await f.model.signOut() // Real marker failure captures the NEW public snapshot.
            let latest = try #require(f.model.currentSession)
            let candidate = MealRecordRecoveryOffer(anchorTicket: try #require(f.tickets.issued.last), session: latest)
            let count = f.tickets.issued.count
            #expect(f.model.isMealRecordAuthenticationBusy)
            #expect(f.model.beginMealRecordRecovery(offer: candidate) == nil)
            #expect(f.tickets.issued.count == count)
            await hold.release(); await old.value
            #expect(!f.model.isMealRecordAuthenticationBusy)
            #expect(f.model.state == .authenticated(userID: latest.userID))
            #expect(f.model.currentSession?.userID == latest.userID)
            #expect(f.model.currentSession != latest)
            #expect(f.model.availableMealRecordRecoveryOffer == nil)
            #expect(f.model.beginMealRecordRecovery(offer: candidate) == nil)
            #expect(f.tickets.issued.count == count)
            #expect(await f.runtime.counted.leaseCalls == 1)
            #expect(await f.runtime.stub.requests().isEmpty)
            await f.end()
        } catch { await hold.release(); await old.value; await f.end(); throw error }
    }

    @MainActor
    @Test("C11 H05: cancelled recovery retains its explicit retry offer while password recovery is still held")
    func c11H05RecoveryFailureDuringPWRetainsOffer() async throws {
        let f = try await C11H05Fixture.make()
        var caller: Task<MealRecordReadyContext?, any Error>?
        var pw: Task<Void, Never>?
        do {
            await f.failLogout()
            let offer = try #require(f.model.availableMealRecordRecoveryOffer)
            let recovery = try #require(f.model.beginMealRecordRecovery(offer: offer))
            await f.runtime.lifecycle.holdNextLease(completeEvenIfCancelled: true)
            let operation = try #require(f.root.beginBinding(activation: recovery, owner: f.owner))
            await f.runtime.lifecycle.leaseHold.waitUntilEntered()
            let pwHold = C11BoundaryHold()
            await f.runtime.authentication.hold(.passwordRecovery, using: pwHold)
            let pendingPW = Task { await f.model.requestPasswordRecovery(email: C11AuthenticationFixtures.email) }
            pw = pendingPW
            await pwHold.waitUntilEntered()
            let cancelling = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await f.root.completeBinding(operation)
            }
            caller = cancelling
            await #expect(throws: CancellationError.self) { _ = try await cancelling.value }
            f.model.finishMealRecordRecovery(recovery, succeeded: false)
            #expect(f.model.isMealRecordAuthenticationBusy)
            #expect(!f.model.isMealRecordRecoveryInProgress)
            #expect(f.model.availableMealRecordRecoveryOffer == nil)
            #expect(f.model.mealRecordActivation == nil)
            let issued = f.tickets.issued.count
            #expect(issued == 3)
            await pwHold.release(); await pendingPW.value
            #expect(!f.model.isMealRecordAuthenticationBusy)
            let next = try #require(f.model.availableMealRecordRecoveryOffer)
            #expect(next.anchorTicket == recovery.ticket)
            #expect(next.session == offer.session)
            #expect(f.tickets.issued.count == issued)
            #expect(await f.runtime.counted.leaseCalls == 2)
            #expect(await f.runtime.stub.requests().isEmpty)
            await f.runtime.lifecycle.leaseHold.release()
            await f.end()
        } catch {
            await f.runtime.releaseAll()
            if let caller { _ = try? await caller.value }
            if let pw { await pw.value }
            await f.end(); throw error
        }
    }

    @MainActor
    @Test("C11 I3: same-record Model.start cancels a completed 401 before unauthorized refresh")
    func c11I3Completed401CannotRefreshAfterSameRecordStart() async throws {
        let f = try await C11H05Fixture.make()
        var oldRead: Task<Void, Never>?
        do {
            let originalActivation = try #require(f.model.mealRecordActivation)
            let originalSession = try #require(f.model.currentSession)
            let originalBinding = try #require(f.owner.mealRecordBinding)
            let originalLease = try #require(originalBinding.capturedLease)
            #expect(f.originalContext.isActive)
            #expect(f.root.readyContext === f.originalContext)
            let center = FeatureInvalidationCenter()
            let keys = C11OwnerFixtureKeys()
            let oldModel = MealRecordModel(
                recordID: C11RealLifecycleTransportHarness.recordID,
                provider: f.originalContext.capability, time: C11OwnerFixtureTime(),
                keys: keys, invalidation: center,
                isSessionActive: { f.originalContext.isActive })
            let official = C11RealLifecycleTransportHarness.detail()
            let success = StubResponse(status: 200, body: try JSONEncoder().encode(official))
            await f.runtime.stub.respond { _, call in
                call == 1 ? .failure(status: 401, code: "expired_token") : success
            }
            await f.runtime.lifecycle.holdNextFinish()
            let pending = Task { @MainActor in _ = await oldModel.load() }
            oldRead = pending
            // finishPatientWork is reached only after networkTask.value returned.
            // Do not hold URLProtocol before delivering the first real 401.
            await f.runtime.lifecycle.finishHold.waitUntilEntered()
            #expect(await f.runtime.stub.requests().count == 1)
            #expect(await f.runtime.remote.counts() == [0, 0, 0, 0, 0])
            #expect(oldModel.isLoading)
            #expect(oldModel.detail == nil)
            #expect(oldModel.draft == nil)
            #expect(await f.runtime.lifecycle.heldFinishReturnedWhileCancelled == nil)

            // This accepted public boundary closes the registered old leaf.
            // The test does not close a gate, cancel the request or switch a record.
            await f.model.start()
            let currentActivation = try #require(f.model.mealRecordActivation)
            #expect(currentActivation.ticket != originalActivation.ticket)
            #expect(currentActivation.userID == originalActivation.userID)
            #expect(f.model.currentSession == originalSession)
            #expect(f.model.state == .authenticated(userID: originalSession.userID))
            #expect(!f.owner.isInvalidated)
            #expect(!originalBinding.isOpen)
            #expect(originalBinding.capability == nil)
            #expect(originalBinding.capturedLease == nil)
            #expect(!f.originalContext.isActive)
            #expect(!f.originalContext.capability.hasRetainedCapability)
            #expect(f.root.readyContext == nil)
            let sameRecordLease = try await f.runtime.session.leaseForRequest()
            #expect(sameRecordLease.userID == originalLease.userID)
            #expect(sameRecordLease.generation == originalLease.generation)
            let sameBearer = sameRecordLease.bearer == originalLease.bearer
            #expect(sameBearer)
            try await f.runtime.session.validate(originalLease)
            #expect(await f.runtime.stub.requests().count == 1)
            #expect(await f.runtime.remote.counts() == [0, 0, 0, 0, 0])

            // A separate actual grant/read is the current-scope positive control.
            // It never returns 401, so any refresh can only come from old A1.
            let operation = try #require(f.root.beginBinding(
                activation: currentActivation, owner: f.owner))
            let currentBinding = try #require(f.owner.mealRecordBinding)
            #expect(currentBinding !== originalBinding)
            let current = try #require(try await f.root.completeBinding(operation))
            #expect(current.activation == currentActivation)
            #expect(current.capability !== f.originalContext.capability)
            #expect(current.isActive)
            #expect(await f.runtime.counted.leaseCalls == 2)
            let currentModel = MealRecordModel(
                recordID: C11RealLifecycleTransportHarness.recordID,
                provider: current.capability, time: C11OwnerFixtureTime(),
                keys: keys, invalidation: center,
                isSessionActive: { current.isActive })
            await currentModel.load()
            #expect(currentModel.detail == official)
            #expect(currentModel.readFailure == nil)
            #expect(currentModel.canStartMutation)
            currentModel.draft?.items[0].quantityText = "75"
            #expect(currentModel.canSave(language: .englishUnitedStates))
            let beforeRelease = await f.runtime.stub.requests()
            try #require(beforeRelease.count == 2)
            let separateLogicalRead = beforeRelease[0].value(forHTTPHeaderField: "X-Request-Id") != nil
                && beforeRelease[1].value(forHTTPHeaderField: "X-Request-Id") != nil
                && beforeRelease[0].value(forHTTPHeaderField: "X-Request-Id")
                    != beforeRelease[1].value(forHTTPHeaderField: "X-Request-Id")
            #expect(separateLogicalRead)
            #expect(beforeRelease.allSatisfy { $0.httpMethod == "GET" })
            let noMutationMetadata = beforeRelease.allSatisfy {
                $0.httpBody == nil && $0.httpBodyStream == nil
                    && $0.value(forHTTPHeaderField: "Idempotency-Key") == nil
            }
            #expect(noMutationMetadata)

            // Resume the completed old response only after its real leaf closed.
            await f.runtime.lifecycle.finishHold.release()
            await pending.value
            #expect(await f.runtime.lifecycle.heldFinishReturnedWhileCancelled == true)
            let remoteCounts = await f.runtime.remote.counts()
            #expect(remoteCounts[3] == 0,
                "A cancelled old same-generation 401 must not initiate unauthorized refresh")
            #expect(remoteCounts[0] == 0 && remoteCounts[1] == 0
                && remoteCounts[2] == 0 && remoteCounts[4] == 0)
            #expect(await f.runtime.stub.requests().count == 2,
                "One old 401 plus one new-scope 200; never an old HTTP replay")
            #expect(oldModel.detail == nil)
            #expect(oldModel.draft == nil)
            #expect(oldModel.readFailure == nil)
            #expect(oldModel.failure == nil)
            #expect(oldModel.retainedAttempt == nil)
            #expect(oldModel.confirmedReceipt == nil)
            #expect(oldModel.completedMutations.isEmpty)
            #expect(currentModel.detail == official)
            #expect(currentModel.draft?.items[0].quantityText == "75")
            #expect(currentModel.canSave(language: .englishUnitedStates))
            #expect(currentModel.readFailure == nil)
            #expect(currentModel.failure == nil)
            #expect(currentModel.confirmedReceipt == nil)
            #expect(current.isActive)
            #expect(f.root.readyContext === current)
            #expect(f.model.mealRecordActivation == currentActivation)
            #expect(f.model.currentSession == originalSession)
            #expect(center.revision(for: .today) == 0)
            #expect(center.revision(for: .history) == 0)
            #expect(keys.count == 0)
            await f.end()
        } catch {
            // Release before join/end on every throwing setup/assertion path.
            await f.runtime.lifecycle.finishHold.release()
            await oldRead?.value
            await f.end()
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
    private var completed = false
    private var entryOrCompletionWaiters: [CheckedContinuation<Bool, Never>] = []
    private var opened = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func enterAndWait() async {
        entered = true
        let completionWaiters = entryOrCompletionWaiters
        entryOrCompletionWaiters.removeAll()
        completionWaiters.forEach { $0.resume(returning: true) }
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
    // Additive completion escape for new H2 tests; existing entry waits stay unchanged.
    func noteCompletion() {
        completed = true
        let waiters = entryOrCompletionWaiters
        entryOrCompletionWaiters.removeAll()
        waiters.forEach { $0.resume(returning: entered) }
    }
    func waitUntilEnteredOrCompleted() async -> Bool {
        if entered { return true }
        if completed { return false }
        return await withCheckedContinuation { entryOrCompletionWaiters.append($0) }
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
    // Observation only: preserve the real cancelled task across finish's await.
    private(set) var heldFinishReturnedWhileCancelled: Bool?

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
        if held {
            await finishHold.enterAndWait()
            heldFinishReturnedWhileCancelled = Task.isCancelled
        }
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
    let registry: PatientWorkRegistry
    let lifecycle: C11HoldingLifecycle
    let transport: MobileAPITransport

    init() async throws {
        let store = AuthenticationSessionStore(
            secureStore: InMemorySecureStore(), now: { Date(timeIntervalSince1970: 1000) }
        )
        try await store.replace(with: Self.record(userID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", ordinal: 1))
        let remote = C11OwnerRemote()
        let registry = PatientWorkRegistry()
        let coordinator = SessionLifecycleCoordinator(
            store: store, remote: remote, patientWorkRegistry: registry,
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
        self.registry = registry
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

enum C11OwnerRenewalHoldBoundary: Equatable, Sendable {
    case beforeLease
    case afterVisibleCommit
}

@MainActor
private func c11OwnerRenewalBindMustSucceed(
    _ binding: MealRecordSessionBinding,
    harness: C11RealLifecycleTransportHarness
) async -> MealRecordSessionCapability? {
    do {
        return try await binding.bind(transport: harness.transport, lifecycle: harness.lifecycle)
    } catch {
        // Runtime failure of an already-started baseline leaf is causal.
        // Record it without swallowing it into a green optional branch.
        Issue.record("H07 causal: the new reservation must bind successfully while the original owner and real lease are valid")
        return nil
    }
}

private func c11OwnerRenewalReleaseHolds(_ harness: C11RealLifecycleTransportHarness) async {
    await harness.lifecycle.leaseHold.release()
    await harness.lifecycle.visibleReturnHold.release()
}


// Root C11 test parameters remain internal for Swift Testing parameter access.
enum C11RootOldCompletion: Equatable, Sendable { case normal, cancelledCaller }
enum C11RootOffSource: Equatable, Sendable { case source, owner }
enum C11RootRejectedAdmission: Equatable, Sendable { case staleTicket, wrongOwner, closedOwner, missingProjection }
enum C11RootLeaseFailure: Equatable, Sendable { case missing, wrongUser }

/// Counts explicit binding lease calls, delegating every authority boundary to
/// the very same real coordinator used by the actual MobileAPITransport.
private actor C11RootCountingLifecycle: SessionLifecycleProviding {
    private let base: C11HoldingLifecycle
    private(set) var leaseCalls = 0
    private(set) var workoutWorkIDs: [UUID] = []
    private(set) var finishedWorkoutWorkIDs: [UUID] = []
    init(base: C11HoldingLifecycle) { self.base = base }
    func currentBearerToken() async -> String? { await base.currentBearerToken() }
    func leaseForRequest() async throws -> SessionLease {
        leaseCalls += 1
        return try await base.leaseForRequest()
    }
    func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease {
        try await base.refreshAfterUnauthorized(lease: lease)
    }
    func validate(_ lease: SessionLease) async throws { try await base.validate(lease) }
    func signOut() async -> RemoteRevocationOutcome { await base.signOut() }
    func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws -> UUID {
        let id = try await base.beginPatientWork(lease: lease, cancel: cancel)
        workoutWorkIDs.append(id)
        return id
    }
    func finishPatientWork(_ id: UUID) async {
        finishedWorkoutWorkIDs.append(id)
        await base.finishPatientWork(id)
    }
    func performPatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @Sendable () throws -> Value) async throws -> Value {
        try await base.performPatientStateOperation(lease: lease, operation: operation)
    }
    func performVisiblePatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @MainActor @Sendable () throws -> Value) async throws -> Value {
        try await base.performVisiblePatientStateOperation(lease: lease, operation: operation)
    }
}

@MainActor
private struct C11RootBindingFixture {
    let wire: C11RealLifecycleTransportHarness
    let countedLifecycle: C11RootCountingLifecycle
    let authentication: C11AuthenticationEntryPeer
    let model: AppFlowModel
    let lifetime: MealRecordAuthenticationLifetime
    let activation: MealRecordAuthenticatedActivation
    let owner: Prompt14SessionOwner
    let coordinator: MealRecordRootBindingCoordinator

    static func make(sourceEnabled: Bool = true, ownerEnabled: Bool = true) async throws -> Self {
        let wire = try await C11RealLifecycleTransportHarness()
        let lifetime = MealRecordAuthenticationLifetime()
        var preparedOwner: Prompt14SessionOwner? = nil
        do {
            let authentication = C11AuthenticationEntryPeer(coordinator: wire.coordinator)
            let model = C11AuthenticationFixtures.model(peer: authentication,
                onboarding: C11AuthenticationOnboardingPeer(completed: true),
                lifetime: lifetime, telemetry: InMemoryTelemetryClient())
            await model.start()
            let activation = try #require(model.mealRecordActivation)
            let owner = Prompt14SessionOwner(userID: activation.userID,
                dependencies: C11BindingTestDependencies.make(), enablesMealRecordBinding: ownerEnabled)
            preparedOwner = owner
            await owner.awaitPatientTimeZoneResolution()
            let counted = C11RootCountingLifecycle(base: wire.lifecycle)
            let source = MealRecordSessionBindingSource(transport: wire.transport, lifecycle: counted)
            let coordinator = MealRecordRootBindingCoordinator(lifetime: lifetime,
                source: sourceEnabled ? source : nil,
                currentActivation: { [weak model] in model?.mealRecordActivation })
            try await wire.respondWithMealDetail()
            return Self(wire: wire, countedLifecycle: counted, authentication: authentication,
                model: model, lifetime: lifetime, activation: activation, owner: owner, coordinator: coordinator)
        } catch {
            await lifetime.endSession()
            await preparedOwner?.endSession()
            throw error
        }
    }

    func end() async {
        await coordinator.endSession()
        await lifetime.endSession()
        await owner.endSession()
    }
}

// H05 private helpers; all authority delegates to the real store/coordinator/adapter.
enum C11H05ReleaseOrder: Equatable, Sendable { case olderFirst, newerFirst }
enum C11H05RecoveryTerminal: Equatable, Sendable { case callerCancelled, lateABA }
enum C11H05NoOffer: Equatable, Sendable { case serviceUnavailable, defaultNil, incomplete }

private actor C11H05MarkerStore: SecureStoring {
    private var values: [String: Data] = [:]
    private var rejectsMarker = false
    func data(forKey key: String) -> Data? { values[key] }
    func store(_ data: Data, forKey key: String) throws {
        if key == AuthenticationSessionStore.invalidationMarkerKey, rejectsMarker {
            throw AuthenticationSessionStoreError.localInvalidationFailed
        }
        values[key] = data
    }
    func removeData(forKey key: String) { values[key] = nil }
    func rejectMarker(_ value: Bool = true) { rejectsMarker = value }
}

private actor C11H05Remote: SupabaseAuthRemoteOperating {
    private let original: AuthenticationSessionRecord
    private var signIns: [AuthenticationSessionRecord] = []
    private var revocation: RemoteRevocationOutcome = .confirmed
    private var counters = [0, 0, 0, 0, 0]
    init(record: AuthenticationSessionRecord) { original = record }
    func setSignIns(_ records: [AuthenticationSessionRecord]) { signIns = records }
    func setRevocation(_ value: RemoteRevocationOutcome) { revocation = value }
    func counts() -> [Int] { counters }
    func signIn(email: String, password: String) -> AuthenticationSessionRecord {
        counters[0] += 1
        return signIns.isEmpty ? original : signIns.removeFirst()
    }
    func signUp(email: String, password: String) -> SupabaseRemoteSignUpResult {
        counters[1] += 1; return .authenticated(original)
    }
    func requestPasswordRecovery(email: String) { counters[2] += 1 }
    func refresh(record: AuthenticationSessionRecord) -> AuthenticationSessionRecord {
        counters[3] += 1; return record
    }
    func revokeCurrentSession(accessToken: String) -> RemoteRevocationOutcome {
        counters[4] += 1; return revocation
    }
}

private actor C11H05Authentication: AuthenticationService {
    private let base: SupabaseAuthenticationService
    private var pendingHolds: [(C11AuthenticationEntry, C11BoundaryHold)] = []
    private var allHolds: [C11BoundaryHold] = []
    private var logoutError: AuthenticationError?
    private var nextRestoredSessionHold: C11BoundaryHold?
    private(set) var entries: [C11AuthenticationEntry] = []
    init(base: SupabaseAuthenticationService) { self.base = base }
    func hold(_ entry: C11AuthenticationEntry, using hold: C11BoundaryHold) {
        pendingHolds.append((entry, hold)); allHolds.append(hold)
    }
    func forceNextLogoutError(_ error: AuthenticationError) { logoutError = error }
    func holdNextRestoredSession(using hold: C11BoundaryHold) {
        nextRestoredSessionHold = hold; allHolds.append(hold)
    }
    func releaseAll() async { for hold in allHolds { await hold.release() } }
    private func enter(_ entry: C11AuthenticationEntry) async {
        entries.append(entry)
        if let index = pendingHolds.firstIndex(where: { $0.0 == entry }) {
            let held = pendingHolds.remove(at: index).1
            await held.enterAndWait()
        }
    }
    func restoreSession() async throws -> AuthSession? {
        await enter(.start)
        let captured = try await base.restoreSession()
        if let hold = nextRestoredSessionHold {
            nextRestoredSessionHold = nil
            await hold.enterAndWait()
        }
        return captured
    }
    func signIn(email: String, password: String) async throws -> AuthSession {
        await enter(.signIn); return try await base.signIn(email: email, password: password)
    }
    func signUp(email: String, password: String) async throws -> AuthSignUpResult {
        await enter(.signUp); return try await base.signUp(email: email, password: password)
    }
    func confirmEmailForDevelopment() async throws -> AuthSession {
        await enter(.confirmDevelopment); return try await base.confirmEmailForDevelopment()
    }
    func requestPasswordRecovery(email: String) async throws {
        await enter(.passwordRecovery); try await base.requestPasswordRecovery(email: email)
    }
    func signOut() async throws {
        await enter(.signOut)
        if let error = logoutError { logoutError = nil; throw error }
        try await base.signOut()
    }
}

private struct C11H05Runtime: Sendable {
    let secure: C11H05MarkerStore
    let store: AuthenticationSessionStore
    let remote: C11H05Remote
    let lifecycle: C11HoldingLifecycle
    let counted: C11RootCountingLifecycle
    let session: SessionLifecycleCoordinator
    let authentication: C11H05Authentication
    let transport: MobileAPITransport
    let stub: TransportStubStore
    let original: AuthenticationSessionRecord
    let originalLease: SessionLease
    init() async throws {
        let original = C11RealLifecycleTransportHarness.record(userID: C11AuthenticationFixtures.a, ordinal: 1)
        let secure = C11H05MarkerStore()
        let store = AuthenticationSessionStore(secureStore: secure, now: { Date(timeIntervalSince1970: 1000) })
        try await store.replace(with: original)
        let remote = C11H05Remote(record: original)
        let session = SessionLifecycleCoordinator(store: store, remote: remote,
            refreshPolicy: SessionRefreshPolicy(now: { Date(timeIntervalSince1970: 1000) }, leeway: 60))
        let lifecycle = C11HoldingLifecycle(base: session)
        let counted = C11RootCountingLifecycle(base: lifecycle)
        let stub = TransportStubStore()
        await StubURLProtocol.install(store: stub)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        self.secure = secure; self.store = store; self.remote = remote
        self.session = session; self.lifecycle = lifecycle; self.counted = counted; self.stub = stub
        self.authentication = C11H05Authentication(base: SupabaseAuthenticationService(remote: remote, lifecycle: session))
        self.transport = MobileAPITransport(
            configuration: try MobileAPIConfiguration(originString: "https://staging.example.test"),
            sessionLifecycle: lifecycle, session: URLSession(configuration: config),
            clock: ContinuousClock(), timeout: .seconds(2))
        self.original = original
        self.originalLease = try await session.leaseForRequest()
    }
    func respond() async throws {
        await stub.respond(with: StubResponse(status: 200,
            body: try JSONEncoder().encode(C11RealLifecycleTransportHarness.detail())))
    }
    func releaseAll() async {
        await authentication.releaseAll()
        await lifecycle.leaseHold.release()
        await lifecycle.visibleReturnHold.release()
    }
}

@MainActor
private struct C11H05Fixture {
    let runtime: C11H05Runtime
    let lifetime: MealRecordAuthenticationLifetime
    let tickets: C11AuthenticationTicketFactorySpy
    let model: AppFlowModel
    let telemetry: InMemoryTelemetryClient
    let owner: Prompt14SessionOwner
    let root: MealRecordRootBindingCoordinator
    let originalContext: MealRecordReadyContext
    static func make() async throws -> Self {
        let runtime = try await C11H05Runtime()
        let tickets = C11AuthenticationTicketFactorySpy()
        let lifetime = MealRecordAuthenticationLifetime(ticketFactory: { tickets.next() })
        var preparedOwner: Prompt14SessionOwner?
        var preparedRoot: MealRecordRootBindingCoordinator?
        do {
            let telemetry = InMemoryTelemetryClient()
            let model = AppFlowModel(authentication: runtime.authentication,
                onboarding: C11AuthenticationOnboardingPeer(completed: true),
                persona: AppDependencies.scaffold().coachPersona, telemetry: telemetry,
                mealRecordAuthenticationLifetime: lifetime,
                developmentConsentAvailability: .syntheticDevelopment)
            await model.start()
            let activation = try #require(model.mealRecordActivation)
            let owner = Prompt14SessionOwner(userID: activation.userID,
                dependencies: C11BindingTestDependencies.make(), enablesMealRecordBinding: true)
            preparedOwner = owner
            await owner.awaitPatientTimeZoneResolution()
            let root = MealRecordRootBindingCoordinator(lifetime: lifetime,
                source: MealRecordSessionBindingSource(transport: runtime.transport, lifecycle: runtime.counted),
                currentActivation: { [weak model] in model?.mealRecordActivation })
            preparedRoot = root
            let operation = try #require(root.beginBinding(activation: activation, owner: owner))
            let context = try #require(try await root.completeBinding(operation))
            try await runtime.respond()
            return Self(runtime: runtime, lifetime: lifetime, tickets: tickets, model: model,
                telemetry: telemetry, owner: owner, root: root, originalContext: context)
        } catch {
            await runtime.releaseAll()
            await preparedRoot?.endSession()
            await lifetime.endSession()
            await preparedOwner?.endSession()
            throw error
        }
    }
    func failLogout() async {
        await runtime.secure.rejectMarker()
        await model.signOut()
    }
    func end() async {
        await runtime.releaseAll()
        await root.endSession()
        await lifetime.endSession()
        await owner.endSession()
    }
}

// I5 binding-only tests: new adapters observe existing APIs and delegate all authority
// to the real coordinator/registry. Transport work uses that same real coordinator.
enum C11I5BindingTerminal: Equatable, Sendable { case invalidGrant, signOut, otherUser }
enum C11I5BindingPreserved: Equatable, Sendable { case transient, markerFailure, sameUserCredentials }
enum C11I5BindingAdmissionTerminal: Equatable, Sendable { case invalidation, callerCancellation, leafClose }

private final class C11I5BindingCancellationCount: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func note() { lock.withLock { value += 1 } }
}

/// A real API-entry hold, with completion escape when the pre-implementation
/// binding never calls that API. No sleep, polling, timeout or fabricated grant.
private actor C11I5BindingCheckpoint {
    private var entered = false
    private var completed = false
    private var opened = false
    private var entryWaiters: [CheckedContinuation<Bool, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    func enterAndWait() async {
        entered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        waiters.forEach { $0.resume(returning: true) }
        if !opened { await withCheckedContinuation { releaseWaiters.append($0) } }
    }
    func noteCompletion() {
        completed = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        waiters.forEach { $0.resume(returning: entered) }
    }
    func waitUntilEnteredOrCompleted() async -> Bool {
        if entered { return true }
        if completed { return false }
        return await withCheckedContinuation { entryWaiters.append($0) }
    }
    func release() {
        opened = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor C11I5BindingLifecycleProbe: SessionLifecycleProviding {
    private let base: C11HoldingLifecycle
    private let cancellations: C11I5BindingCancellationCount
    let beginReturn = C11I5BindingCheckpoint()
    let finishReturn = C11I5BindingCheckpoint()
    private var holdsBegin = false
    private var holdsFinish = false
    private(set) var admittedIDs: [UUID] = []
    private(set) var finishedIDs: [UUID] = []
    init(base: C11HoldingLifecycle, cancellations: C11I5BindingCancellationCount) {
        self.base = base
        self.cancellations = cancellations
    }
    func holdNextBeginReturn() { holdsBegin = true }
    func holdNextFinish() { holdsFinish = true }
    func currentBearerToken() async -> String? { await base.currentBearerToken() }
    func restorePublicSession() async throws -> AuthSession? { try await base.restorePublicSession() }
    func `switch`(to record: AuthenticationSessionRecord) async throws { try await base.switch(to: record) }
    func leaseForRequest() async throws -> SessionLease { try await base.leaseForRequest() }
    func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease {
        try await base.refreshAfterUnauthorized(lease: lease)
    }
    func validate(_ lease: SessionLease) async throws { try await base.validate(lease) }
    func signOut() async -> RemoteRevocationOutcome { await base.signOut() }
    func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws -> UUID {
        let held = holdsBegin
        holdsBegin = false
        let cancellations = cancellations
        let id = try await base.beginPatientWork(lease: lease) {
            cancellations.note()
            cancel()
        }
        admittedIDs.append(id)
        if held { await beginReturn.enterAndWait() }
        return id
    }
    func finishPatientWork(_ id: UUID) async {
        let held = holdsFinish
        holdsFinish = false
        if held { await finishReturn.enterAndWait() }
        await base.finishPatientWork(id)
        finishedIDs.append(id)
    }
    func performPatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @Sendable () throws -> Value) async throws -> Value {
        try await base.performPatientStateOperation(lease: lease, operation: operation)
    }
    func performVisiblePatientStateOperation<Value: Sendable>(lease: SessionLease,
        operation: @MainActor @Sendable () throws -> Value) async throws -> Value {
        try await base.performVisiblePatientStateOperation(lease: lease, operation: operation)
    }
}

private actor C11I5BindingRemote: SupabaseAuthRemoteOperating {
    private var refreshError: SupabaseAuthRemoteError = .invalidGrant
    private(set) var refreshCount = 0
    private(set) var revokeCount = 0
    func failRefresh(with error: SupabaseAuthRemoteError) { refreshError = error }
    func signIn(email: String, password: String) throws -> AuthenticationSessionRecord {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func signUp(email: String, password: String) throws -> SupabaseRemoteSignUpResult {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func requestPasswordRecovery(email: String) throws { throw SupabaseAuthRemoteError.requestFailed }
    func refresh(record: AuthenticationSessionRecord) throws -> AuthenticationSessionRecord {
        refreshCount += 1
        throw refreshError
    }
    func revokeCurrentSession(accessToken: String) -> RemoteRevocationOutcome {
        revokeCount += 1
        return .confirmed
    }
}

private struct C11I5BindingRuntime: Sendable {
    let original: AuthenticationSessionRecord
    let originalLease: SessionLease
    let secure: C11H05MarkerStore
    let store: AuthenticationSessionStore
    let remote: C11I5BindingRemote
    let registry: PatientWorkRegistry
    let session: SessionLifecycleCoordinator
    let held: C11HoldingLifecycle
    let probe: C11I5BindingLifecycleProbe
    let cancellations: C11I5BindingCancellationCount
    let transport: MobileAPITransport
    let stub: TransportStubStore
    init() async throws {
        let original = C11RealLifecycleTransportHarness.record(userID: C11AuthenticationFixtures.a, ordinal: 1)
        let secure = C11H05MarkerStore()
        let store = AuthenticationSessionStore(secureStore: secure, now: { Date(timeIntervalSince1970: 1000) })
        try await store.replace(with: original)
        let remote = C11I5BindingRemote()
        let registry = PatientWorkRegistry()
        let session = SessionLifecycleCoordinator(store: store, remote: remote, patientWorkRegistry: registry,
            refreshPolicy: SessionRefreshPolicy(now: { Date(timeIntervalSince1970: 1000) }, leeway: 60))
        let held = C11HoldingLifecycle(base: session)
        let cancellations = C11I5BindingCancellationCount()
        let probe = C11I5BindingLifecycleProbe(base: held, cancellations: cancellations)
        let stub = TransportStubStore()
        await StubURLProtocol.install(store: stub)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        self.original = original; self.secure = secure; self.store = store; self.remote = remote
        self.registry = registry; self.session = session; self.held = held; self.probe = probe
        self.cancellations = cancellations; self.stub = stub
        self.transport = MobileAPITransport(
            configuration: try MobileAPIConfiguration(originString: "https://staging.example.test"),
            sessionLifecycle: session, session: URLSession(configuration: configuration),
            clock: ContinuousClock(), timeout: .seconds(2))
        self.originalLease = try await session.leaseForRequest()
    }
    func respond() async throws {
        await stub.respond(with: StubResponse(status: 200,
            body: try JSONEncoder().encode(C11RealLifecycleTransportHarness.detail())))
    }
    func releaseAll() async {
        await held.visibleReturnHold.release()
        await probe.beginReturn.release()
        await probe.finishReturn.release()
    }
}

@MainActor
private struct C11I5BindingFixture {
    let runtime: C11I5BindingRuntime
    let owner: Prompt14SessionOwner
    let binding: MealRecordSessionBinding
    func bind() async throws -> MealRecordSessionCapability {
        try await binding.bind(transport: runtime.transport, lifecycle: runtime.probe)
    }
}

@MainActor
private func c11WithI5Binding(_ body: (C11I5BindingFixture) async throws -> Void) async throws {
    let runtime = try await C11I5BindingRuntime()
    let owner = Prompt14SessionOwner(userID: runtime.original.userID,
        dependencies: C11BindingTestDependencies.make(), enablesMealRecordBinding: true)
    do {
        await owner.awaitPatientTimeZoneResolution()
        let binding = try #require(owner.mealRecordBinding)
        try await body(C11I5BindingFixture(runtime: runtime, owner: owner, binding: binding))
        await runtime.releaseAll()
        await owner.endSession()
    } catch {
        await runtime.releaseAll()
        await owner.endSession()
        throw error
    }
}

// Append to MobileAPITransportTests.swift, in the SAME file and serialized
// suite as its existing private C11/HTTP helpers. No new @Suite/URLProtocol.
extension MobileAPITransportTests {
    @MainActor
    @Test("H2: one original scope reads Me and serves the owned projection; only exact ui-v1 opts in",
          arguments: ["ui-v1", "ui-v2", "absent"])
    func h2OneCapturedScopeAndExplicitMeProtocol(advertised: String) async throws {
        try await h2WithWire { fixture in
            let wire = fixture.wire
            #expect(await fixture.counted.leaseCalls == 0)
            #expect(await wire.stub.requests().isEmpty)
            let original = try await wire.coordinator.leaseForRequest()
            let me = try h2Me(owner: fixture.activation.userID, advertised: advertised)
            let projection = try h2Projection()
            await wire.stub.respond { request, _ in
                switch request.url?.path {
                case "/api/mobile/v1/me": return StubResponse(status: 200, body: me)
                case "/api/mobile/v1/registrations/\(h2RegistrationID)": return StubResponse(status: 200, body: projection)
                default: throw H2UnexpectedRequest()
                }
            }
            let binding = try fixture.reserve()
            #expect(await fixture.counted.leaseCalls == 0)
            #expect(binding.readyContext == nil)
            let context = try await fixture.source.bind(binding)
            #expect(context.isActive)
            #expect(context.registrationProtocol == (advertised == "ui-v1" ? .uiV1 : nil))
            #expect(binding.readyContext != nil)
            #expect(binding.capturedLease?.userID == original.userID)
            #expect(binding.capturedLease?.generation == original.generation)
            #expect(await fixture.counted.leaseCalls == 1)
            if advertised == "ui-v1" {
                let response = try await context.provider.loadWorkoutRegistration(id: h2RegistrationID)
                #expect(response.data.id == h2RegistrationID)
                #expect(response.data.workoutVersion?.contentRevision == 0)
            }
            let requests = await wire.stub.requests()
            let paths = advertised == "ui-v1"
                ? ["/api/mobile/v1/me", "/api/mobile/v1/registrations/\(h2RegistrationID)"]
                : ["/api/mobile/v1/me"]
            #expect(requests.compactMap { $0.url?.path } == paths)
            #expect(requests.allSatisfy { $0.httpMethod == "GET" })
            #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Idempotency-Key") == nil })
            #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer \(original.bearer)" })
            #expect(await fixture.counted.leaseCalls == 1)
        }
    }

    @MainActor
    @Test("H2: failed Me stays unready and explicit retry retains the original scope")
    func h2MeRetryDoesNotCaptureAnotherLease() async throws {
        try await h2WithWire { fixture in
            let me = try h2Me(owner: fixture.activation.userID, advertised: "ui-v1")
            await fixture.wire.stub.respond { request, call in
                guard request.url?.path == "/api/mobile/v1/me", request.httpMethod == "GET" else { throw H2UnexpectedRequest() }
                return call == 1 ? .failure(status: 503, code: "internal_error") : StubResponse(status: 200, body: me)
            }
            let binding = try fixture.reserve()
            do {
                _ = try await fixture.source.bind(binding)
                Issue.record("ME_FAILURE_MUST_NOT_PUBLISH_A_READY_OR_LEGACY_CONTEXT")
            } catch { #expect(!(error is CancellationError)) }
            #expect(binding.readyContext == nil)
            #expect(binding.canRetryMe)
            #expect(binding.isOpen)
            let original = try #require(binding.capturedLease)
            #expect(await fixture.counted.leaseCalls == 1)
            #expect(await fixture.wire.stub.requests().count == 1)
            let context = try await fixture.source.retryMe(binding)
            #expect(context.isActive)
            #expect(context.registrationProtocol == .uiV1)
            #expect(binding.capturedLease?.userID == original.userID)
            #expect(binding.capturedLease?.generation == original.generation)
            #expect(await fixture.counted.leaseCalls == 1)
            let requests = await fixture.wire.stub.requests()
            #expect(requests.count == 2)
            #expect(requests.allSatisfy { $0.url?.path == "/api/mobile/v1/me" && $0.httpMethod == "GET" })
            #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer \(original.bearer)" })
        }
    }

    @MainActor
    @Test("H2: a reserved old ticket cannot adopt a returned current lease, including A to B to A",
          arguments: [false, true])
    func h2HeldLeaseCannotRenewAnOldTicket(actualABA: Bool) async throws {
        try await h2WithWire { fixture in
            let wire = fixture.wire
            let original = try await wire.coordinator.leaseForRequest()
            let old = try fixture.reserve()
            await wire.lifecycle.holdNextLease(completeEvenIfCancelled: true)
            let pending = Task {
                do {
                    let context = try await fixture.source.bind(old)
                    await wire.lifecycle.leaseHold.noteCompletion()
                    return context
                } catch {
                    await wire.lifecycle.leaseHold.noteCompletion()
                    throw error
                }
            }
            do {
                let entered = await wire.lifecycle.leaseHold.waitUntilEnteredOrCompleted()
                try #require(entered, "Bind must reach the real lease API before the held-lease oracle")
                let ticket = fixture.lifetime.beginAuthenticationBoundary()
                let current = try #require(fixture.lifetime.publishAuthenticated(userID: original.userID, ticket: ticket))
                #expect(current.ticket != fixture.activation.ticket)
                #expect(!fixture.owner.isInvalidated) // ticket, not owner close, withdraws the old grant
                #expect(!old.isOpen)
                if actualABA { try await wire.replaceSession(returnToA: true) }
                let currentLease = try await wire.coordinator.leaseForRequest()
                #expect(currentLease.userID == original.userID)
                #expect((currentLease.generation != original.generation) == actualABA)
                await wire.lifecycle.leaseHold.release()
                await #expect(throws: CancellationError.self) { _ = try await pending.value }
                #expect(old.readyContext == nil)
                #expect(await wire.stub.requests().isEmpty)
                let me = try h2Me(owner: current.userID, advertised: "ui-v1")
                await wire.stub.respond(with: StubResponse(status: 200, body: me))
                let next = try fixture.reserve(activation: current)
                #expect(next !== old)
                let ready = try await fixture.source.bind(next)
                #expect(ready.isActive)
                #expect(next.capturedLease?.generation == currentLease.generation)
                #expect(await wire.stub.requests().count == 1)
                await old.endSession()
                #expect(ready.isActive)
            } catch {
                await wire.lifecycle.leaseHold.release()
                _ = await pending.result
                throw error
            }
        }
    }

    @MainActor
    @Test("H2: a retained provider cannot send a mutation or owned GET under B or later A",
          arguments: [H2WorkoutCall.propose, .edit, .confirm, .cancel, .get])
    func h2RetainedProviderCannotSendAfterABA(call: H2WorkoutCall) async throws {
        try await h2WithWire { fixture in
            let me = try h2Me(owner: fixture.activation.userID, advertised: "ui-v1")
            await fixture.wire.stub.respond(with: StubResponse(status: 200, body: me))
            let binding = try fixture.reserve()
            let context = try await fixture.source.bind(binding)
            #expect(context.isActive)
            #expect(await fixture.wire.stub.requests().count == 1)
            _ = fixture.lifetime.beginAuthenticationBoundary()
            try await fixture.wire.replaceSession(returnToA: true)
            #expect(!context.isActive)
            await #expect(throws: CancellationError.self) {
                try await h2Invoke(call, provider: context.provider)
            }
            #expect(await fixture.wire.stub.requests().count == 1)
            #expect(await fixture.wire.remote.refreshCount == 0)
            #expect(binding.readyContext == nil)
        }
    }

    @MainActor
    @Test("H2: a completed real EDIT success or error cannot publish after its original ticket retires",
          arguments: [false, true])
    func h2LateWorkoutModelResultIsNotPublished(failure: Bool) async throws {
        try await h2WithWire { fixture in
            let me = try h2Me(owner: fixture.activation.userID, advertised: "ui-v1")
            let pending = try h2Projection()
            let edited = try h2Projection(revision: 1, duration: 61, receiptKey: "wue1:\(H2WorkoutKeys.literal(2))")
            await fixture.wire.stub.respond { request, _ in
                switch (request.httpMethod, request.url?.path) {
                case ("GET", "/api/mobile/v1/me"): return StubResponse(status: 200, body: me)
                case ("POST", "/api/mobile/v1/registrations/propose"): return StubResponse(status: 200, body: pending)
                case ("PATCH", "/api/mobile/v1/registrations/\(h2RegistrationID)"):
                    return failure ? .failure(status: 409, code: "registration_revision_conflict") : StubResponse(status: 200, body: edited)
                default: throw H2UnexpectedRequest()
                }
            }
            let context = try await fixture.source.bind(fixture.reserve())
            let controlled = H2CompletedEditHold(base: context.provider)
            let center = FeatureInvalidationCenter()
            let model = WorkoutRegistrationModel(registration: controlled,
                timeProvider: C11OwnerFixtureTime(), keyProvider: H2WorkoutKeys(),
                invalidationCenter: center, registrationProtocol: context.registrationProtocol,
                isSessionActive: { context.isActive })
            await model.submit(h2Draft)
            #expect(model.currentProposal?.id == h2RegistrationID)
            #expect(center.revision(for: .today) == 1)
            let operation = Task {
                await model.saveEdit(h2EditedDraft)
                await controlled.completed.noteCompletion()
            }
            do {
                let entered = await controlled.completed.waitUntilEnteredOrCompleted()
                try #require(entered)
                #expect(await fixture.wire.stub.requests().count == 3)
                #expect(model.captureError == nil)
                _ = fixture.lifetime.beginAuthenticationBoundary()
                try await fixture.wire.replaceSession(returnToA: true)
                #expect(!context.isActive)
                await controlled.completed.release()
                await operation.value
                #expect(model.currentProposal?.workoutVersion?.contentRevision == 0)
                #expect(model.pendingDraft?.workoutType == h2EditedDraft.workoutType)
                #expect(model.pendingDraft?.durationMin == h2EditedDraft.durationMin)
                #expect(model.pendingDraft?.intensity == h2EditedDraft.intensity)
                #expect(model.pendingDraft?.performedAt == h2EditedDraft.performedAt)
                #expect(model.captureError == nil)
                #expect(model.mutationState.receipt == nil)
                #expect(model.accessibilityFocusTarget == nil)
                #expect(center.revision(for: .today) == 1)
                #expect(center.revision(for: .history) == 0)
                let before = await fixture.wire.stub.requests().count
                await model.confirm()
                await model.cancel()
                #expect(await fixture.wire.stub.requests().count == before)
            } catch {
                await controlled.completed.release()
                await operation.value
                throw error
            }
        }
    }

    @MainActor
    @Test("H2: a real timed-out EDIT completed after ticket retirement throws cancellation directly from the provider")
    func h2ProviderLateErrorCannotEscapeItsRetiredTicket() async throws {
        try await h2WithWire { fixture in
            let wire = fixture.wire
            let me = try h2Me(owner: fixture.activation.userID, advertised: "ui-v1")
            await wire.stub.respond(with: StubResponse(status: 200, body: me))
            let binding = try fixture.reserve()
            let context = try await fixture.source.bind(binding)
            let original = try #require(binding.capturedLease)
            await wire.stub.respond { request, _ in
                guard request.httpMethod == "PATCH",
                      request.url?.path == "/api/mobile/v1/registrations/\(h2RegistrationID)" else {
                    throw H2UnexpectedRequest()
                }
                throw URLError(.timedOut)
            }
            await wire.lifecycle.holdNextFinish()
            let version = try #require(WorkoutRegistrationVersion(contentRevision: 0))
            let attempt = MutationAttempt(operation: .proposalEdit,
                key: try IdempotencyKey(validating: H2WorkoutKeys.literal(8)),
                payload: RegistrationEditCommand(registrationID: h2RegistrationID,
                    proposal: .workout(h2EditedDraft), workoutVersion: version),
                createdAt: C11OwnerFixtureTime().now)
            let pending = Task {
                do {
                    let response = try await context.provider.edit(attempt)
                    await wire.lifecycle.finishHold.noteCompletion()
                    return response
                } catch {
                    await wire.lifecycle.finishHold.noteCompletion()
                    throw error
                }
            }
            do {
                let entered = await wire.lifecycle.finishHold.waitUntilEnteredOrCompleted()
                try #require(entered, "Provider EDIT must reach the completed real HTTP failure before retirement")
                let requests = await wire.stub.requests()
                try #require(requests.count == 2)
                #expect(requests.last?.httpMethod == "PATCH")
                #expect(requests.last?.url?.path == "/api/mobile/v1/registrations/\(h2RegistrationID)")
                #expect(requests.last?.value(forHTTPHeaderField: "Idempotency-Key") == attempt.key.value)
                _ = fixture.lifetime.beginAuthenticationBoundary()
                #expect(!context.isActive)
                #expect(!binding.isOpen)
                #expect(!fixture.owner.isInvalidated)
                // No session switch or model discard can mask the leaf's error barrier.
                try await wire.coordinator.validate(original)
                let current = try await wire.coordinator.leaseForRequest()
                #expect(current.userID == original.userID)
                #expect(current.generation == original.generation)
                await wire.lifecycle.finishHold.release()
                await #expect(throws: CancellationError.self) { _ = try await pending.value }
                #expect(await wire.stub.requests().count == 2)
                #expect(await wire.remote.refreshCount == 0)
                #expect(await wire.lifecycle.heldFinishReturnedWhileCancelled == true)
            } catch {
                await wire.lifecycle.finishHold.release()
                _ = await pending.result
                throw error
            }
        }
    }

    @MainActor
    @Test("H2: same-generation401 refresh preserves the exact versioned command and original grant")
    func h2SameGenerationRefreshKeepsTheWorkoutCommand() async throws {
        try await h2WithWire { fixture in
            let me = try h2Me(owner: fixture.activation.userID, advertised: "ui-v1")
            await fixture.wire.stub.respond(with: StubResponse(status: 200, body: me))
            let binding = try fixture.reserve()
            let context = try await fixture.source.bind(binding)
            let original = try #require(binding.capturedLease)
            let bodies = C11RequestBodyCapture()
            let confirmed = try h2Projection(status: "confirmed", confirmation: true)
            await fixture.wire.stub.respond { request, call in
                guard request.httpMethod == "POST", request.url?.path == "/api/mobile/v1/registrations/\(h2RegistrationID)/confirm" else { throw H2UnexpectedRequest() }
                try await bodies.capture(request)
                return call == 2 ? .failure(status: 401, code: "expired_token") : StubResponse(status: 200, body: confirmed)
            }
            let key = try IdempotencyKey(validating: H2WorkoutKeys.literal(7))
            let version = try #require(WorkoutRegistrationVersion(contentRevision: 0))
            let attempt = MutationAttempt(operation: .proposalConfirm, key: key,
                payload: RegistrationIDCommand(registrationID: h2RegistrationID, workoutVersion: version),
                createdAt: C11OwnerFixtureTime().now)
            let result = try await context.provider.confirm(attempt)
            #expect(result.data.registration.status == "confirmed")
            #expect(context.isActive)
            #expect(context.registrationProtocol == .uiV1)
            #expect(await fixture.counted.leaseCalls == 1)
            #expect(await fixture.wire.remote.refreshCount == 1)
            let current = try await fixture.wire.coordinator.leaseForRequest()
            #expect(current.generation == original.generation)
            let requests = Array((await fixture.wire.stub.requests()).dropFirst())
            #expect(requests.count == 2)
            let first = try #require(requests.first)
            let second = try #require(requests.last)
            #expect(first.httpMethod == second.httpMethod)
            #expect(first.url == second.url)
            #expect(first.value(forHTTPHeaderField: "Idempotency-Key") == key.value)
            #expect(second.value(forHTTPHeaderField: "Idempotency-Key") == key.value)
            #expect(first.value(forHTTPHeaderField: "X-Request-Id") == second.value(forHTTPHeaderField: "X-Request-Id"))
            #expect(first.value(forHTTPHeaderField: "Authorization") != second.value(forHTTPHeaderField: "Authorization"))
            let capturedBodies = await bodies.bodies()
            #expect(capturedBodies.count == 2)
            #expect(capturedBodies[0] == capturedBodies[1])
            let object = try #require(capturedBodies[0].flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
            #expect(Set(object.keys) == ["workout_protocol", "expected_revision"])
            #expect(object["workout_protocol"] as? String == "ui-v1")
            #expect(object["expected_revision"] as? Int == 0)
        }
    }

    @MainActor
    @Test("H2: an admitted work UUID returned after retirement is retained and finished once across reentrant end")
    func h2LateWorkIDAndReentrantEndHaveOneOwner() async throws {
        let runtime = try await C11I5BindingRuntime()
        let lifetime = MealRecordAuthenticationLifetime()
        let ticket = lifetime.beginAuthenticationBoundary()
        let activation = try #require(lifetime.publishAuthenticated(userID: runtime.original.userID, ticket: ticket))
        let owner = Prompt14SessionOwner(userID: activation.userID, dependencies: C11BindingTestDependencies.make())
        await owner.awaitPatientTimeZoneResolution()
        let reservation = owner.reserveWorkoutRegistrationBinding(activation: activation,
            lifetime: lifetime, currentActivation: { lifetime.currentActivation })
        let binding = try #require(reservation)
        let source = WorkoutRegistrationSessionBindingSource(transport: runtime.transport, lifecycle: runtime.probe)
        await runtime.probe.holdNextBeginReturn()
        let pending = Task {
            do {
                let value = try await source.bind(binding)
                await runtime.probe.beginReturn.noteCompletion()
                return value
            } catch {
                await runtime.probe.beginReturn.noteCompletion()
                throw error
            }
        }
        var first: Task<Void, Never>?
        var second: Task<Void, Never>?
        do {
            let entered = await runtime.probe.beginReturn.waitUntilEnteredOrCompleted()
            try #require(entered, "Binding must subscribe through the real beginPatientWork API")
            let admitted = await runtime.probe.admittedIDs
            try #require(admitted.count == 1)
            #expect(await runtime.registry.activeCount == 1)
            _ = lifetime.beginAuthenticationBoundary()
            #expect(!binding.isOpen)
            #expect(binding.readyContext == nil)
            let ends = C11ConcurrentEndProbe()
            let one = Task { @MainActor in ends.didStart(); await binding.endSession(); ends.didFinish() }
            let two = Task { @MainActor in ends.didStart(); await binding.endSession(); ends.didFinish() }
            first = one; second = two
            await ends.waitForBothStarts()
            #expect(ends.finishedCount == 0)
            await runtime.probe.beginReturn.release()
            await #expect(throws: CancellationError.self) { _ = try await pending.value }
            await one.value
            await two.value
            #expect(ends.finishedCount == 2)
            #expect(await runtime.probe.finishedIDs == admitted)
            #expect(await runtime.registry.activeCount == 0)
            #expect(await runtime.stub.requests().isEmpty)
            await binding.endSession()
            #expect(await runtime.probe.finishedIDs == admitted)
            await lifetime.endSession()
            await owner.endSession()
        } catch {
            await runtime.releaseAll()
            _ = await pending.result
            await first?.value
            await second?.value
            await lifetime.endSession()
            await owner.endSession()
            throw error
        }
    }
}

enum H2WorkoutCall: Sendable { case propose, edit, confirm, cancel, get }

private let h2RegistrationID = "11111111-1111-4111-8111-111111111111"
private let h2Draft = WorkoutProposalRequest(workoutType: "Natação", durationMin: 47, intensity: .high,
    performedAt: APITimestamp(value: Date(timeIntervalSince1970: 1_790_000_321)))
private let h2EditedDraft = WorkoutProposalRequest(workoutType: "Remo indoor", durationMin: 61, intensity: .light,
    performedAt: APITimestamp(value: Date(timeIntervalSince1970: 1_790_000_654)))
private struct H2UnexpectedRequest: Error {}

private func h2Me(owner: String, advertised: String) throws -> Data {
    var row: [String: Any] = ["id": owner, "timezone": "America/Sao_Paulo"]
    if advertised != "absent" { row["workout_registration_protocol"] = advertised }
    return try JSONSerialization.data(withJSONObject: ["data": row,
        "meta": ["api_version": "v1", "request_id": "s17h2-me-synthetic"]], options: [.sortedKeys])
}

// `/me.id` belongs to the patient row, while leases and authentication
// activations belong to Supabase Auth. The server permits these UUIDs to differ.
private let h2DistinctPatientID = "00000000-0000-4000-8000-000000000001"

private func h2PatientMe(timezone: String, advertised: String = "absent") throws -> Data {
    var row: [String: Any] = ["id": h2DistinctPatientID, "timezone": timezone]
    if advertised != "absent" { row["workout_registration_protocol"] = advertised }
    return try JSONSerialization.data(withJSONObject: ["data": row,
        "meta": ["api_version": "v1", "request_id": "m1-distinct-patient-me"]], options: [.sortedKeys])
}
private func h2Projection(revision: Int = 0, status: String = "pending", duration: Int = 47,
    receiptKey: String? = nil, confirmation: Bool = false) throws -> Data {
    var row: [String: Any] = ["id": h2RegistrationID, "status": status,
        "created_at": "2026-10-15T15:00:00.123456+00:00", "expires_at": "2026-10-16T15:00:00.123456+00:00",
        "resolved_at": status == "pending" ? NSNull() as Any : "2026-10-15T15:01:00.123456+00:00" as Any,
        "workout_protocol": "ui-v1", "content_revision": revision,
        "proposal": ["kind": "workout", "workout_type": duration == 47 ? "Natação" : "Remo indoor",
            "duration_min": duration, "estimated_kcal": 333, "intensity": duration == 47 ? "alta" : "leve"]]
    if let receiptKey { row["receipt"] = ["requestKey": receiptKey, "expectedRevision": 0, "resultRevision": 1] }
    if confirmation { row["already_confirmed"] = false; row["deduped"] = false }
    return try JSONSerialization.data(withJSONObject: ["data": row,
        "meta": ["api_version": "v1", "request_id": "s17h2-registration-synthetic"]], options: [.sortedKeys])
}

@MainActor
private struct H2WireFixture {
    let wire: C11RealLifecycleTransportHarness
    let counted: C11RootCountingLifecycle
    let source: WorkoutRegistrationSessionBindingSource
    let lifetime: MealRecordAuthenticationLifetime
    let activation: MealRecordAuthenticatedActivation
    let owner: Prompt14SessionOwner
    func reserve(activation incoming: MealRecordAuthenticatedActivation? = nil) throws -> WorkoutRegistrationSessionBinding {
        let lifetime = self.lifetime
        let reservation = owner.reserveWorkoutRegistrationBinding(activation: incoming ?? activation,
            lifetime: lifetime, currentActivation: { lifetime.currentActivation })
        return try #require(reservation)
    }
    func end() async {
        await wire.lifecycle.leaseHold.release()
        await wire.lifecycle.finishHold.release()
        await wire.lifecycle.visibleReturnHold.release()
        await lifetime.endSession()
        await owner.endSession()
    }
}

@MainActor
private func h2WithWire(_ body: (H2WireFixture) async throws -> Void) async throws {
    let wire = try await C11RealLifecycleTransportHarness()
    let lifetime = MealRecordAuthenticationLifetime()
    let ticket = lifetime.beginAuthenticationBoundary()
    let activation = try #require(lifetime.publishAuthenticated(userID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", ticket: ticket))
    let owner = Prompt14SessionOwner(userID: activation.userID, dependencies: C11BindingTestDependencies.make())
    await owner.awaitPatientTimeZoneResolution()
    let counted = C11RootCountingLifecycle(base: wire.lifecycle)
    let source = WorkoutRegistrationSessionBindingSource(transport: wire.transport, lifecycle: counted)
    let fixture = H2WireFixture(wire: wire, counted: counted, source: source, lifetime: lifetime, activation: activation, owner: owner)
    do { try await body(fixture); await fixture.end() }
    catch { await fixture.end(); throw error }
}

private func h2Invoke(_ call: H2WorkoutCall, provider: any RegistrationProviding & WorkoutRegistrationReading) async throws {
    let key = try IdempotencyKey(validating: H2WorkoutKeys.literal(1))
    let version = WorkoutRegistrationVersion(contentRevision: 0)!
    let at = C11OwnerFixtureTime().now
    switch call {
    case .propose:
        let request = WorkoutProposalRequest(workoutType: h2Draft.workoutType, durationMin: h2Draft.durationMin,
            intensity: h2Draft.intensity, performedAt: h2Draft.performedAt, registrationProtocol: .uiV1)
        _ = try await provider.propose(MutationAttempt(operation: .proposalCreate, key: key, payload: .workout(request), createdAt: at))
    case .edit:
        _ = try await provider.edit(MutationAttempt(operation: .proposalEdit, key: key,
            payload: RegistrationEditCommand(registrationID: h2RegistrationID, proposal: .workout(h2EditedDraft), workoutVersion: version), createdAt: at))
    case .confirm:
        _ = try await provider.confirm(MutationAttempt(operation: .proposalConfirm, key: key,
            payload: RegistrationIDCommand(registrationID: h2RegistrationID, workoutVersion: version), createdAt: at))
    case .cancel:
        _ = try await provider.cancel(MutationAttempt(operation: .proposalCancel, key: key,
            payload: RegistrationIDCommand(registrationID: h2RegistrationID, workoutVersion: version), createdAt: at))
    case .get: _ = try await provider.loadWorkoutRegistration(id: h2RegistrationID)
    }
}

private final class H2WorkoutKeys: IdempotencyKeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var issued = 0
    static func literal(_ value: Int) -> String {
        let tail = String(value, radix: 16, uppercase: true)
        return "A17F0000-0000-4000-8000-" + String(repeating: "0", count: 12 - tail.count) + tail
    }
    func nextKey() throws -> IdempotencyKey {
        try lock.withLock { issued += 1; return try IdempotencyKey(validating: Self.literal(issued)) }
    }
}

// Holds only the delivery of an ACTUAL provider result (including its catch).
// It does not decide authority, manufacture HTTP results or replace the real
// registration repository / session / transport / ticket / registry.
private actor H2CompletedEditHold: RegistrationProviding, WorkoutRegistrationReading {
    let completed = C11I5BindingCheckpoint()
    private let base: any RegistrationProviding & WorkoutRegistrationReading
    init(base: any RegistrationProviding & WorkoutRegistrationReading) { self.base = base }
    func propose(_ attempt: MutationAttempt<RegistrationProposalRequest>) async throws -> RegistrationProposalResponse { try await base.propose(attempt) }
    func edit(_ attempt: MutationAttempt<RegistrationEditCommand>) async throws -> RegistrationProposalResponse {
        let result: Result<RegistrationProposalResponse, any Error>
        do { result = .success(try await base.edit(attempt)) } catch { result = .failure(error) }
        await completed.enterAndWait()
        return try result.get()
    }
    func confirm(_ attempt: MutationAttempt<RegistrationIDCommand>) async throws -> RegistrationConfirmationResponse { try await base.confirm(attempt) }
    func cancel(_ attempt: MutationAttempt<RegistrationIDCommand>) async throws -> RegistrationCancellationResponse { try await base.cancel(attempt) }
    func loadWorkoutRegistration(id: String) async throws -> RegistrationProposalResponse { try await base.loadWorkoutRegistration(id: id) }
}

extension MobileAPITransportTests {
    @MainActor
    @Test("H2: ending the workout leaf preserves meal editing; the shared auth boundary withdraws both")
    func h2WorkoutAndMealLeavesRemainIndependent() async throws {
        try await h2WithWire { fixture in
            let owner = Prompt14SessionOwner(userID: fixture.activation.userID,
                dependencies: C11BindingTestDependencies.make(), enablesMealRecordBinding: true)
            await owner.awaitPatientTimeZoneResolution()
            do {
                let meal = try #require(owner.mealRecordBinding)
                try #require(fixture.lifetime.register(binding: meal, owner: owner, activation: fixture.activation))
                let mealProvider = try await meal.bind(transport: fixture.wire.transport, lifecycle: fixture.counted)
                let me = try h2Me(owner: fixture.activation.userID, advertised: "ui-v1")
                let detail = try JSONEncoder().encode(C11RealLifecycleTransportHarness.detail())
                await fixture.wire.stub.respond { request, _ in
                    switch request.url?.path {
                    case "/api/mobile/v1/me": return StubResponse(status: 200, body: me)
                    case "/api/mobile/v1/meal-records/\(h2RegistrationID)": return StubResponse(status: 200, body: detail)
                    default: throw H2UnexpectedRequest()
                    }
                }
                let lifetime = fixture.lifetime
                let reservation = owner.reserveWorkoutRegistrationBinding(activation: fixture.activation,
                    lifetime: lifetime, currentActivation: { lifetime.currentActivation })
                let workout = try #require(reservation)
                let context = try await fixture.source.bind(workout)
                #expect(context.isActive)
                #expect(meal.isOpen)
                await workout.endSession()
                #expect(!context.isActive)
                #expect(!owner.isInvalidated)
                #expect(meal.isOpen)
                let response = try await mealProvider.mealRecord(id: h2RegistrationID)
                #expect(response.data.recordID == h2RegistrationID)
                _ = lifetime.beginAuthenticationBoundary()
                #expect(!meal.isOpen)
                #expect(!workout.isOpen)
                let before = await fixture.wire.stub.requests().count
                await #expect(throws: CancellationError.self) { _ = try await mealProvider.mealRecord(id: h2RegistrationID) }
                #expect(await fixture.wire.stub.requests().count == before)
                await owner.endSession()
            } catch {
                await owner.endSession()
                throw error
            }
        }
    }
}

extension MobileAPITransportTests {
    @MainActor
    @Test("H2: a new ticket binds through the real owner wrapper while the old lease resolver is still pending")
    func h2OwnerCannotLoseTheNewTicketBehindOldResolution() async throws {
        try await h2WithWire { fixture in
            var dependencies = C11BindingTestDependencies.make()
            dependencies.workoutRegistrationSessionSource = fixture.source
            let owner = Prompt14SessionOwner(userID: fixture.activation.userID, dependencies: dependencies)
            let lifetime = fixture.lifetime
            let firstReservation = owner.reserveWorkoutRegistrationBinding(activation: fixture.activation,
                lifetime: lifetime, currentActivation: { lifetime.currentActivation })
            let first = try #require(firstReservation)
            let starts = C11ConcurrentEndProbe()
            await fixture.wire.lifecycle.holdNextLease(completeEvenIfCancelled: true)
            let oldTask = Task {
                starts.didStart()
                await owner.resolveWorkoutRegistration(first)
                await fixture.wire.lifecycle.leaseHold.noteCompletion()
            }
            var newTask: Task<Void, Never>?
            do {
                let entered = await fixture.wire.lifecycle.leaseHold.waitUntilEnteredOrCompleted()
                try #require(entered)
                let ticket = lifetime.beginAuthenticationBoundary()
                let activation = try #require(lifetime.publishAuthenticated(userID: fixture.activation.userID, ticket: ticket))
                let me = try h2Me(owner: activation.userID, advertised: "ui-v1")
                await fixture.wire.stub.respond(with: StubResponse(status: 200, body: me))
                let nextReservation = owner.reserveWorkoutRegistrationBinding(activation: activation,
                    lifetime: lifetime, currentActivation: { lifetime.currentActivation })
                let next = try #require(nextReservation)
                let task = Task {
                    starts.didStart()
                    await owner.resolveWorkoutRegistration(next)
                }
                newTask = task
                await starts.waitForBothStarts()
                await fixture.wire.lifecycle.leaseHold.release()
                await oldTask.value
                await task.value
                #expect(owner.workoutRegistrationContext?.activation == activation)
                #expect(owner.workoutRegistrationContext?.isActive == true)
                #expect(!owner.isResolvingWorkoutRegistration)
                #expect(first.readyContext == nil)
                #expect(await fixture.wire.stub.requests().count == 1)
                await owner.endSession()
            } catch {
                await fixture.wire.lifecycle.leaseHold.release()
                await oldTask.value
                await newTask?.value
                await owner.endSession()
                throw error
            }
        }
    }

    @MainActor
    @Test("H2: foreground recovers an offline initial Me on its retained scope without a workout-sheet visit")
    func h2ForegroundRestoresTheDocumentedTimeZoneAfterOfflineMe() async throws {
        try await h2WithWire { fixture in
            var dependencies = C11BindingTestDependencies.make()
            dependencies.workoutRegistrationSessionSource = fixture.source
            let owner = Prompt14SessionOwner(userID: fixture.activation.userID, dependencies: dependencies)
            let lifetime = fixture.lifetime
            let reservation = owner.reserveWorkoutRegistrationBinding(activation: fixture.activation,
                lifetime: lifetime, currentActivation: { lifetime.currentActivation })
            let binding = try #require(reservation)
            do {
                await fixture.wire.stub.respond(with: .failure(status: 503, code: "internal_error"))
                await owner.resolveWorkoutRegistration(binding)
                #expect(binding.canRetryMe)
                #expect(!dependencies.patientTimeZoneStore.isSettled)
                #expect(owner.workoutRegistrationContext == nil)
                let me = try h2Me(owner: fixture.activation.userID, advertised: "ui-v1")
                await fixture.wire.stub.respond(with: StubResponse(status: 200, body: me))
                await owner.refreshPatientTimeZone()
                #expect(dependencies.patientTimeZone.documentedIANAIdentifier == "America/Sao_Paulo")
                #expect(dependencies.patientTimeZoneStore.isSettled)
                #expect(owner.workoutRegistrationContext?.isActive == true)
                #expect(owner.workoutRegistrationContext?.registrationProtocol == .uiV1)
                #expect(await fixture.wire.stub.requests().count == 2)
                #expect(await fixture.counted.leaseCalls == 1)
                let originalContext = owner.workoutRegistrationContext
                let laterMe = try h2Me(owner: fixture.activation.userID, advertised: "ui-v2")
                await fixture.wire.stub.respond(with: StubResponse(status: 200, body: laterMe))
                await owner.refreshPatientTimeZone()
                #expect(owner.workoutRegistrationContext === originalContext)
                #expect(owner.workoutRegistrationContext?.registrationProtocol == .uiV1)
                #expect(await fixture.wire.stub.requests().count == 3)
                await owner.endSession()
            }
        }
    }

    @MainActor
    @Test("M1 physical regression: a patient UUID distinct from Auth opens workout; A-B-A retires its original capability",
          arguments: ["absent", "ui-v1"])
    func m1DistinctPatientIDOpensWorkoutWithoutRenewingRetiredAuth(advertised: String) async throws {
        try await h2WithWire { fixture in
            #expect(fixture.activation.userID != h2DistinctPatientID)
            var dependencies = C11BindingTestDependencies.make()
            dependencies.workoutRegistrationSessionSource = fixture.source
            let owner = Prompt14SessionOwner(userID: fixture.activation.userID, dependencies: dependencies)
            await owner.awaitPatientTimeZoneResolution()
            let lifetime = fixture.lifetime
            let reservation = owner.reserveWorkoutRegistrationBinding(activation: fixture.activation,
                lifetime: lifetime, currentActivation: { lifetime.currentActivation })
            let binding = try #require(reservation)
            do {
                let me = try h2PatientMe(timezone: "America/Sao_Paulo", advertised: advertised)
                await fixture.wire.stub.respond(with: StubResponse(status: 200, body: me))
                await owner.resolveWorkoutRegistration(binding)
                #expect(owner.workoutRegistrationError == nil)
                let context = try #require(owner.workoutRegistrationContext,
                    "A successful patient /me must make the real-account workout form available")
                #expect(context.isActive)
                #expect(context.registrationProtocol == (advertised == "ui-v1" ? .uiV1 : nil))
                #expect(dependencies.patientTimeZone.documentedIANAIdentifier == "America/Sao_Paulo")
                #expect(binding.capturedLease?.userID == fixture.activation.userID)
                #expect(await fixture.counted.leaseCalls == 1)
                let requests = await fixture.wire.stub.requests()
                #expect(requests.count == 1)
                #expect(requests.first?.httpMethod == "GET")
                #expect(requests.first?.url?.path == "/api/mobile/v1/me")

                try await fixture.wire.replaceSession(returnToA: true)
                #expect(!context.isActive)
                #expect(owner.workoutRegistrationContext == nil)
                await #expect(throws: CancellationError.self) {
                    _ = try await context.provider.loadWorkoutRegistration(id: h2RegistrationID)
                }
                #expect(await fixture.wire.stub.requests().count == 1)
                await owner.endSession()
            } catch {
                await owner.endSession()
                throw error
            }
        }
    }

    @MainActor
    @Test("M1 physical regression: explicit workout GET retry accepts the documented patient ID on the original auth lease")
    func m1DistinctPatientIDRecoversThroughWorkoutRetry() async throws {
        try await h2WithWire { fixture in
            var dependencies = C11BindingTestDependencies.make()
            dependencies.workoutRegistrationSessionSource = fixture.source
            let owner = Prompt14SessionOwner(userID: fixture.activation.userID, dependencies: dependencies)
            await owner.awaitPatientTimeZoneResolution()
            let lifetime = fixture.lifetime
            let reservation = owner.reserveWorkoutRegistrationBinding(activation: fixture.activation,
                lifetime: lifetime, currentActivation: { lifetime.currentActivation })
            let binding = try #require(reservation)
            do {
                await fixture.wire.stub.respond(with: .failure(status: 503, code: "internal_error"))
                await owner.resolveWorkoutRegistration(binding)
                #expect(owner.workoutRegistrationContext == nil)
                #expect(binding.canRetryMe)
                let lease = try #require(binding.capturedLease)
                let me = try h2PatientMe(timezone: "Pacific/Tahiti")
                await fixture.wire.stub.respond(with: StubResponse(status: 200, body: me))
                await owner.resolveWorkoutRegistration(binding, retrying: true)
                #expect(owner.workoutRegistrationError == nil)
                #expect(owner.workoutRegistrationContext?.isActive == true)
                #expect(dependencies.patientTimeZone.documentedIANAIdentifier == "Pacific/Tahiti")
                #expect(binding.capturedLease == lease)
                #expect(await fixture.counted.leaseCalls == 1)
                let requests = await fixture.wire.stub.requests()
                #expect(requests.count == 2)
                #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.url?.path == "/api/mobile/v1/me" })
                await owner.endSession()
            } catch {
                await owner.endSession()
                throw error
            }
        }
    }

    @MainActor
    @Test("M1: foreground refresh keeps the patient timezone current without changing the visible workout protocol")
    func m1DistinctPatientIDRefreshesTimezoneOnItsOriginalScope() async throws {
        try await h2WithWire { fixture in
            let dependencies = C11BindingTestDependencies.make()
            let owner = Prompt14SessionOwner(userID: fixture.activation.userID, dependencies: dependencies)
            await owner.awaitPatientTimeZoneResolution()
            let lifetime = fixture.lifetime
            let reservation = owner.reserveWorkoutRegistrationBinding(activation: fixture.activation,
                lifetime: lifetime, currentActivation: { lifetime.currentActivation })
            let binding = try #require(reservation)
            do {
                let me = try h2PatientMe(timezone: "America/Sao_Paulo", advertised: "ui-v1")
                await fixture.wire.stub.respond(with: StubResponse(status: 200, body: me))
                let context = try await fixture.source.bind(binding)
                let refreshed = try h2PatientMe(timezone: "Pacific/Tahiti", advertised: "ui-v2")
                await fixture.wire.stub.respond(with: StubResponse(status: 200, body: refreshed))
                await binding.refreshPatientTimeZone()
                #expect(dependencies.patientTimeZone.documentedIANAIdentifier == "Pacific/Tahiti")
                #expect(binding.readyContext === context)
                #expect(context.isActive)
                #expect(context.registrationProtocol == .uiV1)
                #expect(await fixture.counted.leaseCalls == 1)
                #expect(await fixture.wire.stub.requests().count == 2)
                await owner.endSession()
            } catch {
                await owner.endSession()
                throw error
            }
        }
    }

    @MainActor
    @Test("M1: accepting a distinct patient UUID does not admit an empty Me identity")
    func m1EmptyPatientIDDoesNotPublishWorkoutContext() async throws {
        try await h2WithWire { fixture in
            let me = try h2Me(owner: "", advertised: "ui-v1")
            await fixture.wire.stub.respond(with: StubResponse(status: 200, body: me))
            let binding = try fixture.reserve()
            await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
                _ = try await fixture.source.bind(binding)
            }
            #expect(binding.readyContext == nil)
            #expect(binding.canRetryMe)
            #expect(await fixture.wire.stub.requests().count == 1)
        }
    }
}

// P10D2 uses the existing serialized real lifecycle/URLProtocol harness.
extension MobileAPITransportTests {
    @MainActor
    @Test("P10D2: clarification GET/POST share the admitted scope and 401 keeps tuple and key", arguments: [WorkoutStrengthAnswer.yes, .no])
    func p10d2ClarificationSharesOriginalScope(answer: WorkoutStrengthAnswer) async throws {
        try await h2WithWire { fixture in
            let wire = fixture.wire
            let me = try h2Me(owner: fixture.activation.userID, advertised: "ui-v1")
            let question = try p10d2StrengthQuestion()
            let read = try p10d2StrengthWire(.unanswered(question))
            let accepted = try p10d2StrengthWire(.answered(try #require(WorkoutStrengthAnswerReceipt(
                scope: question.scope, questionKey: question.questionKey, answer: answer,
                acceptedAt: "2026-10-21T01:02:03.123456Z"))))
            let bodies = C11RequestBodyCapture()
            await wire.stub.respond { request, call in
                if request.url?.path == "/api/mobile/v1/me" { return StubResponse(status: 200, body: me) }
                guard request.url?.path == p10d2StrengthPath else { throw H2UnexpectedRequest() }
                if request.httpMethod == "GET" { return StubResponse(status: 200, body: read) }
                guard request.httpMethod == "POST" else { throw H2UnexpectedRequest() }
                try await bodies.capture(request)
                return call == 3 ? .failure(status: 401, code: "expired_token") : StubResponse(status: 200, body: accepted)
            }
            let binding = try fixture.reserve()
            #expect(binding.readyContext == nil)
            let context = try await fixture.source.bind(binding)
            let original = try #require(binding.capturedLease)
            let response = try await context.clarificationProvider.load(workoutID: question.scope.workoutID)
            #expect(response.data == .unanswered(question))
            let attempt = MutationAttempt(operation: .workoutStrengthAnswer,
                key: try IdempotencyKey(validating: H2WorkoutKeys.literal(9)),
                payload: WorkoutStrengthAnswerCommand(question: question, answer: answer),
                createdAt: C11OwnerFixtureTime().now)
            let result = try await context.clarificationProvider.answer(attempt)
            guard case let .answered(receipt) = result.data else { Issue.record("Expected official receipt"); return }
            #expect(receipt.scope == question.scope)
            #expect(receipt.answer == answer)
            #expect(context.isActive)
            #expect(await fixture.counted.leaseCalls == 1)
            #expect(await wire.remote.refreshCount == 1)
            let current = try await wire.coordinator.leaseForRequest()
            #expect(current.generation == original.generation)
            let requests = await wire.stub.requests()
            try #require(requests.count == 4)
            #expect(requests[1].httpMethod == "GET")
            #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer \(original.bearer)")
            #expect(requests[1].value(forHTTPHeaderField: "Idempotency-Key") == nil)
            #expect(requests[2].value(forHTTPHeaderField: "Authorization") != requests[3].value(forHTTPHeaderField: "Authorization"))
            for request in requests.suffix(2) {
                #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == attempt.key.value)
                #expect(request.httpMethod == "POST")
            }
            let captured = await bodies.bodies()
            try #require(captured.count == 2)
            #expect(captured[0] == captured[1])
            let body = try #require(captured[0])
            let object = try #require(JSONSerialization.jsonObject(with: body) as? NSDictionary)
            #expect(object == ["expected_lifecycle_key": question.scope.lifecycleKey,
                "expected_fact_revision": 0, "question_key": question.questionKey, "answer": answer.rawValue] as NSDictionary)
            binding.invalidateSynchronously()
            #expect(!binding.hasRetainedCapability)
            #expect(!context.isActive)
            await #expect(throws: CancellationError.self) {
                _ = try await context.clarificationProvider.load(workoutID: question.scope.workoutID)
            }
            #expect(await wire.stub.requests().count == 4)
            await binding.endSession()
            await binding.endSession()
            let workIDs = await fixture.counted.workoutWorkIDs
            #expect(workIDs.count == 1)
            #expect(await fixture.counted.finishedWorkoutWorkIDs == workIDs)
            #expect(await wire.registry.activeCount == 0)
        }
    }

    @MainActor
    @Test("P10D2: retained clarification read and write cannot send after A to B to A", arguments: [false, true])
    func p10d2ClarificationCannotBorrowNewActivation(write: Bool) async throws {
        try await h2WithWire { fixture in
            let me = try h2Me(owner: fixture.activation.userID, advertised: "ui-v1")
            await fixture.wire.stub.respond(with: StubResponse(status: 200, body: me))
            let context = try await fixture.source.bind(fixture.reserve())
            let question = try p10d2StrengthQuestion()
            _ = fixture.lifetime.beginAuthenticationBoundary()
            try await fixture.wire.replaceSession(returnToA: true)
            #expect(!context.isActive)
            await #expect(throws: CancellationError.self) {
                if write {
                    _ = try await context.clarificationProvider.answer(MutationAttempt(operation: .workoutStrengthAnswer,
                        key: IdempotencyKey(validating: H2WorkoutKeys.literal(9)),
                        payload: WorkoutStrengthAnswerCommand(question: question, answer: .yes), createdAt: C11OwnerFixtureTime().now))
                } else { _ = try await context.clarificationProvider.load(workoutID: question.scope.workoutID) }
            }
            #expect(await fixture.wire.stub.requests().count == 1)
            #expect(await fixture.counted.leaseCalls == 1)
            #expect(await fixture.wire.remote.refreshCount == 0)
        }
    }

    @MainActor
    @Test("P10D2: a late clarification transport error becomes cancellation and end drains its scope")
    func p10d2ClarificationLateErrorAndDrain() async throws {
        try await h2WithWire { fixture in
            let wire = fixture.wire
            let me = try h2Me(owner: fixture.activation.userID, advertised: "ui-v1")
            await wire.stub.respond(with: StubResponse(status: 200, body: me))
            let binding = try fixture.reserve()
            let context = try await fixture.source.bind(binding)
            await wire.stub.respond { request, _ in
                guard request.url?.path == p10d2StrengthPath else { throw H2UnexpectedRequest() }
                throw URLError(.timedOut)
            }
            await wire.lifecycle.holdNextFinish()
            let pending = Task {
                do {
                    let result = try await context.clarificationProvider.load(workoutID: h2RegistrationID)
                    await wire.lifecycle.finishHold.noteCompletion()
                    return result
                } catch {
                    await wire.lifecycle.finishHold.noteCompletion()
                    throw error
                }
            }
            var ending: Task<Void, Never>?
            var endingAgain: Task<Void, Never>?
            do {
                let entered = await wire.lifecycle.finishHold.waitUntilEnteredOrCompleted()
                try #require(entered)
                #expect(await wire.stub.requests().count == 2)
                _ = fixture.lifetime.beginAuthenticationBoundary()
                #expect(!context.isActive)
                let endProbe = C11ConcurrentEndProbe()
                let end = Task { @MainActor in endProbe.didStart(); await binding.endSession(); endProbe.didFinish() }
                ending = end
                let secondEnd = Task { @MainActor in endProbe.didStart(); await binding.endSession(); endProbe.didFinish() }
                endingAgain = secondEnd
                await endProbe.waitForBothStarts()
                #expect(endProbe.finishedCount == 0)
                await wire.lifecycle.finishHold.release()
                await #expect(throws: CancellationError.self) { _ = try await pending.value }
                await end.value
                await secondEnd.value
                #expect(endProbe.finishedCount == 2)
                let workIDs = await fixture.counted.workoutWorkIDs
                #expect(workIDs.count == 1)
                #expect(await fixture.counted.finishedWorkoutWorkIDs == workIDs)
                #expect(await wire.registry.activeCount == 0)
                #expect(!binding.hasRetainedCapability)
                #expect(await fixture.counted.leaseCalls == 1)
                #expect(await wire.stub.requests().count == 2)
            } catch {
                await wire.lifecycle.finishHold.release()
                _ = await pending.result
                await ending?.value
                await endingAgain?.value
                throw error
            }
        }
    }
}

private let p10d2StrengthPath = "/api/mobile/v1/workouts/\(h2RegistrationID)/strength-clarification"
private func p10d2StrengthQuestion() throws -> WorkoutStrengthQuestion {
    try #require(WorkoutStrengthQuestion(workoutID: h2RegistrationID,
        lifecycleKey: "c3900000-0000-4000-8000-000000000001", factRevision: 0,
        questionKey: "d4a00000-0000-4000-8000-000000000001"))
}
private func p10d2StrengthWire(_ value: WorkoutStrengthClarification) throws -> Data {
    try JSONEncoder().encode(MobileResponse(data: value,
        meta: MobileResponseMetadata(apiVersion: "v1", requestID: "synthetic-owned-question")))
}
