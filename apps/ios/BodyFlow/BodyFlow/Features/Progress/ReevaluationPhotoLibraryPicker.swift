import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// System selection only; no historical gallery, cache or signup authority.
@MainActor
struct ReevaluationPhotoLibraryPicker:UIViewControllerRepresentable {
    let requestID:UUID
    let finish:@MainActor (UUID,Result<ReevaluationPickedPhoto?,any Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(requestID:requestID,finish:finish) }
    func makeUIViewController(context:Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(); config.selectionLimit = 1; config.filter = .images
        config.preferredAssetRepresentationMode = .compatible
        let picker = PHPickerViewController(configuration:config); picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ controller:PHPickerViewController,context:Context) {}
    @MainActor final class Coordinator:NSObject,PHPickerViewControllerDelegate {
        private let requestID:UUID
        private let finish:@MainActor (UUID,Result<ReevaluationPickedPhoto?,any Error>) -> Void
        private var finished = false
        init(requestID:UUID,finish:@escaping @MainActor (UUID,Result<ReevaluationPickedPhoto?,any Error>) -> Void) { self.requestID = requestID; self.finish = finish }
        func picker(_ picker:PHPickerViewController,didFinishPicking results:[PHPickerResult]) {
            guard !finished else { return }; finished = true
            if results.isEmpty { finish(requestID,.success(nil)) }
            else if results.count == 1 { finish(requestID,.success(ReevaluationPickedPhoto(provider:results[0].itemProvider))) }
            else { finish(requestID,.failure(ReevaluationPhotoFailure.invalidInput)) }
        }
    }
}
@MainActor final class ReevaluationPickedPhoto {
    private let provider:NSItemProvider
    private var started = false
    init(provider:NSItemProvider) { self.provider = provider }
    func load() async throws -> Data {
        try Task.checkCancellation()
        guard !started, let type = provider.registeredTypeIdentifiers.first(where:{ UTType($0)?.conforms(to:.image) == true }) else { throw ReevaluationPhotoFailure.invalidInput }
        started = true
        let reply = ReevaluationPickerReply()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard reply.install(continuation) else { return }
                let progress = provider.loadDataRepresentation(forTypeIdentifier:type) { data,error in
                    if let error { reply.finish(.failure(error)) }
                    else if let data { reply.finish(.success(data)) }
                    else { reply.finish(.failure(ReevaluationPhotoFailure.invalidInput)) }
                }
                reply.install(progress)
            }
        } onCancel: { reply.cancel() }
    }
}
/// The SDK may call on any queue or after cancellation. Sole continuation and
/// cancellable SDK progress are locked; no provider/UI/bytes are retained here.
private final class ReevaluationPickerReply:@unchecked Sendable {
    private let lock = NSLock()
    private var continuation:CheckedContinuation<Data,any Error>?
    private var progress:Progress?
    private var finished = false
    func install(_ value:CheckedContinuation<Data,any Error>) -> Bool {
        let allowed = lock.withLock { if finished { return false }; continuation = value; return true }
        if !allowed { value.resume(throwing:CancellationError()) }; return allowed
    }
    func install(_ value:Progress) { let cancelNow = lock.withLock { if finished { return true }; progress = value; return false }; if cancelNow { value.cancel() } }
    func finish(_ result:Result<Data,any Error>) {
        let once = lock.withLock { let value = continuation; continuation = nil; progress = nil; finished = true; return value }
        once?.resume(with:result)
    }
    func cancel() {
        let once = lock.withLock { let value = (continuation,progress); continuation = nil; progress = nil; finished = true; return value }
        once.1?.cancel(); once.0?.resume(throwing:CancellationError())
    }
}
