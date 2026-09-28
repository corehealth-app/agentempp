import SwiftUI

struct MealAudioRecorderView: View {
    let recorder: MealAudioRecorder
    let isBusy: Bool
    let use: @MainActor (URL) -> Void
    let fail: @MainActor (MealCaptureFailure) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Text(copy("registration.live.record.title"))
                .font(BodyFlowTypography.headline)
                .accessibilityAddTraits(.isHeader)
            BodyFlowStatusLine(copy("registration.live.record.hint"), kind: .info)

            Text(verbatim: "\(MealCaptureCopy.clock(recorder.elapsed)) / "
                + MealCaptureCopy.clock(MealMediaLimits.maximumAudioDuration))
                .font(BodyFlowTypography.metricSmall)
                .monospacedDigit()
                .foregroundStyle(BodyFlowColor.primaryText)
                .accessibilityIdentifier("registration.meal.record.elapsed")

            controls
        }
        .onChange(of: recorder.state) { _, state in
            if case let .failed(failure) = state {
                recorder.discard()
                fail(failure)
            }
        }
        .onDisappear { recorder.discard() }
    }

    @ViewBuilder
    private var controls: some View {
        switch recorder.state {
        case .idle, .failed:
            button("registration.live.record.start", role: .primary, id: "start") {
                Task { await recorder.start() }
            }
        case .recording:
            button("registration.live.record.stop", role: .primary, id: "stop") {
                recorder.stop()
            }
        case .finished:
            button("registration.live.record.use", role: .primary, id: "use") {
                if let url = recorder.takeRecording() { use(url) }
            }
            button("registration.live.record.redo", role: .secondary, id: "redo") {
                recorder.discard()
            }
        }
    }

    private func button(
        _ key: String.LocalizationValue,
        role: BodyFlowButtonRole,
        id: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Text(copy(key))
                .frame(maxWidth: .infinity)
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
        }
        .buttonStyle(BodyFlowButtonStyle(role: role))
        .disabled(isBusy)
        .accessibilityIdentifier("registration.meal.record.\(id)")
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(key, language: BodyFlowPresentationLanguage.resolve(locale))
    }
}
