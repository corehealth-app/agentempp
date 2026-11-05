import Foundation
import Testing
@testable import BodyFlow

@Suite("Today v4 independent energy presentation")
struct TodayFieldAvailabilityPresentationTests {
    @Test func unknownExerciseDoesNotHideProvedNutritionOrPriorLedger() throws {
        let p = TodayPresentation(snapshot: try TodayFieldAvailabilityFixture.response().data)
        #expect(p.energy.exerciseText(for: .portugueseBrazil) == "Indisponível")
        #expect(p.energy.exerciseText(for: .englishUnitedStates) == "Not available")
        #expect(p.energy.targetKcal == 1900 && p.energy.consumedKcal == 1200)
        #expect(p.energy.remainingFoodKcal == 700 && p.energy.foodExcessKcal == 0)
        #expect(p.protein.consumedG == Decimal(string: "90.5") && p.protein.targetG == 130)
        #expect(p.energy.netBalanceText == "Indisponível")
        #expect(p.energy.netBalanceCaption == "Indisponível enquanto houver gasto de exercício desconhecido.")
        #expect(!p.energy.netBalanceCaption.contains("nível de atividade"))
        #expect(p.blockPolicy.showsBlock)
    }

    @Test(arguments: ["ganho_massa", "manutencao"])
    func officialIndependentBalanceIsShownWithoutSubtractingUnknownEnergy(_ objective: String) throws {
        let p = TodayPresentation(snapshot: try TodayFieldAvailabilityFixture.response { data in
            data["protocol"] = objective
            data["current_protocol"] = objective
            data["daily_balance_kcal"] = 142
            data["daily_balance_reference_kcal"] = 2838
            data["daily_balance_includes_exercise"] = false
            data["daily_balance_energy"] = ["status":"available"]
            data["block_7700"] = ["enabled":false,"availability":"not_applicable","source":"not_applicable"]
        }.data)
        #expect(p.energy.netBalanceText == "Superávit de 142 kcal")
        #expect(p.energy.netBalanceCaption == "Exercício já contado no nível de atividade")
        #expect(p.energy.exerciseText == "Indisponível")
        #expect(p.energy.remainingFoodKcal == 700)
        #expect(!p.blockPolicy.showsBlock)
    }
}

#if canImport(UIKit)
import SwiftUI
import UIKit

@MainActor
@Suite("Today real content renders per-field energy", .serialized)
struct TodayFieldAvailabilityRenderingTests {
    @Test(arguments: [false, true])
    func unknownExerciseKeepsTheActualFoodAndProteinTiles(_ english: Bool) throws {
        let p = TodayPresentation(snapshot: try TodayFieldAvailabilityFixture.response().data)
        let host = SignUpRenderingProbe.host(
            TodaySummaryPanel(energy: p.energy, protein: p.protein, macros: p.macros,
                hydration: p.hydration, completionMessage: nil, countsUp: false)
                .environment(\.locale, Locale(identifier: english ? "en_US" : "pt_BR")),
            width: 390, height: 1800)
        defer { host.detach() }
        let nodes = host.nodes()
        let exercise = try #require(nodes.first { $0.identifier == "today.exercise" })
        #expect(exercise.frame.width > 0 && exercise.frame.height > 0)
        #expect(exercise.label.contains(english ? "Not available" : "Indisponível"))
        #expect(!exercise.label.contains("0 kcal") && !exercise.label.contains("120 kcal"))
        let remaining = try #require(nodes.first { $0.identifier == "today.energy.remaining-food" })
        #expect(remaining.value == (english ? "700 kilocalories; exercise excluded" : "700 quilocalorias; exercício excluído"))
        let protein = try #require(nodes.first { $0.identifier == "today.protein" })
        #expect(protein.label.contains(english ? "90.5" : "90,5"))
        #expect(nodes.contains { $0.identifier == "today.hydration" && $0.label.contains("750") })
        #expect(host.geometry().isMounted)
    }

    @Test func actualBalanceDetailsShowUnknownReasonWithoutLegacyIncludesExerciseCaption() throws {
        let p = TodayPresentation(snapshot: try TodayFieldAvailabilityFixture.response().data)
        let host = SignUpRenderingProbe.host(TodayEnergyDetailsView(energy: p.energy, language: .portugueseBrazil), width: 390, height: 700)
        defer { host.detach() }
        let nodes = host.nodes()
        #expect(nodes.contains { $0.identifier == "today.energy.net-balance" && $0.label.contains("Indisponível") })
        #expect(nodes.contains { $0.label.contains("gasto de exercício desconhecido") })
        #expect(!nodes.contains { $0.label.contains("Exercício incluído") || $0.label.contains("nível de atividade") })
    }
}
#endif
