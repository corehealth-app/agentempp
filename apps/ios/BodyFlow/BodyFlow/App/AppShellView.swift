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
    @State private var todayWeekViewModel: TodayWeekViewModel
    @State private var flowChatModel: FlowChatModel
    @State private var contentCoverEnvironment: ContentCoverEnvironment
    @State private var localReminders: LocalReminderModel?
    @State private var planDraftsModel: PlanDraftsModel?
    @State private var currentObjectiveModel: CurrentObjectiveModel?
    @State private var tutorialPresentation: GuidedTutorialPresentation?
    @State private var tour: GuidedTourModel?
    @State private var tipsShownThisSession = 0
    /// Counts the user's own taps on the tab bar; programmatic changes
    /// (a tour step, a reminder route) never tick.
    @State private var tabTaps = 0
    /// Counts finished tours (not skipped ones) for the celebration burst.
    @State private var tourFinishes = 0
    /// One namespace for the card → detail zoom of every stack.
    @Namespace private var zoomNamespace
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
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
        #if DEBUG
        let launch = AppLaunchConfiguration.current()
        if launch.mode == .demo, launch.block7700Scenario != nil,
           ProcessInfo.processInfo.arguments.contains("--ui-testing-block-direct-detail") {
            let fixtureRouter = AppRouter()
            fixtureRouter.navigate(to: .progress(.block7700), in: .progress)
            _router = State(initialValue: fixtureRouter)
            _selectedTab = State(initialValue: .progress)
        }
        #endif
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
        _todayWeekViewModel = State(
            initialValue: TodayWeekViewModel(provider: sessionOwner.progress)
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
        _currentObjectiveModel = State(initialValue: dependencies.currentObjective.map {
            CurrentObjectiveModel(userID: userID, provider: $0)
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
        shell
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
        .background { tutorialSheetPresenter }
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
            let routedReminder = routePendingReminderTap()
            offerTutorialIfEligible(afterRoutingReminder: routedReminder)
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
        .onChange(of: tutorialFacts) {
            guard !sessionOwner.isInvalidated else { return }
            tour?.updateFacts(tutorialFacts, ownerKey: tutorialOwnerKey)
        }
        .onDisappear {
            flowChatModel.invalidate()
            planDraftsModel?.invalidate()
            currentObjectiveModel?.invalidate()
            sessionOwner.invalidateSynchronously()
            localReminders?.endSession()
        }
    }

    /// The five stacks, with the guided tour drawn over them. Split from
    /// `body` so the type checker handles each chain on its own.
    private var shell: some View {
        tabs
            // The guided tour draws over the real screen and its tab bar.
            .overlayPreferenceValue(GuidedTourAnchorKey.self) { anchors in
                tourOverlay(anchors: anchors)
            }
            .animation(BodyFlowMotion.animation(.content, reduceMotion: reduceMotion), value: tour == nil)
            .onChange(of: tour?.index) { followTourStep() }
            .onChange(of: selectedTab) {
                guard selectedTab == .register else { return }
                offerContextualTip(.mealCommand)
            }
            .onChange(of: router.path(for: .today).last) {
                guard router.path(for: .today).last == .flowChat else { return }
                offerContextualTip(.flowComposer)
            }
    }

    private var tabs: some View {
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
        // One tick per tap on the bar, from the shell (the bar is drawn once per stack).
        .sensoryFeedback(BodyFlowHaptics.Tap.selection, trigger: tabTaps)
        .environment(\.bodyFlowZoomNamespace, zoomNamespace)
        // Finishing the tour (not skipping it) earns a short burst.
        .bodyFlowCelebration({ $0 > 0 ? .progress : nil }, trigger: tourFinishes)
        // Today scrolls its spotlighted control into view for the tour.
        .environment(\.guidedTourFocus, tour?.current.target)
    }

    @ViewBuilder
    private func tourOverlay(anchors: [GuidedTourTarget: Anchor<CGRect>]) -> some View {
        if let tour {
            GeometryReader { proxy in
                GuidedTourOverlay(model: tour, anchors: anchors, proxy: proxy) { outcome in
                    endTour(tour, outcome: outcome)
                }
            }
            .ignoresSafeArea()
            // Fades in; leaves at once, so a tap right after the tour never
            // lands on a dim layer that is still fading.
            .transition(.asymmetric(
                insertion: BodyFlowMotion.stateTransition(reduceMotion: reduceMotion),
                removal: .identity
            ))
        }
    }

    /// Each step is shown on its own tab (a replay from Profile starts on
    /// Today); the stacks underneath are untouched.
    private func followTourStep() {
        guard let tour else { return }
        if selectedTab != tour.current.tab { selectedTab = tour.current.tab }
    }

    /// Its own presenter, so it never competes with the registration sheet;
    /// it is only offered while no sheet is shown.
    private var tutorialSheetPresenter: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .sheet(item: $tutorialPresentation) { presentation in
                GuidedTutorialView(
                    presentation: presentation,
                    steps: GuidedTutorialContent.steps(facts: tutorialFacts)
                ) { outcome in
                    recordTutorial(outcome, for: presentation)
                }
                .installAppDependencies(dependencies)
            }
    }

    /// Opens a tapped reminder only for this session's owner; a tap of
    /// another account is discarded unopened, and nothing is recorded.
    @discardableResult
    private func routePendingReminderTap() -> Bool {
        guard !sessionOwner.isInvalidated,
              let tap = LocalReminderRouteInbox.shared.take(
                  ownerKey: LocalReminderPlanner.ownerKey(for: userID)
              ) else { return false }
        // The reminder's screen wins over the tour, which only closes; it is
        // not the user's answer, so it is offered again next time.
        if let tutorialPresentation {
            recordTutorial(.interrupted, for: tutorialPresentation)
        }
        if let tour {
            endTour(tour, outcome: .interrupted)
        }
        selectedTab = .today
        router.popToRoot(in: .today)
        if case let .routineItem(kind, itemID) = tap.destination {
            router.navigate(
                to: .routine(RoutineRoute(kind: kind, itemID: itemID, destination: .detail)),
                in: .today
            )
        }
        return true
    }

    private var tutorialOwnerKey: String {
        LocalReminderPlanner.ownerKey(for: userID)
    }

    private var tutorialFacts: GuidedTutorialFacts {
        GuidedTutorialFacts(
            // The same condition the meal screen uses to offer photo/audio.
            mealMedia: dependencies.mealCapture.map { $0.media != nil && $0.uploader != nil } ?? false,
            planDrafts: dependencies.planDrafts != nil,
            planImport: dependencies.planDrafts?.supportsImport == true,
            reminders: localReminders != nil,
            // Profile shows "Sair da conta" only with both.
            realAccount: accountEmail != nil && signOut != nil,
            showsBlock7700: !sessionOwner.isInvalidated
                && (todayViewModel.state.presentation.value?.blockPresentationPolicy.showsBlock ?? false)
        )
    }

    /// The first eligible entry offers the tour once; it never covers a
    /// sheet or a reminder being opened, and never moves the user's tab.
    private func offerTutorialIfEligible(afterRoutingReminder routedReminder: Bool) {
        guard !sessionOwner.isInvalidated, tutorialPresentation == nil else { return }
        let capability = dependencies.guidedTutorial
        guard GuidedTutorialOffer.shouldOffer(
            status: capability.store.status(ownerKey: tutorialOwnerKey),
            offersOnFirstEntry: capability.offersOnFirstEntry,
            isPresentingSheet: router.presentedSheet != nil,
            hasPendingRoute: routedReminder
        ) else { return }
        if prefersTextTour {
            tutorialPresentation = GuidedTutorialPresentation(
                origin: .firstEntry,
                ownerKey: tutorialOwnerKey
            )
        } else {
            startTour(origin: .firstEntry)
        }
    }

    private func presentTutorialFromProfile() {
        guard !sessionOwner.isInvalidated,
              tutorialPresentation == nil, tour == nil,
              router.presentedSheet == nil else { return }
        if prefersTextTour {
            tutorialPresentation = GuidedTutorialPresentation(
                origin: .profile,
                ownerKey: tutorialOwnerKey
            )
        } else {
            startTour(origin: .profile)
        }
    }

    /// VoiceOver reads the text tour; everyone else gets the spotlight tour.
    private var prefersTextTour: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(GuidedTutorialCapability.textTourTestArgument) {
            return true
        }
        #endif
        return UIAccessibility.isVoiceOverRunning
    }

    /// The spotlight tour points at Today's real controls, so a replay asked
    /// for from Profile moves to Today's root and comes back at the end.
    private func startTour(origin: GuidedTourModel.Origin) {
        let model = GuidedTourModel(
            steps: GuidedTourContent.steps(facts: tutorialFacts),
            origin: origin,
            ownerKey: tutorialOwnerKey,
            returnTab: selectedTab,
            isSessionActive: { [weak owner = sessionOwner] in
                owner?.isInvalidated == false
            }
        )
        if origin == .profile {
            router.popToRoot(in: .today)
            selectedTab = .today
        }
        tour = model
    }

    /// One contextual tip per control, once per account, at most three per
    /// session, and never over a running tour or a sheet.
    private func offerContextualTip(_ target: GuidedTourTarget) {
        let capability = dependencies.guidedTutorial
        guard capability.offersOnFirstEntry, !prefersTextTour,
              tour == nil, tutorialPresentation == nil, router.presentedSheet == nil,
              tipsShownThisSession < GuidedTourContent.tipsPerSession,
              !capability.store.hasShownTip(target, ownerKey: tutorialOwnerKey),
              let step = GuidedTourContent.tip(target),
              !sessionOwner.isInvalidated else { return }
        let ownerKey = tutorialOwnerKey
        Task { @MainActor in
            // The screen settles first, so the spotlight finds its control.
            try? await Task.sleep(for: .milliseconds(600))
            guard tour == nil, router.presentedSheet == nil, !sessionOwner.isInvalidated else { return }
            switch target {
            case .mealCommand: guard selectedTab == .register else { return }
            case .flowComposer: guard router.path(for: .today).last == .flowChat else { return }
            default: return
            }
            tipsShownThisSession += 1
            capability.store.markTipShown(target, ownerKey: ownerKey)
            tour = GuidedTourModel(
                steps: [step], origin: .tip, ownerKey: ownerKey, returnTab: selectedTab,
                isSessionActive: { [weak owner = sessionOwner] in
                    owner?.isInvalidated == false
                }
            )
        }
    }

    /// Records the answer for the account that opened the tour; a tip
    /// records nothing beyond having been shown. A replay returns to the
    /// tab it started from.
    private func endTour(_ model: GuidedTourModel, outcome: GuidedTutorialOutcome) {
        guard !sessionOwner.isInvalidated, model.isSessionActive(), tour === model else { return }
        if model.origin != .tip {
            guard GuidedTutorialOffer.record(
                outcome, ownerKey: model.ownerKey,
                store: dependencies.guidedTutorial.store,
                sessionIsActive: model.isSessionActive()
            ) else { return }
        }
        tour = nil
        if outcome == .finished { tourFinishes += 1 }
        if model.origin == .profile, outcome != .interrupted {
            selectedTab = model.returnTab
        }
    }

    /// Writes the answer for the account that opened the tour and closes only
    /// that presentation; a late answer never reaches another one.
    private func recordTutorial(
        _ outcome: GuidedTutorialOutcome,
        for presentation: GuidedTutorialPresentation
    ) {
        guard !sessionOwner.isInvalidated, tutorialPresentation?.id == presentation.id else { return }
        guard GuidedTutorialOffer.record(
            outcome, ownerKey: presentation.ownerKey,
            store: dependencies.guidedTutorial.store,
            sessionIsActive: !sessionOwner.isInvalidated
        ) else { return }
        tutorialPresentation = nil
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
                .safeAreaInset(edge: .bottom, spacing: 0) { navigationBar(for: tab, atRoot: true) }
                .navigationDestination(for: AppRoute.self) { route in
                    zoomed(route) {
                        destination(for: route)
                            .safeAreaInset(edge: .bottom, spacing: 0) { navigationBar(for: tab, atRoot: false) }
                    }
                }
        }
        .toolbar(.hidden, for: .tabBar)
        // The arriving tab fades in and slides from the side it sits on in
        // the bar (300 ms spring; instant under Reduce Motion). Stacks, state
        // and the tab bar's native control are untouched.
        .opacity(selectedTab == tab ? 1 : 0)
        .offset(x: reduceMotion ? 0 : Self.tabSlideOffset(for: tab, selected: selectedTab))
        .animation(BodyFlowMotion.animation(.navigation, reduceMotion: reduceMotion), value: selectedTab)
        .accessibilityHidden(selectedTab != tab)
    }

    /// Routes whose card marks itself with `bodyFlowZoomSource`; only these
    /// grow from the card. Every other route keeps the standard push.
    nonisolated static let zoomRoutes: Set<AppRoute> = [
        .mainHistory,
        .detail(tab: .today, id: "daily-summary"),
        .progress(.block7700),
    ]

    @ViewBuilder
    private func zoomed<Content: View>(_ route: AppRoute, @ViewBuilder content: () -> Content) -> some View {
        if Self.zoomRoutes.contains(route) {
            content().navigationTransition(.zoom(sourceID: route, in: zoomNamespace))
        } else {
            content()
        }
    }

    nonisolated static let tabSlide: CGFloat = 16

    /// A hidden tab waits on the side it occupies in the bar relative to the
    /// selected one, so a change always slides in the direction of travel.
    nonisolated static func tabSlideOffset(for tab: AppTab, selected: AppTab) -> CGFloat {
        guard tab != selected,
              let position = AppTab.displayOrder.firstIndex(of: tab),
              let current = AppTab.displayOrder.firstIndex(of: selected) else { return 0 }
        return position < current ? -tabSlide : tabSlide
    }

    /// Reserve space on each actual screen, inside the native navigation
    /// controller boundary, so its own bottom composer receives the inset.
    @ViewBuilder private func navigationBar(for tab: AppTab, atRoot: Bool) -> some View {
        if !keyboardVisible {
            PerformeTabBar(
                selection: $selectedTab,
                language: presentationLanguage,
                attachesTourTargets: atRoot && selectedTab == tab && router.path(for: tab).isEmpty,
                onUserSelect: { tabTaps += 1 }
            )
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
                week: todayWeekViewModel,
                invalidationCenter: invalidationCenter,
                showsDemonstrationSummaryLink: TodayRootView.showsDemonstrationSummaryLink(
                    presentsRealAccountIdentity: dependencies.presentsRealAccountIdentity
                )
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
                showTutorial: { presentTutorialFromProfile() },
                showsCurrentObjective: currentObjectiveModel != nil,
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
        case .currentObjective:
            if let currentObjectiveModel {
                CurrentObjectiveView(model: currentObjectiveModel)
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
