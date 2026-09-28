import AVFoundation
import SwiftUI
import UIKit

/// The system camera for one photo of the meal. The photo comes back as
/// bytes; nothing is saved to the library.
struct MealCameraPicker: UIViewControllerRepresentable {
    let finish: @MainActor (Data?) -> Void

    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// Asks for the camera when it was never asked; false when the patient
    /// has refused it.
    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted: false
        @unknown default: false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(finish: finish)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject,
        UIImagePickerControllerDelegate,
        UINavigationControllerDelegate {
        private let finish: @MainActor (Data?) -> Void

        init(finish: @escaping @MainActor (Data?) -> Void) {
            self.finish = finish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let data = (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.9)
            finish(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            finish(nil)
        }
    }
}
