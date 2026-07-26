import SwiftUI
import Testing
import UIKit
@testable import BodyFlow

@MainActor
@Suite("Screen states and design tokens")
struct ScreenStateTests {
    @Test(arguments: [
        (ScreenContentState.loading, ScreenState.loading),
        (ScreenContentState.empty, ScreenState.empty),
        (ScreenContentState.recoverableError, ScreenState.recoverableError),
        (ScreenContentState.offline, ScreenState.offline),
    ])
    func nonContentStatesMapToSharedPresentation(
        contentState: ScreenContentState,
        expectedState: ScreenState
    ) {
        #expect(contentState.screenState == expectedState)
    }

    @Test("loaded content stays feature-owned")
    func loadedContentHasNoSharedPresentation() {
        #expect(ScreenContentState.loaded.screenState == nil)
    }

    @Test(arguments: [
        (
            ScreenState.loading,
            "Carregando",
            "Preparando suas informações.",
            "hourglass",
            false
        ),
        (
            ScreenState.empty,
            "Nada por aqui",
            "Ainda não há conteúdo para mostrar.",
            "tray",
            false
        ),
        (
            ScreenState.recoverableError,
            "Não foi possível carregar",
            "Ocorreu um problema temporário. Tente novamente.",
            "arrow.clockwise",
            true
        ),
        (
            ScreenState.offline,
            "Você está offline",
            "Confira sua conexão e tente novamente.",
            "wifi.slash",
            true
        ),
    ])
    func descriptors(
        state: ScreenState,
        title: String,
        message: String,
        symbol: String,
        showsRetry: Bool
    ) {
        #expect(state.descriptor.title == title)
        #expect(state.descriptor.message == message)
        #expect(state.descriptor.systemImage == symbol)
        #expect(state.descriptor.showsRetry == showsRetry)
    }

    @Test("retry uses the closure supplied by the feature")
    func retry() {
        var callCount = 0
        let view = ScreenStateView(state: .offline) { callCount += 1 }

        view.triggerRetry()

        #expect(callCount == 1)
    }

    @Test("spacing keeps a consistent scale and accessible tap target")
    func spacingScale() {
        #expect([
            BodyFlowSpacing.xxs,
            BodyFlowSpacing.xs,
            BodyFlowSpacing.sm,
            BodyFlowSpacing.md,
            BodyFlowSpacing.lg,
            BodyFlowSpacing.xl,
            BodyFlowSpacing.minimumTapTarget,
        ] == [4, 8, 12, 16, 24, 32, 44])
    }

    @Test("typography uses only system Dynamic Type text styles")
    func dynamicTypeStyles() {
        #expect(BodyFlowTypography.largeTitle == Font.largeTitle)
        #expect(BodyFlowTypography.title == Font.title2)
        #expect(BodyFlowTypography.headline == Font.headline)
        #expect(BodyFlowTypography.body == Font.body)
        #expect(BodyFlowTypography.callout == Font.callout)
        #expect(BodyFlowTypography.caption == Font.caption)
    }

    @Test("semantic brand colors resolve correctly in light appearance")
    func lightSemanticColors() throws {
        try expectRGB(BodyFlowColor.background, style: .light, rgb: (246, 239, 227))
        try expectRGB(BodyFlowColor.primaryText, style: .light, rgb: (34, 37, 40))
        try expectRGB(BodyFlowColor.accent, style: .light, rgb: (0, 109, 103))
        try expectRGB(BodyFlowColor.warning, style: .light, rgb: (255, 127, 107))
        try expectRGB(BodyFlowColor.achievement, style: .light, rgb: (212, 175, 122))
    }

    @Test("semantic brand colors resolve correctly in dark appearance")
    func darkSemanticColors() throws {
        try expectRGB(BodyFlowColor.background, style: .dark, rgb: (34, 37, 40))
        try expectRGB(BodyFlowColor.primaryText, style: .dark, rgb: (246, 239, 227))
        try expectRGB(BodyFlowColor.accent, style: .dark, rgb: (212, 175, 122))
        try expectRGB(BodyFlowColor.warning, style: .dark, rgb: (255, 127, 107))
        try expectRGB(BodyFlowColor.achievement, style: .dark, rgb: (212, 175, 122))
    }

    @Test("surface and secondary text preserve native semantic contrast")
    func nativeSemanticColors() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let surface = UIColor(BodyFlowColor.surface).resolvedColor(with: traits)
            let expectedSurface = UIColor.secondarySystemBackground.resolvedColor(with: traits)
            let secondaryText = UIColor(BodyFlowColor.secondaryText).resolvedColor(with: traits)
            let expectedSecondaryText = UIColor.secondaryLabel.resolvedColor(with: traits)

            #expect(surface.isEqual(expectedSurface))
            #expect(secondaryText.isEqual(expectedSecondaryText))
        }
    }

    private func expectRGB(
        _ color: Color,
        style: UIUserInterfaceStyle,
        rgb: (red: Int, green: Int, blue: Int),
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let resolvedColor = UIColor(color).resolvedColor(with: traits)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        let resolved = resolvedColor.getRed(
            &red,
            green: &green,
            blue: &blue,
            alpha: &alpha
        )
        try #require(resolved, sourceLocation: sourceLocation)

        let divisor = CGFloat(255)
        let expectedRed = CGFloat(rgb.red) / divisor
        let expectedGreen = CGFloat(rgb.green) / divisor
        let expectedBlue = CGFloat(rgb.blue) / divisor
        let tolerance = CGFloat(0.001)

        #expect(abs(red - expectedRed) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(green - expectedGreen) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(blue - expectedBlue) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(alpha - 1) < tolerance, sourceLocation: sourceLocation)
    }
}
