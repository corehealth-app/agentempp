import Foundation
import Testing

@testable import BodyFlow

@MainActor
@Suite("Billing plans BFF reconciliation")
struct BillingPlansModelTests {
    @Test("only an explicit unambiguous DEBUG UI selection installs the synthetic source")
    func fixtureGate() throws {
        #expect(BillingUISelection.resolve(arguments: ["--ui-testing-billing-sync"]) == nil)
        #expect(BillingUISelection.resolve(arguments: ["--ui-testing"]) == nil)
        #expect(BillingUISelection.resolve(arguments: ["--ui-testing", "--ui-testing-billing-sync", "--ui-testing-billing-config-off"]) == nil)
        #expect(BillingUISelection.resolve(arguments: ["--ui-testing", "--ui-testing-billing-sync"]) == .sync)
        let fixture = try BillingUIFixture.make(selection: .configOff)
        #expect(fixture.dependencies.presentsRealAccountIdentity)
        #expect(fixture.dependencies.billingSessionSource != nil)
        #expect(fixture.dependencies.workoutRegistrationSessionSource == nil)
        #expect(fixture.dependencies.mealRecordBindingSource == nil)
        #expect(fixture.probe.sdk == 0)
        #expect(fixture.probe.today402 == 0)
    }

    @Test("subscription copy is localized in both languages, including real store periods",
          arguments: SupportedAppLanguage.allCases)
    func localization(language: SupportedAppLanguage) throws {
        let keys = ["billing.title", "billing.profile-detail", "billing.session-loading", "billing.session-unavailable",
            "billing.refresh", "billing.check-status", "billing.access-active", "billing.access-inactive",
            "billing.access-unavailable", "billing.plan-monthly", "billing.plan-annual", "billing.plan-trial",
            "billing.access-until", "billing.renewal-cancelled", "billing.loading", "billing.offline",
            "billing.read-error", "billing.checkout-unavailable", "billing.no-products", "billing.subscribe",
            "billing.restore", "billing.store-details", "billing.catalog-error", "billing.purchasing",
            "billing.restoring", "billing.sync-pending", "billing.store-pending", "billing.cancelled", "billing.store-error"]
        for key in keys { #expect(try AppLocalization.string(String.LocalizationValue(key), for: language) != key) }
        #expect(BillingPlansCopy.period(.init(value: 1, unit: .month), language: language)
            == (language == .portugueseBrazil ? "A cada mês" : "Per month"))
        #expect(BillingPlansCopy.period(.init(value: 3, unit: .month), language: language)
            == (language == .portugueseBrazil ? "A cada 3 meses" : "Every 3 months"))
        for unit in [BillingSubscriptionPeriod.Unit.day, .week, .month, .year] {
            #expect(!BillingPlansCopy.period(.init(value: 1, unit: unit), language: language).contains("billing.period"))
            #expect(!BillingPlansCopy.period(.init(value: 2, unit: unit), language: language).contains("billing.period"))
        }
    }

    @Test("Profile route is independent of the training plan and other tab stacks")
    func route() {
        let router = AppRouter()
        router.navigate(to: .billingPlans, in: .today)
        #expect(router.path(for: .today).isEmpty)
        router.navigate(to: .billingPlans, in: .profile)
        #expect(router.path(for: .profile) == [.billingPlans])
        #expect(AppRoute.billingPlans.accessibilityIdentifier == "screen.billing-plans")
        #expect(router.path(for: .plan).isEmpty)
    }

    @Test("key or checkout absence preserves official granted access", arguments: [false, true])
    func disabledCheckout(missingKey: Bool) async throws {
        let provider = BillingPlansProbe(configured: !missingKey)
        provider.responses = [try billingAccess(true, available: missingKey)]
        let model = BillingPlansModel(provider: provider, isActive: { true })
        await model.load()
        #expect(model.hasActiveAccess)
        #expect(model.catalog == nil)
        #expect(model.checkoutUnavailable)
        #expect(!model.canRestore)
        #expect(provider.offerCalls == 0)
    }

    @Test("catalog metadata is supplied unchanged; restore survives an offerings failure")
    func restoreDoesNotDependOnOffers() async throws {
        let provider = BillingPlansProbe()
        provider.responses = [try billingAccess(false), try billingAccess(false)]
        provider.offerError = .storeUnavailable
        let model = BillingPlansModel(provider: provider, isActive: { true })
        await model.load()
        #expect(model.catalog == nil)
        #expect(model.canRestore)
        await model.restore()
        #expect(provider.restoreCalls == 1)
        #expect(model.operationState == .syncPending)
        #expect(!model.hasActiveAccess)
    }

    @Test("completed plus denied or failed BFF read remains pending; retry only reads BFF", arguments: [false, true])
    func completedRequiresBFF(failingRead: Bool) async throws {
        let provider = BillingPlansProbe()
        provider.responses = [try billingAccess(false), try billingAccess(false), try billingAccess(true)]
        let model = BillingPlansModel(provider: provider, isActive: { true })
        await model.load()
        let catalog = try #require(model.catalog)
        #expect(catalog.products.first?.localizedPrice == "localized-price-from-store")
        if failingRead { provider.failNextRead = true }
        await model.purchase(productID: "synthetic-plan")
        #expect(provider.purchaseCalls == 1)
        #expect(!model.hasActiveAccess)
        #expect(model.operationState == .syncPending)
        #expect(!model.canPurchase(productID: "synthetic-plan"))
        let offers = provider.offerCalls
        provider.responses = [try billingAccess(true)]
        await model.retry()
        #expect(model.hasActiveAccess)
        #expect(model.operationState == .idle)
        #expect(provider.purchaseCalls == 1)
        #expect(provider.restoreCalls == 0)
        #expect(provider.offerCalls == offers)
    }

    @Test("store pending and cancellation do not grant; a final cancellation refreshes catalog only")
    func storePendingAndCancelled() async throws {
        for outcome in [BillingStoreOutcome.pending, .cancelled] {
            let provider = BillingPlansProbe()
            provider.outcome = outcome
            provider.responses = [try billingAccess(false), try billingAccess(false)]
            let model = BillingPlansModel(provider: provider, isActive: { true })
            await model.load()
            let first = try #require(model.catalog)
            await model.purchase(productID: "synthetic-plan")
            #expect(!model.hasActiveAccess)
            #expect(model.operationState == (outcome == .pending ? .storePending : .cancelled))
            #expect(provider.purchaseCalls == 1)
            if outcome == .cancelled {
                #expect(model.catalog?.revision != first.revision)
                #expect(provider.offerCalls == 2)
            } else {
                #expect(model.catalog == nil)
                #expect(provider.offerCalls == 1)
                #expect(!model.canRestore)
            }
        }
    }

    @Test("double taps are not queued behind the same unfinished store callback")
    func duplicateTap() async throws {
        let provider = BillingPlansProbe()
        let hold = BillingModelHold()
        provider.storeHold = hold
        let model = BillingPlansModel(provider: provider, isActive: { true })
        await model.load()
        let operation = observeBillingModel(hold) { await model.purchase(productID: "synthetic-plan") }
        let entered = await hold.waitForEntryOrCompletion()
        #expect(entered)
        if entered {
            await model.purchase(productID: "synthetic-plan")
            await model.restore()
            #expect(provider.purchaseCalls == 1)
            #expect(provider.restoreCalls == 0)
            #expect(model.isBusy)
        }
        await hold.release()
        await operation.value
        #expect(!model.isBusy)
    }

    @Test("a late read success or error cannot publish into an inactive original context", arguments: [false, true])
    func lateRead(fails: Bool) async throws {
        let provider = BillingPlansProbe()
        let active = BillingModelActivity()
        let hold = BillingModelHold()
        provider.readHold = hold
        provider.failNextRead = fails
        provider.responses = [try billingAccess(true)]
        let model = BillingPlansModel(provider: provider, isActive: { active.value })
        let operation = observeBillingModel(hold) { await model.load() }
        let entered = await hold.waitForEntryOrCompletion()
        #expect(entered)
        active.value = false
        model.invalidate()
        await hold.release()
        await operation.value
        #expect(model.access == nil)
        #expect(model.accessError == nil)
        #expect(!model.hasActiveAccess)
        #expect(provider.offerCalls == 0)
    }

    @Test("a cancelled or inactive store callback cannot start reconciliation or reload products", arguments: [false, true])
    func lateStore(inactive: Bool) async throws {
        let provider = BillingPlansProbe()
        let active = BillingModelActivity()
        let hold = BillingModelHold()
        provider.storeHold = hold
        let model = BillingPlansModel(provider: provider, isActive: { active.value })
        await model.load()
        let reads = provider.readCalls
        let operation = observeBillingModel(hold) { await model.purchase(productID: "synthetic-plan") }
        #expect(await hold.waitForEntryOrCompletion())
        if inactive { active.value = false; model.invalidate() }
        else { operation.cancel() }
        await hold.release()
        await operation.value
        #expect(provider.readCalls == reads)
        #expect(provider.offerCalls == 1)
        #expect(!model.hasActiveAccess)
        if !inactive { #expect(model.operationState == .syncPending) }
    }

    @Test("a failed status read cannot preserve an active-looking access decision")
    func failedReadNeverGrants() async throws {
        let provider = BillingPlansProbe()
        provider.responses = [try billingAccess(true)]
        let model = BillingPlansModel(provider: provider, isActive: { true })
        await model.load()
        #expect(model.hasActiveAccess)
        provider.failNextRead = true
        await model.load()
        #expect(!model.hasActiveAccess)
        #expect(model.accessError == .offline)
        #expect(!model.canRestore)
    }

    @Test("official access appears while the independent store catalog is still loading")
    func accessDoesNotWaitForCatalog() async throws {
        let provider = BillingPlansProbe()
        provider.responses = [try billingAccess(true)]
        let hold = BillingModelHold()
        provider.catalogHold = hold
        let model = BillingPlansModel(provider: provider, isActive: { true })
        let operation = observeBillingModel(hold) { await model.load() }
        let entered = await hold.waitForEntryOrCompletion()
        #expect(entered)
        #expect(model.hasActiveAccess)
        #expect(model.access?.hasActiveAccess == true)
        #expect(model.catalog == nil)
        await hold.release()
        await operation.value
        #expect(model.catalog != nil)
    }

    @Test("a successful requested refresh clears the prior failed store instruction")
    func refreshClearsStoreFailure() async throws {
        let provider = BillingPlansProbe()
        let model = BillingPlansModel(provider: provider, isActive: { true })
        await model.load()
        provider.purchaseError = BillingStoreError.storeUnavailable
        await model.purchase(productID: "synthetic-plan")
        #expect(model.operationState == .failed(.storeUnavailable))
        provider.purchaseError = nil
        await model.load()
        #expect(model.operationState == .idle)
        #expect(model.canPurchase(productID: "synthetic-plan"))
        #expect(provider.purchaseCalls == 1)
    }

    @Test("an interrupted preflight does not claim that the store completed a purchase")
    func uncertainOperationCopy() async throws {
        let provider = BillingPlansProbe()
        provider.purchaseError = CancellationError()
        let model = BillingPlansModel(provider: provider, isActive: { true })
        await model.load()
        await model.purchase(productID: "synthetic-plan")
        #expect(model.operationState == .syncPending)
        #expect(provider.readCalls == 1)
        #expect(provider.offerCalls == 1)
        let pt = try AppLocalization.string("billing.sync-pending", for: .portugueseBrazil)
        let en = try AppLocalization.string("billing.sync-pending", for: .englishUnitedStates)
        #expect(!pt.contains("A loja concluiu"))
        #expect(!en.contains("The store completed"))
    }
}

@MainActor
private final class BillingModelActivity { var value = true }

@MainActor
private final class BillingPlansProbe: BillingProviding {
    let isCheckoutConfigured: Bool
    var responses: [EntitlementResponse] = []
    var outcome = BillingStoreOutcome.completed
    var offerError: BillingStoreError?
    var failNextRead = false
    var readHold: BillingModelHold?
    var catalogHold: BillingModelHold?
    var storeHold: BillingModelHold?
    var purchaseError: (any Error)?
    private(set) var readCalls = 0
    private(set) var offerCalls = 0
    private(set) var purchaseCalls = 0
    private(set) var restoreCalls = 0
    init(configured: Bool = true) { isCheckoutConfigured = configured }
    func entitlement() async throws -> EntitlementResponse {
        readCalls += 1
        let hold = readHold; readHold = nil
        let fails = failNextRead; failNextRead = false
        await hold?.enter()
        if fails { throw BodyFlowCapabilityError.offline }
        return try responses.isEmpty ? billingAccess(false) : responses.removeFirst()
    }
    func offers() async throws -> BillingCatalog {
        offerCalls += 1
        await catalogHold?.enter()
        if let offerError { throw offerError }
        return BillingCatalog(revision: UUID(), products: [BillingProduct(id: "synthetic-plan",
            title: "Store title", localizedPrice: "localized-price-from-store", period: nil)])
    }
    func purchase(productID: String, catalogRevision: UUID) async throws -> BillingStoreOutcome {
        purchaseCalls += 1
        await storeHold?.enter()
        if let purchaseError { throw purchaseError }
        return outcome
    }
    func restore() async -> BillingStoreOutcome { restoreCalls += 1; return outcome }
}

private func billingAccess(_ granted: Bool, available: Bool = true) throws -> EntitlementResponse {
    let data: [String: Any] = ["entitlement": "bodyflow_full", "has_active_access": granted,
        "status": granted ? "active" : "expired", "source": NSNull(), "plan": NSNull(),
        "access_expires_at": NSNull(), "grace_expires_at": NSNull(), "cancel_at_period_end": false,
        "reason": "synthetic", "decision_at": "2026-10-29T15:00:00Z",
        "mobile_billing": ["provider": "revenuecat", "available": available, "reason": "synthetic"]]
    return try JSONDecoder().decode(EntitlementResponse.self, from: JSONSerialization.data(withJSONObject:
        ["data": data, "meta": ["api_version": "v1", "request_id": "synthetic-billing-model"]]))
}

private actor BillingModelHold {
    private var entered = false
    private var completed = false
    private var released = false
    private var entries: [CheckedContinuation<Void, Never>] = []
    private var blocked: CheckedContinuation<Void, Never>?
    func enter() async {
        entered = true
        let waiting = entries; entries = []; waiting.forEach { $0.resume() }
        if !released { await withCheckedContinuation { blocked = $0 } }
    }
    func waitForEntryOrCompletion() async -> Bool {
        if !entered && !completed { await withCheckedContinuation { entries.append($0) } }
        return entered
    }
    func finish() { completed = true; let waiting = entries; entries = []; waiting.forEach { $0.resume() } }
    func release() { released = true; blocked?.resume(); blocked = nil; finish() }
}

@MainActor
private func observeBillingModel(_ hold: BillingModelHold,
    _ operation: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never> {
    Task { await operation(); await hold.finish() }
}
