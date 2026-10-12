import Foundation
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import BodyFlow

@Suite("Signup photo retained capture scope")
struct SignupBodyPhotoCaptureScopeTests {
    private static let a = "00000000-0000-4000-8000-00000000c701"
    private static let b = "00000000-0000-4000-8000-00000000c702"

    @Test("The entire signup operation is registered, not only its PUT")
    func entirePipelineIsRegistered() async throws {
        let lifecycle = PhotoScopeLifecycle(userID: Self.a)
        let scope = try await capability(lifecycle, PhotoScopeUploader(), MediaStagingStore()).scoped(Self.a)
        let peer = PhotoScopeWorkPeer()
        var failure = false
        do { try await scope.performWork { await peer.enter() } } catch { failure = true }
        #expect(!failure)
        #expect(await peer.calls == 1)
        #expect(await lifecycle.began == 1)
        #expect(await lifecycle.finished == 1)
        #expect(await lifecycle.activeCount == 0)
    }

    @Test("Staged discard is owner gated and removes only its own capture")
    func discardUsesBoundLocalGate() async throws {
        let lifecycle = PhotoScopeLifecycle(userID: Self.a)
        let staging = MediaStagingStore(temporaryDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: staging.root.deletingLastPathComponent()) }
        let scope = try await capability(lifecycle, PhotoScopeUploader(), staging).scoped(Self.a)
        let data = try image()
        let first = try await scope.stagePhoto(data, .camera)
        let other = try await scope.stagePhoto(data, .gallery)
        var failure = false
        do { try await scope.discardStaged(first.fileURL) } catch { failure = true }
        #expect(!failure)
        #expect(!FileManager.default.fileExists(atPath: first.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: other.fileURL.path))
        #expect(await lifecycle.localWrites == 3)
    }

    @Test("Cancellation does not prevent cleanup of the same owner's local file")
    func cancelledCallerCanDiscardOwnFile() async throws {
        let lifecycle = PhotoScopeLifecycle(userID: Self.a)
        let staging = MediaStagingStore(temporaryDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: staging.root.deletingLastPathComponent()) }
        let scope = try await capability(lifecycle, PhotoScopeUploader(), staging).scoped(Self.a)
        let data = try image()
        let own = try await scope.stagePhoto(data, .camera)
        let other = try await scope.stagePhoto(data, .gallery)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await scope.discardStaged(own.fileURL)
        }
        var failure = false
        do { try await task.value } catch { failure = true }
        #expect(!failure)
        #expect(!FileManager.default.fileExists(atPath: own.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: other.fileURL.path))
        #expect(await lifecycle.localWrites == 3)
    }

    @Test("A retained scope cannot discard files or register work in a later session", arguments: [false, true])
    func oldScopeCannotDiscardOrRegister(returnToA: Bool) async throws {
        let lifecycle = PhotoScopeLifecycle(userID: Self.a)
        let scope = try await capability(lifecycle, PhotoScopeUploader(), MediaStagingStore()).scoped(Self.a)
        await lifecycle.move(to: Self.b)
        if returnToA { await lifecycle.move(to: Self.a) }
        await #expect(throws: SessionLifecycleError.sessionSuperseded) {
            try await scope.discardStaged(URL(fileURLWithPath: "/synthetic/not-opened.jpg"))
        }
        await #expect(throws: SessionLifecycleError.sessionSuperseded) { try await scope.performWork {} }
        #expect(await lifecycle.began == 0)
        #expect(await lifecycle.localWrites == 0)
    }

    @Test("Live scope binds the owner once and stages a protected signup JPEG")
    func stagesOnlyForBoundOwner() async throws {
        let lifecycle = PhotoScopeLifecycle(userID: Self.a)
        let staging = MediaStagingStore(temporaryDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: staging.root.deletingLastPathComponent()) }
        let uploader = PhotoScopeUploader()
        let capability = capability(lifecycle, uploader, staging)
        let scope = try? await capability.scoped(Self.a)
        #expect(scope?.userID == Self.a)
        let bound = try #require(scope)
        let jpeg = try image()
        let staged = try await bound.stagePhoto(jpeg, .camera)
        #expect(staged.kind == .signupBodyPhoto)
        #expect(staged.mimeType == "image/jpeg")
        #expect(FileManager.default.fileExists(atPath: staged.fileURL.path))
        #expect(await lifecycle.localWrites == 1)
        #expect(await uploader.calls == 0)
        bound.staging.remove(staged.fileURL)
    }

    @Test("A retained A scope cannot stage in B or a later A", arguments: [false, true])
    func oldScopeCannotRebind(returnToA: Bool) async throws {
        let lifecycle = PhotoScopeLifecycle(userID: Self.a)
        let staging = MediaStagingStore(temporaryDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: staging.root.deletingLastPathComponent()) }
        let bound = try? await capability(lifecycle, PhotoScopeUploader(), staging).scoped(Self.a)
        #expect(bound != nil)
        let scope = try #require(bound)
        await lifecycle.move(to: Self.b)
        if returnToA { await lifecycle.move(to: Self.a) }
        await #expect(throws: SessionLifecycleError.sessionSuperseded) { try await scope.validateSession() }
        let data = try image()
        await #expect(throws: SessionLifecycleError.sessionSuperseded) { _ = try await scope.stagePhoto(data, .gallery) }
        #expect(await lifecycle.localWrites == 0)
        #expect(!FileManager.default.fileExists(atPath: staging.root.path))
    }

    @Test("The factory refuses an owner different from the current lease")
    func factoryRejectsDifferentOwner() async throws {
        let lifecycle = PhotoScopeLifecycle(userID: Self.a)
        await #expect(throws: SessionLifecycleError.sessionSuperseded) {
            _ = try await capability(lifecycle, PhotoScopeUploader(), MediaStagingStore()).scoped(Self.b)
        }
    }

    @Test("A PUT is registered as patient work and finishes its registration")
    func registeredUpload() async throws {
        let lifecycle = PhotoScopeLifecycle(userID: Self.a)
        let uploader = PhotoScopeUploader()
        let bound = SignupSessionBoundUploader(uploader: uploader, lifecycle: lifecycle, lease: try await lifecycle.leaseForRequest())
        var failure = false
        do { try await bound.upload(media, with: ticket) } catch { failure = true }
        #expect(!failure)
        #expect(await uploader.calls == 1)
        #expect(await lifecycle.began == 1)
        #expect(await lifecycle.finished == 1)
        #expect(await lifecycle.activeCount == 0)
    }

    @Test("A PUT after a session switch sends no bytes")
    func oldUploadCannotStart() async throws {
        let lifecycle = PhotoScopeLifecycle(userID: Self.a)
        let uploader = PhotoScopeUploader()
        let bound = SignupSessionBoundUploader(uploader: uploader, lifecycle: lifecycle, lease: try await lifecycle.leaseForRequest())
        await lifecycle.move(to: Self.b)
        await #expect(throws: SessionLifecycleError.sessionSuperseded) { try await bound.upload(media, with: ticket) }
        #expect(await uploader.calls == 0)
        #expect(await lifecycle.activeCount == 0)
    }

    @Test("A late PUT result from A is refused after B or a later A", arguments: [false, true])
    func lateUploadCannotPublish(returnToA: Bool) async throws {
        let lifecycle = PhotoScopeLifecycle(userID: Self.a)
        let uploader = PhotoScopeUploader(holdsResult: true)
        let bound = SignupSessionBoundUploader(uploader: uploader, lifecycle: lifecycle, lease: try await lifecycle.leaseForRequest())
        let task = Task { try await bound.upload(media, with: ticket) }
        await uploader.waitUntilStarted()
        await lifecycle.move(to: Self.b)
        if returnToA { await lifecycle.move(to: Self.a) }
        // Deliberately ignores cancellation: a peer already accepted bytes.
        await uploader.finish()
        await #expect(throws: SessionLifecycleError.sessionSuperseded) { try await task.value }
        #expect(await lifecycle.finished == 1)
        #expect(await lifecycle.activeCount == 0)
    }

    @Test("Cancelling the local wait keeps its late result cancelled")
    func cancelledUploadCannotSucceed() async throws {
        let lifecycle = PhotoScopeLifecycle(userID: Self.a)
        let uploader = PhotoScopeUploader(holdsResult: true)
        let bound = SignupSessionBoundUploader(uploader: uploader, lifecycle: lifecycle, lease: try await lifecycle.leaseForRequest())
        let task = Task { try await bound.upload(media, with: ticket) }
        await uploader.waitUntilStarted()
        task.cancel()
        await uploader.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await lifecycle.finished == 1)
        #expect(await lifecycle.activeCount == 0)
    }

    @Test("An upload error finishes registration and preserves its error")
    func uploadErrorFinishesWork() async throws {
        let lifecycle = PhotoScopeLifecycle(userID: Self.a)
        let uploader = PhotoScopeUploader(failure: .uploadRejected)
        let bound = SignupSessionBoundUploader(uploader: uploader, lifecycle: lifecycle, lease: try await lifecycle.leaseForRequest())
        await #expect(throws: MealCaptureFailure.uploadRejected) { try await bound.upload(media, with: ticket) }
        #expect(await uploader.calls == 1)
        #expect(await lifecycle.finished == 1)
        #expect(await lifecycle.activeCount == 0)
    }

    @Test("Generic meal media cannot pass through the signup uploader")
    func refusesMealUpload() async throws {
        let lifecycle = PhotoScopeLifecycle(userID: Self.a)
        let uploader = PhotoScopeUploader()
        let bound = SignupSessionBoundUploader(uploader: uploader, lifecycle: lifecycle, lease: try await lifecycle.leaseForRequest())
        let meal = StagedMedia(fileURL: media.fileURL, kind: .mealPhoto, mimeType: "image/jpeg", sizeBytes: 1, duration: nil, channel: .camera)
        await #expect(throws: SignupBodyPhotoFailure.invalidInput) { try await bound.upload(meal, with: ticket) }
        #expect(await uploader.calls == 0)
        #expect(await lifecycle.began == 0)
    }

    @Test("Cancellation before child installation never starts the PUT")
    func cancellationAtRegistrationBoundary() async throws {
        let lifecycle = PhotoScopeLifecycle(userID: Self.a, switchOnBegin: Self.b)
        let uploader = PhotoScopeUploader()
        let bound = SignupSessionBoundUploader(uploader: uploader, lifecycle: lifecycle, lease: try await lifecycle.leaseForRequest())
        var rejected = false
        do { try await bound.upload(media, with: ticket) } catch { rejected = true }
        #expect(rejected)
        #expect(await uploader.calls == 0)
        #expect(await lifecycle.began == 1)
        #expect(await lifecycle.finished == 1)
        #expect(await lifecycle.activeCount == 0)
    }

    @Test("A→B→A while finishing patient work refuses the old result", arguments: [false, true])
    func switchDuringFinishCannotSucceed(returnToA: Bool) async throws {
        let lifecycle = PhotoScopeLifecycle(userID: Self.a, holdsFinish: true)
        let uploader = PhotoScopeUploader()
        let bound = SignupSessionBoundUploader(uploader: uploader, lifecycle: lifecycle, lease: try await lifecycle.leaseForRequest())
        let task = Task { try await bound.upload(media, with: ticket) }
        await lifecycle.waitUntilFinishing()
        await lifecycle.move(to: Self.b)
        if returnToA { await lifecycle.move(to: Self.a) }
        await lifecycle.releaseFinish()
        await #expect(throws: SessionLifecycleError.sessionSuperseded) { try await task.value }
        #expect(await lifecycle.finished == 1)
        #expect(await lifecycle.activeCount == 0)
    }

    @Test("Cancel while finishing patient work cannot return success")
    func cancelDuringFinishCannotSucceed() async throws {
        let lifecycle = PhotoScopeLifecycle(userID: Self.a, holdsFinish: true)
        let bound = SignupSessionBoundUploader(uploader: PhotoScopeUploader(), lifecycle: lifecycle, lease: try await lifecycle.leaseForRequest())
        let task = Task { try await bound.upload(media, with: ticket) }
        await lifecycle.waitUntilFinishing()
        task.cancel()
        await lifecycle.releaseFinish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await lifecycle.finished == 1)
        #expect(await lifecycle.activeCount == 0)
    }

    private func capability(_ lifecycle: PhotoScopeLifecycle, _ uploader: PhotoScopeUploader, _ staging: MediaStagingStore) -> SignupBodyPhotoCaptureCapability {
        .live(transport: MobileAPITransport(configuration: nil, sessionLifecycle: lifecycle, session: .shared, clock: ContinuousClock()),
              lifecycle: lifecycle, uploader: uploader, staging: staging, camera: .unavailable)
    }

    private var media: StagedMedia {
        StagedMedia(fileURL: URL(fileURLWithPath: "/synthetic/no-read.jpg"), kind: .signupBodyPhoto, mimeType: "image/jpeg", sizeBytes: 1, duration: nil, channel: .camera)
    }
    private var ticket: MediaUploadTicket {
        // This test peer never constructs a request or consumes this capability.
        MediaUploadTicket(signedURL: "synthetic-unused", method: "PUT", headers: [:], expiresAt: APITimestamp(value: .distantFuture))
    }
    private func image() throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try #require(context.makeImage()); let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }
}

private actor PhotoScopeWorkPeer {
    private(set) var calls = 0
    func enter() { calls += 1 }
}

private actor PhotoScopeUploader: StorageUploading {
    private(set) var calls = 0
    let holdsResult: Bool
    let failure: MealCaptureFailure?
    private var started: CheckedContinuation<Void, Never>?
    private var result: CheckedContinuation<Void, Never>?
    init(holdsResult: Bool = false, failure: MealCaptureFailure? = nil) {
        self.holdsResult = holdsResult; self.failure = failure
    }
    func upload(_ media: StagedMedia, with ticket: MediaUploadTicket) async throws {
        calls += 1
        started?.resume(); started = nil
        if let failure { throw failure }
        if holdsResult { await withCheckedContinuation { result = $0 } }
    }
    func waitUntilStarted() async {
        if calls > 0 { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish() { result?.resume(); result = nil }
}

private actor PhotoScopeLifecycle: SessionLifecycleProviding {
    private var current: SessionLease
    private let switchOnBegin: String?
    private let holdsFinish: Bool
    private var finishStarted: CheckedContinuation<Void, Never>?
    private var finishReleased: CheckedContinuation<Void, Never>?
    private var work: [UUID: @Sendable () -> Void] = [:]
    private(set) var began = 0
    private(set) var finished = 0
    private(set) var localWrites = 0
    var activeCount: Int { work.count }
    init(userID: String, switchOnBegin: String? = nil, holdsFinish: Bool = false) {
        current = SessionLease(userID: userID, generation: 1, bearer: "synthetic-only")
        self.switchOnBegin = switchOnBegin
        self.holdsFinish = holdsFinish
    }
    func currentBearerToken() async -> String? { current.bearer }
    func leaseForRequest() async throws -> SessionLease { current }
    func validate(_ lease: SessionLease) async throws {
        guard lease.userID == current.userID, lease.generation == current.generation else { throw SessionLifecycleError.sessionSuperseded }
    }
    func move(to userID: String) {
        current = SessionLease(userID: userID, generation: current.generation + 1, bearer: "synthetic-only")
        let pending = Array(work.values); work.removeAll(); for cancel in pending { cancel() }
    }
    func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease { try await validate(lease); return current }
    func signOut() async -> RemoteRevocationOutcome { .unconfirmed }
    func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws -> UUID {
        try await validate(lease); let id = UUID(); work[id] = cancel; began += 1
        if let switchOnBegin { move(to: switchOnBegin) }
        return id
    }
    func finishPatientWork(_ id: UUID) async {
        work[id] = nil; finished += 1
        finishStarted?.resume(); finishStarted = nil
        if holdsFinish { await withCheckedContinuation { finishReleased = $0 } }
    }
    func waitUntilFinishing() async {
        if finished > 0 { return }
        await withCheckedContinuation { finishStarted = $0 }
    }
    func releaseFinish() { finishReleased?.resume(); finishReleased = nil }
    func performPatientStateOperation<Value: Sendable>(lease: SessionLease, operation: @Sendable () throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        try await validate(lease); localWrites += 1; return try operation()
    }
}
