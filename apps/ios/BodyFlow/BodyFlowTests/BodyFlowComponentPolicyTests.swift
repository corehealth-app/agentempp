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
        #expect(BodyFlowMotion.duration(reduceMotion: false, disclosure: false) == 0.22)
        #expect(BodyFlowMotion.duration(reduceMotion: false, disclosure: true) == 0.22)
    }

    @Test func uiLocaleSelectionDoesNotChangeServerLocale() {
        for identifier in ["en", "en_US", "en_GB"] {
            #expect(BodyFlowPresentationLanguage.resolve(Locale(identifier: identifier)) == .englishUnitedStates)
        }
        for identifier in ["pt_BR", "pt_PT", "fr_FR"] {
            #expect(BodyFlowPresentationLanguage.resolve(Locale(identifier: identifier)) == .portugueseBrazil)
        }
    }

    @Test func motionAndOpacityTokensCollapseUnderReduceMotion() {
        for kind in [BodyFlowMotion.Kind.content, .disclosure, .press, .tap, .brand] {
            #expect(BodyFlowMotion.animation(kind, reduceMotion: true) == nil)
            #expect(BodyFlowMotion.animation(kind, reduceMotion: false) != nil)
        }
        #expect(BodyFlowMotion.pressedScale >= 0.98)
        #expect(BodyFlowOpacity.tintWash == 0.10)
        #expect(BodyFlowOpacity.pressed == 0.85)
    }

    @Test func buttonPressFeedbackDropsScaleUnderReduceMotion() {
        #expect(BodyFlowMotion.tapScale == 0.96)
        #expect(BodyFlowButtonStyle.pressedScale(reduceMotion: true) == 1)
        #expect(BodyFlowButtonStyle.pressedScale(reduceMotion: false) == BodyFlowMotion.tapScale)
        #expect(PerformeBrandAction.pulseScale == 1.06)
        #expect(AppShellView.tabArrivalOffset == 6)
    }

    @Test func openingMotionIsBoundedAndStillUnderReduceMotion() {
        #expect(SplashView.loadingTextDelay == .milliseconds(1200))
        #expect(SplashView.breathScale == 1.03)
        #expect(BodyFlowArrival.rise == 8)
        #expect(BodyFlowArrival.delay(index: 0, reduceMotion: false) == 0)
        #expect(BodyFlowArrival.delay(index: 3, reduceMotion: false) == 0.12)
        // A long list never waits more than a quarter second.
        #expect(BodyFlowArrival.delay(index: 40, reduceMotion: false) == 0.24)
        #expect(BodyFlowArrival.delay(index: 40, reduceMotion: true) == 0)
        #expect(BodyFlowShimmer.period == 1.2)
        #expect(BodyFlowShimmer.phase(elapsed: 0) == -1)
        #expect(abs(BodyFlowShimmer.phase(elapsed: 0.6) - 0.5) < 0.0001)
        #expect(abs(BodyFlowShimmer.phase(elapsed: 1.2) - (-1)) < 0.0001)
        #expect(BodyFlowOpacity.shimmer == 0.55)
    }

    @Test func tapHapticsAnswerOnlyThePrimaryActions() {
        #expect(BodyFlowHaptics.Tap.feedback(for: .primary) == .impact(weight: .light))
        for role in [BodyFlowButtonRole.secondary, .tertiary, .destructive] {
            #expect(BodyFlowHaptics.Tap.feedback(for: role) == nil)
        }
        #expect(BodyFlowRowButtonStyle().playsTapFeedback == false)
        #expect(BodyFlowRowButtonStyle.bodyFlowRowAction.playsTapFeedback == true)
        #expect(BodyFlowHaptics.Tap.selection == .selection)
    }

    @Test func rowPressFeedbackDropsScaleUnderReduceMotion() {
        #expect(BodyFlowRowButtonStyle.pressedScale(reduceMotion: true) == 1)
        #expect(BodyFlowRowButtonStyle.pressedScale(reduceMotion: false) == BodyFlowMotion.pressedScale)
        #expect(BodyFlowRowButtonStyle.pressedOpacity(isPressed: true) == BodyFlowOpacity.pressed)
        #expect(BodyFlowRowButtonStyle.pressedOpacity(isPressed: false) == 1)
    }

    /// Section headings must outrank the card titles beneath them. The token
    /// set resolves `sectionTitle` and `cardTitle` to the same font, so the
    /// shared header takes the larger in-content role instead.
    @Test func sectionHeadingsOutrankCardTitles() {
        #expect(BodyFlowTypography.sectionTitle == BodyFlowTypography.cardTitle)
        #expect(BodyFlowTypography.screenTitle != BodyFlowTypography.cardTitle)
    }

    @Test func compactButtonsShareTheRoleContractOfFullWidthButtons() {
        let compact = BodyFlowButtonStyle(role: .secondary, isCompact: true)
        #expect(compact.role == .secondary)
        #expect(compact.isCompact)
        #expect(!compact.isLoading)
        #expect(!BodyFlowButtonStyle(role: .primary).isCompact)
    }

    @Test func loadingButtonsKeepRoleColorsWhileDisabled() {
        for role in BodyFlowButtonRole.allCases {
            #expect(
                role.presentedBackgroundRole(isEnabled: false, isLoading: true)
                    == role.backgroundRole(isEnabled: true)
            )
            #expect(
                role.presentedForegroundRole(isEnabled: false, isLoading: true)
                    == role.foregroundRole(isEnabled: true)
            )
            #expect(role.presentedBackgroundRole(isEnabled: false, isLoading: false) == .disabledFill)
            #expect(role.presentedForegroundRole(isEnabled: false, isLoading: false) == .disabledText)
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

    @Test func emphasizedListRowsLiftToTheElevatedSurface() {
        #expect(BodyFlowListRowStyle.backgroundRole(isEmphasized: false) == .backgroundSecondary)
        #expect(BodyFlowListRowStyle.backgroundRole(isEmphasized: true) == .surfaceElevated)
    }

    @MainActor @Test func progressRestartAppearanceRendersAsThePrimaryRole() {
        #expect(ProgressContentView.role(for: .streakRestart) == .primary)
        let other = ProgressActionAppearance(background: .achievement, foreground: .onAchievement)
        #expect(ProgressContentView.role(for: other) == .secondary)
    }

    @MainActor @Test func routineOutcomesMapToStatusKindsAndResultFeedback() {
        #expect(RoutineActionSummary.kind(for: .idle) == nil)
        #expect(RoutineActionSummary.kind(for: .unavailable) == .unavailable)
        #expect(RoutineActionSummary.feedback(for: .success) == .success)
        #expect(RoutineActionSummary.feedback(for: .error) == .failure)
        #expect(RoutineActionSummary.feedback(for: .unavailable) == nil)
        #expect(RoutineActionSummary.feedback(for: nil) == nil)
    }

    @MainActor @Test func contentMutationGlyphsMapToStatusKinds() {
        func kind(_ image: String) -> BodyFlowStatusLine.Kind {
            PublishedContentDetailView.statusKind(for: ContentMutationPresentation(
                message: "",
                systemImage: image,
                allowsRetry: false
            ))
        }
        #expect(kind("bookmark.fill") == .success)
        #expect(kind("bookmark.slash") == .success)
        #expect(kind("checkmark.circle.fill") == .success)
        #expect(kind("exclamationmark.triangle") == .error)
        #expect(kind("exclamationmark.circle") == .unavailable)
        #expect(kind("arrow.triangle.2.circlepath") == .pending)
        #expect(kind("arrow.clockwise") == .pending)
    }

    @MainActor @Test func reviewedDefaultCardUsesSemanticSurfaceAndKeepsRollbackRole() {
        let grouped = BodyFlowCard { Text("Received value") }
        let legacy = BodyFlowCard(surface: .legacy) { Text("Received value") }
        #expect(legacy.surface == .legacy)
        #expect(grouped.surface == .card)
    }
}
