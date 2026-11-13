import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI
  import UIKit
  @MainActor @Suite("Recorded training is readable without a completion form")
  struct TrainingWindowRenderingTests {
    @Test(arguments: [false, true]) func activityShowsOriginalDurationAndEnergyInBothLanguages(
      _ english: Bool
    ) throws {
      let s = try TrainingWindowFixture().snapshot()
      let w = try #require(s.days[2].workouts.first)
      let host = SignUpRenderingProbe.host(
        TrainingActivityFactView(activity: w, timezone: s.timezone, english: english).environment(
          \.locale, Locale(identifier: english ? "en_US" : "pt_BR")), width: 390, height: 400)
      defer { host.detach() }
      let n = try #require(
        host.nodes().first { $0.identifier == "training.recorded.\(w.id.uuidString.lowercased())" })
      #expect(n.frame.width > 0 && n.frame.height > 0)
      #expect(n.label.contains("Caminhada") && n.label.contains("30") && n.label.contains("116"))
      #expect(n.label.contains(english ? "Estimated expenditure" : "Gasto estimado"))
      #expect(!n.label.contains(english ? "Confirm" : "Confirmar"))
    }
    @Test func unknownEnergyDoesNotAppearAsZeroOrARequiredCalorieField() throws {
      let f = try TrainingWindowFixture()
      var raw = try f.raw()
      var days = try #require(raw["days"] as? [[String: Any]])
      var records = try #require(days[2]["workouts"] as? [[String: Any]])
      records[0]["estimated_kcal"] = NSNull()
      records[0]["duration_min"] = NSNull()
      days[2]["workouts"] = records
      raw["days"] = days
      let s = try f.snapshot(raw)
      let w = try #require(s.days[2].workouts.first)
      let host = SignUpRenderingProbe.host(
        TrainingActivityFactView(activity: w, timezone: s.timezone, english: false), width: 390,
        height: 400)
      defer { host.detach() }
      let n = try #require(
        host.nodes().first { $0.identifier == "training.recorded.\(w.id.uuidString.lowercased())" })
      #expect(n.label.contains("Gasto não informado") && n.label.contains("Duração não informada"))
      #expect(!n.label.contains("0 kcal"))
      #expect(!host.nodes().contains { $0.identifier.contains("quantity") })
    }
  }
#endif
