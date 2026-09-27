import Foundation

/// Turns the meal text the patient typed into the structured proposal the
/// BFF accepts: one food per line with its quantity in grams. Nothing
/// nutritional happens here — the server prices every item — and a line
/// without an explicit gram figure is rejected rather than guessed.
struct TextMealDetector: MealDetectionProviding {
    static let maximumItems = 30
    static let maximumQuantityG = Decimal(9_999)
    static let maximumNameLength = 160

    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.now = now
        self.calendar = calendar
    }

    func detect(_ input: MealDetectionInput) async throws -> RegistrationProposalRequest {
        guard case let .text(text) = input else {
            throw BodyFlowCapabilityError.operationUnavailable
        }
        return .meal(MealProposalRequest(
            mealType: Self.suggestedMealType(at: now(), calendar: calendar),
            items: try Self.items(from: text),
            consumedAt: nil
        ))
    }

    static func items(from text: String) throws -> [MealProposalItemRequest] {
        let lines = text
            .split(whereSeparator: { $0.isNewline || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty, lines.count <= maximumItems else {
            throw BodyFlowCapabilityError.invalidInput
        }
        return try lines.map(item(from:))
    }

    /// Accepts "arroz 120 g", "120 g de arroz", "arroz - 120g", "azeite 10,5 g".
    static func item(from line: String) throws -> MealProposalItemRequest {
        let pattern = #"(\d+(?:[.,]\d+)?)\s*(?:g|gr|grs|grama|gramas|gram|grams)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(
                  in: line,
                  range: NSRange(line.startIndex..., in: line)
              ),
              let quantityRange = Range(match.range(at: 1), in: line),
              let wholeRange = Range(match.range, in: line),
              let quantity = Decimal(
                  string: line[quantityRange].replacingOccurrences(of: ",", with: ".")
              ),
              quantity > 0, quantity <= maximumQuantityG
        else {
            throw BodyFlowCapabilityError.invalidInput
        }

        var name = line
        name.removeSubrange(wholeRange)
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = CharacterSet(charactersIn: "-–:,.;")
        name = name.trimmingCharacters(in: separators.union(.whitespaces))
        for prefix in ["de ", "of "] where name.lowercased().hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }
        name = name
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard (1...maximumNameLength).contains(name.count) else {
            throw BodyFlowCapabilityError.invalidInput
        }
        return MealProposalItemRequest(foodName: name, quantityG: quantity, userKcal: nil)
    }

    /// A default the patient can change in the proposal editor; it is a
    /// convenience, not an official value.
    static func suggestedMealType(at date: Date, calendar: Calendar) -> MealType {
        switch calendar.component(.hour, from: date) {
        case ..<10: .breakfast
        case 10..<15: .lunch
        case 15..<18: .snack
        case 18..<22: .dinner
        default: .supper
        }
    }
}
