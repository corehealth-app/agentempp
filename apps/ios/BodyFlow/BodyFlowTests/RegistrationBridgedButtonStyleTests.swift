import SwiftUI
import Testing
import UIKit

@testable import BodyFlow

/// iPhone, 2026-10-04, dark mode: "Propor treino", "Registrar hidratação" and
/// "Registrar peso" showed white titles on the light teal fill. The bridged
/// primary button must use the brand pair in both appearances.
@MainActor
@Suite("Registration bridged button style")
struct RegistrationBridgedButtonStyleTests {
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func primaryTitleIsReadableOnItsFill(_ style: UIUserInterfaceStyle) throws {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let configuration = RegistrationBridgedButtonStyle.primary()
        let fill = try #require(configuration.baseBackgroundColor).resolvedColor(with: traits)
        let title = try #require(configuration.baseForegroundColor).resolvedColor(with: traits)

        #expect(try contrast(title, fill) >= 4.5)
        #expect(fill == UIColor(BodyFlowColor.color(.brandPrimary)).resolvedColor(with: traits))
        #expect(title == UIColor(BodyFlowColor.color(.onPrimary)).resolvedColor(with: traits))
    }

    @Test
    func darkTitleIsNotTheSystemWhite() throws {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let title = try #require(RegistrationBridgedButtonStyle.primary().baseForegroundColor)
            .resolvedColor(with: dark)
        #expect(try luminance(title) < 0.2, "white on the light teal fill measured about 1.6:1")
    }

    private func contrast(_ first: UIColor, _ second: UIColor) throws -> CGFloat {
        let a = try luminance(first), b = try luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func luminance(_ color: UIColor) throws -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
        try #require(color.getRed(&r, green: &g, blue: &b, alpha: &alpha))
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
