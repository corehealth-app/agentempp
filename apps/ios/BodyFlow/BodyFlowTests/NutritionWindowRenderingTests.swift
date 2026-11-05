import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI
  import UIKit

  @MainActor
  @Suite("Nutrition renders complete read observations without treating plans as consumed")
  struct NutritionWindowRenderingTests {
    @Test func actualSQLUnitRowsRenderLiteralAndApproximateReferencesWithoutAConstructedDay() throws
    {
      let fixture = try NutritionActualUnitFixture()
      for food in ["milk", "whey"] {
        for stage in ["original", "saved", "undone"] {
          let meal = try fixture.meal(food: food, stage: stage)
          let host = SignUpRenderingProbe.host(
            NutritionMealFactView(meal: meal, english: false)
              .environment(\.locale, Locale(identifier: "pt_BR")), width: 390, height: 400)
          defer { host.detach() }
          let node = try #require(
            host.nodes().first {
              $0.identifier == "nutrition.consumed.\(meal.id.uuidString.lowercased())"
            })
          let expected = NutritionQuantityPresentation.consumed(
            meal, locale: Locale(identifier: "pt_BR"), english: false)
          #expect(
            node.label.contains(expected.text) && node.frame.width > 0 && node.frame.height > 0)
          if stage == "saved" {
            #expect(node.label.contains("≈") && node.label.contains("Referência original"))
            #expect(node.label.contains(food == "milk" ? "206 g" : "30 g"))
          } else {
            #expect(!node.label.contains("Referência original"))
          }
        }
      }
    }
    @Test func dayContentShowsTwoLegitimateConsumedRegistrationsAndASeparatePrescription()
      async throws
    {
      let snapshot = try NutritionWindowFixture().snapshot()
      let model = NutritionWindowModel(
        provider: NutritionRenderingProvider(value: snapshot),
        expectedAuthUserID: snapshot.authUserID)
      await model.load(revision: 0)
      let host = SignUpRenderingProbe.host(
        NutritionWindowContentView(model: model, revision: 0)
          .environment(\.locale, Locale(identifier: "pt_BR")), width: 390, height: 2400)
      defer { host.detach() }
      let nodes = host.nodes()
      for meal in snapshot.days[2].meals {
        let row = try #require(
          nodes.first { $0.identifier == "nutrition.consumed.\(meal.id.uuidString.lowercased())" })
        #expect(row.frame.width > 0 && row.frame.height > 0)
        #expect(row.label.contains("Arroz branco cozido") && row.label.contains("150"))
      }
      let plan = try #require(snapshot.days[2].planned.meals.first)
      let planned = try #require(nodes.first { $0.identifier == "nutrition.planned.\(plan.id)" })
      #expect(planned.label.contains("Feijão cozido"))
      #expect(nodes.contains { $0.label.contains("Realizado") })
      #expect(nodes.contains { $0.label.contains("Planejado") })
      #expect(nodes.contains { $0.label.contains("Metas do dia indisponíveis") })
      #expect(!nodes.contains { $0.identifier.contains("meal.edit") })
    }
    @Test func weekContentShowsSevenOfficialDaysAndConfirmedEmptyTotals() async throws {
      let snapshot = try NutritionWindowFixture().snapshot()
      let model = NutritionWindowModel(
        provider: NutritionRenderingProvider(value: snapshot),
        expectedAuthUserID: snapshot.authUserID)
      await model.load(revision: 0)
      model.period = .week
      let host = SignUpRenderingProbe.host(
        NutritionWindowContentView(model: model, revision: 0)
          .environment(\.locale, Locale(identifier: "pt_BR")), width: 390, height: 7000)
      defer { host.detach() }
      let nodes = host.nodes()
      for day in snapshot.days {
        #expect(
          nodes.contains {
            $0.identifier == "nutrition.totals.\(day.localDate)" && $0.frame.height > 0
          })
      }
      let monday = try #require(nodes.first { $0.identifier == "nutrition.totals.2026-11-02" })
      #expect(
        monday.label.contains("0 kcal") && monday.label.contains("Metas do dia indisponíveis"))
    }
    @Test func fullRootKeepsTheSameWeekContentInsideARealScrollableViewport() async throws {
      let snapshot = try NutritionWindowFixture().snapshot()
      let model = NutritionWindowModel(
        provider: NutritionRenderingProvider(value: snapshot),
        expectedAuthUserID: snapshot.authUserID)
      await model.load(revision: 0)
      model.period = .week
      let host = SignUpRenderingProbe.host(
        NutritionWindowRootView(model: model, revision: 0, isSelected: false)
          .environment(\.locale, Locale(identifier: "pt_BR")), width: 390, height: 800)
      defer { host.detach() }
      let scroll = try #require(
        host.scrollViews().first {
          $0.bounds.height > 0 && $0.contentSize.height > $0.bounds.height
        })
      #expect(scroll.isScrollEnabled && scroll.contentSize.width > 0)
      #expect(host.geometry().isMounted)
      #expect(model.snapshot?.sourceVersion == snapshot.sourceVersion)
    }
    @Test func unavailableContentShowsNoCachedNutritionFacts() async throws {
      let snapshot = try NutritionWindowFixture().snapshot()
      let model = NutritionWindowModel(
        provider: NutritionRenderingProvider(value: snapshot),
        expectedAuthUserID: snapshot.authUserID, isCurrent: { false })
      await model.load(revision: 0)
      let host = SignUpRenderingProbe.host(
        NutritionWindowContentView(model: model, revision: 0)
          .environment(\.locale, Locale(identifier: "pt_BR")), width: 390, height: 1200)
      defer { host.detach() }
      let nodes = host.nodes()
      #expect(nodes.contains { $0.label.contains("Alimentação indisponível") })
      #expect(
        !nodes.contains {
          $0.identifier.hasPrefix("nutrition.consumed.")
            || $0.identifier.hasPrefix("nutrition.totals.")
        })
    }
  }
  private struct NutritionRenderingProvider: NutritionWindowProviding {
    let value: NutritionWindowSnapshot
    func nutritionWindow(date: String?) async throws -> NutritionWindowSnapshot { value }
  }
#endif
