enum AppTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case today
    case register
    case plan
    case progress
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Hoje"
        case .register: "Registrar"
        case .plan: "Plano"
        case .progress: "Progresso"
        case .profile: "Perfil"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "house"
        case .register: "plus.circle"
        case .plan: "list.clipboard"
        case .progress: "chart.line.uptrend.xyaxis"
        case .profile: "person.crop.circle"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .today: "tab.hoje"
        case .register: "tab.registrar"
        case .plan: "tab.plano"
        case .progress: "tab.progresso"
        case .profile: "tab.perfil"
        }
    }

    var rootAccessibilityIdentifier: String {
        switch self {
        case .today: "screen.hoje"
        case .register: "screen.registrar"
        case .plan: "screen.plano"
        case .progress: "screen.progresso"
        case .profile: "screen.perfil"
        }
    }
}
