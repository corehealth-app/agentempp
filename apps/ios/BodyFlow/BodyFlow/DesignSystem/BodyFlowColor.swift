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

    // Legacy APIs retain their previous palette and native semantic behavior.
    static let tealGreen = brandColor(0x006D67)
    static let warmCream = brandColor(0xF6EFE3)
    static let charcoal = brandColor(0x222528)
    static let mutedCoral = brandColor(0xFF7F6B)
    static let softGold = brandColor(0xD4AF7A)

    static let background = dynamicColor(light: warmCream, dark: charcoal)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let primaryText = dynamicColor(light: charcoal, dark: warmCream)
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let accent = dynamicColor(light: tealGreen, dark: softGold)
    static let warning = mutedCoral
    static let achievement = softGold
    static let onAchievement = charcoal

    private static func brandColor(_ hexadecimal: UInt32) -> Color {
        let divisor = Double(255)
        let red = Double((hexadecimal >> 16) & 0xFF) / divisor
        let green = Double((hexadecimal >> 8) & 0xFF) / divisor
        let blue = Double(hexadecimal & 0xFF) / divisor

        return Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    private static func dynamicColor(light: Color, dark: Color) -> Color {
        Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
            }
        )
    }
}
