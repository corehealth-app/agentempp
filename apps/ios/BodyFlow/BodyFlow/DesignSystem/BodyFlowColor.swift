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
        // Domain colors (direction v2, 2026-10-03): one color per metric so the
        // eye learns the color before reading the number. All readable as text
        // on the three theme surfaces (≥ 4.5:1, locked in
        // BodyFlowSemanticColorTests).
        case energy, protein, carbs, fat, hydration, exercise, block, progress
        /// End of the hero gradient (start is `heroBackground`); `onHero`
        /// stays readable across the whole sweep.
        case heroGradientEnd
    }

    static func hex(_ role: Role, dark: Bool) -> UInt32 {
        switch role {
        case .backgroundPrimary: dark ? 0x071E20 : 0xF6EFE3
        case .backgroundSecondary: dark ? 0x102D30 : 0xFFFCF6
        case .surfaceElevated, .surfaceInteractive: dark ? 0x193C40 : 0xFFFFFF
        case .brandPrimary: dark ? 0x55D5C7 : 0x006D67
        case .onPrimary: dark ? 0x071E20 : 0xFFFFFF
        case .brandSecondary: 0x55D5C7
        case .accentCoral: 0xFF7F6B
        case .textPrimary: dark ? 0xF6EFE3 : 0x222528
        case .textSecondary: dark ? 0xB3C7C2 : 0x4D6260
        case .textTertiary: dark ? 0x97ACA8 : 0x596E6B
        case .borderSubtle: dark ? 0x355155 : 0xD8DED7
        case .controlBoundary: dark ? 0x8CA7A1 : 0x627A75
        case .feedbackPositive: dark ? 0x7CDDCA : 0x006D67
        case .feedbackWarning: dark ? 0xF2C976 : 0x8A5A00
        case .feedbackDestructive: dark ? 0xFF98A3 : 0xB42332
        case .disabledFill: dark ? 0x193C40 : 0xF0F0E8
        case .disabledText: dark ? 0x97ACA8 : 0x596E6B
        case .heroBackground: 0x003B3B
        case .onHero: 0xF6EFE3
        case .heroSupporting: 0xB3C7C2
        case .achievement: 0xD4AF7A
        case .onAchievement: 0x222528
        case .energy: dark ? 0xFF8E7A : 0xB93C27
        case .protein: dark ? 0xF48FC3 : 0x9E2F6B
        case .carbs: dark ? 0x8FB8FF : 0x2A62C9
        case .fat: dark ? 0xFFB76E : 0x9C5A14
        case .hydration: dark ? 0x7CC6FF : 0x1A6FB5
        case .exercise: dark ? 0xA6E07A : 0x3E7A1A
        case .block: dark ? 0xE8B86D : 0x8F5A12
        case .progress: dark ? 0xBBA8FF : 0x5A3DC0
        case .heroGradientEnd: dark ? 0x0E5A54 : 0x0C6B64
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
