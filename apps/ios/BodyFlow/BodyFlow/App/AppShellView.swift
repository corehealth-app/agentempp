import SwiftUI

@MainActor
struct AppShellView: View {
    @State private var selectedTab = AppTab.today
    @State private var keyboardVisible = false
    @State private var router = AppRouter()
    @State private var invalidationCenter: FeatureInvalidationCenter
    @State private var todayViewModel: TodayViewModel
    @State private var planViewModel: PlanViewModel
    @State private var progressViewModel: ProgressViewModel
    @State private var historyViewModel: HistoryViewModel
    @State private var historyCoordinator: HistoryFeatureCoordinator
    @State private var todayRecommendationsViewModel: TodayRecommendationsViewModel
    @State private var todayMascotViewModel: MascotExperienceViewModel
    @State private var flowChatModel: FlowChatModel
    @State private var contentCoverEnvironment: ContentCoverEnvironment
    @State private var localReminders: LocalReminderModel?
    @State private var planDraftsModel: PlanDraftsModel?
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    let userID: String
    let dependencies: AppDependencies
    let sessionOwner: Prompt14SessionOwner
    let accountEmail: String?
    /// The root's sign-out for a real account; nil keeps the demonstration
    /// without an account action.
    let signOut: (@MainActor () async -> Void)?

    init(
        userID: String,
        dependencies: AppDependencies,
        sessionOwner: Prompt14SessionOwner,
        accountEmail: String? = nil,
        signOut: (@MainActor () async -> Void)? = nil
    ) {
        self.userID = userID
        self.dependencies = dependencies
        self.sessionOwner = sessionOwner
        self.accountEmail = accountEmail
        self.signOut = signOut
        let invalidationCenter = FeatureInvalidationCenter()
        _invalidationCenter = State(initialValue: invalidationCenter)
        _todayViewModel = State(
            initialValue: TodayViewModel(provider: dependencies.today)
        )
        _planViewModel = State(
            initialValue: PlanViewModel(provider: dependencies.plan)
        )
        _progressViewModel = State(
            initialValue: ProgressViewModel(provider: sessionOwner.progress)
        )
        let historyModel = HistoryViewModel(provider: dependencies.history)
        _historyViewModel = State(initialValue: historyModel)
        _historyCoordinator = State(
            initialValue: HistoryFeatureCoordinator(model: historyModel)
        )
        _todayRecommendationsViewModel = State(
            initialValue: TodayRecommendationsViewModel(
                listing: sessionOwner.contentListing,
                stateRecorder: sessionOwner.contentState,
                keyProvider: dependencies.idempotencyKeyProvider,
                timeProvider: dependencies.timeProvider,
                invalidationCenter: invalidationCenter,
                coverLoader: sessionOwner.coverLoader
            )
        )
        _todayMascotViewModel = State(
            initialValue: MascotExperienceViewModel(
                provider: sessionOwner.coachExperience
            )
        )
        _flowChatModel = State(
            initialValue: FlowChatModel(
                userID: userID,
                provider: dependencies.flowChat,
                keyProvider: dependencies.idempotencyKeyProvider
            )
        )
        _contentCoverEnvironment = State(
            initialValue: ContentCoverEnvironment.make(
                loader: sessionOwner.coverLoader,
                session: ContentCoverSessionToken(),
                invalidationCenter: invalidationCenter
            )
        )
        _planDraftsModel = State(initialValue: dependencies.planDrafts.map {
            PlanDraftsModel(provider: $0.drafts)
        })
        let timeZoneStore = dependencies.patientTimeZoneStore
        _localReminders = State(initialValue: dependencies.localReminders.map { capability in
            LocalReminderModel(
                userID: userID,
                sources: capability.sources,
                scheduler: capability.scheduler,
                optIn: capability.optIn,
                timeZone: { timeZoneStore.current },
                timeZoneSettled: { timeZoneStore.isSettled },
                // Reminders follow the real clock, never a fixture clock.
                now: { Date() },
                language: BodyFlowPresentationLanguage.resolve(.current)
            )
        })
    }

    var body: some View {
        TabView(selection: $selectedTab) {
                ForEach(AppTab.displayOrder) { tab in
                    Tab(
                        tab.title(for: presentationLanguage),
                        systemImage: tab.systemImage,
                        value: tab
                    ) {
                        navigationStack(for: tab)
                    }
                    .accessibilityIdentifier(tab.accessibilityIdentifier)
                }
        }
        .toolbar(.hidden, for: .tabBar)
        .tint(BodyFlowColor.accent)
#if DEBUG
        .task {
            guard ProcessInfo.processInfo.arguments.contains("--ui-testing-prompt13-stale-offline") else {
                return
            }
            await historyViewModel.load(revision: 0)
            await historyViewModel.retry()
        }
#endif
        .background {
            BodyFlowKeyboardObserver { keyboardVisible = $0 }
            .frame(width: 0, height: 0)
        }
        .environment(router)
        .environment(
            \.contentCoverEnvironment,
            contentCoverEnvironment
        )
        .sheet(item: presentedSheetBinding) { sheet in
            RegistrationSheet(
                sheet: sheet,
                dependencies: dependencies,
                invalidationCenter: invalidationCenter
            )
                .environment(router)
        }
        .task {
            routePendingReminderTap()
            guard let localReminders else { return }
            // Session start: after `/me` settles the documented time zone.
            await sessionOwner.awaitPatientTimeZoneResolution()
            await localReminders.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            routePendingReminderTap()
            guard let localReminders else { return }
            Task {
                // Settles a zone `/me` could not answer offline and follows a
                // change of the documented zone, then re-syncs.
                await sessionOwner.refreshPatientTimeZone()
                await localReminders.refresh()
            }
        }
        .onChange(of: invalidationCenter.revision(for: .routineList(kind: .supplement))) {
            Task { await localReminders?.refresh() }
        }
        .onChange(of: invalidationCenter.revision(for: .routineList(kind: .medication))) {
            Task { await localReminders?.refresh() }
        }
        .onChange(of: LocalReminderRouteInbox.shared.pending) {
            routePendingReminderTap()
        }
        .onDisappear {
            flowChatModel.invalidate()
            planDraftsModel?.invalidate()
            sessionOwner.invalidateSynchronously()
            localReminders?.endSession()
        }
    }

    /// Opens a tapped reminder only for this session's owner; a tap of
    /// another account is discarded unopened, and nothing is recorded.
    private func routePendingReminderTap() {
        guard !sessionOwner.isInvalidated,
              let tap = LocalReminderRouteInbox.shared.take(
                  ownerKey: LocalReminderPlanner.ownerKey(for: userID)
              ) else { return }
        selectedTab = .today
        router.popToRoot(in: .today)
        if case let .routineItem(kind, itemID) = tap.destination {
            router.navigate(
                to: .routine(RoutineRoute(kind: kind, itemID: itemID, destination: .detail)),
                in: .today
            )
        }
    }

    private var presentedSheetBinding: Binding<AppSheet?> {
        Binding(
            get: { router.presentedSheet },
            set: { router.presentedSheet = $0 }
        )
    }

    @ViewBuilder
    private func navigationStack(for tab: AppTab) -> some View {
        NavigationStack(path: router.binding(for: tab)) {
            rootView(for: tab)
                .safeAreaInset(edge: .bottom, spacing: 0) { navigationBar }
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                        .safeAreaInset(edge: .bottom, spacing: 0) { navigationBar }
                }
        }
        .toolbar(.hidden, for: .tabBar)
        .accessibilityHidden(selectedTab != tab)
    }

    /// Reserve space on each actual screen, inside the native navigation
    /// controller boundary, so its own bottom composer receives the inset.
    @ViewBuilder private var navigationBar: some View {
        if !keyboardVisible {
            PerformeTabBar(selection: $selectedTab, language: presentationLanguage)
        }
    }

    private var presentationLanguage: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    @ViewBuilder
    private func rootView(for tab: AppTab) -> some View {
        switch tab {
        case .today:
            TodayRootView(
                model: todayViewModel,
                recommendations: todayRecommendationsViewModel,
                mascot: todayMascotViewModel,
                invalidationCenter: invalidationCenter
            )
        case .register:
            RegisterRootView(
                state: dependencies.isRegistrationAvailable ? .loaded : .unavailable,
                presentsLocalDemonstration: !dependencies.presentsRealAccountIdentity
            )
        case .plan:
            PlanRootView(
                model: planViewModel,
                selectedTab: $selectedTab,
                drafts: planDraftsModel,
                supportsImport: dependencies.planDrafts?.supportsImport == true
            )
        case .progress:
            ProgressRootView(
                model: progressViewModel,
                selectedTab: $selectedTab
            )
        case .profile:
            ProfileRootView(
                userID: userID,
                accountEmail: accountEmail,
                coachExperienceProvider: sessionOwner.coachExperience,
                invalidationCenter: invalidationCenter,
                localReminders: localReminders,
                signOut: signOut
            )
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .detail:
            FeatureDetailView(route: route)
        case .mainHistory:
            MainHistoryView(
                model: historyViewModel,
                invalidationCenter: invalidationCenter
            )
        case .historyMealLog:
            HistoryMealLogDetailView(
                row: historyCoordinator.mealLogRow(for: route)
            )
        case .historyWorkout:
            HistoryWorkoutDetailView(
                row: historyCoordinator.workoutLogRow(for: route)
            )
        case let .routine(routineRoute):
            switch routineRoute.destination {
            case .list:
                RoutineListView(
                    kind: routineRoute.kind,
                    dependencies: dependencies,
                    invalidationCenter: invalidationCenter
                )
            case .detail:
                RoutineDetailRouteView(
                    route: routineRoute,
                    dependencies: dependencies,
                    invalidationCenter: invalidationCenter
                )
            case .history:
                RoutineHistoryView(
                    kind: routineRoute.kind,
                    itemID: routineRoute.itemID ?? "",
                    dependencies: dependencies,
                    invalidationCenter: invalidationCenter
                )
            }
        case .plan:
            PlanDetailView(provider: dependencies.plan)
        case .progress:
            Block7700DetailView(today: dependencies.today)
        case let .content(contentRoute):
            switch contentRoute {
            case let .library(initialSelection):
                LibraryRootView(
                    initialSelection: initialSelection,
                    sessionOwner: sessionOwner,
                    dependencies: dependencies,
                    invalidationCenter: invalidationCenter
                )
            case let .detail(publicationID, origin):
                PublishedContentDetailView(
                    publicationID: publicationID,
                    origin: origin,
                    detailProvider: sessionOwner.contentDetail,
                    stateRecorder: sessionOwner.contentState,
                    keyProvider: dependencies.idempotencyKeyProvider,
                    timeProvider: dependencies.timeProvider,
                    invalidationCenter: invalidationCenter,
                    coverLoader: sessionOwner.coverLoader
                )
            }
        case .mascot(.detail):
            MascotDetailView(
                provider: sessionOwner.coachExperience,
                invalidationCenter: invalidationCenter
            )
        case .flowChat:
            FlowChatView(model: flowChatModel)
        case let .planDraft(route):
            if let capability = dependencies.planDrafts {
                PlanDraftReviewView(model: PlanDraftReviewModel(
                    draftID: route.draftID,
                    provider: capability.drafts,
                    timeProvider: dependencies.timeProvider,
                    keyProvider: dependencies.idempotencyKeyProvider,
                    planChanged: {
                        flowChatModel.consumeTurnDraft()
                        Task {
                            await planViewModel.retry()
                            await planDraftsModel?.load()
                        }
                    }
                ))
            } else {
                ScreenStateView(state: .unavailable, retryAction: {})
            }
        case .planImport:
            if let capability = dependencies.planDrafts {
                PlanImportView(
                    model: PlanImportModel(
                        capability: capability,
                        timeProvider: dependencies.timeProvider,
                        keyProvider: dependencies.idempotencyKeyProvider
                    ),
                    stager: MealMediaStager(staging: capability.staging),
                    openDraft: { draftID in
                        // The import screen gives its place to the review.
                        router.popToRoot(in: .plan)
                        router.navigate(
                            to: .planDraft(PlanDraftRoute(draftID: draftID, origin: .plan)),
                            in: .plan
                        )
                    }
                )
            } else {
                ScreenStateView(state: .unavailable, retryAction: {})
            }
        case .localReminders:
            if let localReminders {
                LocalRemindersView(model: localReminders)
            } else {
                ScreenStateView(state: .unavailable, retryAction: {})
            }
        }
    }
}

#Preview("App Shell · Loaded") {
    let dependencies = AppDependencies.scaffold()
    AppShellView(
        userID: "fixture-user",
        dependencies: dependencies,
        sessionOwner: Prompt14SessionOwner(
            userID: "fixture-user",
            dependencies: dependencies
        )
    )
        .installAppDependencies(dependencies)
}
