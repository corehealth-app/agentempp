import SwiftUI

/// The app's metric domains, each with its own color and glyph (direction
/// v2, 2026-10-03): energy, the three macros, hydration, exercise, the 7,700
/// block and progress. Screens ask the domain for its color; the raw role
/// lives here only, so a metric never changes color between screens.
enum BodyFlowDomain: CaseIterable, Sendable {
    case energy, protein, carbs, fat, hydration, exercise, block, progress

    var colorRole: BodyFlowColor.Role {
        switch self {
        case .energy: .energy
        case .protein: .protein
        case .carbs: .carbs
        case .fat: .fat
        case .hydration: .hydration
        case .exercise: .exercise
        case .block: .block
        case .progress: .progress
        }
    }

    var color: Color { BodyFlowColor.color(colorRole) }

    /// The vivid tone for fills (rings, bars, glyphs and their washes).
    var fillRole: BodyFlowColor.Role {
        switch self {
        case .energy: .energyVivid
        case .protein: .proteinVivid
        case .carbs: .carbsVivid
        case .fat: .fatVivid
        case .hydration: .hydrationVivid
        case .exercise: .exerciseVivid
        case .block: .blockVivid
        case .progress: .progressVivid
        }
    }

    var fill: Color { BodyFlowColor.color(fillRole) }

    var symbol: BodyFlowSymbol {
        switch self {
        case .energy: .energy
        case .protein: .protein
        case .carbs: .carbs
        case .fat: .fat
        case .hydration: .hydration
        case .exercise: .workouts
        case .block: .block
        case .progress: .weight
        }
    }
}

/// A domain glyph in a tinted round wash — the "colored bubble" icon of the
/// reference apps. Decorative: the label next to it carries the meaning.
struct BodyFlowDomainGlyph: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let domain: BodyFlowDomain
    var diameter: CGFloat = 32

    var body: some View {
        Image(symbol: domain.symbol)
            .font(.system(size: diameter * 0.45, weight: .semibold))
            .foregroundStyle(domain.fill)
            .frame(width: diameter, height: diameter)
            .background(fill, in: Circle())
            .accessibilityHidden(true)
    }

    /// Opaque secondary surface under Increase Contrast, like a text wash.
    private var fill: Color {
        contrast == .increased
            ? BodyFlowColor.color(.backgroundSecondary)
            : domain.fill.opacity(BodyFlowOpacity.glyphWash)
    }
}
