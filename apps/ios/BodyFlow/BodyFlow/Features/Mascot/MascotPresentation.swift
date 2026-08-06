import Foundation

enum MascotPersonalityGeometry: Equatable, Sendable {
    case stable
    case energetic
    case calm
    case neutral
}

enum MascotPersonalityTone: Equatable, Sendable {
    case restrained
    case bright
    case soft
    case neutral
}

struct MascotPersonalityDescriptor: Equatable, Sendable {
    let geometry: MascotPersonalityGeometry
    let tone: MascotPersonalityTone
}

enum MascotSemanticState: Equatable, Sendable {
    case inactive
    case reactivating
    case active
    case neglected
    case unsupported
}

struct MascotStateDescriptor: Equatable, Sendable {
    let semanticState: MascotSemanticState
    let title: String
}

struct MascotPersonaOptionPresentation: Identifiable, Equatable, Sendable {
    let code: SelectableCoachPersona
    let name: String
    let description: String

    var id: SelectableCoachPersona { code }
}

struct MascotExperiencePresentation: Equatable, Sendable {
    let selected: SelectableCoachPersona?
    let effective: EffectiveCoachPersona
    let options: [MascotPersonaOptionPresentation]
    let optionsByCode: [SelectableCoachPersona: MascotPersonaOptionPresentation]
    let personality: MascotPersonalityDescriptor
    let mascotState: MascotStateDescriptor
    let changedAtText: String

    init(snapshot: CoachExperienceSnapshot) {
        selected = snapshot.selected
        effective = snapshot.effective
        options = MascotPresentation.options(snapshot.options)
        optionsByCode = MascotPresentation.optionsByCode(snapshot.options)
        personality = MascotPresentation.personality(snapshot.effective)
        mascotState = MascotPresentation.state(snapshot.mascot.state)
        changedAtText = MascotPresentation.changedAt(snapshot.mascot.changedAt)
    }
}

enum MascotPresentation {
    static func personality(
        _ persona: EffectiveCoachPersona
    ) -> MascotPersonalityDescriptor {
        switch persona {
        case .focus:
            MascotPersonalityDescriptor(
                geometry: .stable,
                tone: .restrained
            )
        case .impulse:
            MascotPersonalityDescriptor(
                geometry: .energetic,
                tone: .bright
            )
        case .zen:
            MascotPersonalityDescriptor(
                geometry: .calm,
                tone: .soft
            )
        case .balanced:
            MascotPersonalityDescriptor(
                geometry: .neutral,
                tone: .neutral
            )
        }
    }

    static func state(_ state: MascotWireState) -> MascotStateDescriptor {
        switch state {
        case .inactive:
            MascotStateDescriptor(
                semanticState: .inactive,
                title: "Em repouso"
            )
        case .reactivating:
            MascotStateDescriptor(
                semanticState: .reactivating,
                title: "Retomando com você"
            )
        case .active:
            MascotStateDescriptor(
                semanticState: .active,
                title: "Ativo"
            )
        case .neglected:
            MascotStateDescriptor(
                semanticState: .neglected,
                title: "Em pausa"
            )
        case .evolving, .unknown:
            MascotStateDescriptor(
                semanticState: .unsupported,
                title: "Estado do mascote em atualização"
            )
        }
    }

    static func options(
        _ options: [CoachPersonaOption]
    ) -> [MascotPersonaOptionPresentation] {
        options.map { option in
            MascotPersonaOptionPresentation(
                code: option.code,
                name: option.name,
                description: option.description
            )
        }
    }

    static func optionsByCode(
        _ options: [CoachPersonaOption]
    ) -> [SelectableCoachPersona: MascotPersonaOptionPresentation] {
        options.reduce(into: [:]) { result, option in
            result[option.code] = MascotPersonaOptionPresentation(
                code: option.code,
                name: option.name,
                description: option.description
            )
        }
    }

    static func changedAt(_ timestamp: APITimestamp) -> String {
        timestamp.value.formatted(
            Date.FormatStyle(
                date: .numeric,
                time: .shortened,
                locale: Locale(identifier: "pt_BR"),
                timeZone: .gmt
            )
        )
    }
}
