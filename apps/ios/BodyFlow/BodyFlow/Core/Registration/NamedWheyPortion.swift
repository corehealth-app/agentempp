import Foundation

/// An explicit household measure in a NEW ingredient's name. This is an
/// editable generic reference, never a measured scoop or a branded label.
/// Existing proposals/history do not pass through this resolver.
struct NamedWheyPortion: Equatable, Sendable {
    let grams: Decimal
    let canonicalName = "whey protein em pó"
    let metadata = MealQuantityDisplay(unit: "scoop", gramsPerUnit: 30,
        referenceID: "app-household-whey-scoop-v1", estimated: true)

    static func parse(_ value: String) -> NamedWheyPortion? {
        let text = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let pattern = #"^(1|um|uma|one|\d+(?:[.,]\d+)?) (?:(?:medidas?|doses?) de|scoops? of) whey(?: protein(?: em po)?)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        let countText = String(text[range])
        let count = ["um", "uma", "one"].contains(countText) ? Decimal(1)
            : Decimal(string: countText.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX"))
        guard let count, count > 0, count <= 100 else { return nil }
        return NamedWheyPortion(grams: count * 30)
    }
}
