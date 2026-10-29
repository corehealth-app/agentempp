import Foundation

struct BillingSubscriptionPeriod: Equatable, Sendable {
    enum Unit: Sendable { case day, week, month, year }
    let value: Int
    let unit: Unit
}

struct BillingProduct: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let localizedPrice: String
    let period: BillingSubscriptionPeriod?
}

struct BillingCatalog: Sendable {
    let revision: UUID
    let products: [BillingProduct]
}

/// Completion of a store operation is not an access decision. Only the BFF
/// entitlement response can supply that decision to the presentation layer.
enum BillingStoreOutcome: Equatable, Sendable { case completed, cancelled, pending }
enum BillingStoreError: Error, Equatable, Sendable {
    case configurationUnavailable, storeUnavailable, invalidSelection
}

protocol BillingSDKDriving: Sendable {
    func configure(publicAPIKey: String, patientID: UUID) async throws
    func logIn(patientID: UUID) async throws
    func logOut() async throws
    func offers() async throws -> [BillingProduct]
    func purchase(productID: String) async throws -> BillingStoreOutcome
    func restore() async throws -> BillingStoreOutcome
}

/// The session binding supplies validation of its original lease and activation
/// ticket. This separate grant can be withdrawn synchronously from auth teardown.
final class BillingSessionGrant: @unchecked Sendable {
    let token = UUID()
    let patientID: UUID
    private let lock = NSLock()
    private var open = true
    private let authorize: @Sendable () async throws -> Void

    init(patientID: UUID, authorize: @escaping @Sendable () async throws -> Void) {
        self.patientID = patientID
        self.authorize = authorize
    }

    func close() { lock.withLock { open = false } }
    private var isOpen: Bool { lock.withLock { open } }

    func check() async throws {
        try Task.checkCancellation()
        guard isOpen else { throw CancellationError() }
        try await authorize()
        try Task.checkCancellation()
        guard isOpen else { throw CancellationError() }
    }
}

/// The actor protects state; the explicit permit also excludes SDK operations
/// across suspension points. Never release it from a cancellation handler: the
/// pinned SDK's continuation still awaits the actual store callback.
actor BillingSDKCoordinator {
    nonisolated let isCheckoutConfigured: Bool
    private let configuration: BillingConfiguration?
    private let driver: any BillingSDKDriving
    private var initialized = false
    private var owner: UUID?
    private var patient: UUID?
    private var catalogRevision: UUID?
    private var productIDs: Set<String> = []
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(configuration: BillingConfiguration?, driver: any BillingSDKDriving) {
        self.configuration = configuration
        self.driver = driver
        isCheckoutConfigured = configuration != nil
    }

    func offers(for grant: BillingSessionGrant) async throws -> BillingCatalog {
        guard configuration != nil else { throw BillingStoreError.configurationUnavailable }
        try await grant.check()
        await acquire()
        defer { releasePermit() }
        try await admit(grant)
        invalidateCatalog()
        let driver = driver
        let products = try await checkedSDKResult(for: grant) { try await driver.offers() }
        let ids = Set(products.map(\.id))
        guard ids.count == products.count,
              products.allSatisfy({ !$0.id.isEmpty && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && !$0.localizedPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw BillingStoreError.storeUnavailable
        }
        let revision = UUID()
        catalogRevision = revision
        productIDs = ids
        return BillingCatalog(revision: revision, products: products)
    }

    func purchase(productID: String, catalogRevision: UUID, for grant: BillingSessionGrant) async throws -> BillingStoreOutcome {
        guard configuration != nil else { throw BillingStoreError.configurationUnavailable }
        try await grant.check()
        await acquire()
        defer { releasePermit() }
        try await admit(grant)
        guard self.catalogRevision == catalogRevision, productIDs.contains(productID) else {
            throw BillingStoreError.invalidSelection
        }
        // One catalog selection admits one purchase attempt. A retry requires a
        // fresh catalog, never a second automatic store prompt from an old tap.
        invalidateCatalog()
        let driver = driver
        return try await checkedSDKResult(for: grant) { try await driver.purchase(productID: productID) }
    }

    func restore(for grant: BillingSessionGrant) async throws -> BillingStoreOutcome {
        guard configuration != nil else { throw BillingStoreError.configurationUnavailable }
        try await grant.check()
        await acquire()
        defer { releasePermit() }
        try await admit(grant)
        invalidateCatalog()
        let driver = driver
        return try await checkedSDKResult(for: grant) { try await driver.restore() }
    }

    func release(_ grant: BillingSessionGrant) async throws {
        grant.close()
        await acquire()
        defer { releasePermit() }
        guard owner == grant.token else { return }
        owner = nil
        patient = nil
        invalidateCatalog()
        if initialized { try await driver.logOut() }
    }

    private func admit(_ grant: BillingSessionGrant) async throws {
        try await grant.check()
        guard let configuration else { throw BillingStoreError.configurationUnavailable }
        if owner == grant.token, patient == grant.patientID { return }
        // Retain ownership of an attempted identity transition even if the SDK
        // reports an error. Its cleanup remains conditional on this exact token.
        owner = grant.token
        patient = nil
        invalidateCatalog()
        do {
            if !initialized {
                try await driver.configure(publicAPIKey: configuration.publicAPIKey, patientID: grant.patientID)
                initialized = true
            } else {
                try await driver.logIn(patientID: grant.patientID)
            }
            // Record the SDK transition before post-validation can reject its
            // late result. Cleanup still belongs to the exact attempted owner.
            patient = grant.patientID
        } catch {
            try await grant.check()
            throw error
        }
        try await grant.check()
    }

    private func checkedSDKResult<Value: Sendable>(
        for grant: BillingSessionGrant,
        operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        do {
            let value = try await operation()
            try await grant.check()
            return value
        } catch {
            // Errors belong to their original session just like successful
            // callbacks; an ended owner cannot publish a recoverable SDK error.
            try await grant.check()
            throw error
        }
    }

    private func invalidateCatalog() { catalogRevision = nil; productIDs = [] }

    private func acquire() async {
        if busy { await withCheckedContinuation { waiters.append($0) } }
        else { busy = true }
    }

    private func releasePermit() {
        if waiters.isEmpty { busy = false }
        else { waiters.removeFirst().resume() }
    }
}
