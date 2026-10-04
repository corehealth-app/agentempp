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
        (.backgroundPrimary, 0xF5F6F8, 0x090D10),
        (.backgroundSecondary, 0xFFFFFF, 0x141B20),
        (.surfaceElevated, 0xFFFFFF, 0x1B242A),
        (.surfaceInteractive, 0xFFFFFF, 0x1B242A),
        (.brandPrimary, 0x007A72, 0x3DE0CE),
        (.onPrimary, 0xFFFFFF, 0x06211E),
        (.brandSecondary, 0x55D5C7, 0x55D5C7),
        (.accentCoral, 0xFF7F6B, 0xFF7F6B),
        (.textPrimary, 0x141A21, 0xF2F5F6),
        (.textSecondary, 0x5C6672, 0x9AA7AF),
        (.textTertiary, 0x626C78, 0x8E9BA3),
        (.borderSubtle, 0xE9ECF0, 0x232D34),
        (.controlBoundary, 0x7C8792, 0x70808A),
        (.feedbackPositive, 0x007A72, 0x3DE0CE),
        (.feedbackWarning, 0x8A5A00, 0xFFC24D),
        (.feedbackDestructive, 0xC02634, 0xFF98A3),
        (.disabledFill, 0xE9ECF0, 0x1B242A),
        (.disabledText, 0x5C6672, 0x9AA7AF),
        (.heroBackground, 0x003B3B, 0x003B3B),
        (.onHero, 0xF6EFE3, 0xF6EFE3),
        (.heroSupporting, 0xB3C7C2, 0xB3C7C2),
        (.achievement, 0xD4AF7A, 0xD4AF7A),
        (.onAchievement, 0x222528, 0x222528),
        // Domain colors as text (directions A/B, 2026-10-03).
        (.energy, 0xC2391A, 0xFF7A59),
        (.protein, 0xB5246A, 0xFF6FB5),
        (.carbs, 0x1D5BC9, 0x6EA8FF),
        (.fat, 0x8F5A00, 0xFFC24D),
        (.hydration, 0x0A6C9E, 0x5ED0FF),
        (.exercise, 0x3A7410, 0xA6E86B),
        (.block, 0x8A5A12, 0xE8B86D),
        (.progress, 0x5A3DC0, 0xB49CFF),
        // Domain colors as fills (never text in light mode).
        (.energyVivid, 0xFF6B4A, 0xFF7A59),
        (.proteinVivid, 0xE0458B, 0xFF6FB5),
        (.carbsVivid, 0x3B82F6, 0x6EA8FF),
        (.fatVivid, 0xF5A524, 0xFFC24D),
        (.hydrationVivid, 0x19B4EE, 0x5ED0FF),
        (.exerciseVivid, 0x62B531, 0xA6E86B),
        (.blockVivid, 0xE0A21E, 0xE8B86D),
        (.progressVivid, 0x7C5CFC, 0xB49CFF),
        (.heroGradientEnd, 0x0C6B64, 0x0E5A54),
        (.dataHeroStart, 0xFFFFFF, 0x16262A),
        (.dataHeroEnd, 0xFFFFFF, 0x10181C),
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
        // Domain colors are used as text (figures, labels), so they meet the
        // same bar as the semantic foregrounds.
        let foregrounds: [BodyFlowColor.Role] = [
            .textPrimary, .textSecondary, .textTertiary, .brandPrimary,
            .feedbackPositive, .feedbackWarning, .feedbackDestructive,
        ] + BodyFlowDomain.allCases.map(\.colorRole)
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
                (.onHero, .heroGradientEnd),
                (.textPrimary, .dataHeroStart), (.textPrimary, .dataHeroEnd),
                (.textSecondary, .dataHeroStart), (.textSecondary, .dataHeroEnd),
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
