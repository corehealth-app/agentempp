#if DEBUG
import Foundation
@testable import BodyFlow

private enum PollProofCall: Equatable, Sendable {
    case state, consent, stage, create, put, complete, delete, repair
}

enum CapturePollingInactiveCase: String, CaseIterable, Sendable {
    case read, unreadable, readingFailed, pendingUpload, unknown, missing, disabled, noConsent
}

enum CapturePollingStopCase: String, CaseIterable, Sendable {
    case invalidate, decline, otherOwner, sameOwnerNewGeneration
}

@MainActor
final class CapturePollingOwnerBox {
    var current: OnboardingOwnerToken
    init(_ current: OnboardingOwnerToken) { self.current = current }
}

actor CapturePollingReadGate {
    private var entered = false
    private var released = false
    private var workFinished = false
    private var observers: [CheckedContinuation<Bool, Never>] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        entered = true
        let ready = observers; observers.removeAll()
        for observer in ready { observer.resume(returning: true) }
        if !released { await withCheckedContinuation { waiters.append($0) } }
    }
    func waitUntilEntered() async -> Bool {
        if entered { return true }
        if workFinished { return false }
        return await withCheckedContinuation { observers.append($0) }
    }
    func workStarted() { workFinished = false }
    func workEnded() {
        workFinished = true
        let ready = observers; observers.removeAll()
        for observer in ready { observer.resume(returning: false) }
    }
    func release() {
        released = true
        let ready = waiters; waiters.removeAll()
        for waiter in ready { waiter.resume() }
    }
}

/// Local precedent: FlowPreviewReplyClock. One actor owns elapsed and sleep.
/// Tests wait for registration before advance; no wall-clock sleeps or yields.
actor CapturePollingClock {
    private struct Sleeper {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }
    private var instant = Duration.zero
    private var sleepers: [UUID: Sleeper] = [:]
    private var registrationCount = 0
    private var workFinished = false
    private var registrationBarriers: [(Int, CheckedContinuation<Bool, Never>)] = []
    private(set) var durations: [Duration] = []
    var pendingCount: Int { sleepers.count }
    var registrations: Int { registrationCount }

    func elapsed() -> Duration { instant }
    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError()); return
                }
                sleepers[id] = Sleeper(deadline: instant + duration, continuation: continuation)
                durations.append(duration)
                registrationCount += 1
                let ready = registrationBarriers.filter { $0.0 <= registrationCount }
                registrationBarriers.removeAll { $0.0 <= registrationCount }
                for (_, barrier) in ready { barrier.resume(returning: true) }
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    func waitForRegistrations(_ count: Int) async -> Bool {
        if registrationCount >= count { return true }
        if workFinished { return false }
        return await withCheckedContinuation { registrationBarriers.append((count, $0)) }
    }
    func advance(by duration: Duration) {
        instant += duration
        let ready = sleepers.compactMap { $0.value.deadline <= instant ? $0.key : nil }
        for id in ready { sleepers.removeValue(forKey: id)?.continuation.resume() }
    }
    private func cancel(_ id: UUID) {
        sleepers.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }
    func workStarted() { workFinished = false }
    // Producer end is only a negative fallback for an unmet registration;
    // it is NEVER used as evidence that the model published its last state.
    func workEnded() {
        workFinished = true
        let pending = registrationBarriers; registrationBarriers.removeAll()
        for (_, barrier) in pending { barrier.resume(returning: false) }
    }
}

actor CapturePollingPeer: SignupBodyPhotosProviding, StorageUploading {
    private let script: [SignupBodyPhotoState]
    private let allowsConsent: Bool
    private let failsSecondState: Bool
    private let holdSecondState: CapturePollingReadGate?
    private var calls: [PollProofCall] = []
    private var stateCallCount = 0
    private var workFinished = false
    private var barriers: [(Int, CheckedContinuation<Bool, Never>)] = []
    var stateCalls: Int { stateCallCount }
    var nonReadCalls: Int { calls.filter { $0 != .state }.count }

    init(script: [SignupBodyPhotoState], holdSecondState: CapturePollingReadGate? = nil, allowsConsent: Bool = false, failsSecondState: Bool = false) {
        precondition(!script.isEmpty)
        self.script = script; self.holdSecondState = holdSecondState
        self.allowsConsent = allowsConsent
        self.failsSecondState = failsSecondState
    }
    func waitForStateCalls(_ count: Int) async -> Bool {
        if stateCallCount >= count { return true }
        if workFinished { return false }
        return await withCheckedContinuation { barriers.append((count, $0)) }
    }
    func workStarted() { workFinished = false }
    func workEnded() {
        workFinished = true
        let pending = barriers; barriers.removeAll()
        for (_, barrier) in pending { barrier.resume(returning: false) }
    }
    func state() async throws -> SignupBodyPhotoState {
        calls.append(.state); stateCallCount += 1
        let callNumber = stateCallCount
        // The response is captured BEFORE the await, so a held old response
        // cannot magically see a later fixture snapshot.
        let result = script[min(callNumber - 1, script.count - 1)]
        let ready = barriers.filter { $0.0 <= stateCallCount }
        barriers.removeAll { $0.0 <= stateCallCount }
        for (_, barrier) in ready { barrier.resume(returning: true) }
        if callNumber == 2 { await holdSecondState?.enter() }
        if callNumber == 2, failsSecondState { throw SignupBodyPhotoFailure.offline }
        return result
    }
    func noteStage() { calls.append(.stage) }
    func consent(_ attempt: MutationAttempt<SignupBodyPhotoConsentRequest>) async throws -> SignupBodyPhotoConsentReceipt {
        calls.append(.consent)
        guard allowsConsent else { throw SignupBodyPhotoFailure.unavailable }
        return SignupBodyPhotoConsentReceipt(documentKey: "body_photo_estimate_consent", version: attempt.payload.version,
            acceptedAt: APITimestamp(value: Date(timeIntervalSince1970: 1_790_000_000)))
    }
    func create(_ attempt: MutationAttempt<SignupBodyPhotoCreateRequest>) async throws -> SignupBodyPhotoCreateReceipt {
        calls.append(.create); throw SignupBodyPhotoFailure.unavailable
    }
    func complete(_ attempt: MutationAttempt<MediaAssetCommand>) async throws -> SignupBodyPhotoCompleteReceipt {
        calls.append(.complete); throw SignupBodyPhotoFailure.unavailable
    }
    func delete(_ attempt: MutationAttempt<SignupBodyPhotoDeleteCommand>) async throws -> SignupBodyPhotoDeleteReceipt {
        calls.append(.delete); throw SignupBodyPhotoFailure.unavailable
    }
    func repair(_ attempt: MutationAttempt<SignupBodyPhotoRepairCommand>) async throws -> SignupBodyPhotoDeleteReceipt {
        calls.append(.repair); throw SignupBodyPhotoFailure.unavailable
    }
    func upload(_ media: StagedMedia, with ticket: MediaUploadTicket) async throws {
        calls.append(.put); throw SignupBodyPhotoFailure.unavailable
    }
}

@MainActor
struct CapturePollingHarness {
    let model: SignupBodyPhotoCaptureModel
    let peer: CapturePollingPeer
    let clock: CapturePollingClock
    let readGate: CapturePollingReadGate
    let ownerBox: CapturePollingOwnerBox

    init(holdSecondState: Bool = false, script: [SignupBodyPhotoState]? = nil, allowsConsent: Bool = false, failsSecondState: Bool = false) {
        let clock = CapturePollingClock()
        let gate = CapturePollingReadGate()
        let peer = CapturePollingPeer(script: script ?? [Self.waiting(), Self.waiting(), Self.terminal()],
            holdSecondState: holdSecondState ? gate : nil, allowsConsent: allowsConsent, failsSecondState: failsSecondState)
        let owner = OnboardingOwnerToken(userID: "00000000-0000-4000-8000-000000c70601", restoreGeneration: 1)
        let ownerBox = CapturePollingOwnerBox(owner)
        let staging = MediaStagingStore(temporaryDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("signup-poll-proof-\(UUID().uuidString)", isDirectory: true))
        let scope = SignupBodyPhotoCaptureScope(userID: owner.userID, photos: peer, uploader: peer,
            staging: staging, camera: .unavailable,
            validateSession: { try Task.checkCancellation() },
            stagePhoto: { _, _ in await peer.noteStage(); throw SignupBodyPhotoFailure.unavailable },
            performWork: { operation in
                await clock.workStarted(); await peer.workStarted(); await gate.workStarted()
                do { try await operation() }
                catch {
                    await clock.workEnded(); await peer.workEnded(); await gate.workEnded()
                    throw error
                }
                await clock.workEnded(); await peer.workEnded(); await gate.workEnded()
            },
            discardStaged: { url in staging.remove(url) },
            rememberUnboundCreate: { _ in })
        self.clock = clock; self.peer = peer; self.readGate = gate
        self.ownerBox = ownerBox
        self.model = SignupBodyPhotoCaptureModel(scope: scope, ownerToken: owner,
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "signup-poll-unused"),
            pollingTiming: SignupBodyPhotoPollingTiming(
                elapsed: { await clock.elapsed() }, sleep: { try await clock.sleep($0) }),
            isCurrentOwner: { $0 == ownerBox.current })
    }

    static func waiting() -> SignupBodyPhotoState {
        snapshot(statuses: [.front: "uploaded", .side: "reading", .back: "read"])
    }
    static func frontWaitingOnly() -> SignupBodyPhotoState {
        snapshot(statuses: [.front: "uploaded", .side: "read", .back: "read"])
    }
    static func terminal() -> SignupBodyPhotoState {
        snapshot(statuses: [.front: "read", .side: "unreadable", .back: "read"])
    }
    static func inactive(_ scenario: CapturePollingInactiveCase) -> SignupBodyPhotoState {
        let status: String?
        switch scenario {
        case .read: status = "read"
        case .unreadable: status = "unreadable"
        case .readingFailed: status = "reading_failed"
        case .pendingUpload: status = "pending_upload"
        case .unknown: status = "future_unknown"
        case .missing: status = nil
        case .disabled, .noConsent: status = "reading"
        }
        return snapshot(statuses: status.map { [.front: $0] } ?? [:],
            available: scenario != .disabled, accepted: scenario != .noConsent)
    }
    private static func snapshot(statuses: [SignupBodyPhotoPose: String], available: Bool = true, accepted: Bool = true) -> SignupBodyPhotoState {
        let timestamp = APITimestamp(value: Date(timeIntervalSince1970: 1_790_000_000))
        return SignupBodyPhotoState(available: available, unavailableReason: available ? nil : "disabled",
            consent: available ? SignupBodyPhotoConsent(documentKey: "body_photo_estimate_consent", version: "poll-proof-v1",
                locale: "pt-BR", body: "Synthetic polling consent already accepted",
                bodyHash: String(repeating: "a", count: 64), acceptedAt: accepted ? timestamp : nil) : nil,
            minimumAge: 18, poses: SignupBodyPhotoPose.allCases.map { pose in
                let suffix: String
                switch pose { case .front: suffix = "01"; case .side: suffix = "02"; case .back: suffix = "03" }
                let photo = statuses[pose].map { SignupBodyPhoto(
                    id: "00000000-0000-4000-8000-000000c706\(suffix)", status: $0, createdAt: timestamp) }
                return SignupBodyPhotoSlot(pose: pose, photo: photo)
            }, estimate: nil, remainingUploads: 9)
    }
}
#endif
