/// Presentation authority comes from the two fields of one official response.
/// Missing, invalid or contradictory context never proves block eligibility.
enum Block7700PresentationPolicy: Equatable, Sendable {
    case enabled
    case ineligible
    case unknown

    init(currentProtocol: String?, enabled: Bool?) {
        switch (currentProtocol, enabled) {
        case ("recomposicao"?, true?): self = .enabled
        case ("ganho_massa"?, false?), ("manutencao"?, false?): self = .ineligible
        default: self = .unknown
        }
    }

    var showsBlock: Bool { self == .enabled }
    var showsExplanation: Bool { self == .ineligible }
}
