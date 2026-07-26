import Observation
import SwiftUI

enum AppRoute: Hashable, Sendable {
    case detail(tab: AppTab, id: String)
}

enum RegistrationKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case meal
    case training
    case weight
    case hydration

    var id: String {
        switch self {
        case .meal: "refeicao"
        case .training: "treino"
        case .weight: "peso"
        case .hydration: "hidratacao"
        }
    }
}

enum AppSheet: Identifiable, Hashable, Sendable {
    case registration(RegistrationKind)

    var id: String {
        switch self {
        case let .registration(kind):
            "sheet.registrar.\(kind.id)"
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    private var paths = Dictionary(
        uniqueKeysWithValues: AppTab.allCases.map { ($0, [AppRoute]()) }
    )
    var presentedSheet: AppSheet?

    func path(for tab: AppTab) -> [AppRoute] {
        paths[tab, default: []]
    }

    func binding(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(
            get: { self.path(for: tab) },
            set: { self.paths[tab] = $0 }
        )
    }

    func navigate(to route: AppRoute, in tab: AppTab) {
        paths[tab, default: []].append(route)
    }

    func popToRoot(in tab: AppTab) {
        paths[tab] = []
    }
}
