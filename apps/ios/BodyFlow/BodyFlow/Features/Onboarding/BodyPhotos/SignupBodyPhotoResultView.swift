import Foundation
import SwiftUI

/// Public official values only. Confirmability is a readonly presentation
/// gate; the existing explicit model action remains the final authority.
@MainActor
struct SignupBodyPhotoResultView: View {
    let photos: SignupBodyPhotoPresentationModel
    private let onConfirmed: (@MainActor () -> Void)?
    private let onExit: (@MainActor () -> Void)?
    @Environment(\.locale) private var locale

    init(photos: SignupBodyPhotoPresentationModel,
        onConfirmed: (@MainActor () -> Void)? = nil,
        onExit: (@MainActor () -> Void)? = nil) {
        self.photos = photos
        self.onConfirmed = onConfirmed; self.onExit = onExit
    }

    var body: some View {
        if photos.route == .result {
            let decision = photos.currentEstimateDecision
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                disclosure("onboarding.photos.result.disclaimer.estimate", id: "estimate")
                disclosure("onboarding.photos.result.disclaimer.variation", id: "variation")
                disclosure("onboarding.photos.result.disclaimer.comparison", id: "comparison")
                if let readings = currentReadings {
                    ForEach(readings, id: \.pose) { reading in
                        readingRow(reading)
                    }
                    if let value = decision?.bodyFatPercent,
                       NSDecimalNumber(decimal: value).doubleValue.isFinite {
                        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                            Text(copy("onboarding.photos.result.mean-label"))
                                .font(BodyFlowTypography.sectionTitle)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(percentage(value))
                                .font(BodyFlowTypography.metricSmall)
                                .accessibilityIdentifier("onboarding.photos.result.mean")
                        }
                    }
                    if decision?.usable == false {
                        BodyFlowStatusLine(copy("onboarding.photos.result.unusable"), kind: .unavailable)
                            .accessibilityIdentifier("onboarding.photos.result.unusable")
                    }
                } else {
                    BodyFlowStatusLine(copy("onboarding.photos.result.readings-unavailable"), kind: .unavailable)
                        .accessibilityIdentifier("onboarding.photos.result.readings-unavailable")
                }
                if decision == nil {
                    BodyFlowStatusLine(copy(photos.resultRequiresBiologicalSex
                        ? "onboarding.photos.result.sex-required" : "state.error.detail"), kind: .unavailable)
                        .accessibilityIdentifier("onboarding.photos.result.sex-required")
                }
                Text(copy("onboarding.photos.result.effect"))
                    .font(BodyFlowTypography.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboarding.photos.result.effect")
                Button(copy("onboarding.photos.result.confirm"), action: confirm)
                    .buttonStyle(BodyFlowButtonStyle(role: .primary))
                    .disabled(photos.confirmableEstimate == nil)
                    .accessibilityIdentifier("onboarding.photos.result.confirm")
                Button(copy("onboarding.photos.result.retake")) { _ = photos.beginRetake() }
                    .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                    .accessibilityIdentifier("onboarding.photos.result.retake")
                SignupBodyPhotoDeleteControl(photos: photos)
                Button(copy("onboarding.photos.change-percentage")) { select(.typed) }
                    .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                    .accessibilityIdentifier("onboarding.photos.result.manual")
                Button(copy("onboarding.body-fat.choice.skip")) { select(.skip) }
                    .buttonStyle(BodyFlowButtonStyle(role: .tertiary))
                    .accessibilityIdentifier("onboarding.photos.result.skip")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
    }

    private var currentReadings: [SignupBodyPhotoEstimate.Reading]? {
        guard let readings = photos.capture?.state?.estimate?.readings,
              readings.map(\.pose) == SignupBodyPhotoPose.allCases,
              readings.allSatisfy({ NSDecimalNumber(decimal: $0.bodyFatPercent).doubleValue.isFinite })
        else { return nil }
        return readings
    }

    private func readingRow(_ reading: SignupBodyPhotoEstimate.Reading) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Text(poseTitle(reading.pose)).font(BodyFlowTypography.sectionTitle)
            Text(percentage(reading.bodyFatPercent))
                .font(BodyFlowTypography.metricSmall)
                .accessibilityIdentifier("onboarding.photos.result.reading." + reading.pose.rawValue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func disclosure(_ key: String.LocalizationValue, id: String) -> some View {
        Text(copy(key))
            .font(BodyFlowTypography.body)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("onboarding.photos.result.disclaimer." + id)
    }

    private func confirm() {
        guard photos.confirmableEstimate != nil, photos.confirmEstimate() else { return }
        onConfirmed?()
    }

    private func select(_ choice: SignupBodyFatChoice) {
        guard photos.route == .result else { return }
        photos.select(choice)
        onExit?()
    }

    /// Values are already percentages. Localize their decimal representation
    /// without percent-style multiplication, rounding or mean recomputation.
    private func percentage(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = language.formattingLocale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 38
        let number = formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
        return number + "%"
    }

    private func poseTitle(_ pose: SignupBodyPhotoPose) -> String {
        switch pose {
        case .front: copy("onboarding.photos.pose.front")
        case .side: copy("onboarding.photos.pose.side")
        case .back: copy("onboarding.photos.pose.back")
        }
    }
    private var language: SupportedAppLanguage { BodyFlowPresentationLanguage.resolve(locale) }
    private func copy(_ key: String.LocalizationValue) -> String { OnboardingCopy.string(key, language: language) }
}
