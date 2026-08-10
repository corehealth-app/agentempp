import Foundation
import Testing

@testable import BodyFlow

@Suite("Mascot presentation")
struct MascotPresentationTests {
    @Test("effective personas select only their approved geometry and tone")
    func personalityDescriptors() {
        #expect(MascotPresentation.personality(.focus) == MascotPersonalityDescriptor(
            geometry: .stable,
            tone: .restrained
        ))
        #expect(MascotPresentation.personality(.impulse) == MascotPersonalityDescriptor(
            geometry: .energetic,
            tone: .bright
        ))
        #expect(MascotPresentation.personality(.zen) == MascotPersonalityDescriptor(
            geometry: .calm,
            tone: .soft
        ))
        #expect(MascotPresentation.personality(.balanced) == MascotPersonalityDescriptor(
            geometry: .neutral,
            tone: .neutral
        ))
    }

    @Test("requested mascot states use the approved neutral copy")
    func requestedStateCopy() {
        #expect(MascotPresentation.state(.inactive) == MascotStateDescriptor(
            semanticState: .inactive,
            title: "Em repouso"
        ))
        #expect(MascotPresentation.state(.reactivating) == MascotStateDescriptor(
            semanticState: .reactivating,
            title: "Retomando com você"
        ))
        #expect(MascotPresentation.state(.active) == MascotStateDescriptor(
            semanticState: .active,
            title: "Ativo"
        ))
        #expect(MascotPresentation.state(.neglected) == MascotStateDescriptor(
            semanticState: .neglected,
            title: "Em pausa"
        ))
    }

    @Test("evolving and unknown are explicit neutral states")
    func neutralUnsupportedStates() {
        #expect(
            MascotPresentation.state(.evolving).title
                == "Estado do mascote em atualização"
        )
        #expect(
            MascotPresentation.state(.unknown("future")).title
                == "Estado do mascote em atualização"
        )
        #expect(
            MascotPresentation.state(.unknown("future")).semanticState
                != .active
        )
        #expect(MascotPresentation.state(.evolving).semanticState == .unsupported)
        #expect(
            MascotPresentation.state(.unknown("future")).semanticState
                == .unsupported
        )
    }

    @Test("server option names and descriptions remain code keyed and literal")
    func serverOwnedOptions() {
        let serverOptions = [
            CoachPersonaOption(
                code: .zen,
                name: "Zen do servidor",
                description: "Descrição Zen do servidor."
            ),
            CoachPersonaOption(
                code: .focus,
                name: "Foco do servidor",
                description: "Descrição Focus do servidor."
            ),
            CoachPersonaOption(
                code: .impulse,
                name: "Impulso do servidor",
                description: "Descrição Impulse do servidor."
            ),
        ]
        let options = MascotPresentation.options(serverOptions)
        let optionsByCode = MascotPresentation.optionsByCode(serverOptions)

        #expect(options.map(\.code) == [.zen, .focus, .impulse])
        #expect(options.map(\.name) == [
            "Zen do servidor",
            "Foco do servidor",
            "Impulso do servidor",
        ])
        #expect(optionsByCode[.focus] == MascotPersonaOptionPresentation(
            code: .focus,
            name: "Foco do servidor",
            description: "Descrição Focus do servidor."
        ))
        #expect(optionsByCode[.impulse]?.name == "Impulso do servidor")
        #expect(
            optionsByCode[.impulse]?.description
                == "Descrição Impulse do servidor."
        )
        #expect(optionsByCode[.zen]?.name == "Zen do servidor")
        #expect(optionsByCode[.zen]?.description == "Descrição Zen do servidor.")
    }

    @Test("changed_at has one literal UTC independent display format")
    func changedAtLiteralFormatting() {
        let timestamp = APITimestamp(
            value: Date(timeIntervalSince1970: 1_784_502_900)
        )

        #expect(MascotPresentation.changedAt(timestamp) == "19/07/2026, 23:15")
    }

    @Test("state is orthogonal to effective personality")
    func stateDoesNotChangePersonality() {
        let states: [MascotWireState] = [
            .inactive,
            .reactivating,
            .active,
            .evolving,
            .neglected,
            .unknown("future"),
        ]

        for state in states {
            _ = MascotPresentation.state(state)
            #expect(
                MascotPresentation.personality(.focus)
                    == MascotPersonalityDescriptor(
                        geometry: .stable,
                        tone: .restrained
                    )
            )
        }
    }

    @Test("time XP weight streak and activity cannot change a descriptor")
    func unrelatedProgressInputsDoNotChangePersonality() {
        let early = MascotExperiencePresentation(
            snapshot: Self.snapshot(
                state: .inactive,
                changedAt: Date(timeIntervalSince1970: 0)
            )
        )
        let late = MascotExperiencePresentation(
            snapshot: Self.snapshot(
                state: .active,
                changedAt: Date(timeIntervalSince1970: 4_102_444_800)
            )
        )

        #expect(early.personality == MascotPersonalityDescriptor(
            geometry: .calm,
            tone: .soft
        ))
        #expect(late.personality == early.personality)
    }

    private static func snapshot(
        state: MascotWireState,
        changedAt: Date
    ) -> CoachExperienceSnapshot {
        CoachExperienceSnapshot(
            selected: .zen,
            effective: .zen,
            options: [
                CoachPersonaOption(
                    code: .focus,
                    name: "Foco",
                    description: "Descrição remota Focus."
                ),
                CoachPersonaOption(
                    code: .impulse,
                    name: "Impulso",
                    description: "Descrição remota Impulse."
                ),
                CoachPersonaOption(
                    code: .zen,
                    name: "Zen",
                    description: "Descrição remota Zen."
                ),
            ],
            mascot: MascotSnapshot(
                state: state,
                changedAt: APITimestamp(value: changedAt)
            ),
            contractVersion: "bodyflow.coach-persona.v1"
        )
    }
}
