import Testing
@testable import BodyFlow

@MainActor
struct FeatureActionLabelTests {
    @Test
    func canDelegateDisclosureIndicatorToNavigationContainer() {
        let label = FeatureActionLabel(
            title: "Destino",
            detail: "Abrir destino",
            systemImage: "list.clipboard",
            showsDisclosureIndicator: false
        )

        #expect(label.disclosureSystemImage == nil)
    }

    @Test
    func standaloneActionKeepsDisclosureIndicator() {
        let label = FeatureActionLabel(
            title: "Ação",
            detail: "Abrir ação",
            systemImage: "plus.circle"
        )

        #expect(label.disclosureSystemImage == "chevron.right")
    }
}
