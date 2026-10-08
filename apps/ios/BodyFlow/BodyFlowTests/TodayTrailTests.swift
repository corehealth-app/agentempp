import Foundation
import Testing

@testable import BodyFlow

@Suite("Today trail and food ring")
struct TodayTrailTests {
    @Test("Nodes carry only official figures; nothing is invented")
    func nodesAreHonest() {
        let trail = TodayTrailDescriptor(
            recordCount: 3, remainingFood: "731 kcal", blockPercentage: 32, showsBlock7700: true, language: .portugueseBrazil
        )
        #expect(trail.nodes.map(\.kind) == [.register, .today, .block, .progress])
        #expect(trail.nodes[0].detail == "3 registros" && trail.nodes[0].reached)
        #expect(trail.nodes[1].detail == "731 kcal" && trail.nodes[1].reached)
        // The block is credited only when the day closes: never ticked today.
        #expect(trail.nodes[2].detail == "32% acumulado" && !trail.nodes[2].reached)
        #expect(trail.nodes[3].detail == "Resultado ao longo das semanas" && !trail.nodes[3].reached)

        let empty = TodayTrailDescriptor(
            recordCount: 0, remainingFood: nil, blockPercentage: nil, showsBlock7700: true, language: .englishUnitedStates
        )
        #expect(empty.nodes[0].detail == "0 entries" && !empty.nodes[0].reached)
        #expect(empty.nodes[1].detail == nil && !empty.nodes[1].reached)
        #expect(empty.nodes[2].detail == nil && !empty.nodes[2].reached)
        // A target without any record today is not a reached "Hoje".
        let noRecords = TodayTrailDescriptor(recordCount: 0, remainingFood: "731 kcal", blockPercentage: 0, showsBlock7700: true, language: .portugueseBrazil)
        #expect(noRecords.nodes[1].detail == "731 kcal" && !noRecords.nodes[1].reached)
        #expect(noRecords.nodes[2].detail == "0% acumulado" && !noRecords.nodes[2].reached)
    }

    @Test("Node titles resolve through the real lookup, never as raw keys", arguments: SupportedAppLanguage.allCases)
    func titlesResolve(_ language: SupportedAppLanguage) {
        let expected: [TodayTrailDescriptor.Node.Kind: String] = language == .portugueseBrazil
            ? [.register: "Registrar", .today: "Hoje", .block: "Bloco 7.700", .progress: "Progresso"]
            : [.register: "Register", .today: "Today", .block: "7,700 Block", .progress: "Progress"]
        for (kind, title) in expected {
            #expect(TodayCopy.string(kind.titleKey, language: language) == title)
        }
    }

    @Test("The ring draws consumed over target, clamped, and nothing without a target")
    func ringFraction() {
        #expect(BodyFlowRing.clampedFraction(consumed: 676, target: 3355) == 676.0 / 3355.0)
        #expect(BodyFlowRing.clampedFraction(consumed: 4000, target: 3355) == 1)
        #expect(BodyFlowRing.clampedFraction(consumed: 0, target: 3355) == 0)
        #expect(BodyFlowRing.clampedFraction(consumed: 500, target: nil) == nil)
        #expect(BodyFlowRing.clampedFraction(consumed: 500, target: 0) == nil)
    }

    @Test("Trail copy exists in both languages", arguments: SupportedAppLanguage.allCases)
    func copyExists(_ language: SupportedAppLanguage) throws {
        for key in ["today.trail.title", "today.trail.detail", "today.trail.records", "today.trail.pending",
                    "today.trail.reached", "today.trail.node.register", "today.trail.node.today",
                    "today.trail.node.block", "today.trail.node.progress"] {
            let text = try AppLocalization.string(String.LocalizationValue(key), for: language)
            #expect(text != key && !text.isEmpty, "\(key) / \(language)")
        }
    }
}
