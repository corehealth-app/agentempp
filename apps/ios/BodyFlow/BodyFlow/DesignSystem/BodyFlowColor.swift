import SwiftUI
import UIKit

enum BodyFlowColor {
    enum Role: CaseIterable, Hashable, Sendable {
        case backgroundPrimary, backgroundSecondary, surfaceElevated, surfaceInteractive
        case brandPrimary, onPrimary, brandSecondary, accentCoral
        case textPrimary, textSecondary, textTertiary, borderSubtle, controlBoundary
        case feedbackPositive, feedbackWarning, feedbackDestructive
        case disabledFill, disabledText, heroBackground, onHero, heroSupporting
        case achievement, onAchievement
        // Domain colors as TEXT: one color per metric, each readable on the
        // three theme surfaces (≥ 4.5:1, locked in BodyFlowSemanticColorTests).
        case energy, protein, carbs, fat, hydration, exercise, block, progress
        // The same domains as FILLS (rings, bars, glyph washes): the vivid
        // tone of the approved directions. Never used for text in light mode.
        case energyVivid, proteinVivid, carbsVivid, fatVivid, hydrationVivid, exerciseVivid, blockVivid, progressVivid
        /// End of the brand hero gradient (start is `heroBackground`).
        case heroGradientEnd
        /// The data hero card (Today): flat white in light, a soft dark
        /// sweep in dark. `textPrimary` is readable across both.
        case dataHeroStart, dataHeroEnd
    }

    /// Direction A (light, airy) and direction B (dark, bold), approved by
    /// Eduardo on 2026-10-03 from the "Performe AI Direções" mockups: one app,
    /// A as its light mode and B as its dark mode. The brand hero roles
    /// (launch screen, splash) keep the Signal Spark teal in both.
    static func hex(_ role: Role, dark: Bool) -> UInt32 {
        switch role {
        case .backgroundPrimary: dark ? 0x090D10 : 0xF5F6F8
        case .backgroundSecondary: dark ? 0x141B20 : 0xFFFFFF
        case .surfaceElevated, .surfaceInteractive: dark ? 0x1B242A : 0xFFFFFF
        case .brandPrimary: dark ? 0x3DE0CE : 0x007A72
        case .onPrimary: dark ? 0x06211E : 0xFFFFFF
        case .brandSecondary: 0x55D5C7
        case .accentCoral: 0xFF7F6B
        case .textPrimary: dark ? 0xF2F5F6 : 0x141A21
        case .textSecondary: dark ? 0x9AA7AF : 0x5C6672
        case .textTertiary: dark ? 0x8E9BA3 : 0x626C78
        case .borderSubtle: dark ? 0x232D34 : 0xE9ECF0
        case .controlBoundary: dark ? 0x70808A : 0x7C8792
        case .feedbackPositive: dark ? 0x3DE0CE : 0x007A72
        case .feedbackWarning: dark ? 0xFFC24D : 0x8A5A00
        case .feedbackDestructive: dark ? 0xFF98A3 : 0xC02634
        case .disabledFill: dark ? 0x1B242A : 0xE9ECF0
        case .disabledText: dark ? 0x9AA7AF : 0x5C6672
        case .heroBackground: 0x003B3B
        case .onHero: 0xF6EFE3
        case .heroSupporting: 0xB3C7C2
        case .achievement: 0xD4AF7A
        case .onAchievement: 0x222528
        case .energy: dark ? 0xFF7A59 : 0xC2391A
        case .protein: dark ? 0xFF6FB5 : 0xB5246A
        case .carbs: dark ? 0x6EA8FF : 0x1D5BC9
        case .fat: dark ? 0xFFC24D : 0x8F5A00
        case .hydration: dark ? 0x5ED0FF : 0x0A6C9E
        case .exercise: dark ? 0xA6E86B : 0x3A7410
        case .block: dark ? 0xE8B86D : 0x8A5A12
        case .progress: dark ? 0xB49CFF : 0x5A3DC0
        case .energyVivid: dark ? 0xFF7A59 : 0xFF6B4A
        case .proteinVivid: dark ? 0xFF6FB5 : 0xE0458B
        case .carbsVivid: dark ? 0x6EA8FF : 0x3B82F6
        case .fatVivid: dark ? 0xFFC24D : 0xF5A524
        case .hydrationVivid: dark ? 0x5ED0FF : 0x19B4EE
        case .exerciseVivid: dark ? 0xA6E86B : 0x62B531
        case .blockVivid: dark ? 0xE8B86D : 0xE0A21E
        case .progressVivid: dark ? 0xB49CFF : 0x7C5CFC
        case .heroGradientEnd: dark ? 0x0E5A54 : 0x0C6B64
        case .dataHeroStart: dark ? 0x16262A : 0xFFFFFF
        case .dataHeroEnd: dark ? 0x10181C : 0xFFFFFF
        }
    }

    static func color(_ role: Role) -> Color {
        Color(uiColor: UIColor { traits in
            let value = hex(role, dark: traits.userInterfaceStyle == .dark)
            return UIColor(
                red: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255,
                alpha: 1
            )
        })
    }

    // Legacy palette constants remain byte-identical for historical assets and
    // the explicit rollback surface. Public aliases converge on semantic roles.
    static let tealGreen = brandColor(0x006D67)
    static let warmCream = brandColor(0xF6EFE3)
    static let charcoal = brandColor(0x222528)
    static let mutedCoral = brandColor(0xFF7F6B)
    static let softGold = brandColor(0xD4AF7A)

    static let background = color(.backgroundPrimary)
    static let surface = color(.backgroundSecondary)
    static let primaryText = color(.textPrimary)
    static let secondaryText = color(.textSecondary)
    static let accent = color(.brandPrimary)
    static let warning = color(.feedbackWarning)
    static let achievement = softGold
    static let onAchievement = charcoal

    private static func brandColor(_ hexadecimal: UInt32) -> Color {
        let divisor = Double(255)
        let red = Double((hexadecimal >> 16) & 0xFF) / divisor
        let green = Double((hexadecimal >> 8) & 0xFF) / divisor
        let blue = Double(hexadecimal & 0xFF) / divisor

        return Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
