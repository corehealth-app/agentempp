import Foundation
import Testing

@testable import BodyFlow

@Suite("Billing SDK ownership")
struct BillingSDKCoordinatorTests {
    private let patientA = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let patientB = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

    @Test("missing or non-Apple public configuration never configures the SDK")
    func disabledWithoutConfiguration() async {
        for value in [nil, "", " ", "$(REVENUECAT_KEY)", "sk_private", "test_other_store", "appl_", "appl_a b"] as [String?] {
            #expect(BillingConfiguration(publicAPIKey: value) == nil)
        }
        let sdk = BillingSDKBoundary()
        let coordinator = BillingSDKCoordinator(configuration: nil, driver: sdk)
        await #expect(throws: BillingStoreError.configurationUnavailable) {
            try await coordinator.offers(for: BillingSessionGrant(patientID: patientA, authorize: {}))
        }
        #expect(await sdk.events.isEmpty)
    }

    @Test("catalog uses the SDK's localized metadata and one configuration for the original patient")
    func catalogAndSelection() async throws {
        let sdk = BillingSDKBoundary()
        let coordinator = try coordinator(sdk)
        let grant = BillingSessionGrant(patientID: patientA, authorize: {})
        let first = try await coordinator.offers(for: grant)
        #expect(first.products.map(\.localizedPrice) == ["localized-store-price"])
        #expect(first.products.first?.title == "Store product title")
        let latest = try await coordinator.offers(for: grant)
        #expect(first.revision != latest.revision)
        await #expect(throws: BillingStoreError.invalidSelection) {
            try await coordinator.purchase(productID: "qa-monthly", catalogRevision: first.revision, for: grant)
        }
        let outcome = try await coordinator.purchase(productID: "qa-monthly", catalogRevision: latest.revision, for: grant)
        #expect(outcome == .completed)
        await #expect(throws: BillingStoreError.invalidSelection) {
            try await coordinator.purchase(productID: "qa-monthly", catalogRevision: latest.revision, for: grant)
        }
        #expect(await sdk.events == ["configure:\(patientA)", "offers", "offers", "purchase-start", "purchase-end"])
    }

    @Test("an old owner's teardown cannot log out its replacement")
    func oldReleaseDoesNotLogOutNewOwner() async throws {
        let sdk = BillingSDKBoundary()
        let coordinator = try coordinator(sdk)
        let old = BillingSessionGrant(patientID: patientA, authorize: {})
        _ = try await coordinator.offers(for: old)
        old.close()
        let new = BillingSessionGrant(patientID: patientB, authorize: {})
        _ = try await coordinator.offers(for: new)
        try await coordinator.release(old)
        #expect(await sdk.events == ["configure:\(patientA)", "offers", "login:\(patientB)", "offers"])
        try await coordinator.release(new)
        #expect(await sdk.events.last == "logout")
    }

    @Test("a new ticket for the same patient withdraws the old catalog")
    func samePatientNewTicket() async throws {
        let sdk = BillingSDKBoundary()
        let coordinator = try coordinator(sdk)
        let old = BillingSessionGrant(patientID: patientA, authorize: {})
        let first = try await coordinator.offers(for: old)
        old.close()
        let replacement = BillingSessionGrant(patientID: patientA, authorize: {})
        let next = try await coordinator.offers(for: replacement)
        #expect(first.revision != next.revision)
        await #expect(throws: BillingStoreError.invalidSelection) {
            try await coordinator.purchase(productID: "qa-monthly", catalogRevision: first.revision, for: replacement)
        }
        try await coordinator.release(old)
        #expect(await sdk.events == ["configure:\(patientA)", "offers", "login:\(patientA)", "offers"])
    }

    @Test("ended or unauthorized sessions cannot reach the SDK")
    func closedGrantIsDenied() async throws {
        let sdk = BillingSDKBoundary()
        let coordinator = try coordinator(sdk)
        let grant = BillingSessionGrant(patientID: patientA, authorize: {})
        grant.close()
        await #expect(throws: CancellationError.self) { try await coordinator.offers(for: grant) }
        let stale = BillingSessionGrant(patientID: patientA, authorize: { throw CancellationError() })
        await #expect(throws: CancellationError.self) { try await coordinator.restore(for: stale) }
        #expect(await sdk.events.isEmpty)
    }

    @Test("cancelling a purchase keeps SDK ownership until its real callback completes")
    func cancellationWaitsForSDKCallback() async throws {
        let sdk = BillingSDKBoundary()
        let coordinator = try coordinator(sdk)
        let grantA = BillingSessionGrant(patientID: patientA, authorize: {})
        let catalog = try await coordinator.offers(for: grantA)
        await sdk.holdPurchase()
        let purchase = Task { try await coordinator.purchase(productID: "qa-monthly", catalogRevision: catalog.revision, for: grantA) }
        await sdk.purchaseLatch.waitUntilEntered()
        purchase.cancel()
        grantA.close()
        let bEligible = BillingTestSignal()
        let grantB = BillingSessionGrant(patientID: patientB, authorize: { await bEligible.signal() })
        let replacement = Task { try await coordinator.offers(for: grantB) }
        await bEligible.wait()
        await sdk.purchaseLatch.release()
        await #expect(throws: CancellationError.self) { try await purchase.value }
        _ = try await replacement.value
        try await coordinator.release(grantA)
        #expect(await sdk.events == ["configure:\(patientA)", "offers", "purchase-start", "purchase-end", "login:\(patientB)", "offers"])
    }

    @Test("closing a session during catalog loading rejects the late result")
    func lateCatalogCannotPublish() async throws {
        let sdk = BillingSDKBoundary()
        await sdk.holdOffers()
        let coordinator = try coordinator(sdk)
        let grant = BillingSessionGrant(patientID: patientA, authorize: {})
        let load = Task { try await coordinator.offers(for: grant) }
        await sdk.offersLatch.waitUntilEntered()
        grant.close()
        await sdk.offersLatch.release()
        await #expect(throws: CancellationError.self) { try await load.value }
        try await coordinator.release(grant)
        #expect(await sdk.events.last == "logout")
    }

    @Test("a late SDK catalog error belongs to its retired session too")
    func lateCatalogFailureIsCancelled() async throws {
        let sdk = BillingSDKBoundary()
        await sdk.holdOffers()
        await sdk.failNext("offers")
        let coordinator = try coordinator(sdk)
        let grant = BillingSessionGrant(patientID: patientA, authorize: {})
        let load = Task { try await coordinator.offers(for: grant) }
        await sdk.offersLatch.waitUntilEntered()
        grant.close()
        await sdk.offersLatch.release()
        await #expect(throws: CancellationError.self) { try await load.value }
    }

    @Test("a late purchase error cannot become a store error for a retired owner")
    func latePurchaseFailureIsCancelled() async throws {
        let sdk = BillingSDKBoundary()
        let coordinator = try coordinator(sdk)
        let grant = BillingSessionGrant(patientID: patientA, authorize: {})
        let catalog = try await coordinator.offers(for: grant)
        await sdk.holdPurchase()
        await sdk.failNext("purchase")
        let purchase = Task { try await coordinator.purchase(productID: "qa-monthly", catalogRevision: catalog.revision, for: grant) }
        await sdk.purchaseLatch.waitUntilEntered()
        grant.close()
        await sdk.purchaseLatch.release()
        await #expect(throws: CancellationError.self) { try await purchase.value }
    }

    @Test("a failed login callback cannot publish an error after its activation ended")
    func lateLoginFailureIsCancelled() async throws {
        let sdk = BillingSDKBoundary()
        let coordinator = try coordinator(sdk)
        let first = BillingSessionGrant(patientID: patientA, authorize: {})
        _ = try await coordinator.offers(for: first)
        first.close()
        await sdk.holdLogin()
        await sdk.failNext("login")
        let next = BillingSessionGrant(patientID: patientB, authorize: {})
        let load = Task { try await coordinator.offers(for: next) }
        await sdk.loginLatch.waitUntilEntered()
        next.close()
        await sdk.loginLatch.release()
        await #expect(throws: CancellationError.self) { try await load.value }
        try await coordinator.release(next)
        #expect(await sdk.events.last == "logout")
    }

    @Test("pending, cancelled and completed store results do not become access grants", arguments: [
        BillingStoreOutcome.pending, .cancelled, .completed
    ])
    func storeOutcomes(_ outcome: BillingStoreOutcome) async throws {
        let sdk = BillingSDKBoundary(outcome: outcome)
        let coordinator = try coordinator(sdk)
        let grant = BillingSessionGrant(patientID: patientA, authorize: {})
        #expect(try await coordinator.restore(for: grant) == outcome)
        #expect(await sdk.events == ["configure:\(patientA)", "restore"])
    }

    @Test("failed configuration does not pretend that the SDK is initialized")
    func configureFailureRequiresConfiguration() async throws {
        let sdk = BillingSDKBoundary()
        await sdk.failNext("configure")
        let coordinator = try coordinator(sdk)
        let first = BillingSessionGrant(patientID: patientA, authorize: {})
        await #expect(throws: BillingStoreError.storeUnavailable) { try await coordinator.offers(for: first) }
        try await coordinator.release(first)
        _ = try await coordinator.offers(for: BillingSessionGrant(patientID: patientB, authorize: {}))
        #expect(await sdk.events == ["configure:\(patientA)", "configure:\(patientB)", "offers"])
    }

    @Test("an explicit retry after a failed login repeats login before loading products")
    func loginFailureRequiresLogin() async throws {
        let sdk = BillingSDKBoundary()
        let coordinator = try coordinator(sdk)
        let first = BillingSessionGrant(patientID: patientA, authorize: {})
        _ = try await coordinator.offers(for: first)
        first.close()
        let next = BillingSessionGrant(patientID: patientB, authorize: {})
        await sdk.failNext("login")
        await #expect(throws: BillingStoreError.storeUnavailable) { try await coordinator.offers(for: next) }
        _ = try await coordinator.offers(for: next)
        try await coordinator.release(first)
        #expect(await sdk.events == ["configure:\(patientA)", "offers", "login:\(patientB)", "login:\(patientB)", "offers"])
    }

    @Test("failed logout is reported and an old teardown cannot retry against a new owner")
    func logoutFailureCannotAffectReplacement() async throws {
        let sdk = BillingSDKBoundary()
        let coordinator = try coordinator(sdk)
        let first = BillingSessionGrant(patientID: patientA, authorize: {})
        _ = try await coordinator.offers(for: first)
        await sdk.failNext("logout")
        await #expect(throws: BillingStoreError.storeUnavailable) { try await coordinator.release(first) }
        let next = BillingSessionGrant(patientID: patientB, authorize: {})
        _ = try await coordinator.offers(for: next)
        try await coordinator.release(first)
        #expect(await sdk.events == ["configure:\(patientA)", "offers", "logout", "login:\(patientB)", "offers"])
    }

    @Test("A to B to A uses a new ownership token and rejects both retired grants")
    func returningPatientHasNewOwnership() async throws {
        let sdk = BillingSDKBoundary()
        let coordinator = try coordinator(sdk)
        let first = BillingSessionGrant(patientID: patientA, authorize: {})
        _ = try await coordinator.offers(for: first)
        first.close()
        let middle = BillingSessionGrant(patientID: patientB, authorize: {})
        _ = try await coordinator.offers(for: middle)
        middle.close()
        _ = try await coordinator.offers(for: BillingSessionGrant(patientID: patientA, authorize: {}))
        await #expect(throws: CancellationError.self) { try await coordinator.restore(for: first) }
        await #expect(throws: CancellationError.self) { try await coordinator.restore(for: middle) }
        try await coordinator.release(first)
        try await coordinator.release(middle)
        #expect(await sdk.events == ["configure:\(patientA)", "offers", "login:\(patientB)", "offers", "login:\(patientA)", "offers"])
    }

    private func coordinator(_ driver: BillingSDKBoundary) throws -> BillingSDKCoordinator {
        BillingSDKCoordinator(configuration: try #require(BillingConfiguration(publicAPIKey: "appl_synthetic_qa_public")), driver: driver)
    }
}

/// Only the external SDK boundary is replaced. Ownership and serialization are real.
private actor BillingSDKBoundary: BillingSDKDriving {
    private(set) var events: [String] = []
    let purchaseLatch = BillingTestLatch()
    let offersLatch = BillingTestLatch()
    let loginLatch = BillingTestLatch()
    private var holdsPurchase = false
    private var holdsOffers = false
    private var holdsLogin = false
    private var failures: Set<String> = []
    private let outcome: BillingStoreOutcome
    init(outcome: BillingStoreOutcome = .completed) { self.outcome = outcome }
    func holdPurchase() { holdsPurchase = true }
    func holdOffers() { holdsOffers = true }
    func holdLogin() { holdsLogin = true }
    func failNext(_ operation: String) { failures.insert(operation) }
    private func throwRequestedFailure(_ operation: String) throws {
        if failures.remove(operation) != nil { throw BillingStoreError.storeUnavailable }
    }
    func configure(publicAPIKey: String, patientID: UUID) throws { events.append("configure:\(patientID)"); try throwRequestedFailure("configure") }
    func logIn(patientID: UUID) async throws {
        events.append("login:\(patientID)")
        if holdsLogin { await loginLatch.suspend() }
        try throwRequestedFailure("login")
    }
    func logOut() throws { events.append("logout"); try throwRequestedFailure("logout") }
    func offers() async throws -> [BillingProduct] {
        events.append("offers")
        if holdsOffers { await offersLatch.suspend() }
        try throwRequestedFailure("offers")
        return [BillingProduct(id: "qa-monthly", title: "Store product title", localizedPrice: "localized-store-price", period: BillingSubscriptionPeriod(value: 1, unit: .month))]
    }
    func purchase(productID: String) async throws -> BillingStoreOutcome {
        events.append("purchase-start")
        if holdsPurchase { await purchaseLatch.suspend() }
        events.append("purchase-end")
        try throwRequestedFailure("purchase")
        return outcome
    }
    func restore() -> BillingStoreOutcome { events.append("restore"); return outcome }
}

private actor BillingTestSignal {
    private var signalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func signal() { signalled = true; let pending = waiters; waiters = []; pending.forEach { $0.resume() } }
    func wait() async { if !signalled { await withCheckedContinuation { waiters.append($0) } } }
}

private actor BillingTestLatch {
    private var entered = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<Void, Never>?
    func suspend() async {
        entered = true
        let waiters = entryWaiters; entryWaiters = []; waiters.forEach { $0.resume() }
        if !released { await withCheckedContinuation { continuation = $0 } }
    }
    func waitUntilEntered() async { if !entered { await withCheckedContinuation { entryWaiters.append($0) } } }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
