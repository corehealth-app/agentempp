import Foundation
import Testing

@testable import BodyFlow

@Suite("Today block availability")
struct TodayBlockAvailabilityTests {
    // Staging 2026-09-29: the Bloco 7.700 card showed the raw code "available".
    @Test("the server availability code is shown in the reader's language")
    func availabilityCodeIsLocalized() {
        #expect(TodayBlockDescriptor.availabilityText(
            "available",
            language: .portugueseBrazil
        ) == "Disponível")
        #expect(TodayBlockDescriptor.availabilityText(
            "available",
            language: .englishUnitedStates
        ) == "Available")
        #expect(TodayBlockDescriptor.availabilityText(
            "unavailable",
            language: .portugueseBrazil
        ) == "Indisponível")
        #expect(TodayBlockDescriptor.availabilityText(
            nil,
            language: .englishUnitedStates
        ) == "Not available")
    }

    @Test("an unknown availability code is shown as sent")
    func unknownCodeIsNotGuessed() {
        #expect(TodayBlockDescriptor.availabilityText(
            "paused",
            language: .portugueseBrazil
        ) == "paused")
    }
}

@Suite("Meal type label")
struct MealTypeLabelTests {
    // Staging 2026-09-30: Today and History showed the raw code "cafe".
    @Test("a meal type code is shown in the reader's language")
    func codeIsLocalized() {
        #expect(RegistrationCopy.mealTypeTitle(code: "cafe", language: .portugueseBrazil) == "Café da manhã")
        #expect(RegistrationCopy.mealTypeTitle(code: "almoco", language: .portugueseBrazil) == "Almoço")
        #expect(RegistrationCopy.mealTypeTitle(code: "ceia", language: .portugueseBrazil) == "Ceia")
    }

    @Test("an unknown meal type code is shown as sent")
    func unknownCodeIsKept() {
        #expect(RegistrationCopy.mealTypeTitle(code: "brunch", language: .portugueseBrazil) == "brunch")
    }

    @Test("a pending meal in Precisa da sua atenção shows its type in Portuguese")
    func pendingMealTypeIsLocalized() {
        let pending = TodayPendingDescriptor(id: "p1", kind: "meal", mealType: "almoco")
        #expect(pending.detail(for: .portugueseBrazil) == "Almoço")
    }
}

@Suite("Today expanded status labels")
struct TodayExpandedStatusLabelTests {
    // iPhone staging 2026-10-01: after confirming the 6-second audio
    // "No almoço eu comi 150g de arroz branco cozido e 120g de frango grelhado",
    // expanded Today showed provisional / below_target / not_recorded.
    @Test("the exact post-audio statuses are readable without changing official figures")
    func recordedAudioStatusesAreLocalized() {
        let energy = TodayEnergyDescriptor(
            targetKcal: 3_361, consumedKcal: 383, remainingFoodKcal: 2_978,
            foodExcessKcal: 0, exerciseKcal: 0, dailyBalanceKcal: -2_978,
            dailyBalanceStatus: "provisional"
        )
        let protein = TodayProteinDescriptor(
            consumedG: Decimal(string: "42.22")!, targetG: Decimal(string: "186.1")!,
            remainingG: Decimal(string: "143.88")!, percentage: 23, status: "below_target"
        )
        let hydration = TodayHydrationDescriptor(
            consumedML: 0, targetML: nil, remainingML: nil, percentage: nil,
            status: "not_recorded"
        )
        #expect(TodayStatusText.label(energy.dailyBalanceStatus, kind: .balance,
            language: .portugueseBrazil) == "Dia em andamento")
        #expect(TodayStatusText.label(protein.status, kind: .protein,
            language: .portugueseBrazil) == "Abaixo da meta")
        #expect(TodayStatusText.label(hydration.status, kind: .hydration,
            language: .portugueseBrazil) == "Nenhum registro")
        #expect(TodayStatusText.label(energy.dailyBalanceStatus, kind: .balance,
            language: .englishUnitedStates) == "Day in progress")
        #expect(TodayStatusText.label(protein.status, kind: .protein,
            language: .englishUnitedStates) == "Below target")
        #expect(TodayStatusText.label(hydration.status, kind: .hydration,
            language: .englishUnitedStates) == "No records")
        #expect(energy.remainingFoodKcal == 2_978 && energy.dailyBalanceKcal == -2_978)
        #expect(protein.consumedG == Decimal(string: "42.22"))
        #expect(protein.remainingG == Decimal(string: "143.88"))
        #expect(hydration.targetML == nil && hydration.consumedML == 0)
        #expect(energy.dailyBalanceStatus == "provisional")
        #expect(protein.status == "below_target" && hydration.status == "not_recorded")
    }

    @Test("neighboring documented states are localized in both app languages")
    func neighboringStatusesAreLocalized() {
        let cases: [(TodayStatusText.Kind, String, String, String)] = [
            (.balance, "final", "Balanço final", "Final balance"),
            (.balance, "insufficient_data", "Dados insuficientes", "Insufficient data"),
            (.protein, "target_unavailable", "Meta indisponível", "Target unavailable"),
            (.protein, "target_reached", "Meta atingida", "Target reached"),
            (.hydration, "target_reached", "Meta atingida", "Target reached"),
            (.hydration, "tracked_without_target", "Registrado sem meta", "Recorded without a target"),
            (.hydration, "not_started", "Ainda não iniciado", "Not started yet"),
            (.hydration, "in_progress", "Em andamento", "In progress"),
        ]
        for (kind, code, pt, en) in cases {
            #expect(TodayStatusText.label(code, kind: kind, language: .portugueseBrazil) == pt)
            #expect(TodayStatusText.label(code, kind: kind, language: .englishUnitedStates) == en)
        }
    }

    @Test("unknown status codes and codes from another section are not guessed")
    func unknownCodesRemainLiteral() {
        for kind in [TodayStatusText.Kind.balance, .protein, .hydration] {
            #expect(TodayStatusText.label("paused", kind: kind,
                language: .portugueseBrazil) == "paused")
        }
        #expect(TodayStatusText.label("below_target", kind: .balance,
            language: .portugueseBrazil) == "below_target")
    }
}
