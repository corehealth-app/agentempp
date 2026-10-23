import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

#if DEBUG
/// UI-test scenario for the meal capture (Debug builds only): free text
/// becomes synthetic candidates, with no server and no media.
enum DemoMealCaptureScenario {
    static let argument = "--ui-testing-meal-capture"
    static let emptyBreakfastArgument = "--ui-testing-meal-capture-empty-breakfast"
    /// Text that the synthetic reader does not recognize.
    static let unrecognizedText = "xyz"

    /// With the capture: the reader never answers, so a UI test can look at
    /// the wait for as long as it needs and then cancel it.
    static let holdArgument = "--ui-testing-meal-capture-hold"

    /// With the capture: the photo and audio entries are offered too. Every
    /// media call is refused, so nothing is ever sent.
    static let mediaArgument = "--ui-testing-meal-capture-media"

    /// With the capture and the media: a stand-in camera a UI test can
    /// drive. Without it the synthetic capture has no camera at all, so no
    /// test ever raises the system's own camera or its permission prompt.
    static let cameraArgument = "--ui-testing-meal-capture-camera"

    static func isEnabled(arguments: [String]) -> Bool {
        arguments.contains(argument)
    }

    /// The synthetic capture a launch asks for, or `nil`: only the local
    /// demonstration can have one, whatever the arguments say.
    static func capability(
        arguments: [String],
        mode: AppRuntimeMode
    ) -> MealCaptureCapability? {
        guard mode == .demo, isEnabled(arguments: arguments) else { return nil }
        let offersMedia = arguments.contains(mediaArgument)
        return MealCaptureCapability(
            media: offersMedia ? DemoRefusingMealMedia() : nil,
            drafts: DemoMealDraftProvider(
                holdsUntilCancelled: arguments.contains(holdArgument)
            ),
            uploader: offersMedia ? DemoRefusingMealMedia() : nil,
            staging: MediaStagingStore(),
            camera: offersMedia && arguments.contains(cameraArgument)
                ? .synthetic : .unavailable
        )
    }
}

/// Only the explicit capture UI-test launch uses this synthetic empty slot.
/// Other meal slots, totals and global demonstration fixtures stay unchanged.
struct DemoEmptyBreakfastCaptureToday: TodayProviding {
    let base: any TodayProviding

    func today() async throws -> TodayResponse {
        let response = try await base.today()
        guard var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(response)) as? [String: Any],
              var data = object["data"] as? [String: Any],
              let meals = data["meals"] as? [[String: Any]] else {
            throw BodyFlowCapabilityError.operationUnavailable
        }
        data["meals"] = meals.filter { $0["meal_type"] as? String != "cafe" }
        object["data"] = data
        return try JSONDecoder().decode(TodayResponse.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

extension MealCameraAccess {
    /// The stand-in camera of a UI test: there, allowed, and never the
    /// system's.
    static let synthetic = MealCameraAccess(
        origin: .synthetic,
        isAvailable: { true },
        permission: { .authorized },
        requestAccess: { true }
    )
}

/// What the stand-in camera "takes".
enum DemoMealCamera {
    static let sampleSize = 64

    /// A real JPEG, drawn here: one flat square. It goes through the same
    /// preparation as a photo from the system's camera, so a UI test proves
    /// that what the camera hands over reaches the upload.
    static func samplePhoto() -> Data {
        guard let context = CGContext(
            data: nil,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return Data()
        }
        context.setFillColor(red: 0.2, green: 0.6, blue: 0.55, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))
        let output = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(
                  output, UTType.jpeg.identifier as CFString, 1, nil
              )
        else {
            return Data()
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : Data()
    }
}

/// Synthetic candidates; no real account data and nothing calculated.
struct DemoMealDraftProvider: MealDraftProviding {
    /// The read stays pending until the capture is cancelled.
    var holdsUntilCancelled = false

    func draft(
        _ attempt: MutationAttempt<MealDraftRequest>
    ) async throws -> MealDraftSnapshot {
        if holdsUntilCancelled {
            await DemoCancellationGate.waitForCancellation()
            throw CancellationError()
        }
        guard case let .text(text) = attempt.payload,
              text != DemoMealCaptureScenario.unrecognizedText
        else {
            throw MealCaptureFailure.nothingRecognized
        }
        return MealDraftSnapshot(
            source: "text",
            mediaAssetID: nil,
            transcript: nil,
            contextNote: nil,
            items: [
                MealDraftCandidate(
                    candidateID: "c1-0a1b2c3d", name: "ovos mexidos", quantityG: 100,
                    quantityBasis: "portion_reference", count: 2, unitLabel: "unidade",
                    confidence: nil, needsReview: true, reviewReason: "estimated_quantity"
                ),
                MealDraftCandidate(
                    candidateID: "c2-1b2c3d4e", name: "granola", quantityG: nil,
                    quantityBasis: "missing", count: nil, unitLabel: nil,
                    confidence: nil, needsReview: true, reviewReason: "missing_quantity"
                ),
            ],
            nutritionLabel: nil
        )
    }
}

/// Makes the media entries of the capture available to a UI test and refuses
/// every call: the photo step and the recorder can be reached, nothing is
/// created, uploaded or processed.
struct DemoRefusingMealMedia: MealMediaProviding, StorageUploading {
    func create(
        _ attempt: MutationAttempt<MediaUploadRequest>
    ) async throws -> MediaCreateSnapshot {
        throw MealCaptureFailure.captureUnavailable
    }

    func complete(
        _ attempt: MutationAttempt<MediaAssetCommand>
    ) async throws -> MediaAssetSnapshot {
        throw MealCaptureFailure.captureUnavailable
    }

    func requestProcessing(
        _ attempt: MutationAttempt<MediaAssetCommand>
    ) async throws -> MediaAssetSnapshot {
        throw MealCaptureFailure.captureUnavailable
    }

    func asset(id: String) async throws -> MediaAssetSnapshot {
        throw MealCaptureFailure.captureUnavailable
    }

    func delete(_ attempt: MutationAttempt<MediaAssetCommand>) async throws {
        throw MealCaptureFailure.captureUnavailable
    }

    func upload(_ media: StagedMedia, with ticket: MediaUploadTicket) async throws {
        throw MealCaptureFailure.captureUnavailable
    }
}

/// Suspends the caller until its task is cancelled: no timer, no polling.
private final class DemoCancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    static func waitForCancellation() async {
        let gate = DemoCancellationGate()
        await withTaskCancellationHandler {
            await withCheckedContinuation { gate.install($0) }
        } onCancel: {
            gate.open()
        }
    }

    private func install(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        if isOpen {
            lock.unlock()
            continuation.resume()
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    private func open() {
        lock.lock()
        isOpen = true
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume()
    }
}
#endif
