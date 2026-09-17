import Foundation
import SwiftUI
import Testing
import UIKit
@testable import BodyFlow

@MainActor
@Suite("Premium semantic color contracts")
struct BodyFlowSemanticColorTests {
    // Independent approved literals: catches a wrong theme/role or altered palette.
    private let pairs: [(BodyFlowColor.Role, UInt32, UInt32)] = [
        (.backgroundPrimary, 0xF6EFE3, 0x071E20),
        (.backgroundSecondary, 0xFFFCF6, 0x102D30),
        (.surfaceElevated, 0xFFFFFF, 0x193C40),
        (.surfaceInteractive, 0xFFFFFF, 0x193C40),
        (.brandPrimary, 0x006D67, 0x55D5C7),
        (.onPrimary, 0xFFFFFF, 0x071E20),
        (.brandSecondary, 0x55D5C7, 0x55D5C7),
        (.accentCoral, 0xFF7F6B, 0xFF7F6B),
        (.textPrimary, 0x222528, 0xF6EFE3),
        (.textSecondary, 0x4D6260, 0xB3C7C2),
        (.textTertiary, 0x596E6B, 0x97ACA8),
        (.borderSubtle, 0xD8DED7, 0x355155),
        (.controlBoundary, 0x627A75, 0x8CA7A1),
        (.feedbackPositive, 0x006D67, 0x7CDDCA),
        (.feedbackWarning, 0x8A5A00, 0xF2C976),
        (.feedbackDestructive, 0xB42332, 0xFF98A3),
        (.disabledFill, 0xF0F0E8, 0x193C40),
        (.disabledText, 0x596E6B, 0x97ACA8),
        (.heroBackground, 0x003B3B, 0x003B3B),
        (.onHero, 0xF6EFE3, 0xF6EFE3),
        (.heroSupporting, 0xB3C7C2, 0xB3C7C2),
        (.achievement, 0xD4AF7A, 0xD4AF7A),
        (.onAchievement, 0x222528, 0x222528),
    ]

    @Test func exactPairsAndNativeTraitResolution() throws {
        #expect(Set(pairs.map(\.0)) == Set(BodyFlowColor.Role.allCases))
        for (role, light, dark) in pairs {
            for (isDark, expected) in [(false, light), (true, dark)] {
                #expect(BodyFlowColor.hex(role, dark: isDark) == expected)
                let color = UIColor(BodyFlowColor.color(role)).resolvedColor(
                    with: UITraitCollection(userInterfaceStyle: isDark ? .dark : .light)
                )
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                try #require(color.getRed(&r, green: &g, blue: &b, alpha: &a))
                #expect(abs(r - CGFloat((expected >> 16) & 255) / 255) < 0.001)
                #expect(abs(g - CGFloat((expected >> 8) & 255) / 255) < 0.001)
                #expect(abs(b - CGFloat(expected & 255) / 255) < 0.001)
                #expect(a == 1)
            }
        }
    }

    @Test func readableForegroundsOnEveryApprovedThemeSurface() {
        let foregrounds: [BodyFlowColor.Role] = [
            .textPrimary, .textSecondary, .textTertiary, .brandPrimary,
            .feedbackPositive, .feedbackWarning, .feedbackDestructive,
        ]
        let surfaces: [BodyFlowColor.Role] = [
            .backgroundPrimary, .backgroundSecondary, .surfaceElevated,
        ]
        for dark in [false, true] {
            for foreground in foregrounds {
                for surface in surfaces {
                    #expect(ratio(foreground, surface, dark: dark) >= 4.5)
                }
            }
            for surface in surfaces {
                #expect(ratio(.controlBoundary, surface, dark: dark) >= 3)
            }
            let pairedForegrounds: [(BodyFlowColor.Role, BodyFlowColor.Role)] = [
                (BodyFlowColor.Role.onPrimary, .brandPrimary),
                (.onHero, .heroBackground), (.heroSupporting, .heroBackground),
                (.disabledText, .disabledFill), (.onAchievement, .achievement),
            ]
            for (foreground, background) in pairedForegrounds {
                #expect(ratio(foreground, background, dark: dark) >= 4.5)
            }
        }
    }

    private func ratio(_ a: BodyFlowColor.Role, _ b: BodyFlowColor.Role, dark: Bool) -> Double {
        let x = luminance(BodyFlowColor.hex(a, dark: dark))
        let y = luminance(BodyFlowColor.hex(b, dark: dark))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private func luminance(_ hex: UInt32) -> Double {
        func linear(_ channel: UInt32) -> Double {
            let c = Double(channel) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear((hex >> 16) & 255)
            + 0.7152 * linear((hex >> 8) & 255) + 0.0722 * linear(hex & 255)
    }
}
