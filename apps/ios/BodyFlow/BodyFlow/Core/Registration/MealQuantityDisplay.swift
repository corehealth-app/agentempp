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

    init(unit: String, gramsPerUnit: Decimal, referenceID: String, estimated: Bool) {
        self.unit = unit
        self.gramsPerUnit = gramsPerUnit
        self.referenceID = referenceID
        self.estimated = estimated
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
        let references: [String:(String,Decimal,[String])] = [
            "fao-infoods-v2-whole-milk-tb": ("mL",Decimal(103)/100,["leite","leite integral"]),
            "fao-infoods-v2-coffee-fndds4-1": ("mL",1,["cafe coado","cafe preparado","cafe expresso","cafe espresso"]),
            "fao-infoods-v2-tea-fndds4-1": ("mL",1,["cha preparado","cha liquido"]),
            "fao-infoods-v2-water-cg": ("mL",1,["agua"]),
            "fao-infoods-v2-orange-juice-sw": ("mL",Decimal(1038)/1000,["suco de laranja"]),
            "app-household-whey-scoop-v1": ("scoop",30,["whey","whey protein","whey protein em po"]),
            "app-household-cheese-bread-unit-v1": ("unit",30,["pao de queijo","paes de queijo","pao de queijo com requeijao"]),
            "app-household-egg-unit-v1": ("unit",50,["ovo","ovos","ovo de galinha","ovos de galinha"]),
            "app-household-french-bread-unit-v1": ("unit",50,["pao frances","paes franceses","paozinho"]),
            "app-household-banana-unit-v1": ("unit",100,["banana","bananas"]),
            "app-household-apple-unit-v1": ("unit",150,["maca","macas"]),
        ]
        guard estimated, let reference = references[referenceID], unit == reference.0,
              gramsPerUnit == reference.1, reference.2.contains(food)
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

    var usesReference: Bool { metadata != nil }
    var isVolume: Bool { metadata?.unit == "mL" }
    var unit: String { metadata?.unit ?? "g" }
    var captionID: String {
        switch unit {
        case "mL": "meal.quantity.volume"
        case "unit": "meal.quantity.units"
        case "scoop": "meal.quantity.scoops"
        default: "registration.editor.quantity"
        }
    }
    var captionKey: String.LocalizationValue {
        String.LocalizationValue(captionID)
    }
    var invalidKey: String.LocalizationValue {
        switch unit {
        case "mL": "meal.quantity.volume.invalid"
        case "unit", "scoop": "meal.quantity.reference.invalid"
        default: "registration.editor.quantity.invalid"
        }
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
        let labelUnit: String
        switch unit {
        case "unit": labelUnit = language == .portugueseBrazil ? "unid." : "units"
        case "scoop": labelUnit = language == .portugueseBrazil ? "medida(s)" : "scoop(s)"
        default: labelUnit = unit
        }
        return "\(usesReference ? "≈ " : "")\(text) \(labelUnit)"
    }

    func presenting(grams: Decimal?, inGrams: Bool = false) -> MealQuantityValue {
        // Metadata is already validated by this instance; avoid revalidating
        // against a fabricated food name when changing presentation only.
        MealQuantityValue(canonicalGrams: grams, validatedMetadata: inGrams ? nil : metadata)
    }

    private init(canonicalGrams: Decimal?, validatedMetadata: MealQuantityDisplay?) {
        self.canonicalGrams = canonicalGrams
        metadata = validatedMetadata
    }
}

/// Display mode and authorship are independent. Formatting a conversion must
/// never replace exact original grams or the patient's original typed value.
struct MealQuantityEntry: Equatable, Sendable {
    private(set) var text: String?
    private(set) var displaysGrams = false
    private(set) var typedUsingReference = false

    mutating func setText(_ text: String?, usesReference: Bool) {
        self.text = text
        typedUsingReference = usesReference
    }

    func presentation(_ reference: MealQuantityValue) -> MealQuantityValue {
        reference.presenting(grams: reference.canonicalGrams, inGrams: displaysGrams)
    }

    func grams(_ reference: MealQuantityValue, language: SupportedAppLanguage) -> Decimal? {
        guard let text else { return reference.canonicalGrams }
        return reference.presenting(grams: nil, inGrams: !typedUsingReference).grams(from: text, language: language)
    }

    func display(_ reference: MealQuantityValue, language: SupportedAppLanguage) -> String {
        let visible = presentation(reference)
        guard let text else { return visible.displayText(language: language) }
        if typedUsingReference == visible.usesReference { return text }
        guard let grams = grams(reference, language: language) else { return text }
        return visible.presenting(grams: grams).displayText(language: language)
    }

    func canToggle(_ reference: MealQuantityValue, language: SupportedAppLanguage) -> Bool {
        reference.usesReference && (text == nil || grams(reference, language: language) != nil)
    }

    mutating func toggle(_ reference: MealQuantityValue, language: SupportedAppLanguage) {
        guard canToggle(reference, language: language) else { return }
        displaysGrams.toggle()
    }
}
