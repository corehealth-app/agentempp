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
