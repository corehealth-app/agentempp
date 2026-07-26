import SwiftUI
import UIKit

enum BodyFlowColor {
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
