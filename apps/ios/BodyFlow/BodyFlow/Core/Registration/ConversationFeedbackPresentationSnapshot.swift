import Foundation

/// A CURRENT-policy presentation of HISTORICAL facts, never an immutable receipt,
/// saved-meal acknowledgement, clinical authority or transport authentication.
struct ConversationFeedbackPresentationSnapshot: Decodable, Equatable, Sendable {
    struct Original: Equatable, Sendable {
        let schema: String
        let registrationID: String
        let localDate: String
    }
    /// The actual public projection includes the core budget visibility flag.
    /// Keep it here without changing older read-surface policy compatibility.
    struct Policy: Equatable, Sendable {
        struct Hidden: Equatable, Sendable {
            let objective: Bool
            let calories: Bool
            let protein: Bool
            let balance: Bool
            let block: Bool
            let budget: Bool
        }
        let version: Int
        let observedAt: APITimestamp
        let assessment: CurrentClinicalPolicy.Assessment
        let recordingAllowed: Bool
        let pauseWeightLossGuidance: Bool
        let professionalAssessmentRecommended: Bool
        let phaseSelectionPending: Bool
        let targetSource: CurrentClinicalPolicy.TargetSource
        let hide: Hidden
        fileprivate init(_ p: CurrentClinicalPolicy, budget: Bool) {
            version = p.version; observedAt = p.observedAt; assessment = p.assessment
            recordingAllowed = p.recordingAllowed; pauseWeightLossGuidance = p.pauseWeightLossGuidance
            professionalAssessmentRecommended = p.professionalAssessmentRecommended
            phaseSelectionPending = p.phaseSelectionPending; targetSource = p.targetSource
            hide = Hidden(objective: p.hide.objective, calories: p.hide.calories, protein: p.hide.protein,
                          balance: p.hide.balance, block: p.hide.block, budget: budget)
        }
    }
    struct Provenance: Equatable, Sendable {
        let epoch: String
        let commandID: String
        /// Preserve the server's full precision rather than round-tripping Date.
        let observedAt: String
    }
    struct Section: Equatable, Sendable {
        enum Key: String, Sendable { case saved, items, summary, day, block, education }
        let key: Key
        let text: String
    }
    enum Content: Equatable, Sendable {
        case sections(recorded: RegistrationFeedbackV2Snapshot.Meal, sections: [Section])
        case legacy(RegistrationFeedbackV1Snapshot)
        case placeholder([Section])
    }
    /// Obtained from the authenticated session and actual server journal binding.
    /// The payload contains no owner ID and cannot establish this scope itself.
    struct Scope: Equatable, Sendable {
        let ownerID: String
        let sessionGeneration: UInt64
        let epoch: String
    }
    struct Binding: Sendable {
        var scope: Scope
        var commandID: String
        var registrationID: String
        var localDate: String
        var mealKind: String
        var logIDs: [String]
        var admittedAt: String
    }
    struct Bound: Equatable, Sendable {
        let presentation: ConversationFeedbackPresentationSnapshot
        let scope: Scope
        fileprivate init(presentation: ConversationFeedbackPresentationSnapshot, scope: Scope) {
            self.presentation = presentation
            self.scope = scope
        }
    }

    let original: Original
    let currentPolicy: Policy
    let provenance: Provenance
    let content: Content

    var isRestricted: Bool {
        let p = currentPolicy
        return p.assessment != .complete || !p.recordingAllowed || p.pauseWeightLossGuidance ||
            p.hide.objective || p.hide.calories || p.hide.protein || p.hide.balance || p.hide.block || p.hide.budget
    }

    /// Call only after trusted transport and session validation. The future caller
    /// must publish under the existing visible-session mutation gate, and clear
    /// bound values on account/generation/epoch changes. This performs no ACK.
    func bound(to binding: Binding, current: Scope) -> Bound? {
        guard binding.scope == current, validUUID(current.ownerID), validUUID(current.epoch),
              provenance.epoch == current.epoch, provenance.commandID == binding.commandID,
              original.registrationID == binding.registrationID, original.localDate == binding.localDate,
              !binding.logIDs.isEmpty, binding.logIDs.count <= 30,
              binding.logIDs.allSatisfy(validUUID), Set(binding.logIDs).count == binding.logIDs.count,
              ["cafe", "almoco", "lanche", "jantar", "ceia", "outro"].contains(binding.mealKind),
              let admitted = PresentationInstant(binding.admittedAt),
              let observed = PresentationInstant(provenance.observedAt), admitted <= observed else { return nil }
        if case let .sections(recorded, _) = content {
            guard recorded.mealKind == binding.mealKind,
                  Set(recorded.items.map(\.logID)) == Set(binding.logIDs) else { return nil }
        }
        return Bound(presentation: self, scope: current)
    }

    init(from decoder: any Decoder) throws {
        do {
            let raw = try PresentationValue(from: decoder)
            let format = try raw.member("format").string()
            let common = ["schema", "mode", "assistant", "original", "current_policy", "provenance", "status", "format"]
            let extra: [String]
            switch format {
            case "sections": extra = ["recorded", "sections"]
            case "legacy": extra = ["legacy_body"]
            case "placeholder": extra = ["sections"]
            default: throw InvalidPresentation.value
            }
            let o = try raw.object(common + extra)
            try check(o.value("schema").string() == "conversation.feedback-presentation.v1")
            try check(o.value("mode").string() == "historical")
            try check(o.value("assistant").string() == "Flow AI")
            let identity = try o.value("original").object(["schema", "registration_id", "kind", "local_date"])
            let schema = try identity.value("schema").oneOf(["registration.feedback.v1", "registration.feedback.v2"])
            try check(identity.value("kind").string() == "meal")
            original = Original(schema: schema, registrationID: try identity.value("registration_id").uuid(),
                                localDate: try identity.value("local_date").civilDate())
            let policy = try o.value("current_policy")
            _ = try policy.object(["version", "observed_at", "assessment", "recording_allowed", "pause_weight_loss_guidance",
                "professional_assessment_recommended", "phase_selection_pending", "target_source", "hide"])
            try check(policy.member("version").amount() == 1)
            let hidden = try policy.member("hide").object(["objective", "calories", "protein", "balance", "block", "budget"])
            for value in hidden.values { _ = try value.bool() }
            currentPolicy = try Policy(policy.decode(CurrentClinicalPolicy.self), budget: hidden.value("budget").bool())
            let p = try o.value("provenance").object(["epoch", "command_id", "observed_at"])
            let observedAt = try p.value("observed_at").string()
            try check(PresentationInstant(observedAt) != nil)
            try check(policy.member("observed_at").string().utf16.elementsEqual(observedAt.utf16))
            provenance = Provenance(epoch: try p.value("epoch").uuid(), commandID: try p.value("command_id").uuid(), observedAt: observedAt)
            // Use the same policy rule as the actual server guard; no prose redaction.
            let limited = currentPolicy.assessment != .complete || !currentPolicy.recordingAllowed ||
                currentPolicy.pauseWeightLossGuidance || currentPolicy.hide.objective || currentPolicy.hide.calories ||
                currentPolicy.hide.protein || currentPolicy.hide.balance || currentPolicy.hide.block || currentPolicy.hide.budget
            switch format {
            case "sections":
                try check(schema == "registration.feedback.v2" && o.value("status").string() == "available")
                content = .sections(recorded: try Self.meal(o.value("recorded")),
                    sections: try Self.sections(o.value("sections"), keys: [.saved, .items, .summary, .day, .block, .education]))
            case "legacy":
                try check(schema == "registration.feedback.v1" && !limited && o.value("status").string() == "available")
                let legacy = try o.value("legacy_body")
                try Self.closedLegacy(legacy)
                let body = try legacy.decode(RegistrationFeedbackV1Snapshot.self)
                try check(body.kind == .meal && body.registrationID == original.registrationID)
                try check(body.day == nil || body.day?.localDate == original.localDate)
                content = .legacy(body)
            default:
                try check(schema == "registration.feedback.v1" && limited && o.value("status").string() == "unavailable")
                content = .placeholder(try Self.sections(o.value("sections"), keys: [.saved, .summary]))
            }
        } catch {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Historical feedback presentation unavailable"))
        }
    }

    private static func sections(_ value: PresentationValue, keys: [Section.Key]) throws -> [Section] {
        let rows = try value.array()
        try check(rows.count == keys.count)
        return try zip(rows, keys).map { raw, key in
            let o = try raw.object(["key", "text"])
            try check(o.value("key").string() == key.rawValue)
            let text = try o.value("text").string()
            try check(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            return Section(key: key, text: text) // server text is preserved byte-for-byte
        }
    }
    private static func nutrients(_ raw: PresentationValue) throws -> RegistrationFeedbackSnapshot.Nutrients {
        let o = try raw.object(["kcal", "protein_g", "carbs_g", "fat_g"])
        return .init(kcal: try o.value("kcal").amount(), proteinG: try o.value("protein_g").amount(),
                     carbsG: try o.value("carbs_g").amount(), fatG: try o.value("fat_g").amount())
    }
    private static func meal(_ raw: PresentationValue) throws -> RegistrationFeedbackV2Snapshot.Meal {
        let o = try raw.object(["kind", "meal_kind", "items", "totals"])
        try check(o.value("kind").string() == "meal")
        let mealKind = try o.value("meal_kind").oneOf(["cafe", "almoco", "lanche", "jantar", "ceia", "outro"])
        let rows = try o.value("items").array()
        try check((1...30).contains(rows.count))
        let items: [RegistrationFeedbackV2Snapshot.MealItem] = try rows.map { raw in
            let i = try raw.object(["log_id", "food_name", "quantity_g", "quantity", "nutrition_source", "kcal", "protein_g", "carbs_g", "fat_g"])
            let mass = try i.value("quantity_g").amount(positive: true, max: 9999)
            let q = try i.value("quantity").object(["value", "unit", "estimated", "reference_id"])
            let quantity = RegistrationFeedbackV2Snapshot.Quantity(value: try q.value("value").amount(positive: true, max: 999999),
                unit: try q.value("unit").oneOf(["g", "mL", "unit", "scoop"]), estimated: try q.value("estimated").bool(),
                referenceID: try q.value("reference_id").nullable { try $0.text() })
            try check(quantity.unit != "g" || abs(quantity.value - mass) < 0.000001)
            try check(!quantity.estimated || quantity.unit == "g" || quantity.referenceID != nil)
            return .init(logID: try i.value("log_id").uuid(), foodName: try i.value("food_name").text(), quantityG: mass,
                quantity: quantity, nutritionSource: try i.value("nutrition_source").oneOf(["taco", "canonical_exact", "canonical_fuzzy", "canonical_composite",
                    "canonical_composite_partial", "rule_based", "user_correction", "history", "user_kcal", "product_label", "pending_approved", "llm_estimate"]),
                nutrients: .init(kcal: try i.value("kcal").amount(), proteinG: try i.value("protein_g").amount(),
                    carbsG: try i.value("carbs_g").amount(), fatG: try i.value("fat_g").amount()))
        }
        try check(Set(items.map(\.logID)).count == items.count)
        return .init(mealKind: mealKind, items: items, totals: try nutrients(o.value("totals")))
    }
    private static func closedLegacy(_ raw: PresentationValue) throws {
        let o = try raw.object(["schema", "registration_id", "kind", "locale", "meal_totals", "day", "lines", "food_comment", "incentive"])
        if case .null = try o.value("meal_totals") {} else { _ = try nutrients(o.value("meal_totals")) }
        for line in try o.value("lines").array() { _ = try line.object(["key", "text"]) }
        if case .null = try o.value("day") { return }
        let day = try o.value("day").object(["local_date", "current_protocol", "consumed", "targets", "calorie_percentage",
            "protein_percentage", "remaining_food_kcal", "food_excess_kcal", "exercise_kcal"])
        _ = try day.value("consumed").object(["calories_kcal", "protein_g", "carbs_g", "fat_g"])
        _ = try day.value("targets").object(["calories_kcal", "protein_g"])
    }
}

private enum InvalidPresentation: Error { case value }
private func check(_ condition: Bool) throws { if !condition { throw InvalidPresentation.value } }
private func validUUID(_ value: String) -> Bool { value.utf8.count == 36 && UUID(uuidString: value) != nil }

private indirect enum PresentationValue: Decodable, Encodable {
    case object([String: Self]), array([Self]), string(String), number(Double), bool(Bool), null
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([Self].self) { self = .array(a) }
        else { self = .object(try c.decode([String: Self].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .object(v): try c.encode(v)
        case let .array(v): try c.encode(v)
        case let .string(v): try c.encode(v)
        case let .number(v): try c.encode(v)
        case let .bool(v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    func decode<T: Decodable>(_ type: T.Type) throws -> T { try JSONDecoder().decode(type, from: JSONEncoder().encode(self)) }
    func object(_ keys: [String]) throws -> [String: Self] {
        guard case let .object(o) = self, Set(o.keys) == Set(keys) else { throw InvalidPresentation.value }; return o
    }
    func member(_ key: String) throws -> Self { guard case let .object(o) = self else { throw InvalidPresentation.value }; return try o.value(key) }
    func array() throws -> [Self] { guard case let .array(a) = self else { throw InvalidPresentation.value }; return a }
    func string() throws -> String { guard case let .string(s) = self else { throw InvalidPresentation.value }; return s }
    func bool() throws -> Bool { guard case let .bool(b) = self else { throw InvalidPresentation.value }; return b }
    func amount(positive: Bool = false, max: Double = 9_007_199_254_740_991) throws -> Double {
        guard case let .number(n) = self else { throw InvalidPresentation.value }
        try check(n.isFinite && (positive ? n > 0 : n >= 0) && n <= max); return n
    }
    func oneOf(_ values: [String]) throws -> String { let s = try string(); try check(values.contains(s)); return s }
    func text() throws -> String { let s = RegistrationFeedbackV2Snapshot.trimmedText(try string()); try check((1...240).contains(s.utf16.count)); return s }
    func uuid() throws -> String { let s = try string(); try check(validUUID(s)); return s }
    func civilDate() throws -> String { let s = try string(); try check(validCivil(s)); return s }
    func nullable<T>(_ parse: (Self) throws -> T) throws -> T? { if case .null = self { nil } else { try parse(self) } }
}
private extension Dictionary where Key == String, Value == PresentationValue {
    func value(_ key: String) throws -> Value { guard let v = self[key] else { throw InvalidPresentation.value }; return v }
}
private func validCivil(_ s: String) -> Bool {
    let b = Array(s.utf8)
    guard b.count == 10, b[4] == 45, b[7] == 45,
          b.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }) else { return false }
    let p = s.split(separator: "-")
    guard let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]), y > 0, (1...12).contains(m) else { return false }
    let leap = y % 400 == 0 || (y % 4 == 0 && y % 100 != 0)
    return (1...[31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]).contains(d)
}
/// RFC3339 comparison retains all nine fractional digits for pre-admission fences.
private struct PresentationInstant: Comparable {
    let seconds: Int64
    let nanos: Int
    init?(_ raw: String) {
        let pattern = #"^(\d{4}-\d{2}-\d{2})T([01]\d|2[0-3]):([0-5]\d):([0-5]\d)(?:\.(\d{1,9}))?(Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let match = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              match.range.length == raw.utf16.count else { return nil }
        func part(_ index: Int) -> String {
            guard let range = Range(match.range(at: index), in: raw) else { return "" }; return String(raw[range])
        }
        guard validCivil(part(1)) else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: "\(part(1))T\(part(2)):\(part(3)):\(part(4))\(part(6))") else { return nil }
        seconds = Int64(date.timeIntervalSince1970.rounded())
        let fraction = part(5); nanos = Int(fraction + String(repeating: "0", count: 9 - fraction.count)) ?? 0
    }
    static func < (a: Self, b: Self) -> Bool { a.seconds == b.seconds ? a.nanos < b.nanos : a.seconds < b.seconds }
}
