import AVFoundation
import ImageIO
import SwiftUI

/// A bounded display copy for the active chat. Never serialized to the outbox
/// or used as input to an upload or a meal.
struct FlowChatMediaPreview: Sendable {
  let kind: MediaUploadKind
  let duration: TimeInterval?
  let thumbnail: CGImage?

  static func load(_ staged: StagedMedia) async -> Self {
    let thumbnail: CGImage?
    if staged.kind == .audioNote {
      thumbnail = nil
    } else {
      thumbnail = await Task.detached(priority: .utility) {
        guard let source = CGImageSourceCreateWithURL(
          staged.fileURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil as CGImage? }
        return CGImageSourceCreateThumbnailAtIndex(
          source, 0,
          [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 540,
          ] as CFDictionary)
      }.value
    }
    return .init(kind: staged.kind, duration: staged.duration, thumbnail: thumbnail)
  }
}

struct FlowChatAttachmentView: View {
  var preview: FlowChatMediaPreview?
  let english: Bool
  var sent = true

  var body: some View {
    if let image = preview?.thumbnail {
      Image(decorative: image, scale: 1)
        .resizable()
        .scaledToFill()
        .frame(width: 218, height: 128)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel(
          sent ? (english ? "Photo sent" : "Foto enviada") : (english ? "Photo" : "Foto"))
    } else if preview?.kind == .audioNote {
      Label {
        Text(sent ? (english ? "Audio sent" : "Áudio enviado") : (english ? "Audio" : "Áudio"))
        if let duration = preview?.duration {
          Text(duration.formatted(.number.precision(.fractionLength(0))) + " s")
            .foregroundStyle(BodyFlowColor.secondaryText)
        }
      } icon: {
        Image(systemName: "waveform").foregroundStyle(BodyFlowColor.accent)
      }
    } else {
      Label(
        preview == nil
          ? (sent ? (english ? "Attachment sent" : "Anexo enviado") : (english ? "Attachment" : "Anexo"))
          : (sent ? (english ? "Photo sent" : "Foto enviada") : (english ? "Photo" : "Foto")),
        systemImage: preview == nil ? "paperclip" : "photo")
    }
  }
}

/// Loads only the selected recording while it still exists in staging.
struct FlowChatAudioDraftButton: View {
  let url: URL
  let english: Bool
  @State private var player: AVAudioPlayer?
  @State private var playing = false
  @State private var unavailable = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        if playing {
          stop()
        } else {
          do {
            let audio = try AVAudioPlayer(contentsOf: url)
            unavailable = !audio.play()
            if !unavailable {
              player = audio
              playing = true
            }
          } catch {
            unavailable = true
          }
        }
      } label: {
        Image(systemName: playing ? "stop.fill" : "play.fill")
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.plain)
      .foregroundStyle(BodyFlowColor.accent)
      .accessibilityLabel(
        playing
          ? (english ? "Stop audio" : "Parar áudio")
          : (english ? "Play audio" : "Ouvir áudio"))
      if unavailable {
        Text(english ? "Audio unavailable" : "Áudio indisponível")
          .font(BodyFlowTypography.caption)
      }
    }
    .task(id: playing) {
      guard playing, let duration = player?.duration else { return }
      try? await Task.sleep(for: .seconds(duration))
      if !Task.isCancelled { stop() }
    }
    .onDisappear { stop() }
  }

  private func stop() {
    player?.stop()
    player = nil
    playing = false
  }
}
