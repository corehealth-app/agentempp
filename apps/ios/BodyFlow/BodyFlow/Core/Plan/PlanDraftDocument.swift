import Foundation

/// The content of a draft as the patient edits it: the server's JSON, changed
/// only where the patient typed. Fields the app does not show travel back
/// untouched, and an emptied field is sent as `null` — never as a guess.
struct PlanDraftDocument: Equatable, Sendable {
    enum Step: Hashable, Sendable {
        case key(String)
        case index(Int)
    }

    typealias Path = [Step]

    enum FieldKind: Hashable, Sendable {
        case text(maximumLength: Int)
        case integer(ClosedRange<Int>)
        case decimal(maximum: Decimal)
        case mealType
    }

    struct Field: Hashable, Sendable, Identifiable {
        let key: String
        let kind: FieldKind
        let path: Path
        let isRequired: Bool

        var id: String { PlanDraftDocument.pointer(path) }
        var pointer: String { id }
    }

    /// A value of the draft the app shows and does not edit. Everything
    /// that will be confirmed is on screen: nothing becomes part of a plan
    /// without having been shown.
    struct Detail: Hashable, Sendable, Identifiable {
        let key: String
        let text: String
        let path: Path

        var id: String { PlanDraftDocument.pointer(path) }
    }

    struct Row: Hashable, Sendable, Identifiable {
        let path: Path
        let fields: [Field]
        /// What the document said about the portion, shown as it came.
        let note: String?
        var details: [Detail] = []
        /// What the patient reads as the name of this row.
        var title: String = ""

        var id: String { PlanDraftDocument.pointer(path) }
    }

    struct Section: Hashable, Sendable, Identifiable {
        let path: Path
        let fields: [Field]
        let rows: [Row]
        var details: [Detail] = []

        var id: String { PlanDraftDocument.pointer(path) }
    }

    /// Item values that depend on the quantity: they are cleared when the
    /// patient changes it, never kept for another quantity.
    static let quantityDependentKeys = ["kcal", "protein_g", "carbs_g", "fat_g"]
    static let quantityDependentTotals = ["total_kcal", "total_protein_g"]

    static let mealTypes = ["cafe", "lanche_manha", "almoco", "lanche_tarde", "jantar", "ceia"]

    let domain: PlanDraftDomain
    private(set) var root: JSONValue

    init(domain: PlanDraftDomain, payload: JSONValue?) {
        self.domain = domain
        if case .object = payload {
            root = payload ?? .object([:])
        } else {
            root = .object([:])
        }
    }

    /// RFC 6901, as the server writes its uncertain fields.
    static func pointer(_ path: Path) -> String {
        path.map { step in
            switch step {
            case let .key(key):
                "/" + key.replacingOccurrences(of: "~", with: "~0")
                    .replacingOccurrences(of: "/", with: "~1")
            case let .index(index):
                "/\(index)"
            }
        }.joined()
    }

    private var listKey: String {
        domain == .training ? "weekly_schedule" : "daily_meals"
    }

    private var rowKey: String {
        domain == .training ? "exercises" : "items"
    }

    var sections: [Section] {
        guard case let .array(entries) = value(at: [.key(listKey)]) else { return [] }
        return entries.indices.map { index in
            let path: Path = [.key(listKey), .index(index)]
            return Section(
                path: path,
                fields: sectionFields(at: path),
                rows: rows(at: path + [.key(rowKey)]),
                details: details(
                    at: path,
                    keys: domain == .training
                        ? [] : ["day_of_week", "total_kcal", "total_protein_g", "notes"]
                )
            )
        }
    }

    /// Values of the plan as a whole.
    func planDetails(language: SupportedAppLanguage) -> [Detail] {
        details(
            at: [],
            keys: domain == .training
                ? ["plan_type", "equipment_summary", "progression_rule", "notes"]
                : ["mode", "horizon", "meta_kcal", "meta_protein_g", "notes"],
            language: language
        )
    }

    /// The shopping list of a meal plan, one line per item, as it came.
    func shoppingList(language: SupportedAppLanguage) -> [Detail] {
        guard domain == .nutrition,
              case let .array(entries) = value(at: [.key("shopping_list")])
        else {
            return []
        }
        return entries.indices.compactMap { index in
            let path: Path = [.key("shopping_list"), .index(index)]
            let parts = ["food_name", "quantity_g", "category"].compactMap { key -> String? in
                guard let text = Self.text(value(at: path + [.key(key)]), language: language)
                else {
                    return nil
                }
                return key == "quantity_g" ? "\(text) g" : text
            }
            return parts.isEmpty
                ? nil : Detail(key: "shopping_item", text: parts.joined(separator: " · "), path: path)
        }
    }

    private func details(
        at path: Path,
        keys: [String],
        language: SupportedAppLanguage = .portugueseBrazil
    ) -> [Detail] {
        keys.compactMap { key in
            let detailPath = path + [.key(key)]
            guard let text = Self.text(value(at: detailPath), language: language) else {
                return nil
            }
            return Detail(key: key, text: text, path: detailPath)
        }
    }

    /// A value as text, or nil when there is nothing to show.
    static func text(_ value: JSONValue?, language: SupportedAppLanguage) -> String? {
        switch value {
        case let .string(text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let .number(number):
            return MealProposalNumberParser.format(number, language: language)
        case let .boolean(flag):
            return flag ? "true" : "false"
        case let .array(entries):
            let texts = entries.compactMap { text($0, language: language) }
            return texts.isEmpty ? nil : texts.joined(separator: "; ")
        case .object, .null, nil:
            return nil
        }
    }

    /// True when the content carries something this screen cannot show: a
    /// value of an unexpected shape where a known one was expected.
    var hasUnreadableContent: Bool {
        sections.contains { section in
            (section.fields + section.rows.flatMap(\.fields)).contains { field in
                switch value(at: field.path) {
                case .object, .array, .boolean: true
                default: false
                }
            }
        }
    }

    var isEmpty: Bool { sections.isEmpty }

    private func sectionFields(at path: Path) -> [Field] {
        switch domain {
        case .training:
            [
                Field(key: "day", kind: .text(maximumLength: 20),
                      path: path + [.key("day")], isRequired: true),
                Field(key: "focus", kind: .text(maximumLength: 80),
                      path: path + [.key("focus")], isRequired: true),
                Field(key: "duration_min", kind: .integer(10...180),
                      path: path + [.key("duration_min")], isRequired: true),
            ]
        case .nutrition:
            [
                Field(key: "meal_type", kind: .mealType,
                      path: path + [.key("meal_type")], isRequired: true),
                Field(key: "time_suggestion", kind: .text(maximumLength: 40),
                      path: path + [.key("time_suggestion")], isRequired: false),
            ]
        }
    }

    private func rows(at path: Path) -> [Row] {
        guard case let .array(entries) = value(at: path) else { return [] }
        return entries.indices.map { index in
            let rowPath = path + [.index(index)]
            switch domain {
            case .training:
                return Row(
                    path: rowPath,
                    fields: [
                        Field(key: "name", kind: .text(maximumLength: 120),
                              path: rowPath + [.key("name")], isRequired: true),
                        Field(key: "muscle_group", kind: .text(maximumLength: 80),
                              path: rowPath + [.key("muscle_group")], isRequired: true),
                        Field(key: "sets", kind: .integer(1...15),
                              path: rowPath + [.key("sets")], isRequired: true),
                        Field(key: "reps_range", kind: .text(maximumLength: 40),
                              path: rowPath + [.key("reps_range")], isRequired: true),
                        Field(key: "rest_seconds", kind: .integer(0...600),
                              path: rowPath + [.key("rest_seconds")], isRequired: true),
                    ],
                    note: nil,
                    details: details(
                        at: rowPath,
                        keys: ["rpe_target", "notes", "execution_steps", "common_mistakes"]
                    ),
                    title: Self.text(value(at: rowPath + [.key("name")]), language: .portugueseBrazil)
                        ?? ""
                )
            case .nutrition:
                return Row(
                    path: rowPath,
                    fields: [
                        Field(key: "food_name", kind: .text(maximumLength: 120),
                              path: rowPath + [.key("food_name")], isRequired: true),
                        Field(key: "quantity_g", kind: .decimal(maximum: 2_000),
                              path: rowPath + [.key("quantity_g")], isRequired: true),
                    ],
                    note: portionNote(at: rowPath),
                    details: details(at: rowPath, keys: Self.quantityDependentKeys),
                    title: Self.text(
                        value(at: rowPath + [.key("food_name")]),
                        language: .portugueseBrazil
                    ) ?? ""
                )
            }
        }
    }

    /// "1 colher de sopa", when the document gave a household measure.
    private func portionNote(at path: Path) -> String? {
        guard case let .string(unit) = value(at: path + [.key("display_unit")]),
              case let .number(quantity) = value(at: path + [.key("display_qty")])
        else {
            return nil
        }
        return "\(NSDecimalNumber(decimal: quantity).stringValue) \(unit)"
    }

    func value(at path: Path) -> JSONValue? {
        var current = root
        for step in path {
            switch (step, current) {
            case let (.key(key), .object(object)):
                guard let next = object[key] else { return nil }
                current = next
            case let (.index(index), .array(array)):
                guard array.indices.contains(index) else { return nil }
                current = array[index]
            default:
                return nil
            }
        }
        return current
    }

    /// Writes the value of a field of an existing day, meal, exercise or
    /// item. A path that does not lead to an existing container is ignored:
    /// the app never adds a day, a meal, an exercise or an item.
    mutating func set(_ value: JSONValue, at path: Path) {
        guard !path.isEmpty, let updated = Self.setting(value, in: root, at: path[...]) else {
            return
        }
        root = updated
    }

    /// Removes one exercise, item, day or meal.
    mutating func remove(at path: Path) {
        guard case let .index(index) = path.last,
              case var .array(entries) = value(at: Array(path.dropLast())),
              entries.indices.contains(index)
        else {
            return
        }
        entries.remove(at: index)
        set(.array(entries), at: Array(path.dropLast()))
    }

    private static func setting(
        _ value: JSONValue,
        in node: JSONValue,
        at path: ArraySlice<Step>
    ) -> JSONValue? {
        guard let step = path.first else { return value }
        let rest = path.dropFirst()
        switch (step, node) {
        case let (.key(key), .object(object)):
            var updated = object
            if rest.isEmpty {
                updated[key] = value
            } else {
                guard let child = object[key],
                      let changed = setting(value, in: child, at: rest)
                else {
                    return nil
                }
                updated[key] = changed
            }
            return .object(updated)
        case let (.index(index), .array(array)):
            guard array.indices.contains(index) else { return nil }
            var updated = array
            if rest.isEmpty {
                updated[index] = value
            } else {
                guard let changed = setting(value, in: array[index], at: rest) else { return nil }
                updated[index] = changed
            }
            return .array(updated)
        default:
            return nil
        }
    }

    /// The text a field shows for the value the server sent.
    func text(of field: Field, language: SupportedAppLanguage) -> String {
        switch value(at: field.path) {
        case let .string(text): text
        case let .number(number): MealProposalNumberParser.format(number, language: language)
        default: ""
        }
    }

    /// What the patient typed, as the value that travels. nil = not valid for
    /// the field (saving is blocked); `.null` = emptied.
    static func value(
        for text: String,
        of field: Field,
        language: SupportedAppLanguage
    ) -> JSONValue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .null }
        switch field.kind {
        case let .text(maximumLength):
            return trimmed.count <= maximumLength ? .string(trimmed) : nil
        case .mealType:
            return mealTypes.contains(trimmed) ? .string(trimmed) : nil
        case let .integer(range):
            guard trimmed.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(trimmed), range.contains(number)
            else {
                return nil
            }
            return .number(Decimal(number))
        case let .decimal(maximum):
            guard let number = MealProposalNumberParser.parse(trimmed, language: language),
                  number > 0, number <= maximum
            else {
                return nil
            }
            return .number(number)
        }
    }
}
