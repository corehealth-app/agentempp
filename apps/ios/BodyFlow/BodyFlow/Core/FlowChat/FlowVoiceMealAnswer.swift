import Foundation

struct FlowVoiceCaptureTarget: Equatable {
  enum Destination: Equatable {
    case composer
    case mealReply(UUID)
    case photoReview(UUID)
  }
  let identity: ConversationCommandContext.Identity
  let destination: Destination
}

/// Interprets a short answer in the selected meal question. The existing
/// typed writer still validates the item, reference, current revision and day.
enum FlowVoiceMealAnswer {
  struct Quantity {
    let amount: Decimal
    let unit: String
  }

  private static let units: [String: String] = [
    "g": "g", "grama": "g", "gramas": "g", "gram": "g", "grams": "g",
    "kg": "kg", "quilo": "kg", "quilos": "kg", "quilograma": "kg", "quilogramas": "kg",
    "kilogram": "kg", "kilograms": "kg",
    "ml": "mL", "mililitro": "mL", "mililitros": "mL",
    "milliliter": "mL", "milliliters": "mL",
    "l": "L", "litro": "L", "litros": "L", "liter": "L", "liters": "L",
    "unidade": "unit", "unidades": "unit", "unit": "unit", "units": "unit",
    "medida": "scoop", "medidas": "scoop", "scoop": "scoop", "scoops": "scoop",
    "caneca": "caneca", "canecas": "caneca", "cup": "caneca", "cups": "caneca",
  ]

  static func name(_ transcript: String) -> String? {
    guard let text = shortAnswer(transcript) else { return nil }
    let value = text.replacingOccurrences(
      of: #"^(?:(?:o recheio (?:era|foi) (?:de )?)|(?:era|foi|é|it was)\s+)"#,
      with: "", options: [.regularExpression, .caseInsensitive])
    guard value.range(of: #"^[\p{L}\p{M}][\p{L}\p{M}0-9 \-']*$"#,
      options: .regularExpression) != nil else { return nil }
    return value
  }

  static func quantity(
    _ transcript: String, language: SupportedAppLanguage
  ) -> Quantity? {
    guard let text = shortAnswer(transcript) else { return nil }
    let words = text.replacingOccurrences(of: #"(?<=\d)(?=[a-zA-Z])"#, with: " ",
      options: .regularExpression).split(separator: " ")
    guard words.count > 1, let last = words.last,
      let unit = units[last.lowercased()]
    else { return nil }
    let number = words.dropLast().joined(separator: " ").replacingOccurrences(
      of: #"^(?:foram|foi|comi|bebi|tomei|it was)\s+"#,
      with: "", options: [.regularExpression, .caseInsensitive])
    let amount = MealProposalNumberParser.parse(number, language: language)
      ?? spokenAmount(number, language: language)
    guard let amount, amount > 0, amount <= 9_999 else { return nil }
    return .init(amount: amount, unit: unit)
  }

  static func meal(_ transcript: String) -> ConversationMealCommand.MealType? {
    guard let text = name(transcript)?.folding(options: [.diacriticInsensitive, .caseInsensitive],
      locale: Locale(identifier: "pt_BR")).lowercased()
    else { return nil }
    switch text.replacingOccurrences(of: #"^(?:o|a|the) "#, with: "", options: .regularExpression) {
    case "cafe da manha", "breakfast": return .cafe
    case "almoco", "lunch": return .almoco
    case "lanche", "snack": return .lanche
    case "jantar", "dinner": return .jantar
    case "ceia", "supper": return .ceia
    case "outra refeicao", "other meal": return .outro
    default: return nil
    }
  }

  static func photo(
    _ transcript: String, language: SupportedAppLanguage
  ) -> (name: String?, amount: Quantity?) {
    guard let text = shortAnswer(transcript) else { return (nil, nil) }
    if let amount = quantity(text, language: language) { return (nil, amount) }
    if let split = text.range(of: #",\s*"#, options: .regularExpression),
      let name = name(String(text[..<split.lowerBound])),
      let amount = quantity(String(text[split.upperBound...]), language: language)
    {
      return (name, amount)
    }
    if let split = text.range(of: " de ", options: .caseInsensitive),
      let amount = quantity(String(text[..<split.lowerBound]), language: language),
      let name = name(String(text[split.upperBound...]))
    {
      return (name, amount)
    }
    if let unit = text.split(separator: " ").last, units[unit.lowercased()] != nil {
      return (nil, nil)
    }
    return (name(text), nil)
  }

  private static func spokenAmount(_ number: String, language: SupportedAppLanguage) -> Decimal? {
    let formatter = NumberFormatter()
    formatter.locale = language.formattingLocale
    formatter.numberStyle = .spellOut
    let spoken = number.lowercased()
    let normalized = ["uma": "um", "duas": "dois"][spoken] ?? spoken
    guard let amount = formatter.number(from: normalized),
      formatter.string(from: amount)?.lowercased() == normalized else { return nil }
    return amount.decimalValue
  }

  private static func shortAnswer(_ transcript: String) -> String? {
    let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: #"[.!]+$"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.count <= 160,
      text.range(of: #"(?i)[?;\r\n]|\b(?:não|nao|not|ontem|amanhã|tomorrow|talvez|maybe|acho|será|ou|or)\b"#,
        options: .regularExpression) == nil
    else { return nil }
    return text
  }
}
