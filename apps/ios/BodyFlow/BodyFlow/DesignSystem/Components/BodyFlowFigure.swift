import SwiftUI

/// A figure the way the approved directions set it: the number large, the
/// unit small beside it, as ONE text ("2.007 kcal" stays a single accessible
/// string). A value without a leading number ("Indisponível") is one style.
enum BodyFlowFigure {
    nonisolated static func split(_ text: String) -> (value: String, unit: String?) {
        guard let first = text.first, first.isNumber || first == "-" || first == "−",
              let space = text.lastIndex(of: " ") else { return (text, nil) }
        let unit = String(text[text.index(after: space)...])
        guard !unit.isEmpty, unit.first?.isNumber == false else { return (text, nil) }
        return (String(text[..<space]), unit)
    }

    static func text(_ full: String, value: Font, unit: Font, unitColor: Color) -> Text {
        let parts = split(full)
        guard let unitText = parts.unit else { return Text(verbatim: full).font(value) }
        return Text(verbatim: parts.value).font(value)
            + Text(verbatim: " \(unitText)").font(unit).foregroundStyle(unitColor)
    }
}

/// The data hero of a screen: flat white on the light canvas (direction A),
/// a soft dark sweep in dark mode (direction B). Text inside is the regular
/// primary/secondary text. Increase Contrast adds a boundary.
struct BodyFlowDataHeroCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: BodyFlowRadius.card, style: .continuous)
    }

    var body: some View {
        content
            .foregroundStyle(BodyFlowColor.color(.textPrimary))
            .padding(BodyFlowSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // The lift is on the shape only, never on the text inside.
                shape
                    .fill(LinearGradient(
                        colors: [BodyFlowColor.color(.dataHeroStart), BodyFlowColor.color(.dataHeroEnd)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .shadow(
                        color: .black.opacity(colorScheme == .light ? BodyFlowElevation.heroOpacity : 0),
                        radius: BodyFlowElevation.heroBlur, y: BodyFlowElevation.heroY
                    )
            }
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(BodyFlowColor.color(.controlBoundary), lineWidth: 1)
                }
            }
    }
}
