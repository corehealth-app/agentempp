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
}
