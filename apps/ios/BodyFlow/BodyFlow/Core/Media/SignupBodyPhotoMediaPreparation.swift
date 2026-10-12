import Foundation

struct SignupBodyPhotoStager: Sendable {
    let staging: MediaStagingStore

    func stagePhoto(_ data: Data, channel: MealSourceChannel) throws -> StagedMedia {
        guard channel.isPhoto else { throw SignupBodyPhotoFailure.invalidInput }
        do {
            let photo = try MealMediaStager(staging: staging).stagePhoto(data, channel: channel)
            return StagedMedia(
                fileURL: photo.fileURL, kind: .signupBodyPhoto, mimeType: photo.mimeType,
                sizeBytes: photo.sizeBytes, duration: nil, channel: photo.channel
            )
        } catch {
            throw SignupBodyPhotoFailure(error)
        }
    }
}
