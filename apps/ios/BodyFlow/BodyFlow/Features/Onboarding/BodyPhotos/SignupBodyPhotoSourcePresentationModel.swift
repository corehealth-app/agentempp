import Foundation
import Observation

/// The UI identity only. Parent/D1 supplies the authority and owns the producer.
struct SignupBodyPhotoSourcePresentation: Identifiable, Sendable {
    let id: UUID
    let channel: MealSourceChannel
    let camera: MealCameraAccess?
}

@MainActor
@Observable
final class SignupBodyPhotoSourcePresentationModel {
    private(set) var presentation: SignupBodyPhotoSourcePresentation?
    @ObservationIgnored private var contexts: [UUID: RequestContext] = [:]
    @ObservationIgnored private var uiRequestID: UUID?

    func request(channel: MealSourceChannel, camera: MealCameraAccess?,
        authorization: SignupBodyPhotoProducerAuthorization) async throws -> Data? {
        guard channel.isPhoto else { throw SignupBodyPhotoFailure.invalidInput }
        // Supersede only an unresolved UI decision. A selected provider for a
        // different pose stays in its original Parent producer until it ends.
        if let previous = uiRequestID { cancel(requestID: previous) }
        let context = RequestContext(channel: channel, camera: camera, authorization: authorization)
        contexts[context.id] = context
        uiRequestID = context.id
        return try await withTaskCancellationHandler {
            defer { finish(context) }
            do {
                try await validate(context)
                if context.userCancelled { return nil }
                if channel == .camera {
                    guard let camera, camera.origin != .none, camera.isAvailable() else {
                        throw SignupBodyPhotoFailure.unavailable
                    }
                    switch camera.permission() {
                    case .denied: throw SignupBodyPhotoFailure.unavailable
                    case .authorized: break
                    case .notAsked:
                        let granted = await camera.requestAccess()
                        try await validate(context)
                        if context.userCancelled { return nil }
                        guard granted else { throw SignupBodyPhotoFailure.unavailable }
                    }
                    guard camera.isAvailable(), camera.permission() != .denied else {
                        throw SignupBodyPhotoFailure.unavailable
                    }
                }
                try check(context)
                guard uiRequestID == context.id else { throw CancellationError() }
                let reply = await withCheckedContinuation { continuation in
                    context.phase = .choosing
                    context.continuation = continuation
                    presentation = .init(id: context.id, channel: channel,
                        camera: channel == .camera ? camera : nil)
                }
                try await validate(context)
                if context.userCancelled { return nil }
                switch reply {
                case .cancelled: return nil
                case .camera(let data): return data
                case .library(.failure(let error)): throw error
                case .library(.success(let selected)):
                    guard let selected else { return nil }
                    context.phase = .loadingData
                    let data = try await selected.loadData(authorization: authorization)
                    try await validate(context)
                    return context.userCancelled ? nil : data
                }
            } catch {
                // An SDK error cannot publish for an obsolete producer either.
                try await validate(context)
                if context.userCancelled { return nil }
                throw error
            }
        } onCancel: {
            // Parent revokes authority synchronously. This hop only closes UI
            // and resolves a pending decision; it never ends a provider await.
            Task { @MainActor [weak self] in self?.cancelWork(context) }
        }
    }

    func finishLibrary(requestID: UUID,
        result: Result<SignupBodyPhotoPickedImage?, any Error>) {
        guard let context = contexts[requestID], context.channel == .gallery else { return }
        resolve(context, reply: .library(result))
    }

    func finishCamera(requestID: UUID, data: Data?) {
        guard let context = contexts[requestID], context.channel == .camera else { return }
        resolve(context, reply: .camera(data))
    }

    func cancel(requestID: UUID) {
        guard let context = contexts[requestID] else { return }
        context.userCancelled = true
        clearUI(context)
        resolve(context, reply: .cancelled)
        // If selected/loadingData, continuation is already nil. Keep the real
        // SDK await alive and discard its result only after it actually returns.
    }

    private func cancelWork(_ context: RequestContext) {
        guard contexts[context.id] === context else { return }
        context.workCancelled = true
        clearUI(context)
        resolve(context, reply: .cancelled)
    }

    private func resolve(_ context: RequestContext, reply: SourceReply) {
        guard contexts[context.id] === context, context.phase == .choosing,
              let continuation = context.continuation else { return }
        context.continuation = nil
        context.phase = .selected
        clearUI(context) // matching ID only; claim precedes resume/dismiss
        continuation.resume(returning: reply)
    }

    private func clearUI(_ context: RequestContext) {
        if presentation?.id == context.id { presentation = nil }
        if uiRequestID == context.id { uiRequestID = nil }
    }

    private func validate(_ context: RequestContext) async throws {
        try check(context)
        try await context.authorization.validate()
        try check(context)
    }

    private func check(_ context: RequestContext) throws {
        try Task.checkCancellation()
        guard contexts[context.id] === context, !context.workCancelled else { throw CancellationError() }
    }

    private func finish(_ context: RequestContext) {
        clearUI(context)
        contexts[context.id] = nil
        context.phase = .finished
    }

    private enum SourceReply: Sendable {
        case cancelled
        case camera(Data?)
        case library(Result<SignupBodyPhotoPickedImage?, any Error>)
    }

    @MainActor
    private final class RequestContext {
        enum Phase { case preparing, choosing, selected, loadingData, finished }
        let id = UUID()
        let channel: MealSourceChannel
        let camera: MealCameraAccess?
        let authorization: SignupBodyPhotoProducerAuthorization
        var userCancelled = false
        var workCancelled = false
        var phase = Phase.preparing
        var continuation: CheckedContinuation<SourceReply, Never>?
        init(channel: MealSourceChannel, camera: MealCameraAccess?,
            authorization: SignupBodyPhotoProducerAuthorization) {
            self.channel = channel; self.camera = camera; self.authorization = authorization
        }
    }
}
