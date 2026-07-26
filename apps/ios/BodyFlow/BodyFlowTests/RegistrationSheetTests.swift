import SwiftUI
import Testing
@testable import BodyFlow

@MainActor
struct RegistrationSheetTests {
    @Test
    func standardTypeUsesCompactDemonstrationDetent() {
        #expect(
            RegistrationSheet.presentationDetents(for: .large) == [.medium]
        )
    }

    @Test
    func accessibilityTypeUsesFullHeightDetent() {
        #expect(
            RegistrationSheet.presentationDetents(for: .accessibility3) == [.large]
        )
    }
}
