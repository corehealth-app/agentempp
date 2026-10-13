import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// System picker adapter only. FlowSurface owns presentation and Parent owns work.
@MainActor
struct SignupBodyPhotoLibraryPicker: UIViewControllerRepresentable {
    let requestID: UUID
    let finish: @MainActor (UUID, Result<SignupBodyPhotoPickedImage?, any Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(requestID: requestID, finish: finish) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 1
        configuration.filter = .images
        configuration.preferredAssetRepresentationMode = .compatible
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: PHPickerViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let requestID: UUID
        private let finish: @MainActor (UUID, Result<SignupBodyPhotoPickedImage?, any Error>) -> Void
        private var finished = false

        init(requestID: UUID,
            finish: @escaping @MainActor (UUID, Result<SignupBodyPhotoPickedImage?, any Error>) -> Void) {
            self.requestID = requestID; self.finish = finish
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !finished else { return }
            finished = true // claim before invoking a potentially reentrant UI callback
            if results.isEmpty {
                finish(requestID, .success(nil))
            } else if results.count == 1 {
                finish(requestID, .success(SignupBodyPhotoPickedImage(itemProvider: results[0].itemProvider)))
            } else {
                finish(requestID, .failure(SignupBodyPhotoFailure.invalidInput))
            }
            // SDK does not dismiss automatically. FlowSurface first claims
            // this reply by requestID, then clears its presented item.
        }
    }
}

/// The NSItemProvider never leaves MainActor; only its Data/Error cross the
/// SDK completion queue through a guarded Sendable continuation box.
@MainActor
final class SignupBodyPhotoPickedImage {
    private let itemProvider: NSItemProvider
    private var started = false

    init(itemProvider: NSItemProvider) { self.itemProvider = itemProvider }

    func loadData(authorization: SignupBodyPhotoProducerAuthorization) async throws -> Data {
        try await authorization.validate()
        guard !started else { throw SignupBodyPhotoFailure.invalidInput }
        guard let identifier = itemProvider.registeredTypeIdentifiers.first(where: {
            UTType($0)?.conforms(to: .image) == true
        }) else { throw SignupBodyPhotoFailure.unreadableImage }
        started = true
        let data: Data
        do {
            data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, any Error>) in
                let reply = SignupBodyPhotoProviderReply(continuation)
                _ = itemProvider.loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
                    if let error { reply.finish(.failure(error)) }
                    else if let data { reply.finish(.success(data)) }
                    else { reply.finish(.failure(SignupBodyPhotoFailure.unreadableImage)) }
                }
            }
        } catch {
            try await authorization.validate()
            throw error
        }
        try await authorization.validate()
        return data // no decoding, normalization, staging, request or extra cache
    }
}

/// Foundation's callback can run on an arbitrary queue. Lock protects the
/// sole continuation; neither the provider nor UI state is stored here.
private final class SignupBodyPhotoProviderReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, any Error>?
    init(_ continuation: CheckedContinuation<Data, any Error>) { self.continuation = continuation }
    func finish(_ result: Result<Data, any Error>) {
        let once = lock.withLock {
            let value = continuation
            continuation = nil
            return value
        }
        once?.resume(with: result)
    }
}
