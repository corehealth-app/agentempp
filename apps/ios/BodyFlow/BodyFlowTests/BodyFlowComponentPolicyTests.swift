import Foundation
import SwiftUI
import Testing
@testable import BodyFlow

@Suite("Premium geometry motion and presentation policies")
struct BodyFlowComponentPolicyTests {
    @Test func compactAndComfortableGuttersPreserveScale() {
        #expect(BodyFlowSpacing.screenGutter(usableWidth: 375) == 16)
        #expect(BodyFlowSpacing.screenGutter(usableWidth: 389) == 16)
        #expect(BodyFlowSpacing.screenGutter(usableWidth: 390) == 24)
        #expect(BodyFlowSpacing.screenGutter(usableWidth: 430) == 24)
        #expect(BodyFlowSpacing.minimumTapTarget == 44)
        #expect(BodyFlowRadius.small == 8)
        #expect(BodyFlowRadius.field == 12)
        #expect(BodyFlowRadius.card == 20)
        #expect(BodyFlowElevation.heroOpacity == 0.06)
        #expect(BodyFlowElevation.heroY == 2)
        #expect(BodyFlowElevation.heroBlur == 12)
    }

    @Test func reduceMotionRemovesBothTransitionKinds() {
        #expect(BodyFlowMotion.duration(reduceMotion: true, disclosure: false) == 0)
        #expect(BodyFlowMotion.duration(reduceMotion: true, disclosure: true) == 0)
        #expect(BodyFlowMotion.duration(reduceMotion: false, disclosure: false) == 0.20)
        #expect(BodyFlowMotion.duration(reduceMotion: false, disclosure: true) == 0.25)
    }

    @Test func uiLocaleSelectionDoesNotChangeServerLocale() {
        for identifier in ["en", "en_US", "en_GB"] {
            #expect(BodyFlowPresentationLanguage.resolve(Locale(identifier: identifier)) == .englishUnitedStates)
        }
        for identifier in ["pt_BR", "pt_PT", "fr_FR"] {
            #expect(BodyFlowPresentationLanguage.resolve(Locale(identifier: identifier)) == .portugueseBrazil)
        }
    }

    @Test func premiumTypographyUsesScalableNativeStyles() {
        #expect(BodyFlowTypography.largeTitle == Font.largeTitle.bold())
        #expect(BodyFlowTypography.screenTitle == Font.title2.weight(.semibold))
        #expect(BodyFlowTypography.sectionTitle == Font.headline.weight(.semibold))
        #expect(BodyFlowTypography.cardTitle == Font.headline.weight(.semibold))
        #expect(BodyFlowTypography.supporting == Font.callout)
        #expect(BodyFlowTypography.metricLarge == Font.largeTitle.weight(.semibold).monospacedDigit())
        #expect(BodyFlowTypography.metricSmall == Font.title2.weight(.semibold).monospacedDigit())
        #expect(BodyFlowTypography.button == Font.headline.weight(.semibold))
        #expect(BodyFlowTypography.title == Font.title2)
        #expect(BodyFlowTypography.headline == Font.headline)
        #expect(BodyFlowTypography.callout == Font.callout)
        #expect(BodyFlowTypography.brandCompact == Font.subheadline.weight(.bold))
    }

    @Test func actionRolesPreserveHierarchyAndReadableDisabledPair() {
        #expect(BodyFlowButtonRole.primary.foregroundRole(isEnabled: true) == .onPrimary)
        #expect(BodyFlowButtonRole.primary.backgroundRole(isEnabled: true) == .brandPrimary)
        #expect(BodyFlowButtonRole.secondary.foregroundRole(isEnabled: true) == .brandPrimary)
        #expect(BodyFlowButtonRole.secondary.backgroundRole(isEnabled: true) == .surfaceElevated)
        #expect(BodyFlowButtonRole.tertiary.backgroundRole(isEnabled: true) == nil)
        #expect(BodyFlowButtonRole.destructive.foregroundRole(isEnabled: true) == .feedbackDestructive)
        for role in BodyFlowButtonRole.allCases {
            #expect(role.foregroundRole(isEnabled: false) == .disabledText)
            #expect(role.backgroundRole(isEnabled: false) == .disabledFill)
        }
    }

    @MainActor @Test func reviewedDefaultCardUsesSemanticSurfaceAndKeepsRollbackRole() {
        let grouped = BodyFlowCard { Text("Received value") }
        let legacy = BodyFlowCard(surface: .legacy) { Text("Received value") }
        #expect(legacy.surface == .legacy)
        #expect(grouped.surface == .card)
    }
}
