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

    var summary: String {
        switch self {
        case .focus: "Direto, firme e objetivo."
        case .impulse: "Motivador, positivo e energético."
        case .zen: "Calmo, didático e acolhedor."
        }
    }
}
