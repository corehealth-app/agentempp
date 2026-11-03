import Foundation
import Testing
#if canImport(UIKit)
import UIKit
import SwiftUI
#endif

@testable import BodyFlow

@Suite("Closed versioned registration feedback v2 reader")
struct RegistrationFeedbackV2Tests {
    private let registrationID = "c2b00000-0000-4000-8000-000000000001"

    @Test("all canonical public receipts render exactly as TypeScript and preserve explicit nulls")
    func canonicalParity() throws {
        for item in try fixtures() {
            let label = try #require(item["label"] as? String)
            let object = try #require(item["payload"] as? [String: Any])
            let receipt = try decode(object)
            guard case let .v2(value) = receipt else { Issue.record("Not v2: \(label)"); continue }
            let expected = try #require(item["sections"] as? [[String: String]])
            #expect(value.sections.count == expected.count)
            for (actual, saved) in zip(value.sections, expected) {
                #expect(actual.key.rawValue == saved["key"], "\(label)")
                let text = try #require(saved["text"])
                #expect(actual.text.utf16.elementsEqual(text.utf16), "\(label)/\(actual.key)")
            }
            #expect(value.sections.map(\.key) == [.saved, .items, .summary, .day, .block, .education])
            let repeated = try JSONDecoder().decode(RegistrationFeedbackSnapshot.self, from: JSONEncoder().encode(receipt))
            #expect(repeated == receipt, "\(label)")
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt)) as? NSDictionary
            #expect(encoded == object as NSDictionary, "Wire nulls or facts changed: \(label)")
        }
    }

    @Test("malformed v2 enrichment never loses a confirmed registration", arguments: [
        "private-root", "assistant", "schema", "locale", "date", "signed-date", "invalid-century-leap", "missing-nullable",
        "private-day", "private-totals", "private-item", "private-quantity", "private-targets", "private-consumed", "missing-item-id",
        "duplicate-item", "negative", "unsafe", "boolean-number", "string-number", "unresolved", "empty-name", "long-name",
        "mass-limit", "quantity-zero", "quantity-limit", "unsupported-unit", "mass-mismatch", "quantity-flag", "quantity-reference",
        "missing-reference", "missing-day-target", "zero-target", "wrong-percent", "percentage-without-target", "both-budgets",
        "wrong-day", "guidance-unavailable", "guidance-paused", "missing-block-day", "fractional-blocks", "block-credit", "block-target",
        "block-percent", "block-state", "block-unavailable-numbers", "block-not-applicable", "education-text", "education-unicode", "education-catalog",
        "education-template", "education-source", "education-prefs", "education-private", "provenance-private", "unavailable-education-text",
    ])
    func invalidOptional(_ attack: String) throws {
        var object = try payload("milk_whey/pt-BR/false/recomposicao")
        switch attack {
        case "private-root": object["clinical"] = [:] as [String: String]
        case "assistant": object["assistant"] = "Roberto nutricionista"
        case "schema": object["schema"] = "registration.feedback.v3"
        case "locale": object["locale"] = "fr"
        case "date": object["local_date"] = "2026-02-30"
        case "signed-date": object["local_date"] = "2026-+1-03"
        case "invalid-century-leap": object["local_date"] = "1900-02-29"
        case "missing-nullable": object.removeValue(forKey: "day")
        case "private-day": try change(&object, ["day", "health"], "private")
        case "private-totals": try change(&object, ["registration", "totals", "cholesterol"], 10)
        case "private-item": try change(&object, ["registration", "items", "0", "authority"], true)
        case "private-quantity": try change(&object, ["registration", "items", "0", "quantity", "density"], 1)
        case "private-targets": try change(&object, ["day", "targets", "authority"], true)
        case "private-consumed": try change(&object, ["day", "consumed", "source"], "daily_snapshot")
        case "missing-item-id": try change(&object, ["registration", "items", "0", "log_id"], nil)
        case "duplicate-item": try change(&object, ["registration", "items", "1", "log_id"], "c2b00000-0000-4000-8000-000000000002")
        case "negative": try change(&object, ["registration", "items", "0", "protein_g"], -1)
        case "unsafe": try change(&object, ["registration", "items", "0", "kcal"], 9_007_199_254_740_992.0)
        case "boolean-number": try change(&object, ["registration", "items", "0", "kcal"], true)
        case "string-number": try change(&object, ["registration", "items", "0", "kcal"], "126")
        case "unresolved": try change(&object, ["registration", "items", "0", "nutrition_source"], "no_match")
        case "empty-name": try change(&object, ["registration", "items", "0", "food_name"], " ")
        case "long-name": try change(&object, ["registration", "items", "0", "food_name"], String(repeating: "a", count: 241))
        case "mass-limit": try change(&object, ["registration", "items", "0", "quantity_g"], 10000)
        case "quantity-zero": try change(&object, ["registration", "items", "0", "quantity", "value"], 0)
        case "quantity-limit": try change(&object, ["registration", "items", "0", "quantity", "value"], 1000000)
        case "unsupported-unit": try change(&object, ["registration", "items", "0", "quantity", "unit"], "glass")
        case "mass-mismatch": try change(&object, ["registration", "items", "0", "quantity", "value"], 99)
        case "quantity-flag": try change(&object, ["registration", "items", "0", "quantity", "estimated"], 1)
        case "missing-reference": try change(&object, ["registration", "items", "0", "quantity", "reference_id"], nil)
        case "quantity-reference":
            try change(&object, ["registration", "items", "0", "quantity"], ["value": 100, "unit": "mL", "estimated": true, "reference_id": NSNull()])
        case "missing-day-target": try change(&object, ["day", "targets", "protein_g"], nil)
        case "zero-target": try change(&object, ["day", "targets", "protein_g"], 0)
        case "wrong-percent": try change(&object, ["day", "protein_percentage"], 99)
        case "percentage-without-target": try change(&object, ["day", "targets", "protein_g"], NSNull())
        case "both-budgets": try change(&object, ["day", "food_excess_kcal"], 10)
        case "wrong-day": try change(&object, ["day", "local_date"], "2026-11-04")
        case "guidance-unavailable": object["guidance"] = "unavailable"
        case "guidance-paused": object["guidance"] = "paused"
        case "missing-block-day": object["day"] = NSNull()
        case "fractional-blocks": try change(&object, ["block", "completed_blocks"], 2.5)
        case "block-credit": try change(&object, ["block", "total_credited_kcal"], 99999)
        case "block-target": try change(&object, ["block", "target_kcal"], 7701)
        case "block-percent": try change(&object, ["block", "percentage"], 40)
        case "block-state": object["block"] = ["status": "pending"]
        case "block-unavailable-numbers": try change(&object, ["block", "status"], "unavailable")
        case "block-not-applicable": object["block"] = ["status": "not_applicable"]
        case "education-text": try change(&object, ["education", "text"], "Sou humano e garanto perda de peso")
        case "education-unicode":
            let education = try #require(object["education"] as? [String: Any])
            let text = try #require(education["text"] as? String)
            try change(&object, ["education", "text"], text.decomposedStringWithCanonicalMapping)
        case "education-catalog": try change(&object, ["education", "provenance", "catalog_version"], "registration.education.v2")
        case "education-template": try change(&object, ["education", "provenance", "template_id"], "meal_protein")
        case "education-source": try change(&object, ["education", "provenance", "source"], "llm")
        case "education-prefs": try change(&object, ["education", "provenance", "preferences_known"], true)
        case "education-private": try change(&object, ["education", "prompt"], "private")
        case "provenance-private": try change(&object, ["education", "provenance", "profile"], "private")
        case "unavailable-education-text": object["education"] = ["status": "unavailable", "text": "Extra"]
        default: Issue.record("Unknown attack"); return
        }
        #expect(throws: (any Error).self) { try decode(object) }
        let confirmed = try confirmation(object)
        #expect(confirmed.registration.status == "confirmed")
        #expect(confirmed.registration.feedback == nil)
    }

    @Test("workout nullables, duration bounds and closed shape match the contract", arguments: [
        "zero-duration", "large-duration", "missing-duration", "missing-intensity", "missing-energy", "negative-energy", "private-workout", "wrong-kind",
    ])
    func invalidWorkout(_ attack: String) throws {
        var object = try payload("activity_walking/pt-BR/false/recomposicao")
        switch attack {
        case "zero-duration": try change(&object, ["registration", "duration_min"], 0)
        case "large-duration": try change(&object, ["registration", "duration_min"], 1441)
        case "missing-duration": try change(&object, ["registration", "duration_min"], nil)
        case "missing-intensity": try change(&object, ["registration", "intensity"], nil)
        case "missing-energy": try change(&object, ["registration", "estimated_kcal"], nil)
        case "negative-energy": try change(&object, ["registration", "estimated_kcal"], -1)
        case "private-workout": try change(&object, ["registration", "capture_epoch"], 1)
        default: try change(&object, ["registration", "kind"], "unknown")
        }
        #expect(throws: (any Error).self) { try decode(object) }
        #expect(try confirmation(object, kind: "workout").registration.feedback == nil)
    }

    @Test("principal proposal ID, kind and confirmed status bind optional v2", arguments: ["wrong-id", "wrong-kind", "pending", "cancelled", "expired", "unknown-proposal"])
    func ownerBinding(_ attack: String) throws {
        var object = try payload("milk_whey/pt-BR/false/recomposicao")
        if attack == "wrong-id" { object["registration_id"] = "c2b00000-0000-4000-8000-000000000099" }
        let status = ["pending", "cancelled", "expired"].contains(attack) ? attack : "confirmed"
        let kind = attack == "wrong-kind" ? "workout" : attack == "unknown-proposal" ? "unknown" : "meal"
        let value = try confirmation(object, kind: kind, status: status)
        #expect(value.registration.feedback == nil)
        #expect(value.registration.status == status)
    }

    @Test("saved canonical totals stay independent from rounded individual facts and replay does not change receipt")
    func confirmedReplay() throws {
        let object = try payload("meal_protein/pt-BR/false/recomposicao")
        let first = try confirmation(object)
        let replay = try confirmation(object, replay: true)
        #expect(first.registration.feedback == replay.registration.feedback)
        #expect(replay.alreadyConfirmed)
        guard case let .v2(value) = first.registration.feedback else { Issue.record("Missing confirmed v2"); return }
        #expect(value.sections[2].text.hasPrefix("Total aproximado da refeição: 100 kcal"))
        #expect(value.sections[1].text.components(separatedBy: "100 kcal").count == 3)
        #expect(try JSONDecoder().decode(RegistrationConfirmationSnapshot.self, from: JSONEncoder().encode(replay)) == replay)
    }

    @Test("accepted text normalization follows JavaScript whitespace without changing saved quantities", arguments: ["spaces", "nel"])
    func canonicalTextNormalization(_ variant: String) throws {
        var object = try payload("milk_whey/pt-BR/false/recomposicao")
        let rawName = variant == "nel" ? "\u{85}leite integral\u{85}" : "  leite integral  "
        let expectedName = variant == "nel" ? rawName : "leite integral"
        try change(&object, ["registration", "items", "0", "food_name"], rawName)
        object["education"] = ["status": "unavailable"]
        let receipt = try decode(object)
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt)) as? [String: Any])
        let registration = try #require(encoded["registration"] as? [String: Any])
        let items = try #require(registration["items"] as? [[String: Any]])
        #expect(items[0]["food_name"] as? String == expectedName)
        #expect(items[0]["quantity_g"] as? Double == 100)
    }

    @Test("legacy history surfaces do not admit unmasked v2 while preserving principal saved records")
    func historyRequiresCurrentPresentation() throws {
        let logID = "c2b00000-0000-4000-8000-000000000002"
        let meal: [String: Any] = ["record_id": logID, "scope": "item", "expected_version": "saved-v1", "item_ids": [logID],
            "items": [], "editable": false, "day_closed": true, "local_date": "2026-11-03", "timezone": "America/Sao_Paulo",
            "edit_block_reason": NSNull(), "feedback": try payload("milk_whey/pt-BR/false/recomposicao")]
        let savedMeal = try JSONDecoder().decode(MealRecordSnapshot.self, from: JSONSerialization.data(withJSONObject: meal))
        #expect(savedMeal.recordID == logID)
        #expect(savedMeal.feedback == nil)
        let workout: [String: Any] = ["clarification": ["status": "not_applicable", "workout_id": logID,
            "lifecycle_key": "c2b00000-0000-4000-8000-000000000003", "fact_revision": 0],
            "feedback": try payload("activity_walking/pt-BR/false/recomposicao")]
        let savedWorkout = try JSONDecoder().decode(WorkoutStrengthHistorySnapshot.self,
            from: JSONSerialization.data(withJSONObject: workout))
        #expect(savedWorkout.clarification.workoutID == logID)
        #expect(savedWorkout.feedback == nil)
        let receipt = try decode(payload("activity_walking/pt-BR/false/recomposicao"))
        #expect(WorkoutStrengthHistorySnapshot(clarification: savedWorkout.clarification, feedback: receipt).feedback == nil)
    }

    #if canImport(UIKit)
    @MainActor
    @Test("native confirmed receipt exposes all six saved sections and follows receipt locale")
    func nativeSixSectionRendering() throws {
        try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).contains { $0.isKeyWindow }, "Native hosting window required")
        for label in ["native/milk-whey-units/pt-BR", "paused-milk_whey/en/true", "native/workout-unavailable-facts"] {
            let receipt = try decode(payload(label))
            guard case let .v2(value) = receipt else { Issue.record("Missing v2"); continue }
            let host = SignUpRenderingProbe.host(RegistrationFeedbackView(feedback: receipt)
                .environment(\.locale, Locale(identifier: "fr_FR")), width: 393, height: 1800)
            defer { host.detach() }
            let nodes = host.nodes()
            for section in value.sections {
                let node = try #require(nodes.first { $0.isElement &&
                    $0.identifier == "registration.feedback.section.\(section.key.rawValue)" }, "Missing \(section.key): \(nodes)")
                #expect(node.label == section.text)
                #expect(node.frame.width > 0 && node.frame.height > 0)
            }
            #expect(nodes.contains { $0.identifier == "registration.feedback" })
        }
    }
    #endif

    private func fixtures() throws -> [[String: Any]] {
        #if SWIFT_PACKAGE
        let url = try #require(Bundle.module.url(forResource: "RegistrationFeedbackV2Fixtures", withExtension: "json"))
        #else
        // Match the existing MarkdownBackendCompatibilityTests fixture convention;
        // synchronized test groups do not package the source fixture directory.
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/RegistrationFeedbackV2Fixtures.json")
        #endif
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try #require(root["cases"] as? [[String: Any]])
        #expect(cases.count == 154)
        return cases
    }
    private func payload(_ label: String) throws -> [String: Any] {
        try #require(fixtures().first { $0["label"] as? String == label }?["payload"] as? [String: Any])
    }
    private func decode(_ object: [String: Any]) throws -> RegistrationFeedbackSnapshot {
        try JSONDecoder().decode(RegistrationFeedbackSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func confirmation(_ object: [String: Any], kind: String = "meal", status: String = "confirmed", replay: Bool = false) throws -> RegistrationConfirmationSnapshot {
        let proposal: [String: Any]
        if kind == "meal" { proposal = ["kind": kind, "meal_type": "cafe", "items": [], "warnings": []] }
        else if kind == "workout" { proposal = ["kind": kind, "workout_type": "Caminhada", "duration_min": 12, "estimated_kcal": 123, "intensity": "moderada"] }
        else { proposal = ["kind": "unknown"] }
        let envelope: [String: Any] = ["id": registrationID, "status": status, "created_at": "2026-11-03T12:00:00Z",
            "expires_at": "2026-11-04T12:00:00Z", "resolved_at": "2026-11-03T12:30:00Z", "already_confirmed": replay,
            "deduped": false, "proposal": proposal, "feedback": object]
        return try JSONDecoder().decode(RegistrationConfirmationSnapshot.self, from: JSONSerialization.data(withJSONObject: envelope))
    }
    /// JSON fixture mutation only; exercises the actual production decoder at every boundary.
    private func change(_ object: inout [String: Any], _ path: [String], _ value: Any?) throws {
        func mutate(_ current: Any, _ keys: ArraySlice<String>) throws -> Any {
            let key = try #require(keys.first)
            if var dictionary = current as? [String: Any] {
                if keys.count == 1 { dictionary[key] = value }
                else { dictionary[key] = try mutate(try #require(dictionary[key]), keys.dropFirst()) }
                return dictionary
            }
            var array = try #require(current as? [Any])
            let index = try #require(Int(key))
            array[index] = try mutate(array[index], keys.dropFirst())
            return array
        }
        object = try #require(mutate(object, path[...]) as? [String: Any])
    }
}
