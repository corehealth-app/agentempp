import Testing
@testable import BodyFlow

@MainActor
@Suite("App router")
struct AppRouterTests {
    @Test("each tab preserves an independent typed path")
    func independentPaths() {
        let router = AppRouter()
        let todayRoute = AppRoute.detail(tab: .today, id: "daily-summary")
        let planRoute = AppRoute.detail(tab: .plan, id: "weekly-plan")

        router.navigate(to: todayRoute, in: .today)
        router.navigate(to: planRoute, in: .plan)

        #expect(router.path(for: .today) == [todayRoute])
        #expect(router.path(for: .plan) == [planRoute])
        #expect(router.path(for: .register).isEmpty)

        router.popToRoot(in: .plan)
        #expect(router.path(for: .today) == [todayRoute])
        #expect(router.path(for: .plan).isEmpty)
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
