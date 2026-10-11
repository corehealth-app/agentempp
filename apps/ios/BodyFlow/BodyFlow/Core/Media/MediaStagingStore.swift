import Foundation

/// Where a captured photo or recording waits on this phone before its upload.
///
/// Files live in `tmp/performe-media/<uuid>/`, excluded from backup and
/// readable only while the phone is unlocked. Nothing here outlives its use:
/// the capture removes its own file, and the whole folder is emptied at
/// launch and when the session ends.
struct MediaStagingStore: Sendable {
    static let folderName = "performe-media"

    let root: URL

    init(temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        root = temporaryDirectory.appendingPathComponent(Self.folderName, isDirectory: true)
    }

    /// A fresh, protected folder for one capture and the file address in it.
    func makeFileURL(fileExtension: String) throws -> URL {
        let allowed = ["jpg", "m4a", "mp3", "wav", "aac", "ogg", "pdf"]
        guard allowed.contains(fileExtension) else {
            throw MealCaptureFailure.unsupportedFile
        }
        let folder = root.appendingPathComponent(
            UUID().uuidString.lowercased(),
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableRoot = root
            try? mutableRoot.setResourceValues(values)
        } catch {
            throw MealCaptureFailure.unavailable
        }
        return folder.appendingPathComponent("capture.\(fileExtension)", isDirectory: false)
    }

    /// Writes the bytes protected and returns the staged address.
    func stage(_ data: Data, fileExtension: String) throws -> URL {
        let url = try makeFileURL(fileExtension: fileExtension)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            remove(url)
            throw MealCaptureFailure.unavailable
        }
        return url
    }

    /// Copies a file the patient picked into the staging area.
    func stageCopy(of source: URL, fileExtension: String) throws -> URL {
        let url = try makeFileURL(fileExtension: fileExtension)
        do {
            try FileManager.default.copyItem(at: source, to: url)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
        } catch {
            remove(url)
            throw MealCaptureFailure.unreadableMedia
        }
        return url
    }

    /// Removes one staged file with its folder. Addresses outside the staging
    /// area are left alone.
    func remove(_ fileURL: URL) {
        let folder = fileURL.deletingLastPathComponent().standardizedFileURL
        guard folder.deletingLastPathComponent().path == root.standardizedFileURL.path else {
            return
        }
        try? FileManager.default.removeItem(at: folder)
    }

    /// Empties the staging area: at launch and when the session ends.
    func purge() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// The camera as the meal capture needs it — whether there is one, whether
/// the person already answered about it, and how to ask — with no view in
/// it. The views that show a camera live in Features.
struct MealCameraAccess: Sendable {
    enum Permission: Equatable, Sendable {
        case authorized
        /// The system has not asked yet: asking shows its prompt, once.
        case notAsked
        /// Refused or restricted: asking again shows nothing.
        case denied
    }

    enum Origin: Equatable, Sendable {
        /// No camera at all.
        case none
        /// The camera of this iPhone.
        case device
        #if DEBUG
        /// A stand-in a UI test can drive (Debug builds only).
        case synthetic
        #endif
    }

    let origin: Origin
    let isAvailable: @MainActor @Sendable () -> Bool
    let permission: @MainActor @Sendable () -> Permission
    /// Asks the system when it was never asked; true when the camera may
    /// be used.
    let requestAccess: @Sendable () async -> Bool

    /// No camera: nothing is offered and nothing is ever asked.
    static let unavailable = MealCameraAccess(
        origin: .none,
        isAvailable: { false },
        permission: { .denied },
        requestAccess: { false }
    )
}

/// What the meal capture needs from the outside: the BFF for records and
/// candidates, storage for the bytes, the staging area on this phone, and
/// the camera.
struct MealCaptureCapability: Sendable {
    let media: (any MealMediaProviding)?
    let drafts: any MealDraftProviding
    let uploader: (any StorageUploading)?
    let staging: MediaStagingStore
    let camera: MealCameraAccess
}

/// Sign-out and user switch: no capture of the ended session stays on the
/// phone.
struct MediaStagingSessionClearer: SensitiveStateClearing {
    let staging: MediaStagingStore

    func clearSensitiveState() async {
        staging.purge()
    }
}
