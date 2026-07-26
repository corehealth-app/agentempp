enum CoachPersona: CaseIterable, Codable, Equatable, Sendable {
    case focus
    case impulse
    case zen

    var displayName: String {
        switch self {
        case .focus: "Focus"
        case .impulse: "Impulse"
        case .zen: "Zen"
        }
    }
}
