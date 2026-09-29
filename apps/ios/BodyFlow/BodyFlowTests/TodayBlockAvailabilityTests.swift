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
