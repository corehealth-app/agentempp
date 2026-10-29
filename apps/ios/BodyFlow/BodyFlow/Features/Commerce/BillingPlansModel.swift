import Foundation
import Observation

enum BillingPlansOperationState: Equatable, Sendable {
    case idle, purchasing, restoring, syncPending, storePending, cancelled
    case failed(BillingStoreError)
    var isPending: Bool { self == .syncPending || self == .storePending }
}

/// Cached by one original BillingReadyContext, including while its route is
/// popped. Navigating cannot reset an in-flight purchase or pending BFF sync.
@MainActor
@Observable
final class BillingPlansModel {
    private enum Kind: Sendable { case read, store }
    private struct Work: Sendable {
        let id = UUID()
        let kind: Kind
        let ownership = FeatureLoadOwnership()
        let accessOwnership = FeatureLoadOwnership()
        func invalidate() { ownership.invalidate(); accessOwnership.invalidate() }
    }
    private let provider: any BillingProviding
    private let isActive: @MainActor @Sendable () -> Bool
    private var ended = false
    private var work: Work?
    private(set) var access: EntitlementSnapshot?
    private(set) var accessError: BodyFlowCapabilityError?
    private(set) var catalog: BillingCatalog?
    private(set) var catalogError: BillingStoreError?
    private(set) var operationState: BillingPlansOperationState = .idle
    var isBusy: Bool { work != nil }
    var hasActiveAccess: Bool { live && accessError == nil && access?.hasActiveAccess == true }
    var checkoutUnavailable: Bool {
        !live || !provider.isCheckoutConfigured || access?.mobileBilling.provider != "revenuecat"
            || access?.mobileBilling.available != true
    }
    var canRestore: Bool { !isBusy && !checkoutUnavailable && accessError == nil && !operationState.isPending }
    func canPurchase(productID: String) -> Bool {
        canRestore && catalog?.products.contains(where: { $0.id == productID }) == true
    }

    init(provider: any BillingProviding, isActive: @escaping @MainActor @Sendable () -> Bool) {
        self.provider = provider
        self.isActive = isActive
    }

    func load() async {
        if operationState.isPending { await reconcile(); return }
        await run(.read) { current in
            do {
                let snapshot = try await self.provider.entitlement().data
                guard self.canContinue(current) else { return }
                self.publishAccess(current) {
                    self.access = snapshot
                    self.accessError = nil
                    self.catalog = nil
                    self.catalogError = nil
                    if case .failed = self.operationState { self.operationState = .idle }
                    if self.operationState == .cancelled { self.operationState = .idle }
                }
                let offering = await self.readCatalog(for: snapshot, work: current)
                self.publish(current) {
                    self.catalog = offering.catalog
                    self.catalogError = offering.error
                }
            } catch {
                self.publish(current) {
                    self.access = nil
                    self.catalog = nil
                    self.accessError = error as? BodyFlowCapabilityError ?? .serviceUnavailable
                }
            }
        }
    }

    /// A synchronization retry never repeats purchase, restore or offerings.
    func retry() async {
        if operationState.isPending { await reconcile() }
        else { await load() }
    }

    private func reconcile() async {
        await run(.read) { current in
            do {
                let snapshot = try await self.provider.entitlement().data
                self.publish(current) {
                    self.access = snapshot
                    self.accessError = nil
                    if snapshot.hasActiveAccess { self.operationState = .idle }
                }
            } catch {
                self.publish(current) {
                    self.access = nil
                    self.accessError = error as? BodyFlowCapabilityError ?? .serviceUnavailable
                    // Keep pending even when the verification request fails.
                }
            }
        }
    }

    func purchase(productID: String) async {
        guard canPurchase(productID: productID), let revision = catalog?.revision else { return }
        await store(purchasing: true) {
            try await self.provider.purchase(productID: productID, catalogRevision: revision)
        }
    }

    func restore() async {
        guard canRestore else { return }
        await store(purchasing: false) { try await self.provider.restore() }
    }

    private func store(purchasing: Bool,
                       operation: @escaping @MainActor @Sendable () async throws -> BillingStoreOutcome) async {
        await run(.store) { current in
            self.catalog = nil // the selection is consumed; no automatic store retry
            self.catalogError = nil
            self.operationState = purchasing ? .purchasing : .restoring
            do {
                let outcome = try await operation()
                guard self.canContinue(current) else { return }
                switch outcome {
                case .completed:
                    do {
                        let snapshot = try await self.provider.entitlement().data
                        self.publish(current) {
                            self.access = snapshot
                            self.accessError = nil
                            self.operationState = snapshot.hasActiveAccess ? .idle : .syncPending
                        }
                    } catch {
                        self.publish(current) {
                            self.access = nil
                            self.accessError = error as? BodyFlowCapabilityError ?? .serviceUnavailable
                            self.operationState = .syncPending
                        }
                    }
                case .pending:
                    self.publish(current) { self.operationState = .storePending }
                case .cancelled:
                    let offering = await self.readCatalog(for: self.access, work: current)
                    self.publish(current) {
                        self.operationState = .cancelled
                        self.catalog = offering.catalog
                        self.catalogError = offering.error
                    }
                }
            } catch is CancellationError {
                // Cancellation is not the store's final .cancelled outcome.
                // No new HTTP or SDK work is admitted from this callback.
            } catch {
                guard self.canContinue(current) else { return }
                let offering = await self.readCatalog(for: self.access, work: current)
                self.publish(current) {
                    self.operationState = .failed(error as? BillingStoreError ?? .storeUnavailable)
                    self.catalog = offering.catalog
                    self.catalogError = offering.error
                }
            }
        }
    }

    private func readCatalog(for snapshot: EntitlementSnapshot?, work: Work)
        async -> (catalog: BillingCatalog?, error: BillingStoreError?) {
        guard canContinue(work), provider.isCheckoutConfigured,
              snapshot?.mobileBilling.provider == "revenuecat", snapshot?.mobileBilling.available == true else {
            return (nil, nil)
        }
        do { return (try await provider.offers(), nil) }
        catch { return (nil, error as? BillingStoreError ?? .storeUnavailable) }
    }

    private var live: Bool { !ended && isActive() }
    private func canContinue(_ candidate: Work) -> Bool {
        live && !Task.isCancelled && work?.id == candidate.id && !candidate.ownership.isInvalidated
    }
    private func publish(_ candidate: Work, _ effect: () -> Void) {
        guard canContinue(candidate), candidate.ownership.claimPublication() else { return }
        effect()
    }
    private func publishAccess(_ candidate: Work, _ effect: () -> Void) {
        guard canContinue(candidate), candidate.accessOwnership.claimPublication() else { return }
        effect()
    }
    private func run(_ kind: Kind, operation: @escaping @MainActor @Sendable (Work) async -> Void) async {
        guard live, !Task.isCancelled, work == nil else { return }
        let current = Work(kind: kind)
        work = current // synchronous reservation; competing taps are never queued
        await withTaskCancellationHandler {
            defer {
                if self.work?.id == current.id {
                    if kind == .store && (operationState == .purchasing || operationState == .restoring) {
                        // The callback was interrupted and its store result is
                        // uncertain. Recheck BFF instead of offering another buy.
                        operationState = .syncPending
                    }
                    self.work = nil
                }
            }
            await operation(current)
        } onCancel: { current.invalidate() }
    }

    func cancelRead() {
        guard let current = work, current.kind == .read else { return }
        current.invalidate()
        work = nil
    }

    func invalidate() {
        ended = true
        work?.invalidate()
        work = nil
        access = nil
        accessError = nil
        catalog = nil
        catalogError = nil
        operationState = .idle
    }
}
