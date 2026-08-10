import Testing
@testable import BodyFlow

@MainActor
@Suite("App router")
struct AppRouterTests {
    @Test("each tab preserves an independent typed path")
    func independentPaths() {
        let router = AppRouter()
        let todayRoute = AppRoute.detail(tab: .today, id: "daily-summary")
        let registerRoute = AppRoute.detail(tab: .register, id: "meal")
        let planRoute = AppRoute.detail(tab: .plan, id: "weekly-plan")
        let progressRoute = AppRoute.detail(tab: .progress, id: "streak")
        let profileRoute = AppRoute.detail(tab: .profile, id: "preferences")

        router.navigate(to: todayRoute, in: .today)
        router.navigate(to: registerRoute, in: .register)
        router.navigate(to: planRoute, in: .plan)
        router.navigate(to: progressRoute, in: .progress)
        router.navigate(to: profileRoute, in: .profile)

        #expect(router.path(for: .today) == [todayRoute])
        #expect(router.path(for: .register) == [registerRoute])
        #expect(router.path(for: .plan) == [planRoute])
        #expect(router.path(for: .progress) == [progressRoute])
        #expect(router.path(for: .profile) == [profileRoute])

        router.popToRoot(in: .plan)
        #expect(router.path(for: .today) == [todayRoute])
        #expect(router.path(for: .register) == [registerRoute])
        #expect(router.path(for: .plan).isEmpty)
        #expect(router.path(for: .progress) == [progressRoute])
        #expect(router.path(for: .profile) == [profileRoute])
    }

    @Test("library and mascot remain typed Today destinations, never tabs")
    func prompt14DestinationsStayOutsideTabIdentity() {
        #expect(AppTab.allCases == [
            .today, .register, .plan, .progress, .profile,
        ])
        #expect(LibrarySelection.all.contentSurface == .library)
        #expect(LibrarySelection.saved.contentSurface == .saved)

        let routes: [AppRoute] = [
            .content(.library(initialSelection: .all)),
            .content(.library(initialSelection: .saved)),
            .content(.detail(
                publicationID: "00000000-0000-4000-8000-000000000101",
                origin: .today
            )),
            .mascot(.detail),
        ]

        #expect(routes.allSatisfy { $0.tab == .today })
    }

    @Test("content detail carries exactly publication identity and origin")
    func contentDetailCarriesNoMutableSnapshot() throws {
        let route = ContentRoute.detail(
            publicationID: "00000000-0000-4000-8000-000000000101",
            origin: .library
        )

        guard case let .detail(publicationID, origin) = route else {
            Issue.record("Expected the typed content detail route")
            return
        }

        #expect(publicationID == "00000000-0000-4000-8000-000000000101")
        #expect(origin == .library)
        let associatedValue = try #require(Mirror(reflecting: route).children.first?.value)
        #expect(Mirror(reflecting: associatedValue).children.map(\.label) == [
            "publicationID", "origin",
        ])
    }

    @Test("content and mascot routes cannot enter another tab stack")
    func prompt14RoutesStayOnToday() {
        let router = AppRouter()
        let detail = AppRoute.content(.detail(
            publicationID: "00000000-0000-4000-8000-000000000101",
            origin: .library
        ))
        let mascot = AppRoute.mascot(.detail)

        router.navigate(to: detail, in: .progress)
        router.navigate(to: mascot, in: .profile)
        #expect(router.path(for: .progress).isEmpty)
        #expect(router.path(for: .profile).isEmpty)

        router.navigate(to: detail, in: .today)
        router.navigate(to: mascot, in: .today)
        #expect(router.path(for: .today) == [detail, mascot])
    }

    @Test("an explicitly mismatched route never mutates any stack")
    func mismatchedTabNavigationIsRejected() {
        let router = AppRouter()
        let planRoute = AppRoute.plan(.detail)

        router.navigate(to: planRoute, in: .today)

        for tab in AppTab.allCases {
            #expect(router.path(for: tab).isEmpty)
        }
    }

    @Test("registration presentation is one enum destination")
    func sheetDestination() {
        let router = AppRouter()
        router.presentedSheet = .registration(.meal)
        #expect(router.presentedSheet?.id == "sheet.registrar.refeicao")
    }

    @Test("detail routes expose stable accessibility identifiers")
    func detailIdentifiers() {
        let routes: [AppRoute] = [
            .detail(tab: .today, id: "daily-summary"),
            .detail(tab: .plan, id: "weekly-plan"),
            .detail(tab: .progress, id: "progress-snapshot"),
            .detail(tab: .profile, id: "profile-preferences"),
        ]

        #expect(routes.map(\.accessibilityIdentifier) == [
            "route.hoje.detalhe",
            "route.plano.detalhe",
            "route.progresso.detalhe",
            "route.perfil.detalhe",
        ])
    }

    @Test("history routes carry only identifiers and remain on the today path")
    func historyRoutesStayTypedAndIndependent() {
        let router = AppRouter()
        let history = AppRoute.mainHistory
        let meal = AppRoute.historyMealLog(rowID: "fixture-meal-row-1")
        let workout = AppRoute.historyWorkout(logID: "fixture-workout-row-1")

        router.navigate(to: history, in: .today)
        router.navigate(to: meal, in: .today)
        router.navigate(to: workout, in: .today)

        #expect(router.path(for: .today) == [history, meal, workout])
        #expect(router.path(for: .register).isEmpty)
        #expect(router.path(for: .plan).isEmpty)
        #expect(router.path(for: .progress).isEmpty)
        #expect(router.path(for: .profile).isEmpty)
    }

    @Test("registration kinds keep copy, symbols, and command identifiers aligned")
    func registrationContract() {
        #expect(RegistrationKind.allCases.map(\.title) == [
            "Refeição", "Treino", "Peso", "Hidratação",
        ])
        #expect(RegistrationKind.allCases.map(\.systemImage) == [
            "fork.knife", "figure.run", "scalemass", "drop",
        ])
        #expect(RegistrationKind.allCases.map(\.commandAccessibilityIdentifier) == [
            "register.refeicao", "register.treino",
            "register.peso", "register.hidratacao",
        ])
        #expect(RegistrationKind.allCases.map { AppSheet.registration($0).id } == [
            "sheet.registrar.refeicao", "sheet.registrar.treino",
            "sheet.registrar.peso", "sheet.registrar.hidratacao",
        ])
    }
}
