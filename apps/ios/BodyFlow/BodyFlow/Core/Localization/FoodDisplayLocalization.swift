import Foundation

/// Read-only presentation aliases. Never used by calculation, decoding, hashing,
/// an editor's stored name or a command body. Unknown names keep their qualifiers.
enum FoodDisplayLocalization {
  private static let reviewed: [(String, String)] = [
    ("Oil, olive, salad or cooking", "azeite de oliva"),
    ("Oil olive salad or cooking", "azeite de oliva"),
    ("Egg, whole, cooked, scrambled", "ovo mexido"),
    ("Egg whole cooked scrambled", "ovo mexido"),
    ("Egg, whole, cooked, fried", "ovo frito"),
    ("Egg whole cooked fried", "ovo frito"),
  ]

  static func name(_ original: String, english: Bool) -> String {
    guard !english else { return original }
    let normalized = original.trimmingCharacters(in: .whitespacesAndNewlines)
    return reviewed.first { $0.0.caseInsensitiveCompare(normalized) == .orderedSame }?.1
      ?? original
  }

  /// Formats an already validated feedback section without changing its receipt.
  /// Match complete reviewed names, not arbitrary English words or food suffixes.
  static func message(_ original: String, english: Bool) -> String {
    guard !english else { return original }
    return reviewed.reduce(original) { text, pair in
      let pattern =
        "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: pair.0)
        + "(?![\\p{L}\\p{N}])"
      return text.replacingOccurrences(
        of: pattern, with: pair.1,
        options: [.regularExpression, .caseInsensitive])
    }
  }
}
