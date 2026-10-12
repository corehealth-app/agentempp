#if DEBUG
import Foundation
@testable import BodyFlow

enum SignupParentProducerExit: String, CaseIterable, Sendable {
    case galleryModeReentry, permissionModeReentry, permissionOwnerRestore
    var channel: MealSourceChannel { self == .galleryModeReentry ? .gallery : .camera }
    var isPermission: Bool { self != .galleryModeReentry }
}
struct SignupParentProducerReport: Sendable {
    let loads: Int
    let authorizedBefore: Int
    let authorizedAfter: Int
    let rejectedAfter: Int
    let permissionPresentations: Int
    let sourceReturning: Bool
    let deleteReturnOrdering: [Bool]
    let discarded: [URL]
}
actor SignupParentProducerProbe {
    private var loads = 0, before = 0, after = 0, rejected = 0, permission = 0
    private var returning = false
    private var orders: [Bool] = []
    private var files: [URL] = []
    func began() { loads += 1; before += 1 }
    func postAwait(authorized: Bool, permissionResult: Bool) {
        if authorized { after += 1; if permissionResult { permission += 1 } }
        else { rejected += 1 }
    }
    func sourceReturning() { returning = true }
    func deletionEntered() { orders.append(returning) }
    func discarded(_ url: URL) { files.append(url) }
    func report() -> SignupParentProducerReport {
        .init(loads: loads, authorizedBefore: before, authorizedAfter: after,
            rejectedAfter: rejected, permissionPresentations: permission,
            sourceReturning: returning, deleteReturnOrdering: orders, discarded: files)
    }
}
/// Cancellation is reported synchronously; no watcher, queued Task or sleep.
final class SignupParentProducerCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.withLock { cancelled = true } }
    var isCancelled: Bool { lock.withLock { cancelled } }
}
/// A typed peer decoration: the existing composition peer owns the actual
/// counted deletion; this only records source-return ordering at its boundary.
actor SignupParentProducerPhotos: SignupBodyPhotosProviding {
    let base: SignupCompositionPhotos
    let probe: SignupParentProducerProbe
    init(base: SignupCompositionPhotos, probe: SignupParentProducerProbe) {
        self.base = base; self.probe = probe
    }
    func state() async throws -> SignupBodyPhotoState { try await base.state() }
    func consent(_ a: MutationAttempt<SignupBodyPhotoConsentRequest>) async throws -> SignupBodyPhotoConsentReceipt { try await base.consent(a) }
    func create(_ a: MutationAttempt<SignupBodyPhotoCreateRequest>) async throws -> SignupBodyPhotoCreateReceipt { try await base.create(a) }
    func complete(_ a: MutationAttempt<MediaAssetCommand>) async throws -> SignupBodyPhotoCompleteReceipt { try await base.complete(a) }
    func delete(_ a: MutationAttempt<SignupBodyPhotoDeleteCommand>) async throws -> SignupBodyPhotoDeleteReceipt {
        await probe.deletionEntered()
        return try await base.delete(a)
    }
    func repair(_ a: MutationAttempt<SignupBodyPhotoRepairCommand>) async throws -> SignupBodyPhotoDeleteReceipt { try await base.repair(a) }
}
#endif
