import Observation
import SwiftUI

enum AppRoute: Hashable, Sendable {
    case detail(tab: AppTab, id: String)
    case mainHistory
    case historyMealLog(rowID: String)
    case historyWorkout(logID: String)
    case routine(RoutineRoute)
    case plan(PlanRoute)
    case progress(ProgressRoute)
    case content(ContentRoute)
    case mascot(MascotRoute)
    case flowChat
    case localReminders
    case currentObjective
    case planDraft(PlanDraftRoute)
    case planImport

    var tab: AppTab {
        switch self {
        case let .detail(tab, _):
            tab
        case .mainHistory, .historyMealLog, .historyWorkout:
            .today
        case .routine:
            .today
        case .plan:
            .plan
        case .progress:
            .progress
        case .content, .mascot, .flowChat:
            .today
        case .localReminders, .currentObjective:
            .profile
        case let .planDraft(route):
            route.origin == .flow ? .today : .plan
        case .planImport:
            .plan
        }
    }

    var accessibilityIdentifier: String {
        if case .flowChat = self {
            return "screen.flow-chat"
        }
        if case .localReminders = self {
            return "screen.local-reminders"
        }
        if case .currentObjective = self { return "screen.current-objective" }
        if case .planDraft = self {
            return "screen.plan.draft"
        }
        if case .planImport = self {
            return "screen.plan.import"
        }
        return switch tab {
        case .today: "route.hoje.detalhe"
        case .register: "route.registrar.detalhe"
        case .plan: "route.plano.detalhe"
        case .progress: "route.progresso.detalhe"
        case .profile: "route.perfil.detalhe"
        }
    }
}

enum LibrarySelection: Hashable, Sendable {
    case all
    case saved

    var contentSurface: ContentSurface {
        switch self {
        case .all: .library
        case .saved: .saved
        }
    }
}

enum ContentRoute: Hashable, Sendable {
    case library(initialSelection: LibrarySelection)
    case detail(publicationID: String, origin: ContentOrigin)
}

enum MascotRoute: Hashable, Sendable {
    case detail
}

/// A draft is addressed by its identity alone; the review reloads it. The
/// origin says which tab's stack shows it (Flow lives in Today).
struct PlanDraftRoute: Hashable, Sendable {
    enum Origin: Hashable, Sendable {
        case flow
        case plan
    }

    let draftID: String
    let origin: Origin
}

/// Plan navigation intentionally carries no mutable plan snapshot. The
/// destination reloads only the current Plan capability.
enum PlanRoute: Hashable, Sendable {
    case detail
}

/// Progress routes carry no response snapshot. The block destination reloads
/// only the Today capability, which is its documented source of truth.
enum ProgressRoute: Hashable, Sendable {
    case block7700
}

enum RoutineRouteDestination: Hashable, Sendable {
    case list
    case detail
    case history
}

/// A routine route intentionally contains only the response item identity and
/// destination. Detail data is always selected from the matching list snapshot.
struct RoutineRoute: Hashable, Sendable {
    let kind: RoutineItemKind
    let itemID: String?
    let destination: RoutineRouteDestination

    init(
        kind: RoutineItemKind,
        itemID: String? = nil,
        destination: RoutineRouteDestination
    ) {
        self.kind = kind
        self.itemID = itemID
        self.destination = destination
    }
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

    var title: String {
        switch self {
        case .meal: "Refeição"
        case .training: "Treino"
        case .weight: "Peso"
        case .hydration: "Hidratação"
        }
    }

    var systemImage: String {
        switch self {
        case .meal: "fork.knife"
        case .training: "figure.run"
        case .weight: "scalemass"
        case .hydration: "drop"
        }
    }

    var commandAccessibilityIdentifier: String {
        "register.\(id)"
    }
}

enum AppSheet: Identifiable, Hashable, Sendable {
    /// `mealEntry` is the way of telling the meal already chosen on the
    /// Register screen (photo, text or audio); it is only read for a meal.
    case registration(RegistrationKind, mealEntry: MealCaptureEntry? = nil, mealType: MealType? = nil)

    /// An explicitly selected Today slot wins over text/clock suggestions.
    var selectedMealType: MealType? {
        switch self {
        case let .registration(kind, _, type): kind == .meal ? type : nil
        }
    }

    /// The entry never changes which sheet this is.
    var id: String {
        switch self {
        case let .registration(kind, _, _):
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
        guard route.tab == tab else { return }
        paths[tab, default: []].append(route)
    }

    func popToRoot(in tab: AppTab) {
        paths[tab] = []
    }
}
