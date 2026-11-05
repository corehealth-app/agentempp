import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI
  import UIKit
#endif

@Suite("Closed per-field registration feedback v3", .serialized)
struct RegistrationFeedbackV3Tests {
  @Test(
    "A wrapper's recorded facts use the same closed registration codec without a fabricated day")
  func recordedFactsHaveTheirOwnClosedBoundary() throws {
    for row in try fixtures() {
      let receipt = try #require(row["payload"] as? [String: Any])
      let object = try #require(receipt["registration"] as? [String: Any])
      let data = try JSONSerialization.data(withJSONObject: object)
      let recorded = try JSONDecoder().decode(
        RegistrationFeedbackV3Snapshot.Recorded.self, from: data)
      let encoded =
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(recorded)) as? NSDictionary
      #expect(encoded == object as NSDictionary)
      var foreign = object
      foreign["clinical_authority"] = true
      #expect(throws: (any Error).self) {
        try JSONDecoder().decode(
          RegistrationFeedbackV3Snapshot.Recorded.self,
          from: JSONSerialization.data(withJSONObject: foreign))
      }
    }
  }

  @Test("A raw v3 receipt is data, not permission for unprojected legacy display")
  func rawV3IsNotLegacyDisplayAuthority() throws {
    let object = try payload("milk_whey_unknown_day/pt-BR")
    let ack = try acknowledgement(object)
    let feedback = try #require(ack.registration.feedback)
    #expect(feedback.schema == "registration.feedback.v3")
    #expect(feedback.admittedToLegacyConfirmation() == nil)
    #expect(feedback.admittedToLegacyHistory(kind: .meal) == nil)
    #expect(ack.registration.status == "confirmed" && ack.alreadyConfirmed)
  }

  @Test("Actual PostgreSQL receipts preserve known zero, formula energy and pre-coverage unknown")
  func actualPGReceiptParity() throws {
    for row in try pgFixtures() {
      let object = try #require(row["payload"] as? [String: Any])
      guard case .v3(let value) = try decode(object) else {
        Issue.record("Expected v3 PG receipt")
        continue
      }
      let encoded =
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? NSDictionary
      #expect(encoded == object as NSDictionary)
      let expected = try #require(row["sections"] as? [[String: String]])
      for (section, saved) in zip(value.sections, expected) {
        #expect(section.key.rawValue == saved["key"])
        #expect(section.text.utf16.elementsEqual(try #require(saved["text"]).utf16))
      }
      if row["label"] as? String == "precoverage_meal" {
        #expect(value.day?.exerciseKcal == nil)
        #expect(value.day?.exerciseEnergy == .unavailable(.sourceUnavailable))
      }
    }
  }

  #if canImport(UIKit)
    @MainActor
    @Test(
      "The actual v3 renderer displays all six persisted sections",
      arguments: [
        "unknown_workout/pt-BR", "known_zero/en", "milk_whey_unknown_day/pt-BR",
        "clinical_pause/en", "no_targets/en", "education_unavailable/pt-BR",
      ])
    func rendersSixRealSections(_ label: String) throws {
      let receipt = try decode(payload(label))
      guard case .v3(let value) = receipt else {
        Issue.record("Missing v3")
        return
      }
      let host = SignUpRenderingProbe.host(
        RegistrationFeedbackView(feedback: receipt), width: 390, height: 6000)
      defer { host.detach() }
      let nodes = host.nodes()
      for section in value.sections {
        let node = try #require(
          nodes.first { $0.identifier == "registration.feedback.section.\(section.key.rawValue)" })
        #expect(node.label.utf16.elementsEqual(section.text.utf16))
        #expect(node.frame.width > 0 && node.frame.height > 0)
      }
      #expect(host.geometry().isMounted)
    }
  #endif

  @Test("All six sections match the frozen TypeScript renderer in PT and EN")
  func sixSectionCanonicalParity() throws {
    for row in try fixtures() {
      let object = try #require(row["payload"] as? [String: Any])
      guard case .v3(let value) = try decode(object) else {
        Issue.record("Expected v3")
        continue
      }
      let sections = try #require(row["sections"] as? [[String: String]])
      #expect(
        value.sections.map(\.key.rawValue) == [
          "saved", "items", "summary", "day", "block", "education",
        ])
      for (actual, expected) in zip(value.sections, sections) {
        #expect(actual.key.rawValue == expected["key"])
        let text = try #require(expected["text"])
        #expect(actual.text.utf16.elementsEqual(text.utf16))
      }
    }
  }

  @Test("Unknown expenditure and known zero remain distinct while nutrition stays available")
  func unknownIsNotKnownZero() throws {
    guard case .v3(let unknown) = try decode(payload("unknown_workout/pt-BR")),
      case .v3(let zero) = try decode(payload("known_zero/pt-BR")),
      case .v3(let noTargets) = try decode(payload("no_targets/pt-BR")),
      case .v3(let protected) = try decode(payload("clinical_pause/pt-BR")),
      case .v3(let unavailable) = try decode(payload("guidance_unavailable/pt-BR"))
    else {
      Issue.record("Missing v3 fixture")
      return
    }
    #expect(unknown.day?.exerciseKcal == nil && zero.day?.exerciseKcal == 0)
    #expect(unknown.day?.exerciseEnergy == .unavailable(.unknownWorkoutEnergy))
    #expect(zero.day?.exerciseEnergy == .available)
    #expect(unknown.day?.consumed.kcal == zero.day?.consumed.kcal)
    #expect(unknown.day?.caloriesTarget != nil && unknown.day?.proteinTarget != nil)
    #expect(noTargets.day?.caloriePercentage == nil && noTargets.day?.proteinPercentage == nil)
    #expect(protected.block == .protected && protected.day?.caloriesTarget == nil)
    #expect(unavailable.guidance == .unavailable && unavailable.day?.consumed.kcal != nil)
    #expect(unavailable.day?.currentProtocol == nil && unavailable.day?.proteinTarget == nil)
    let day = try #require(unknown.sections.first { $0.key == .day })
    #expect(
      day.text.contains("Gasto de exercício indisponível")
        && day.text.contains("não aumenta a comida disponível"))
    #expect(!day.text.contains("Exercício registrado: 0 kcal"))
  }

  @Test(
    "Replayed meal acknowledgement keeps v3 identity and unavailable education without new effects")
  func validOptionalReceiptReplaysReadOnly() throws {
    let object = try payload("milk_whey_unknown_day/pt-BR")
    let first = try acknowledgement(object)
    let replay = try JSONDecoder().decode(
      RegistrationConfirmationSnapshot.self, from: JSONEncoder().encode(first))
    #expect(first == replay && first.alreadyConfirmed)
    guard case .v3 = first.registration.feedback else {
      Issue.record("Missing acknowledged v3")
      return
    }
    var missingEducation = object
    missingEducation["education"] = ["status": "unavailable"]
    let ack = try acknowledgement(missingEducation)
    #expect(ack.registration.id == first.registration.id && ack.registration.status == "confirmed")
    guard case .v3(let value) = ack.registration.feedback else {
      Issue.record("Education retried or receipt lost")
      return
    }
    #expect(value.education == nil && value.sections.count == 6)
    #expect(value.sections.last?.text.contains("seu registro continua salvo") == true)
    #expect(ack.registration.feedback?.admittedToLegacyHistory(kind: .meal) == nil)
  }

  @Test("Actual prepare fixtures decode without changing saved facts or explicit nulls")
  func actualWireAndHistoricalRoundTrip() throws {
    for row in try fixtures() {
      let object = try #require(row["payload"] as? [String: Any])
      let value = try decode(object)
      #expect(value.schema == "registration.feedback.v3")
      #expect(value.registrationID == object["registration_id"] as? String)
      let encoded =
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? NSDictionary
      #expect(encoded == object as NSDictionary)
      #expect(
        try JSONDecoder().decode(
          RegistrationFeedbackSnapshot.self, from: JSONEncoder().encode(value)) == value)
    }
  }

  @Test("Unknown v3 enrichment remains separate from a factual acknowledgement")
  func optionalEducationFailurePreservesMealAcknowledgement() throws {
    var object = try payload("milk_whey_unknown_day/pt-BR")
    var education = try #require(object["education"] as? [String: Any])
    education["text"] = "private-model-comment"
    object["education"] = education
    let id = try #require(object["registration_id"] as? String)
    let ack = try acknowledgement(object)
    #expect(ack.registration.id == id && ack.registration.status == "confirmed")
    #expect(ack.alreadyConfirmed && ack.registration.feedback == nil)
    #expect(throws: (any Error).self) { try decode(object) }
  }

  @Test(
    "Malformed availability cannot turn unknown energy into a number",
    arguments: [
      "missing-energy", "missing-status", "unknown-status", "unknown-reason", "private-energy",
      "available-null",
      "unavailable-number", "both-status-fields", "day-private", "fake-budget",
      "fake-protein-percent", "without-target-percent",
      "unknown-workout-known-day", "extra-balance", "wrong-day", "unsupported-schema",
    ])
  func rejectsMalformedAvailability(_ defect: String) throws {
    var object = try payload("unknown_workout/pt-BR")
    var day = try #require(object["day"] as? [String: Any])
    switch defect {
    case "missing-energy": day.removeValue(forKey: "exercise_kcal")
    case "missing-status": day.removeValue(forKey: "exercise_energy")
    case "unknown-status": day["exercise_energy"] = ["status": "estimated"]
    case "unknown-reason": day["exercise_energy"] = ["status": "unavailable", "reason": "private"]
    case "private-energy":
      day["exercise_energy"] = [
        "status": "unavailable", "reason": "unknown_workout_energy", "weight_kg": 70,
      ]
    case "available-null": day["exercise_energy"] = ["status": "available"]
    case "unavailable-number": day["exercise_kcal"] = 0
    case "both-status-fields":
      day["exercise_energy"] = ["status": "available", "reason": "unknown_workout_energy"]
    case "day-private": day["profile"] = ["private": true]
    case "fake-budget": day["remaining_food_kcal"] = 99999
    case "fake-protein-percent": day["protein_percentage"] = 1
    case "without-target-percent":
      day["targets"] = ["calories_kcal": NSNull(), "protein_g": NSNull()]
    case "unknown-workout-known-day":
      day["exercise_kcal"] = 0
      day["exercise_energy"] = ["status": "available"]
    case "extra-balance": day["daily_balance_kcal"] = 0
    case "wrong-day": day["local_date"] = "2026-11-04"
    default: object["schema"] = "registration.feedback.v4"
    }
    object["day"] = day
    #expect(throws: (any Error).self) { try decode(object) }
  }

  func fixtures() throws -> [[String: Any]] {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(forResource: "RegistrationFeedbackV3Fixtures", withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "Fixtures/RegistrationFeedbackV3Fixtures.json")
    #endif
    let root = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let values = try #require(root["cases"] as? [[String: Any]])
    #expect(values.count == 20)
    return values
  }
  func pgFixtures() throws -> [[String: Any]] {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(forResource: "RegistrationFeedbackV3PGFixtures", withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "Fixtures/RegistrationFeedbackV3PGFixtures.json")
    #endif
    let root = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let values = try #require(root["cases"] as? [[String: Any]])
    #expect(values.count == 4)
    return values
  }
  func payload(_ label: String) throws -> [String: Any] {
    try #require(fixtures().first { $0["label"] as? String == label }?["payload"] as? [String: Any])
  }
  func decode(_ object: [String: Any]) throws -> RegistrationFeedbackSnapshot {
    try JSONDecoder().decode(
      RegistrationFeedbackSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
  }
  func acknowledgement(_ object: [String: Any]) throws -> RegistrationConfirmationSnapshot {
    let id = try #require(object["registration_id"] as? String)
    let envelope: [String: Any] = [
      "id": id, "status": "confirmed", "created_at": "2026-11-05T12:00:00Z",
      "expires_at": "2026-11-06T12:00:00Z", "resolved_at": "2026-11-05T12:30:00Z",
      "already_confirmed": true, "deduped": false,
      "proposal": ["kind": "meal", "meal_type": "cafe", "items": [], "warnings": []],
      "feedback": object,
    ]
    return try JSONDecoder().decode(
      RegistrationConfirmationSnapshot.self, from: JSONSerialization.data(withJSONObject: envelope))
  }
}
