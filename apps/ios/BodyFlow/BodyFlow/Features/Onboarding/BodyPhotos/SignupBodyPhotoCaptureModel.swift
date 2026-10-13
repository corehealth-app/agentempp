import Foundation
import Observation

enum SignupBodyPhotoCapturePhase: Equatable, Sendable {
    case idle, awaitingConsent, preparing, sending, reading, ready
    case failed(SignupBodyPhotoFailure)
}

/// Capture and one owner-bound reading poll. Explicit deletion, repair debt
/// and root/UI callbacks remain separate; no estimate is written here.
@MainActor
@Observable
final class SignupBodyPhotoCaptureModel {
    private struct Context: Sendable {
        let epoch: Int
        let nonce: UUID
        let pose: SignupBodyPhotoPose?
    }
    private struct PollContext: Sendable {
        let epoch: Int
        let nonce: UUID
    }
    private struct ReadingAnchor: Sendable {
        let assetID: String
        let startedAt: Duration
    }
    private struct PollWaiter {
        let nonce: UUID
        let untilStopped: Bool
        let continuation: CheckedContinuation<Bool, Never>
    }
    private struct Pipeline: Sendable {
        let nonce: UUID
        var data: Data?
        let channel: MealSourceChannel
        var staged: StagedMedia?
        var createAttempt: MutationAttempt<SignupBodyPhotoCreateRequest>?
        var assetID: String?
        var uploaded = false
        var completeAttempt: MutationAttempt<MediaAssetCommand>?
        var completed = false
        var failure: SignupBodyPhotoFailure?
    }
    private struct LocalCleanup: Sendable {
        let nonce: UUID
        let token: UUID
        let file: URL
        let task: Task<Void, Error>
    }
    private struct Outcome: Sendable {
        let snapshot: SignupBodyPhotoState
        let failure: SignupBodyPhotoFailure?
        let readIdentity: UUID
    }
    private let scope: SignupBodyPhotoCaptureScope
    private let ownerToken: OnboardingOwnerToken
    private let timeProvider: any TimeProviding
    private let keyProvider: any IdempotencyKeyProviding
    private let pollingTiming: SignupBodyPhotoPollingTiming
    private let isCurrentOwner: @MainActor @Sendable (OnboardingOwnerToken) -> Bool
    private let onStateObserved: @MainActor (SignupBodyPhotoState?) -> Void
    private var epoch = 0
    private var loadNonce = UUID()
    private var consentNonce = UUID()
    private var readNonce = UUID()
    private var pollNonce = UUID()
    private var pollTask: Task<Void, Never>?
    private var ownedPollTasks: [UUID: Task<Void, Never>] = [:]
    private var pollStartedNonce: UUID?
    private var lastPollStoppedSuccessfully = false
    private var pollWaiters: [UUID: PollWaiter] = [:]
    private var pollTerminal: Outcome?
    private var pollReadIdentity: UUID?
    private var readingAnchors: [SignupBodyPhotoPose: ReadingAnchor] = [:]
    private var lastReadingElapsed = Duration.zero
    private var declined = false
    private var consentAttempt: MutationAttempt<SignupBodyPhotoConsentRequest>?
    private var consentTask: Task<Void, Never>?
    private var pipelines: [SignupBodyPhotoPose: Pipeline] = [:]
    private var tasks: [SignupBodyPhotoPose: Task<Void, Never>] = [:]
    private var ownedMutationTasks: [UUID: Task<Void, Never>] = [:]
    private var ownedFiles: [UUID: URL] = [:]
    private var cleanupRequested: Set<UUID> = []
    private var localCleanups: [UUID: LocalCleanup] = [:]
    private var outcomes: [UUID: Outcome] = [:]
    private var consentResults: [UUID: SignupBodyPhotoConsentReceipt] = [:]

    private(set) var phase = SignupBodyPhotoCapturePhase.idle
    private(set) var state: SignupBodyPhotoState? {
        didSet { onStateObserved(state) }
    }
    private(set) var hasAcceptedConsent = false
    private(set) var isActive = true
    private(set) var hasExceededReadingWait = false

    /// Internal resource boundary for deterministic lifecycle tests. This is
    /// only the model's pending input, not caller/camera or process memory.
    var retainedInputBytes: Int {
        pipelines.values.reduce(0) { $0 + ($1.data?.count ?? 0) }
    }

    /// A retained, failed local attempt can recover a transport/read error.
    /// An official terminal reading failure requires another photo instead.
    func canRetry(pose: SignupBodyPhotoPose) -> Bool {
        guard currentOwner, hasAcceptedConsent, !declined, state?.available == true,
              tasks[pose] == nil, let failure = pipelines[pose]?.failure else { return false }
        return failure == .offline || failure == .unavailable
    }

    init(scope: SignupBodyPhotoCaptureScope, ownerToken: OnboardingOwnerToken,
         timeProvider: any TimeProviding = SystemTimeProvider(),
         keyProvider: any IdempotencyKeyProviding = RandomIdempotencyKeyProvider(),
         pollingTiming: SignupBodyPhotoPollingTiming = .live(),
         onStateObserved: @escaping @MainActor (SignupBodyPhotoState?) -> Void = { _ in },
         isCurrentOwner: @escaping @MainActor @Sendable (OnboardingOwnerToken) -> Bool) {
        self.scope = scope; self.ownerToken = ownerToken
        self.timeProvider = timeProvider; self.keyProvider = keyProvider
        self.pollingTiming = pollingTiming
        self.isCurrentOwner = isCurrentOwner
        self.onStateObserved = onStateObserved
    }

    /// Internal readiness from the model task, never from load or a producer.
    /// Terminal success is signalled only after finish, guards and publication.
    func waitForPollingEvent(untilStopped: Bool = false) async -> Bool {
        guard currentOwner else { return false }
        guard pollTask != nil else {
            return untilStopped && lastPollStoppedSuccessfully
        }
        if !untilStopped, pollStartedNonce == pollNonce { return true }
        let id = UUID(), nonce = pollNonce
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return false }
            return await withCheckedContinuation { continuation in
                pollWaiters[id] = PollWaiter(nonce: nonce, untilStopped: untilStopped,
                    continuation: continuation)
            }
        } onCancel: { Task { @MainActor in self.cancelPollWaiter(id) } }
    }

    /// Await only polling tasks already superseded by pause/invalidation.
    /// This is local completion, never proof of remote cancellation. It uses
    /// retained work and does not include a newly armed poll or acquire a lease.
    func waitForStoppedPollingWork() async {
        let stopped = ownedPollTasks.filter { $0.key != pollNonce }.map(\.value)
        for work in stopped { await work.value }
    }

    func load() async {
        guard currentOwner else { return }
        pausePolling()
        loadNonce = UUID()
        let context = Context(epoch: epoch, nonce: loadNonce, pose: nil)
        do {
            let snapshot = try await fetchState(context, consent: false)
            let identity = readNonce
            let elapsed = await pollingTiming.elapsed()
            try await boundary(context, consent: false)
            guard identity == readNonce else { throw CancellationError() }
            refreshReadingWait(snapshot, elapsed: elapsed)
            state = snapshot
            hasAcceptedConsent = !declined && snapshot.available && snapshot.consent?.acceptedAt != nil
            phase = snapshot.available ? (hasAcceptedConsent ? (reading(snapshot) ? .reading : .idle) : .awaitingConsent) : .failed(.unavailable)
            armPollingIfNeeded()
        } catch { publishFailure(error, context, consent: false) }
    }

    func acceptConsent(birthDate: String) async {
        guard currentOwner, let snapshot = state, snapshot.available, let document = snapshot.consent else { return }
        let payload = SignupBodyPhotoConsentRequest(version: document.version, bodyHash: document.bodyHash, birthDate: birthDate)
        do {
            if consentAttempt?.payload != payload {
                consentAttempt = try attempt(.mediaCreate, payload: payload)
            }
        } catch { phase = .failed(.unavailable); return }
        guard let original = consentAttempt else { return }
        pausePolling()
        consentTask?.cancel()
        consentNonce = UUID()
        let context = Context(epoch: epoch, nonce: consentNonce, pose: nil)
        declined = false; hasAcceptedConsent = false; phase = .awaitingConsent
        let work = Task {
            defer { self.ownedMutationTasks[context.nonce] = nil }
            do {
                try await self.boundary(context, consent: true)
                try await self.scope.performWork {
                    try await self.requestConsent(original, context: context)
                }
                try await self.boundary(context, consent: true)
                guard let receipt = self.consentResults.removeValue(forKey: context.nonce),
                      receipt.documentKey == document.documentKey, receipt.version == original.payload.version
                else { throw SignupBodyPhotoFailure.unavailable }
                self.consentAttempt = nil
                guard let current = self.state, current.available, let old = current.consent,
                      old.documentKey == document.documentKey, old.version == document.version,
                      old.bodyHash == document.bodyHash else {
                    self.hasAcceptedConsent = false
                    self.phase = self.state?.available == true ? .awaitingConsent : .failed(.unavailable)
                    return
                }
                // The official receipt supersedes reads started before it.
                self.readNonce = UUID()
                self.hasAcceptedConsent = true
                let accepted = SignupBodyPhotoConsent(documentKey: old.documentKey, version: old.version,
                    locale: old.locale, body: old.body, bodyHash: old.bodyHash, acceptedAt: receipt.acceptedAt)
                self.state = SignupBodyPhotoState(available: current.available, unavailableReason: current.unavailableReason,
                    consent: accepted, minimumAge: current.minimumAge, poses: current.poses,
                    estimate: current.estimate, remainingUploads: current.remainingUploads)
                self.phase = self.reading(current) ? .reading : .idle
            } catch { self.publishFailure(error, context, consent: true) }
            self.consentResults[context.nonce] = nil
        }
        consentTask = work
        ownedMutationTasks[context.nonce] = work
        await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        if consentNonce == context.nonce { consentTask = nil }
        armPollingIfNeeded()
    }

    func declineConsent() {
        guard currentOwner else { return }
        pausePolling(clearAnchors: true)
        epoch += 1
        declined = true; hasAcceptedConsent = false; consentAttempt = nil
        for task in ownedMutationTasks.values { task.cancel() }
        pipelines.removeAll()
        outcomes.removeAll()
        // Local cleanup is independent of a stopped upload pipeline.
        requestAllOwnedCleanup()
        phase = .awaitingConsent
    }

    func capture(_ data: Data, pose: SignupBodyPhotoPose, channel: MealSourceChannel) async {
        guard currentOwner, hasAcceptedConsent, !declined, state?.available == true else { return }
        guard channel.isPhoto else { phase = .failed(.invalidInput); return }
        pausePolling()
        // A failed retake can leave the same official photo in place. Its
        // reading age changes only when a fresh snapshot has another ID.
        let previous = tasks[pose]
        let previousNonce = pipelines[pose]?.nonce
        previous?.cancel()
        let nonce = UUID()
        pipelines[pose] = Pipeline(nonce: nonce, data: data, channel: channel)
        let context = Context(epoch: epoch, nonce: nonce, pose: pose)
        await start(context, previous: previous, previousNonce: previousNonce)
    }

    func retry(pose: SignupBodyPhotoPose) async {
        guard currentOwner, hasAcceptedConsent, !declined, state?.available == true,
              tasks[pose] == nil, let pipeline = pipelines[pose] else { return }
        pausePolling()
        await start(Context(epoch: epoch, nonce: pipeline.nonce, pose: pose), previous: nil, previousNonce: nil)
    }

    func invalidate() {
        pausePolling(clearAnchors: true)
        epoch += 1; isActive = false; hasAcceptedConsent = false
        for task in ownedMutationTasks.values { task.cancel() }
        pipelines.removeAll()
        requestAllOwnedCleanup()
        state = nil; phase = .idle
        outcomes.removeAll(); consentResults.removeAll()
    }

    /// Waits for every retained local consumer, including replaced tasks.
    /// Callers handle local file cleanup separately; no remote absence is proved.
    func invalidateAndWaitForOwnedCaptureWork() async {
        let mutations = Array(ownedMutationTasks.values)
        let polls = Array(ownedPollTasks.values)
        invalidate()
        for task in mutations { await task.value }
        for task in polls { await task.value }
    }

    /// Drains only explicitly requested local cleanup. It never waits for a
    /// provider/PUT pipeline, fetches state or deletes server photos. A failed
    /// URL remains requested so a later drain can retry the same bound lease.
    func waitForLocalCleanup() async throws {
        while !cleanupRequested.isEmpty {
            let jobs = Array(cleanupRequested).compactMap { ensureLocalCleanup($0) }
            guard !jobs.isEmpty else { return }
            var firstFailure: (any Error)?
            for job in jobs {
                do { try await job.task.value }
                catch {
                    releaseFailedCleanup(job)
                    if firstFailure == nil { firstFailure = error }
                }
            }
            // Finish this batch before reporting an error; do not retry a
            // failed discard in a loop within this same call.
            if let firstFailure { throw firstFailure }
        }
    }

    private func requestConsent(_ original: MutationAttempt<SignupBodyPhotoConsentRequest>, context: Context) async throws {
        try await boundary(context, consent: true)
        let receipt = try await scope.photos.consent(original)
        try await boundary(context, consent: true)
        consentResults[context.nonce] = receipt
    }

    private func start(_ context: Context, previous: Task<Void, Never>?, previousNonce: UUID?) async {
        guard let pose = context.pose else { return }
        if pipelines[pose]?.nonce == context.nonce { pipelines[pose]?.failure = nil }
        let work = Task {
            defer { self.ownedMutationTasks[context.nonce] = nil }
            do {
                try await self.boundary(context)
                try await self.scope.performWork {
                    if let previous {
                        await previous.value
                        try await self.boundary(context)
                    }
                    if let previousNonce {
                        try await self.discardOwned(previousNonce)
                        try await self.boundary(context)
                    }
                    try await self.executeCapture(context)
                }
                try await self.boundary(context)
                guard let outcome = self.outcomes[context.nonce] else { throw SignupBodyPhotoFailure.unavailable }
                guard outcome.readIdentity == self.readNonce else { throw CancellationError() }
                let elapsed = await self.pollingTiming.elapsed()
                try await self.boundary(context)
                guard outcome.readIdentity == self.readNonce else { throw CancellationError() }
                self.refreshReadingWait(outcome.snapshot, elapsed: elapsed)
                self.state = outcome.snapshot
                self.hasAcceptedConsent = !self.declined && outcome.snapshot.available && outcome.snapshot.consent?.acceptedAt != nil
                self.pipelines[pose]?.failure = outcome.failure
                if let failure = outcome.failure { self.phase = .failed(failure) }
                else { self.phase = self.reading(outcome.snapshot) ? .reading : .ready }
            } catch {
                var failure: any Error = error
                if (Task.isCancelled || error is CancellationError), self.pipelines[pose]?.nonce == context.nonce {
                    self.pipelines[pose]?.data = nil
                }
                if (self.pipelines[pose]?.nonce == context.nonce && self.pipelines[pose]?.completed == true)
                    || error is CancellationError {
                    do { try await self.discardOwned(context.nonce) }
                    catch {
                        // A live caller sees cleanup failure; superseded/cancelled
                        // callers still cannot publish through the context guard.
                        failure = error
                    }
                }
                self.publishFailure(failure, context)
            }
            self.outcomes[context.nonce] = nil
        }
        tasks[pose] = work
        ownedMutationTasks[context.nonce] = work
        await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        if pipelines[pose]?.nonce == context.nonce { tasks[pose] = nil }
        armPollingIfNeeded()
    }

    private func executeCapture(_ context: Context) async throws {
        guard let pose = context.pose else { throw SignupBodyPhotoFailure.invalidInput }
        try await boundary(context)
        if pipelines[pose]?.completed != true {
            if pipelines[pose]?.uploaded != true {
                if pipelines[pose]?.staged == nil {
                    guard let input = pipelines[pose], let data = input.data else { throw CancellationError() }
                    phase = .preparing
                    let staged = try await scope.stagePhoto(data, input.channel)
                    // Keep ownership privately even if the stage result is late.
                    ownedFiles[context.nonce] = staged.fileURL
                    // Even a cancelled caller no longer needs the raw input.
                    // Never clear a newer capture's input for the same pose.
                    if pipelines[pose]?.nonce == context.nonce { pipelines[pose]?.data = nil }
                    do { try check(context) }
                    catch {
                        // Invalidation may precede a non-cooperative stage's
                        // return. Keep and clean this exact late URL privately.
                        _ = requestLocalCleanup(context.nonce)
                        throw error
                    }
                    try await boundary(context)
                    guard staged.kind == .signupBodyPhoto, staged.mimeType == "image/jpeg", staged.channel.isPhoto,
                          staged.duration == nil, (1...MealMediaLimits.maximumPhotoBytes).contains(staged.sizeBytes)
                    else { throw SignupBodyPhotoFailure.invalidInput }
                    // From this point retries use only the protected file and
                    // immutable attempts, never a second raw-image cache.
                    pipelines[pose]?.staged = staged
                }
                guard let staged = pipelines[pose]?.staged else { throw SignupBodyPhotoFailure.unavailable }
                if pipelines[pose]?.createAttempt == nil {
                    pipelines[pose]?.createAttempt = try attempt(.mediaCreate,
                        payload: SignupBodyPhotoCreateRequest(pose: pose, mimeType: staged.mimeType, sizeBytes: staged.sizeBytes))
                }
                guard let original = pipelines[pose]?.createAttempt else { throw SignupBodyPhotoFailure.unavailable }
                phase = .sending
                try await boundary(context)
                // Keep uncertain CREATEs durably, using the same operation on retry.
                // A cancelled wait cannot prove that the server received nothing.
                try await scope.rememberUnboundCreate(context.nonce)
                try await boundary(context)
                let created = try await scope.photos.create(original)
                try await boundary(context)
                guard created.photo.pose == pose, UUID(uuidString: created.photo.id) != nil else { throw SignupBodyPhotoFailure.invalidInput }
                if let prior = pipelines[pose]?.assetID, prior != created.photo.id { throw SignupBodyPhotoFailure.unavailable }
                pipelines[pose]?.assetID = created.photo.id
                if created.photo.status == "pending_upload", let ticket = created.upload {
                    try await boundary(context)
                    try await scope.uploader.upload(staged, with: ticket)
                    try await boundary(context)
                    pipelines[pose]?.uploaded = true
                } else {
                    let authoritative = try await fetchState(context)
                    guard let photo = authoritative.poses.first(where: { $0.pose == pose })?.photo,
                          photo.id == created.photo.id else { throw SignupBodyPhotoFailure.unavailable }
                    switch photo.status {
                    case "uploaded": pipelines[pose]?.uploaded = true
                    case "reading", "read", "unreadable", "reading_failed":
                        pipelines[pose]?.uploaded = true; pipelines[pose]?.completed = true
                        outcomes[context.nonce] = Outcome(snapshot: authoritative, failure: photo.status == "reading_failed" ? .readingFailed : nil, readIdentity: readNonce)
                        try await discardOwned(context.nonce)
                        try await boundary(context)
                        return
                    default:
                        // A pending replay without a ticket cannot authorize PUT or complete.
                        outcomes[context.nonce] = Outcome(snapshot: authoritative, failure: .unavailable, readIdentity: readNonce)
                        return
                    }
                }
            }
            guard let assetID = pipelines[pose]?.assetID else { throw SignupBodyPhotoFailure.unavailable }
            if pipelines[pose]?.completeAttempt == nil {
                pipelines[pose]?.completeAttempt = try attempt(.mediaComplete, payload: MediaAssetCommand(assetID: assetID))
            }
            guard let original = pipelines[pose]?.completeAttempt else { throw SignupBodyPhotoFailure.unavailable }
            try await boundary(context)
            let completed = try await scope.photos.complete(original)
            try await boundary(context)
            guard completed.photo.id == assetID, completed.photo.pose == pose else { throw SignupBodyPhotoFailure.invalidInput }
            pipelines[pose]?.completed = true
        }
        // A confirmed POST is never repeated because its following GET failed.
        let authoritative = try await fetchState(context)
        guard let assetID = pipelines[pose]?.assetID,
              let photo = authoritative.poses.first(where: { $0.pose == pose })?.photo, photo.id == assetID
        else { throw SignupBodyPhotoFailure.unavailable }
        let failure: SignupBodyPhotoFailure?
        switch photo.status {
        case "read", "unreadable", "uploaded", "reading": failure = nil
        case "reading_failed": failure = .readingFailed
        default: failure = .unavailable
        }
        outcomes[context.nonce] = Outcome(snapshot: authoritative, failure: failure, readIdentity: readNonce)
        try await discardOwned(context.nonce)
        try await boundary(context)
    }

    private func fetchState(_ context: Context, consent: Bool = false) async throws -> SignupBodyPhotoState {
        try await boundary(context, consent: consent)
        let request = UUID(); readNonce = request
        do {
            let snapshot = try await scope.photos.state()
            try await boundary(context, consent: consent)
            guard readNonce == request else { throw CancellationError() }
            return snapshot
        } catch {
            try check(context, consent: consent)
            guard readNonce == request else { throw CancellationError() }
            throw error
        }
    }

    private var currentOwner: Bool {
        isActive && !Task.isCancelled && scope.userID == ownerToken.userID && isCurrentOwner(ownerToken)
    }
    private func check(_ context: Context, consent: Bool = false) throws {
        guard currentOwner, epoch == context.epoch else { throw CancellationError() }
        if let pose = context.pose {
            guard pipelines[pose]?.nonce == context.nonce else { throw CancellationError() }
        } else {
            guard (consent ? consentNonce : loadNonce) == context.nonce else { throw CancellationError() }
        }
    }
    private func boundary(_ context: Context, consent: Bool = false) async throws {
        try check(context, consent: consent)
        try await scope.validateSession()
        try check(context, consent: consent)
    }
    private func attempt<P: Hashable & Sendable>(_ operation: MutationOperation, payload: P) throws -> MutationAttempt<P> {
        MutationAttempt(operation: operation, key: try keyProvider.nextKey(), payload: payload, createdAt: timeProvider.now)
    }
    private func reading(_ snapshot: SignupBodyPhotoState) -> Bool {
        snapshot.poses.contains { $0.photo?.status == "uploaded" || $0.photo?.status == "reading" }
    }
    private func publishFailure(_ error: any Error, _ context: Context, consent: Bool = false) {
        do { try check(context, consent: consent) } catch { return }
        if let outcome = outcomes[context.nonce], outcome.readIdentity != readNonce { return }
        if error is CancellationError { return }
        let failure = SignupBodyPhotoFailure(error)
        if failure == .sessionChanged { invalidate(); return }
        if let pose = context.pose { pipelines[pose]?.failure = failure }
        if failure == .consentRequired || failure == .ageNotAllowed || failure == .signupCompleted { hasAcceptedConsent = false }
        phase = .failed(failure)
    }

    private func refreshReadingWait(_ snapshot: SignupBodyPhotoState, elapsed: Duration) {
        lastReadingElapsed = elapsed
        guard snapshot.available, !declined, snapshot.consent?.acceptedAt != nil else {
            readingAnchors.removeAll(); hasExceededReadingWait = false
            return
        }
        var next: [SignupBodyPhotoPose: ReadingAnchor] = [:]
        for slot in snapshot.poses {
            guard let photo = slot.photo, photo.status == "uploaded" || photo.status == "reading" else { continue }
            if let old = readingAnchors[slot.pose], old.assetID == photo.id { next[slot.pose] = old }
            else { next[slot.pose] = ReadingAnchor(assetID: photo.id, startedAt: elapsed) }
        }
        readingAnchors = next
        updateReadingWaitFlag()
    }

    private func updateReadingWaitFlag() {
        hasExceededReadingWait = readingAnchors.values.contains {
            lastReadingElapsed - $0.startedAt > .seconds(120)
        }
    }

    private func armPollingIfNeeded() {
        guard currentOwner, hasAcceptedConsent, !declined, phase == .reading,
              let snapshot = state, snapshot.available, reading(snapshot), pollTask == nil,
              tasks.values.allSatisfy({ $0.isCancelled }) else { return }
        pollNonce = UUID(); pollStartedNonce = nil; lastPollStoppedSuccessfully = false
        pollTerminal = nil; pollReadIdentity = nil
        let context = PollContext(epoch: epoch, nonce: pollNonce)
        let work = Task { await self.runPoll(context) }
        pollTask = work
        ownedPollTasks[context.nonce] = work
    }

    private func runPoll(_ context: PollContext) async {
        var stoppedSuccessfully = false
        do {
            try await pollBoundary(context)
            try await scope.performWork { try await self.pollLoop(context) }
            // The scope's finish is complete before terminal publication.
            try await pollBoundary(context)
            guard let terminal = pollTerminal, terminal.readIdentity == readNonce else { throw CancellationError() }
            let elapsed = await pollingTiming.elapsed()
            try await pollBoundary(context)
            guard terminal.readIdentity == readNonce else { throw CancellationError() }
            publishPollSnapshot(terminal.snapshot, elapsed: elapsed)
            stoppedSuccessfully = true
        } catch {
            // An old success or error never publishes through a new owner,
            // capture, explicit read, or poll generation.
            do {
                try checkPoll(context)
                if let identity = pollReadIdentity, identity != readNonce { throw CancellationError() }
                if !(error is CancellationError) {
                    let failure = SignupBodyPhotoFailure(error)
                    if failure == .sessionChanged { invalidate() }
                    else { phase = .failed(failure) }
                }
            } catch { /* obsolete/cancelled work has no public effect */ }
        }
        finishPolling(context, successfully: stoppedSuccessfully)
    }

    private func pollLoop(_ context: PollContext) async throws {
        while true {
            try await pollBoundary(context)
            signalPollStarted(context)
            try await pollingTiming.sleep(.milliseconds(1_500))
            try await pollBoundary(context)
            let request = UUID(); readNonce = request; pollReadIdentity = request
            let snapshot: SignupBodyPhotoState
            do {
                snapshot = try await scope.photos.state()
                try await pollBoundary(context)
                guard request == readNonce else { throw CancellationError() }
            } catch {
                try checkPoll(context)
                guard request == readNonce else { throw CancellationError() }
                throw error
            }
            let elapsed = await pollingTiming.elapsed()
            try await pollBoundary(context)
            guard request == readNonce else { throw CancellationError() }
            if snapshot.available, !declined, snapshot.consent?.acceptedAt != nil, reading(snapshot) {
                publishPollSnapshot(snapshot, elapsed: elapsed)
            } else {
                pollTerminal = Outcome(snapshot: snapshot, failure: nil, readIdentity: request)
                return
            }
        }
    }

    private func publishPollSnapshot(_ snapshot: SignupBodyPhotoState, elapsed: Duration) {
        refreshReadingWait(snapshot, elapsed: elapsed)
        state = snapshot
        hasAcceptedConsent = !declined && snapshot.available && snapshot.consent?.acceptedAt != nil
        if !snapshot.available { phase = .failed(.unavailable) }
        else if !hasAcceptedConsent { phase = .awaitingConsent }
        else if reading(snapshot) { phase = .reading }
        else if snapshot.poses.contains(where: { $0.photo?.status == "reading_failed" }) { phase = .failed(.readingFailed) }
        else { phase = .ready }
    }

    private func checkPoll(_ context: PollContext) throws {
        guard currentOwner, epoch == context.epoch, pollNonce == context.nonce else { throw CancellationError() }
    }

    private func pollBoundary(_ context: PollContext) async throws {
        try checkPoll(context)
        try await scope.validateSession()
        try checkPoll(context)
    }

    private func signalPollStarted(_ context: PollContext) {
        guard pollNonce == context.nonce else { return }
        pollStartedNonce = context.nonce
        resolvePollWaiters(context.nonce, stopped: false, value: true)
    }

    private func finishPolling(_ context: PollContext, successfully: Bool) {
        ownedPollTasks[context.nonce] = nil
        guard pollNonce == context.nonce else { return }
        pollTask = nil; pollTerminal = nil; pollReadIdentity = nil
        lastPollStoppedSuccessfully = successfully
        resolvePollWaiters(context.nonce, stopped: true, value: successfully)
    }

    private func pausePolling(clearAnchors: Bool = false) {
        let old = pollNonce
        pollTask?.cancel(); pollTask = nil
        pollNonce = UUID(); readNonce = UUID()
        pollStartedNonce = nil; lastPollStoppedSuccessfully = false
        pollTerminal = nil; pollReadIdentity = nil
        resolvePollWaiters(old, stopped: true, value: false)
        if clearAnchors { readingAnchors.removeAll(); hasExceededReadingWait = false }
    }

    private func resolvePollWaiters(_ nonce: UUID, stopped: Bool, value: Bool) {
        let ids = pollWaiters.compactMap { id, waiter in
            waiter.nonce == nonce && (stopped || !waiter.untilStopped) ? id : nil
        }
        for id in ids { pollWaiters.removeValue(forKey: id)?.continuation.resume(returning: value) }
    }

    private func cancelPollWaiter(_ id: UUID) {
        pollWaiters.removeValue(forKey: id)?.continuation.resume(returning: false)
    }

    private func requestAllOwnedCleanup() {
        for nonce in Array(ownedFiles.keys) { _ = requestLocalCleanup(nonce) }
    }

    private func requestLocalCleanup(_ nonce: UUID) -> LocalCleanup? {
        cleanupRequested.insert(nonce)
        return ensureLocalCleanup(nonce)
    }

    /// One independent task owns a nonce/URL pair. Reentrant callers reuse its
    /// value; the task calls the lease-bound scope directly, never itself.
    private func ensureLocalCleanup(_ nonce: UUID) -> LocalCleanup? {
        if let existing = localCleanups[nonce] { return existing }
        guard let file = ownedFiles[nonce] else {
            cleanupRequested.remove(nonce)
            return nil
        }
        let token = UUID()
        let discard = scope.discardStaged
        let task = Task { @MainActor in
            do {
                try await discard(file)
                self.finishLocalCleanup(nonce, token: token, file: file)
            } catch {
                // Retain the failed task until a drain/await observes its error,
                // even when it finished before waitForLocalCleanup was called.
                // URL ownership remains for a later explicit retry.
                throw error
            }
        }
        let job = LocalCleanup(nonce: nonce, token: token, file: file, task: task)
        localCleanups[nonce] = job
        return job
    }

    private func releaseFailedCleanup(_ job: LocalCleanup) {
        if localCleanups[job.nonce]?.token == job.token {
            localCleanups[job.nonce] = nil
        }
    }

    private func finishLocalCleanup(_ nonce: UUID, token: UUID, file: URL) {
        guard localCleanups[nonce]?.token == token else { return }
        localCleanups[nonce] = nil
        // Nonce and exact URL checks fence a late cleanup from a new capture.
        guard ownedFiles[nonce] == file else { return }
        ownedFiles[nonce] = nil
        cleanupRequested.remove(nonce)
        for pose in Array(pipelines.keys) {
            if pipelines[pose]?.nonce == nonce, pipelines[pose]?.staged?.fileURL == file {
                pipelines[pose]?.staged = nil
            }
        }
    }

    /// Scope-only cleanup remains valid after this model is invalidated. It
    /// uses no currentOwner/context check and never acquires a new lease.
    private func discardOwned(_ nonce: UUID) async throws {
        guard let job = requestLocalCleanup(nonce) else { return }
        do { try await job.task.value }
        catch { releaseFailedCleanup(job); throw error }
    }
}
