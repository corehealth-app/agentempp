import Foundation
import Testing
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif
@testable import BodyFlow

@Suite("Current-policy historical conversation feedback reader")
struct ConversationFeedbackPresentationTests {
    @Test("actual TypeScript variants preserve server text and immutable recorded facts")
    func canonicalVariants() throws {
        for fixture in try cases() {
            let raw = try #require(fixture["payload"] as? [String: Any])
            let value = try decode(raw)
            let bound = try #require(value.bound(to: binding(), current: scope()))
            #expect(bound.presentation.original.localDate == "2026-11-03")
            #expect(value.currentPolicy.observedAt.value > Date(timeIntervalSince1970: 0))
            #expect(value.provenance.observedAt == "2026-11-04T12:00:00.000001Z")
            switch value.content {
            case let .sections(recorded, sections):
                #expect(sections.map(\.key) == [.saved, .items, .summary, .day, .block, .education])
                let expected = try #require(raw["sections"] as? [[String: String]])
                for (section, original) in zip(sections, expected) {
                    #expect(section.text.utf16.elementsEqual(try #require(original["text"]).utf16))
                }
                #expect(recorded.items.count == 1)
                #expect(recorded.items[0].quantity.value == 200)
                #expect(recorded.items[0].quantity.unit == "mL")
                #expect(recorded.items[0].quantityG == 206)
                #expect(recorded.totals.kcal == 126.1)
            case let .legacy(body):
                #expect(body.lines[0].text == "Synthetic total")
                #expect(!value.isRestricted)
            case let .placeholder(sections):
                #expect(sections.map(\.key) == [.saved, .summary])
                #expect(value.isRestricted)
                #expect(!sections.contains { $0.text.contains("Synthetic total") })
            }
        }
    }

    @Test("bindings reject wrong owner, session generation, reset epoch and factual identity", arguments: [
        "owner", "generation", "current-epoch", "command", "epoch", "registration", "date", "meal", "logs", "duplicate-logs", "admitted", "invalid-owner",
    ])
    func bindingRefusals(_ attack: String) throws {
        let value = try decode(payload("unrestricted"))
        var b = try binding(), s = try scope()
        switch attack {
        case "owner": s = .init(ownerID: "10000000-0000-4000-8000-000000000002", sessionGeneration: 7, epoch: s.epoch)
        case "generation": s = .init(ownerID: s.ownerID, sessionGeneration: 8, epoch: s.epoch)
        case "current-epoch": s = .init(ownerID: s.ownerID, sessionGeneration: 7, epoch: "50000000-0000-4000-8000-000000000009")
        case "command": b.commandID = "10000000-0000-4000-8000-000000000008"
        case "epoch": b.scope = .init(ownerID: s.ownerID, sessionGeneration: 7, epoch: "50000000-0000-4000-8000-000000000009")
        case "registration": b.registrationID = "20000000-0000-4000-8000-000000000009"
        case "date": b.localDate = "2026-11-04"
        case "meal": b.mealKind = "jantar"
        case "logs": b.logIDs = ["30000000-0000-4000-8000-000000000009"]
        case "duplicate-logs": b.logIDs += b.logIDs
        case "admitted": b.admittedAt = "2026-11-04T12:00:00.000002Z"
        case "invalid-owner": b.scope = .init(ownerID: "untrusted", sessionGeneration: 7, epoch: s.epoch); s = b.scope
        default: Issue.record("Unknown attack")
        }
        #expect(value.bound(to: b, current: s) == nil)
    }

    @Test("closed variants reject malformed, private or contradictory public payloads", arguments: [
        "schema", "mode", "assistant", "owner-field", "original-extra", "original-kind", "original-schema", "original-date", "status", "format", "legacy-extra", "recorded-extra", "missing-sections", "section-extra", "section-order", "section-duplicate", "empty-text", "section-key", "policy-extra", "policy-missing", "policy-version", "policy-version-bool", "policy-bool", "policy-assessment", "policy-source", "hide-extra", "hide-missing", "provenance-extra", "epoch", "command", "observation-drift", "observation-nanos", "invalid-clock", "year-zero", "invalid-leap", "private-item", "duplicate-item", "item-uuid", "negative", "boolean-number", "unsafe-number", "unit", "mass-mismatch", "reference-missing", "reference-null", "source", "total-extra", "recorded-workout", "item-overflow",
    ])
    func invalidPayload(_ attack: String) throws {
        var p = try payload("unrestricted")
        switch attack {
        case "schema": p["schema"] = "conversation.feedback-presentation.v2"
        case "mode": p["mode"] = "current"
        case "assistant": p["assistant"] = "Roberto nutricionista"
        case "owner-field": p["owner_id"] = "private"
        case "original-extra": try mutate(&p, ["original", "body"], "private")
        case "original-kind": try mutate(&p, ["original", "kind"], "workout")
        case "original-schema": try mutate(&p, ["original", "schema"], "registration.feedback.v1")
        case "original-date": try mutate(&p, ["original", "local_date"], "2026-02-30")
        case "status": p["status"] = "unavailable"
        case "format": p["format"] = "legacy"
        case "legacy-extra": p["legacy_body"] = ["text": "unsafe"]
        case "recorded-extra": try mutate(&p, ["recorded", "day"], [:])
        case "missing-sections": p.removeValue(forKey: "sections")
        case "section-extra": try mutate(&p, ["sections", "0", "raw_receipt"], "unsafe")
        case "section-order": var sections = try #require(p["sections"] as? [[String: Any]]); sections.swapAt(0, 1); p["sections"] = sections
        case "section-duplicate": try mutate(&p, ["sections", "1", "key"], "saved")
        case "empty-text": try mutate(&p, ["sections", "0", "text"], " \n")
        case "section-key": try mutate(&p, ["sections", "0", "key"], "today")
        case "policy-extra": try mutate(&p, ["current_policy", "private_health"], "private")
        case "policy-missing": try mutate(&p, ["current_policy", "recording_allowed"], nil)
        case "policy-version": try mutate(&p, ["current_policy", "version"], 2)
        case "policy-version-bool": try mutate(&p, ["current_policy", "version"], true)
        case "policy-bool": try mutate(&p, ["current_policy", "recording_allowed"], 1)
        case "policy-assessment": try mutate(&p, ["current_policy", "assessment"], "unknown")
        case "policy-source": try mutate(&p, ["current_policy", "target_source"], "model")
        case "hide-extra": try mutate(&p, ["current_policy", "hide", "private"], true)
        case "hide-missing": try mutate(&p, ["current_policy", "hide", "protein"], nil)
        case "provenance-extra": try mutate(&p, ["provenance", "token"], "private")
        case "epoch": try mutate(&p, ["provenance", "epoch"], "bad")
        case "command": try mutate(&p, ["provenance", "command_id"], "bad")
        case "observation-drift": try mutate(&p, ["provenance", "observed_at"], "2026-11-04T12:00:00.000002Z")
        case "observation-nanos": try mutate(&p, ["provenance", "observed_at"], "2026-11-04T12:00:00.0000010001Z")
        case "invalid-clock", "year-zero", "invalid-leap":
            let time = attack == "invalid-clock" ? "2026-11-04T25:00:00Z" : attack == "year-zero" ? "0000-11-04T12:00:00Z" : "1900-02-29T12:00:00Z"
            try mutate(&p, ["provenance", "observed_at"], time); try mutate(&p, ["current_policy", "observed_at"], time)
        case "private-item": try mutate(&p, ["recorded", "items", "0", "authority"], true)
        case "duplicate-item": var r = try #require(p["recorded"] as? [String: Any]); r["items"] = Array(repeating: try #require((r["items"] as? [Any])?.first), count: 2); p["recorded"] = r
        case "item-uuid": try mutate(&p, ["recorded", "items", "0", "log_id"], "bad")
        case "negative": try mutate(&p, ["recorded", "items", "0", "kcal"], -1)
        case "boolean-number": try mutate(&p, ["recorded", "items", "0", "kcal"], true)
        case "unsafe-number": try mutate(&p, ["recorded", "items", "0", "kcal"], 9_007_199_254_740_992.0)
        case "unit": try mutate(&p, ["recorded", "items", "0", "quantity", "unit"], "glass")
        case "mass-mismatch": try mutate(&p, ["recorded", "items", "0", "quantity", "unit"], "g")
        case "reference-missing": try mutate(&p, ["recorded", "items", "0", "quantity", "reference_id"], nil)
        case "reference-null": try mutate(&p, ["recorded", "items", "0", "quantity", "estimated"], true); try mutate(&p, ["recorded", "items", "0", "quantity", "reference_id"], NSNull())
        case "source": try mutate(&p, ["recorded", "items", "0", "nutrition_source"], "no_match")
        case "total-extra": try mutate(&p, ["recorded", "totals", "current_target"], 1900)
        case "recorded-workout": try mutate(&p, ["recorded", "kind"], "workout")
        case "item-overflow": var r = try #require(p["recorded"] as? [String: Any]); r["items"] = Array(repeating: try #require((r["items"] as? [Any])?.first), count: 31); p["recorded"] = r
        default: Issue.record("Unknown attack")
        }
        #expect(throws: (any Error).self) { try decode(p) }
    }

    @Test("restricted legacy never exposes opaque historical advice", arguments: ["pause", "incomplete", "recording", "objective", "calories", "protein", "balance", "block", "budget", "unknown", "private", "wrong-registration", "wrong-day"])
    func legacyRefusals(_ attack: String) throws {
        var p = try payload("legacy")
        switch attack {
        case "pause": try mutate(&p, ["current_policy", "pause_weight_loss_guidance"], true)
        case "incomplete": try mutate(&p, ["current_policy", "assessment"], "incomplete")
        case "recording": try mutate(&p, ["current_policy", "recording_allowed"], false)
        case "objective", "calories", "protein", "balance", "block", "budget": try mutate(&p, ["current_policy", "hide", attack], true)
        case "unknown": try mutate(&p, ["current_policy", "assessment"], "unknown")
        case "private": try mutate(&p, ["legacy_body", "private_health"], true)
        case "wrong-registration": try mutate(&p, ["legacy_body", "registration_id"], "20000000-0000-4000-8000-000000000009")
        case "wrong-day": try mutate(&p, ["original", "schema"], "registration.feedback.v2")
        default: Issue.record("Unknown attack")
        }
        #expect(throws: (any Error).self) { try decode(p) }
    }

    @Test("placeholder is closed, restricted legacy only, with no raw facts or opaque body", arguments: ["body", "recorded", "unrestricted", "wrong-schema", "six-sections"])
    func placeholderRefusals(_ attack: String) throws {
        var p = try payload("placeholder")
        switch attack {
        case "body": p["legacy_body"] = try payload("legacy")["legacy_body"]
        case "recorded": p["recorded"] = try payload("unrestricted")["recorded"]
        case "unrestricted": p["current_policy"] = try payload("legacy")["current_policy"]
        case "wrong-schema": try mutate(&p, ["original", "schema"], "registration.feedback.v2")
        case "six-sections": p["sections"] = try payload("unrestricted")["sections"]
        default: Issue.record("Unknown attack")
        }
        #expect(throws: (any Error).self) { try decode(p) }
    }

    @Test("server Unicode, punctuation and masked historical numbers render without local regeneration")
    func verbatimAndPolicy() throws {
        var p = try payload("pause")
        let text = "Registro **salvo** <b>Flow</b> e\u{301} 🥛\n200 mL ≠ 206 g"
        try mutate(&p, ["sections", "0", "text"], text)
        let value = try decode(p)
        guard case let .sections(recorded, sections) = value.content else { Issue.record("Missing sections"); return }
        #expect(sections[0].text.utf16.elementsEqual(text.utf16))
        #expect(recorded.items[0].quantity.value == 200 && recorded.items[0].quantityG == 206)
        #expect(!sections[3].text.contains("1.900"))
        #expect(!sections[3].text.contains("%"))
        #expect(!sections[4].text.contains("7.700"))
        #expect(value.currentPolicy.pauseWeightLossGuidance)
    }

    @Test("provenance fences retain nanoseconds and compare RFC3339 offsets")
    func timestampPrecision() throws {
        var p = try payload("unrestricted")
        let observed = "2026-11-04T09:00:00.000000001-03:00"
        try mutate(&p, ["provenance", "observed_at"], observed)
        try mutate(&p, ["current_policy", "observed_at"], observed)
        let value = try decode(p)
        var b = try binding()
        b.admittedAt = "2026-11-04T12:00:00.000000001Z"
        #expect(value.bound(to: b, current: try scope()) != nil)
        b.admittedAt = "2026-11-04T12:00:00.000000002Z"
        #expect(value.bound(to: b, current: try scope()) == nil)
    }

    #if canImport(UIKit)
    @Test("SwiftUI renderer accepts only a bound historical presentation") @MainActor
    func renderer() throws {
        for item in try cases() {
            let raw = try #require(item["payload"] as? [String: Any])
            let bound = try #require(decode(raw).bound(to: binding(), current: scope()))
            let host = SignUpRenderingProbe.host(ConversationFeedbackPresentationView(feedback: bound), width: 390, height: 1800)
            defer { host.detach() }
            let nodes = host.nodes()
            #expect(nodes.contains { $0.identifier == "conversation.feedback.presentation" })
            #expect(nodes.contains { $0.label == "Flow AI" && $0.isElement })
            let title = try #require(nodes.first { $0.identifier == "conversation.feedback.historical" && $0.isElement })
            #expect(title.label.contains(bound.presentation.original.localDate))
            switch bound.presentation.content {
            case let .sections(_, sections), let .placeholder(sections):
                for section in sections {
                    let node = try #require(nodes.first { $0.identifier == "conversation.feedback.section.\(section.key.rawValue)" && $0.isElement })
                    #expect(node.label.utf16.elementsEqual(section.text.utf16))
                    #expect(node.frame.width > 0 && node.frame.height > 0)
                }
                #expect(!nodes.contains { $0.label.contains("Synthetic total") })
            case let .legacy(body):
                for line in body.lines {
                    let node = try #require(nodes.first { $0.identifier == "registration.feedback.line.\(line.key.rawValue)" && $0.isElement })
                    #expect(node.label == line.text)
                }
            }
        }
    }
    #endif

    private func root() throws -> [String: Any] {
        #if SWIFT_PACKAGE
        let url = try #require(Bundle.module.url(forResource: "ConversationFeedbackPresentationFixtures", withExtension: "json"))
        #else
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/ConversationFeedbackPresentationFixtures.json")
        #endif
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    private func cases() throws -> [[String: Any]] { try #require(root()["cases"] as? [[String: Any]]) }
    private func payload(_ label: String) throws -> [String: Any] { try #require(cases().first { $0["label"] as? String == label }?["payload"] as? [String: Any]) }
    private func decode(_ raw: [String: Any]) throws -> ConversationFeedbackPresentationSnapshot {
        try JSONDecoder().decode(ConversationFeedbackPresentationSnapshot.self, from: JSONSerialization.data(withJSONObject: raw))
    }
    private func scope() throws -> ConversationFeedbackPresentationSnapshot.Scope {
        let r = try root()
        return .init(ownerID: try #require(r["owner"] as? String), sessionGeneration: 7, epoch: try #require(r["epoch"] as? String))
    }
    private func binding() throws -> ConversationFeedbackPresentationSnapshot.Binding {
        let r = try root()
        return .init(scope: try scope(), commandID: try #require(r["command_id"] as? String), registrationID: try #require(r["registration_id"] as? String), localDate: try #require(r["local_date"] as? String), mealKind: try #require(r["meal_kind"] as? String), logIDs: try #require(r["log_ids"] as? [String]), admittedAt: try #require(r["admitted_at"] as? String))
    }
    private func mutate(_ value: inout [String: Any], _ path: [String], _ replacement: Any?) throws {
        func changed(_ raw: Any, _ keys: ArraySlice<String>) throws -> Any {
            guard let key = keys.first else { return try #require(replacement) }
            if var o = raw as? [String: Any] {
                if keys.count == 1 { o[key] = replacement } else { o[key] = try changed(try #require(o[key]), keys.dropFirst()) }
                return o
            }
            var a = try #require(raw as? [Any]); let index = try #require(Int(key))
            a[index] = try changed(a[index], keys.dropFirst()); return a
        }
        value = try #require(changed(value, path[...]) as? [String: Any])
    }
}
