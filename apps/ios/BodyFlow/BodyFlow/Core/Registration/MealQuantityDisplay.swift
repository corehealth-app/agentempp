import Foundation

/// Optional server presentation, never an original measurement. Canonical
/// requests and persisted nutrition continue to use grams. A bad/unknown
/// reference falls back to grams without hiding a valid historical row.
struct MealQuantityDisplay: Codable, Hashable, Sendable {
    let unit: String
    let gramsPerUnit: Decimal
    let referenceID: String
    let estimated: Bool

    private enum CodingKeys: String, CodingKey {
        case unit, estimated
        case gramsPerUnit = "grams_per_unit"
        case referenceID = "reference_id"
    }

    init(from decoder: any Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        unit = (try? container?.decode(String.self, forKey: .unit)) ?? ""
        gramsPerUnit = (try? container?.decode(Decimal.self, forKey: .gramsPerUnit)) ?? 0
        referenceID = (try? container?.decode(String.self, forKey: .referenceID)) ?? ""
        estimated = (try? container?.decode(Bool.self, forKey: .estimated)) ?? false
    }

    func validated(for name: String) -> MealQuantityDisplay? {
        let food = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        // FAO/INFOODS v2: wholemilkTB, brewedcoffee/teaFNDDS4.1,
        // waterCG, orangejuiceS&W. No generic factor for all liquids.
        let references: [String:(Decimal,[String])] = [
            "fao-infoods-v2-whole-milk-tb": (Decimal(103)/100,["leite","leite integral"]),
            "fao-infoods-v2-coffee-fndds4-1": (1,["cafe coado","cafe preparado","cafe expresso","cafe espresso"]),
            "fao-infoods-v2-tea-fndds4-1": (1,["cha preparado","cha liquido"]),
            "fao-infoods-v2-water-cg": (1,["agua"]),
            "fao-infoods-v2-orange-juice-sw": (Decimal(1038)/1000,["suco de laranja"]),
        ]
        guard unit == "mL", estimated, let reference = references[referenceID],
              gramsPerUnit == reference.0, reference.1.contains(food)
        else { return nil }
        return self
    }
}

struct MealQuantityValue: Equatable, Sendable {
    let canonicalGrams: Decimal?
    let metadata: MealQuantityDisplay?

    init(grams: Decimal?, metadata: MealQuantityDisplay?, name: String) {
        canonicalGrams = grams
        self.metadata = metadata?.validated(for: name)
    }

    var isVolume: Bool { metadata != nil }
    var unit: String { isVolume ? "mL" : "g" }
    var captionKey: String.LocalizationValue {
        isVolume ? "meal.quantity.volume" : "registration.editor.quantity"
    }

    func displayText(language: SupportedAppLanguage) -> String {
        guard let canonicalGrams else { return "" }
        let amount = metadata.map { canonicalGrams / $0.gramsPerUnit } ?? canonicalGrams
        return MealProposalNumberParser.format(amount, language: language)
    }

    func grams(from text: String, language: SupportedAppLanguage) -> Decimal? {
        guard let typed = MealProposalNumberParser.parse(text, language: language) else { return nil }
        let grams = typed * (metadata?.gramsPerUnit ?? 1)
        guard grams > 0, grams <= MealDraftReview.maximumQuantityG else { return nil }
        return grams
    }

    func label(language: SupportedAppLanguage) -> String? {
        guard let canonicalGrams else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = language.formattingLocale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 2
        let amount = metadata.map { canonicalGrams / $0.gramsPerUnit } ?? canonicalGrams
        let text = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? displayText(language: language)
        return "\(isVolume ? "≈ " : "")\(text) \(unit)"
    }
}
