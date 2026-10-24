import Foundation
import Testing

@testable import BodyFlow

@Suite("C13 optional confirmed registration feedback")
struct RegistrationFeedbackTests {
    private let registrationID = "a1700000-0000-4000-8000-000000000001"

    @Test("confirmed PT meal preserves the saved numbers, text and snapshot round trip")
    func mealRoundTrip() throws {
        let value = try decode(feedback: feedback())
        #expect(value.registration.feedback?.registrationID == registrationID)
        #expect(value.registration.feedback?.mealTotals?.kcal == 435)
        #expect(value.registration.feedback?.day?.caloriePercentage == 74.4)
        #expect(value.registration.feedback?.lines.first?.text == "435 kcal | Proteína: 42 g")
        #expect(value.registration.feedback?.foodComment == "Comentário alimentar salvo.")
        let repeated = try JSONDecoder().decode(RegistrationConfirmationSnapshot.self,
            from: JSONEncoder().encode(value))
        #expect(repeated == value)
    }

    @Test("English workout has numeric feedback without invented phrase translation")
    func workoutEnglish() throws {
        let value = try decode(feedback: feedback(kind: "workout", locale: "en"), kind: "workout")
        #expect(value.registration.feedback?.kind == .workout)
        #expect(value.registration.feedback?.locale == .english)
        #expect(value.registration.feedback?.mealTotals == nil)
        #expect(value.registration.feedback?.foodComment == nil)
        #expect(value.registration.feedback?.incentive == nil)
        #expect(value.registration.feedback?.lines.first?.text == "Calorie limit reached: 74.4% (1,785 / 2,400 kcal)")
        #expect(value.registration.workoutVersion?.contentRevision == 0)
        let repeated = try JSONDecoder().decode(RegistrationConfirmationSnapshot.self,
            from: JSONEncoder().encode(value))
        #expect(repeated.registration.feedback == value.registration.feedback)
    }

    @Test("invalid optional feedback never invalidates principal confirmation", arguments: [
        "missing", "null", "number", "unknown-schema", "wrong-id", "wrong-kind", "negative",
        "empty-lines", "duplicate-lines", "empty-text", "bad-date", "unavailable-percentage",
        "english-phrase", "missing-required-nullable", "missing-target-key", "target-zero",
        "boolean-number", "negative-percentage", "unsafe-percentage", "unknown-protocol", "unknown-locale", "unknown-line-key",
        "signed-month", "signed-day", "invalid-century-leap",
    ])
    func invalidOptional(_ variant: String) throws {
        var extra: Any? = feedback()
        var object = feedback()
        switch variant {
        case "missing": extra = nil
        case "null": extra = NSNull()
        case "number": extra = 1
        case "unknown-schema": object["schema"] = "registration.feedback.v2"
        case "wrong-id": object["registration_id"] = "b2800000-0000-4000-8000-000000000001"
        case "wrong-kind": object = feedback(kind: "workout")
        case "negative": object["meal_totals"] = ["kcal": -1, "protein_g": 42, "carbs_g": 49, "fat_g": 5]
        case "empty-lines": object["lines"] = []
        case "duplicate-lines": object["lines"] = [["key": "meal_totals", "text": "One"], ["key": "meal_totals", "text": "Two"]]
        case "empty-text": object["lines"] = [["key": "meal_totals", "text": " "]]
        case "english-phrase": object["locale"] = "en"
        case "missing-required-nullable": object.removeValue(forKey: "incentive")
        case "unknown-locale": object["locale"] = "es"
        case "unknown-line-key": object["lines"] = [["key": "unknown", "text": "Text"]]
        case "boolean-number": object["meal_totals"] = ["kcal": true, "protein_g": 42, "carbs_g": 49, "fat_g": 5]
        default:
            var day = try #require(object["day"] as? [String: Any])
            if variant == "bad-date" { day["local_date"] = "2026-02-30" }
            if variant == "signed-month" { day["local_date"] = "2026-+1-24" }
            if variant == "signed-day" { day["local_date"] = "2026-01-+1" }
            if variant == "invalid-century-leap" { day["local_date"] = "1900-02-29" }
            if variant == "unavailable-percentage" { day["calorie_percentage"] = NSNull() }
            if variant == "missing-target-key" { day["targets"] = ["protein_g": 150] }
            if variant == "target-zero" { day["targets"] = ["calories_kcal": 0, "protein_g": 150] }
            if variant == "negative-percentage" { day["calorie_percentage"] = -1 }
            if variant == "unsafe-percentage" { day["calorie_percentage"] = 9_007_199_254_740_992 }
            if variant == "unknown-protocol" { day["current_protocol"] = "unknown" }
            object["day"] = day
        }
        if !["missing", "null", "number"].contains(variant) { extra = object }
        let value = try decode(feedback: extra)
        #expect(value.registration.status == "confirmed")
        #expect(value.registration.feedback == nil)
        #expect(!value.alreadyConfirmed)
    }

    @Test("valid unavailable facts and percentages above100 are preserved", arguments: ["no-day", "no-targets", "above100"])
    func validAvailability(_ variant: String) throws {
        var object = feedback()
        if variant == "no-day" {
            object["day"] = NSNull()
            object["lines"] = [["key": "meal_totals", "text": "435 kcal | Proteína: 42 g"],
                               ["key": "day_unavailable", "text": "Os dados deste dia estão indisponíveis."]]
        } else {
            var day = try #require(object["day"] as? [String: Any])
            if variant == "no-targets" {
                day["targets"] = ["calories_kcal": NSNull(), "protein_g": NSNull()]
                day["calorie_percentage"] = NSNull(); day["protein_percentage"] = NSNull()
                day["remaining_food_kcal"] = NSNull(); day["food_excess_kcal"] = NSNull()
                object["lines"] = [["key": "meal_totals", "text": "435 kcal | Proteína: 42 g"],
                                   ["key": "day_calories", "text": "Consumido: 1.785 kcal. Meta indisponível."],
                                   ["key": "day_protein", "text": "Proteína: 126 g. Meta indisponível."]]
            } else {
                day["calorie_percentage"] = 120.5
                object["lines"] = [["key": "meal_totals", "text": "435 kcal | Proteína: 42 g"],
                                   ["key": "day_calories", "text": "Limite calórico atingido: 120,5%"],
                                   ["key": "day_protein", "text": "Proteína: 84,0%"]]
            }
            object["day"] = day
        }
        let confirmation = try decode(feedback: object)
        let value = confirmation.registration.feedback
        #expect(value != nil)
        if variant == "no-day" { #expect(value?.day == nil) }
        if variant == "no-targets" { #expect(value?.day?.caloriePercentage == nil) }
        if variant == "above100" { #expect(value?.day?.caloriePercentage == 120.5) }
        let repeated = try JSONDecoder().decode(RegistrationConfirmationSnapshot.self,
            from: JSONEncoder().encode(confirmation))
        #expect(repeated.registration.feedback == value)
    }

    @Test("civil dates use the wire contract's proleptic Gregorian calendar", arguments: ["0000-02-29", "1500-10-10", "2000-02-29"])
    func validCivilDates(_ date: String) throws {
        var object = feedback()
        var day = try #require(object["day"] as? [String: Any])
        day["local_date"] = date
        object["day"] = day
        #expect(try decode(feedback: object).registration.feedback?.day?.localDate == date)
    }

    @Test("a receipt cannot enrich a pending or different-kind registration", arguments: ["pending", "cancelled", "expired", "workout"])
    func binding(_ variant: String) throws {
        let value = try decode(feedback: feedback(), kind: variant == "workout" ? "workout" : "meal",
                               status: variant == "workout" ? "confirmed" : variant)
        #expect(value.registration.feedback == nil)
    }

    @Test("feedback cannot weaken principal workout version validation")
    func principalValidation() {
        #expect(throws: DecodingError.self) {
            try decode(feedback: feedback(kind: "workout"), kind: "workout", revision: -1)
        }
    }

    @Test("the programmatic snapshot initializer enforces the same binding")
    func initializerBinding() throws {
        let original = try decode(feedback: feedback()).registration
        let copied = RegistrationSnapshot(id: original.id, status: original.status,
            createdAt: original.createdAt, expiresAt: original.expiresAt, resolvedAt: original.resolvedAt,
            proposal: original.proposal, feedback: original.feedback)
        #expect(copied.feedback == original.feedback)
        let pending = RegistrationSnapshot(id: original.id, status: "pending",
            createdAt: original.createdAt, expiresAt: original.expiresAt, resolvedAt: nil,
            proposal: original.proposal, feedback: original.feedback)
        #expect(pending.feedback == nil)
    }

    @Test("saved locale and decimal totals remain unchanged when a response is replayed")
    func replayDecimal() throws {
        var object = feedback()
        object["meal_totals"] = ["kcal": 0.3, "protein_g": 0.3, "carbs_g": 0.3, "fat_g": 0.3]
        var lines = try #require(object["lines"] as? [[String: String]])
        lines[0]["text"] = "0,3 kcal | Proteína: 0,3 g | Carboidratos: 0,3 g | Gorduras: 0,3 g"
        object["lines"] = lines
        let value = try decode(feedback: object, replay: true)
        #expect(value.alreadyConfirmed)
        #expect(value.registration.feedback?.mealTotals?.kcal == 0.3)
        #expect(value.registration.feedback?.locale == .portuguese)
    }

    private func feedback(kind: String = "meal", locale: String = "pt-BR") -> [String: Any] {
        let isMeal = kind == "meal"
        return [
            "schema": "registration.feedback.v1", "registration_id": registrationID,
            "kind": kind, "locale": locale,
            "meal_totals": isMeal ? ["kcal": 435, "protein_g": 42, "carbs_g": 49, "fat_g": 5] : NSNull(),
            "day": ["local_date": "2026-10-24", "current_protocol": "recomposicao",
                "remaining_food_kcal": 615, "food_excess_kcal": 0, "exercise_kcal": 504,
                "consumed": ["calories_kcal": 1785, "protein_g": 126, "carbs_g": 200, "fat_g": 50],
                "targets": ["calories_kcal": 2400, "protein_g": 150],
                "calorie_percentage": 74.4, "protein_percentage": 84],
            "lines": (isMeal ? [["key": "meal_totals", "text": "435 kcal | Proteína: 42 g"]] : []) + [
                ["key": "day_calories", "text": locale == "en" ? "Calorie limit reached: 74.4% (1,785 / 2,400 kcal)" : "Limite calórico atingido: 74,4%"],
                ["key": "day_protein", "text": locale == "en" ? "Protein: 84.0% (126 / 150 g)" : "Proteína: 84,0%"],
                ["key": "food_budget", "text": locale == "en" ? "Remaining: 615 kcal for food." : "Restam 615 kcal para comida."],
            ],
            "food_comment": isMeal && locale == "pt-BR" ? "Comentário alimentar salvo." : NSNull(),
            "incentive": locale == "pt-BR" ? "Incentivo salvo." : NSNull(),
        ]
    }

    private func decode(feedback: Any?, kind: String = "meal", status: String = "confirmed",
                        revision: Int = 0, replay: Bool = false) throws -> RegistrationConfirmationSnapshot {
        var envelope: [String: Any] = [
            "id": registrationID, "status": status, "created_at": "2026-10-24T12:00:00Z",
            "expires_at": "2026-10-25T12:00:00Z", "resolved_at": "2026-10-24T12:30:00Z",
            "already_confirmed": replay, "deduped": false,
            "proposal": kind == "workout"
                ? ["kind": "workout", "workout_type": "Natação", "duration_min": 40, "estimated_kcal": 400, "intensity": "moderada"]
                : ["kind": "meal", "meal_type": "cafe", "items": [], "warnings": []],
        ]
        if kind == "workout" { envelope["workout_protocol"] = "ui-v1"; envelope["content_revision"] = revision }
        if let feedback { envelope["feedback"] = feedback }
        return try JSONDecoder().decode(RegistrationConfirmationSnapshot.self,
            from: JSONSerialization.data(withJSONObject: envelope))
    }
}
