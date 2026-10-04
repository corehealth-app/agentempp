import Foundation
import SwiftUI

struct TodayPresentation: Equatable, Sendable {
    let header: TodayHeaderDescriptor
    let attention: TodayAttentionDescriptor
    let energy: TodayEnergyDescriptor
    let protein: TodayProteinDescriptor
    let macros: TodayMacrosDescriptor
    let meals: [TodayMealDescriptor]
    let mealSlots: TodayMealSlotsDescriptor
    let workouts: [TodayWorkoutDescriptor]
    let hydration: TodayHydrationDescriptor
    let routineCollections: [TodayRoutineCollectionDescriptor]
    let block: TodayBlockDescriptor
    let completionStatus: String
    let sectionOrder: [TodaySectionKind]

    init(
        snapshot: TodaySnapshot,
        language: SupportedAppLanguage = .portugueseBrazil
    ) {
        header = TodayHeaderDescriptor(
            localDate: snapshot.localDate,
            protocolName: snapshot.protocolName.map { code in
                BodyFlowObjective(rawValue: code)?.onboardingLabel(for: language) ?? code
            },
            updatedAt: snapshot.updatedAt
        )
        attention = TodayAttentionDescriptor(
            pending: snapshot.pendingActions.registrations.map { registration in
                TodayPendingDescriptor(
                    id: registration.id,
                    kind: registration.kind,
                    mealType: registration.mealType
                )
            },
            routineActions: Self.routineAttention(
                supplements: snapshot.supplements,
                medications: snapshot.medications
            )
        )
        energy = TodayEnergyDescriptor(
            targetKcal: snapshot.targets.caloriesKcal,
            consumedKcal: snapshot.consumed.caloriesKcal,
            remainingFoodKcal: snapshot.remainingFoodKcal,
            foodExcessKcal: snapshot.foodExcessKcal,
            exerciseKcal: snapshot.exerciseKcal,
            dailyBalanceKcal: snapshot.dailyBalanceKcal,
            dailyBalanceStatus: snapshot.dailyBalanceStatus
        )
        protein = TodayProteinDescriptor(
            consumedG: snapshot.proteinStatus.consumedG,
            targetG: snapshot.proteinStatus.targetG,
            remainingG: snapshot.proteinStatus.remainingG,
            percentage: snapshot.proteinStatus.percentage,
            status: snapshot.proteinStatus.status
        )
        macros = TodayMacrosDescriptor(
            carbsG: snapshot.consumed.carbsG,
            fatG: snapshot.consumed.fatG
        )
        meals = snapshot.meals.map { meal in
            TodayMealDescriptor(
                id: meal.id,
                mealType: meal.mealType,
                foodName: meal.foodName,
                quantityG: meal.quantityG,
                kcal: meal.kcal,
                proteinG: meal.proteinG,
                carbsG: meal.carbsG,
                fatG: meal.fatG,
                consumedAt: meal.consumedAt,
                provenance: TodayNutritionProvenance.label(
                    for: meal.nutritionSource,
                    language: language
                )
            )
        }
        mealSlots = TodayMealSlotsDescriptor(
            meals: meals,
            expected: snapshot.pendingActions.mealGaps.expected,
            skipped: snapshot.pendingActions.mealGaps.skipped
        )
        workouts = snapshot.workouts.map { workout in
            TodayWorkoutDescriptor(
                id: workout.id,
                workoutType: workout.workoutType,
                durationMin: workout.durationMin,
                estimatedKcal: workout.estimatedKcal,
                intensity: workout.intensity,
                performedAt: workout.performedAt
            )
        }
        hydration = TodayHydrationDescriptor(
            consumedML: snapshot.hydration.consumedML,
            targetML: snapshot.hydration.targetML,
            remainingML: snapshot.hydration.remainingML,
            percentage: snapshot.hydration.percentage,
            status: snapshot.hydration.status
        )
        routineCollections = [
            Self.routineCollection(
                snapshot.supplements,
                kind: .supplement
            ),
            Self.routineCollection(
                snapshot.medications,
                kind: .medication
            ),
        ]
        if let block = snapshot.block7700 {
            self.block = TodayBlockDescriptor(
                enabled: block.enabled,
                availability: block.availability,
                targetKcal: block.targetKcal,
                currentKcal: block.currentKcal,
                percentage: block.percentage,
                completedBlocks: block.completedBlocks,
                totalCreditedKcal: block.totalCreditedKcal,
                source: block.source
            )
        } else {
            self.block = TodayBlockDescriptor(
                enabled: nil,
                availability: nil,
                targetKcal: nil,
                currentKcal: nil,
                percentage: nil,
                completedBlocks: nil,
                totalCreditedKcal: nil,
                source: nil
            )
        }
        completionStatus = snapshot.completionStatus.status
        sectionOrder = [
            .energy,
            .protein,
            .hydration,
            .attention,
            .pending,
            .meals,
            .workouts,
            .routines,
            .block,
            .history,
        ]
    }

    var completionMessage: String? {
        completionMessage(for: .portugueseBrazil)
    }

    func completionMessage(for language: SupportedAppLanguage) -> String? {
        guard completionStatus == "insufficient_data" else {
            return nil
        }
        return TodayCopy.string(
            "today.completion.insufficient-data",
            language: language
        )
    }

    private static func routineAttention(
        supplements: TodayRoutineSection,
        medications: TodayRoutineSection
    ) -> [TodayRoutineAttentionDescriptor] {
        attentionRows(in: supplements, kind: .supplement)
            + attentionRows(in: medications, kind: .medication)
    }

    private static func attentionRows(
        in section: TodayRoutineSection,
        kind: TodayRoutineAttentionID.Kind
    ) -> [TodayRoutineAttentionDescriptor] {
        section.items.flatMap { item in
            item.occurrences.compactMap { occurrence in
                guard occurrence.status == "pending"
                        || occurrence.status == "snoozed" else {
                    return nil
                }
                return TodayRoutineAttentionDescriptor(
                    id: TodayRoutineAttentionID(
                        kind: kind,
                        itemID: item.id,
                        reminderRuleID: occurrence.reminderRuleID,
                        scheduledFor: occurrence.scheduledFor
                    ),
                    title: item.name,
                    status: occurrence.status
                )
            }
        }
    }

    private static func routineCollection(
        _ section: TodayRoutineSection,
        kind: TodayRoutineCollectionDescriptor.Kind
    ) -> TodayRoutineCollectionDescriptor {
        let items = section.items.map { item in
            TodayRoutineDescriptor(
                id: item.id,
                kind: kind == .supplement ? .supplement : .medication,
                name: item.name,
                doseText: item.doseText,
                occurrenceStatuses: item.occurrences.map(\.status)
            )
        }
        let state: TodayRoutineCollectionDescriptor.State =
            // "not_configured" means the patient has no items yet: an empty
            // collection, not a failure. Any other unknown value stays unavailable.
            if section.availability == "not_configured" && items.isEmpty {
                .empty
            } else if section.availability != "available" {
                .unavailable
            } else if items.isEmpty {
                .empty
            } else {
                .populated
            }
        return TodayRoutineCollectionDescriptor(
            kind: kind,
            state: state,
            items: items
        )
    }
}

@MainActor
struct TodayRootView: View {
    let model: TodayViewModel
    let recommendations: TodayRecommendationsViewModel?
    let mascot: MascotExperienceViewModel?
    let week: TodayWeekViewModel?
    let invalidationCenter: FeatureInvalidationCenter
    /// Absent in previews and unit renders; open meal slots are then inert.
    @Environment(AppRouter.self) private var router: AppRouter?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.guidedTourFocus) private var guidedTourFocus
    /// Absent in previews and unit renders; the control is then not shown.
    @Environment(BodyFlowAppearanceStore.self) private var appearance: BodyFlowAppearanceStore?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @State private var refreshCoordinator = TodayRefreshCoordinator()
    /// The hero figures count up once per load of the day; a later relayout
    /// (a size change swaps the hero's ViewThatFits branch) never recounts.
    @State private var countsUp = true
    nonisolated static let countUpWindow: Duration = .milliseconds(1_500)

    init(
        model: TodayViewModel,
        recommendations: TodayRecommendationsViewModel? = nil,
        mascot: MascotExperienceViewModel? = nil,
        week: TodayWeekViewModel? = nil,
        invalidationCenter: FeatureInvalidationCenter
    ) {
        self.model = model
        self.recommendations = recommendations
        self.mascot = mascot
        self.week = week
        self.invalidationCenter = invalidationCenter
    }

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            stateContent
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // When Today has no snapshot (loading, error, offline,
            // unavailable) the shortcuts stay pinned here so Flow and the
            // Library remain reachable independently of Today's state. Once
            // the snapshot is shown they move into the scrolling content,
            // after the day summary, instead of occupying a fixed band.
            if model.state.presentation.value == nil {
                todayShortcuts
                    .padding(.horizontal, BodyFlowSpacing.md)
                    .padding(.vertical, BodyFlowSpacing.xs)
                    .background(BodyFlowColor.background)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AppTab.today.rootAccessibilityIdentifier)
#if DEBUG
        .accessibilityValue(colorScheme == .dark ? "dark" : "light")
#endif
        .navigationTitle(copy("tab.today"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: invalidationCenter.revision(for: .today)) {
            let revision = invalidationCenter.revision(for: .today)
            async let weekLoad: Void = loadWeek()
            await model.load(revision: revision)
            await weekLoad
        }
        .task(id: invalidationCenter.revision(for: .contentCatalog)) {
            guard let recommendations else { return }
            let revision = invalidationCenter.revision(for: .contentCatalog)
            await recommendations.load(catalogRevision: revision)
        }
        .task(id: invalidationCenter.revision(for: .coachExperience)) {
            guard let mascot else { return }
            await mascot.load(
                revision: invalidationCenter.revision(for: .coachExperience)
            )
        }
        .toolbar {
            let navigation = TodayRootNavigationPresentation(state: model.state)
            if let appearance {
                ToolbarItem(placement: .topBarLeading) {
                    BodyFlowAppearanceMenu(store: appearance)
                }
            }
            if model.state.presentation.value != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: retry) {
                        Group {
                            if refreshCoordinator.isRunning || model.isRefreshing {
                                BodyFlowDelayedProgress()
                            } else {
                                Label(verbatim: copy("today.refresh"), symbol: .refresh)
                            }
                        }
                        .frame(
                            width: BodyFlowSpacing.minimumTapTarget + 1,
                            height: BodyFlowSpacing.minimumTapTarget + 1
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(refreshCoordinator.isRunning || model.isRefreshing)
                    .accessibilityLabel(copy("today.refresh"))
                    .accessibilityIdentifier("today.refresh")
                }
            } else if navigation.toolbarRoutes.contains(.mainHistory) {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: AppRoute.mainHistory) {
                        Label(verbatim: copy("today.history.title"), symbol: .history)
                    }
                    .accessibilityIdentifier("today.history")
                }
            }
        }
    }

    /// Flow (primary, brand fill) and Library (secondary, surface) entries.
    /// Side by side while both labels fit on one line; otherwise (large and
    /// accessibility text sizes) each entry takes the full row width so its
    /// label reflows across the width instead of wrapping word by word
    /// inside a narrow column.
    private var todayShortcuts: some View {
        let navigation = TodayRootNavigationPresentation(state: model.state)
        let libraryRoute = navigation.toolbarRoutes[0]
        return ViewThatFits(in: .horizontal) {
            // Flow takes the remaining width; Library keeps its natural
            // width, so neither label wraps when the row fits.
            HStack(spacing: BodyFlowSpacing.sm) {
                flowNavigationLink(expands: true)
                libraryNavigationLink(route: libraryRoute, expands: false)
            }
            VStack(spacing: BodyFlowSpacing.sm) {
                flowNavigationLink(expands: true)
                libraryNavigationLink(route: libraryRoute, expands: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func flowNavigationLink(expands: Bool) -> some View {
        NavigationLink(value: AppRoute.flowChat) {
            shortcutLabel(
                copy("flow.open"),
                symbol: .flow,
                expands: expands,
                isPrimary: true
            )
        }
        .buttonStyle(.bodyFlowRowAction)
        .accessibilityLabel(copy("flow.open"))
        .accessibilityIdentifier("today.flow-chat")
        .guidedTourTarget(.flow)
    }

    private func libraryNavigationLink(route: AppRoute, expands: Bool) -> some View {
        NavigationLink(value: route) {
            shortcutLabel(
                copy("today.library"),
                symbol: .library,
                expands: expands,
                isPrimary: false
            )
        }
        .buttonStyle(.bodyFlowRow)
        .accessibilityLabel(copy("today.library"))
        .accessibilityIdentifier("today.library")
        .guidedTourTarget(.library)
    }

    private func shortcutLabel(
        _ title: String,
        symbol: BodyFlowSymbol,
        expands: Bool,
        isPrimary: Bool
    ) -> some View {
        Label(verbatim: title, symbol: symbol)
            .font(BodyFlowTypography.headline)
            .foregroundStyle(BodyFlowColor.color(isPrimary ? .onPrimary : .brandPrimary))
            .fixedSize(horizontal: false, vertical: true)
            .frame(
                maxWidth: expands ? .infinity : nil,
                minHeight: BodyFlowSpacing.minimumTapTarget,
                alignment: .leading
            )
            .padding(.horizontal, BodyFlowSpacing.sm)
            .padding(.vertical, BodyFlowSpacing.xs)
            .background(
                BodyFlowColor.color(isPrimary ? .brandPrimary : .backgroundSecondary),
                in: RoundedRectangle(cornerRadius: BodyFlowRadius.field, style: .continuous)
            )
            .accessibilityRepresentation { EmptyView() }
    }

    @ViewBuilder
    private var stateContent: some View {
        let presentation = model.state.presentation
        let transition = BodyFlowMotion.stateTransition(reduceMotion: reduceMotion)
        // Full-screen state ↔ loaded day cross-fades (220 ms); immediate
        // under Reduce Motion.
        Group {
            if presentation.fullScreenState == .loading {
                BodyFlowFeatureSkeleton(kind: .today).transition(transition)
            } else if let fullScreenState = presentation.fullScreenState {
                ScreenStateView(
                    state: fullScreenState,
                    retryAction: retry
                )
                .transition(transition)
            } else if let snapshot = presentation.value {
                loadedContent(
                    TodayPresentation(snapshot: snapshot, language: language),
                    showsStaleBanner: presentation.showsStaleBanner
                )
                .transition(transition)
            }
        }
        .animation(
            BodyFlowMotion.animation(.content, reduceMotion: reduceMotion),
            value: presentation.fullScreenState == nil
        )
    }

    private func loadedContent(
        _ presentation: TodayPresentation,
        showsStaleBanner: Bool
    ) -> some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                if showsStaleBanner {
                    FeatureStaleRecovery(retry: retry)
                }

                // The food balance leads; the technical balance stays in
                // the summary disclosure with its official meaning. Blocks
                // settle in a short cascade once the day has loaded.
                standardSummary(presentation)
                    .bodyFlowArrival(index: 0)

                // Next actions: Flow/Library entries, then pending items.
                todayShortcuts
                    .bodyFlowArrival(index: 1)
                    .id(Self.shortcutsScrollID)
                TodayAttentionSection(descriptor: presentation.attention)
                    .bodyFlowArrival(index: 2)

                // The day by meal, right after what needs attention.
                TodayMealSlotsSection(
                    descriptor: presentation.mealSlots,
                    register: router.map { router in { router.presentedSheet = .registration(.meal) } }
                )
                .bodyFlowArrival(index: 3)

                TodayTrailSection(descriptor: TodayTrailDescriptor(
                    recordCount: presentation.meals.count + presentation.workouts.count,
                    remainingFood: presentation.energy.remainingFoodKcal.map {
                        TodayValueFormatter.kcal($0, language: language)
                    },
                    blockPercentage: presentation.block.percentage,
                    language: language
                ))
                .bodyFlowArrival(index: 3)

                if let recommendations {
                    TodayRecommendationsSection(
                        model: recommendations,
                        catalogRevision: invalidationCenter.revision(for: .contentCatalog)
                    )
                    .bodyFlowArrival(index: 4)
                }
                TodayRoutineSectionView(
                    collections: presentation.routineCollections
                )
                .bodyFlowArrival(index: 5)
                TodayRecordsSection(
                    workouts: presentation.workouts
                )
                .bodyFlowArrival(index: 6)

                NavigationLink(value: AppRoute.mainHistory) {
                    BodyFlowCard {
                        FeatureActionLabel(
                            title: copy("today.history.title"),
                            detail: copy("today.history.detail"),
                            systemImage: BodyFlowSymbol.history.systemName
                        )
                    }
                }
                .buttonStyle(.bodyFlowRow)
                .accessibilityIdentifier("today.history")
                .bodyFlowZoomSource(.mainHistory)

                TodayBlockCard(descriptor: presentation.block)
                if let mascot {
                    MascotCardView(model: mascot)
                }

                NavigationLink(
                    value: AppRoute.detail(tab: .today, id: "daily-summary")
                ) {
                    BodyFlowCard {
                        FeatureActionLabel(
                            title: copy("today.summary.title"),
                            detail: copy("today.summary.detail"),
                            systemImage: BodyFlowSymbol.summary.systemName
                        )
                    }
                }
                .buttonStyle(.bodyFlowRow)
                .accessibilityIdentifier("today.next-action")
                .bodyFlowZoomSource(.detail(tab: .today, id: "daily-summary"))
            }
            .padding(BodyFlowSpacing.md)
            // The day is exactly as wide as the screen: whatever a value or
            // a text size does to one block, the page can only scroll
            // vertically (Eduardo, 03/10: a diagonal drag moved it sideways).
            .containerRelativeFrame(.horizontal)
        }
        .refreshable {
            await refreshAll()
        }
        .onChange(of: guidedTourFocus, initial: true) {
            // The tour's spotlight lands on a control that may be below the
            // fold; bring it to the middle of the viewport first.
            guard let guidedTourFocus, guidedTourFocus == .flow || guidedTourFocus == .library else { return }
            withAnimation(BodyFlowMotion.animation(.content, reduceMotion: reduceMotion)) {
                proxy.scrollTo(Self.shortcutsScrollID, anchor: .center)
            }
        }
        }
    }

    nonisolated static let shortcutsScrollID = "today.shortcuts"

    private func loadWeek() async {
        await week?.load()
    }

    @ViewBuilder
    private func standardSummary(_ presentation: TodayPresentation) -> some View {
        TodayHeaderSection(descriptor: presentation.header)
        TodayWeekStrip(descriptor: TodayWeekDescriptor(
            localDate: presentation.header.localDate,
            trends: week?.trends,
            language: language
        ))
        TodaySummaryPanel(
            energy: presentation.energy,
            protein: presentation.protein,
            macros: presentation.macros,
            hydration: presentation.hydration,
            completionMessage: presentation.completionMessage(for: language),
            countsUp: countsUp
        )
        .task {
            try? await Task.sleep(for: Self.countUpWindow)
            guard !Task.isCancelled else { return }
            countsUp = false
        }
    }

    private func retry() {
        Task {
            await refreshAll()
        }
    }

    private func refreshAll() async {
        await refreshCoordinator.run(isExternallyRefreshing: model.isRefreshing) {
            async let day: Void = model.retry()
            async let content: Void = refreshRecommendations()
            async let coach: Void = refreshMascot()
            _ = await (day, content, coach)
        }
    }

    private func refreshRecommendations() async {
        if let recommendations { await recommendations.retry() }
    }

    private func refreshMascot() async {
        if let mascot { await mascot.retry() }
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        TodayCopy.string(key, language: language)
    }
}

struct TodayRootNavigationPresentation: Equatable, Sendable {
    let toolbarRoutes: [AppRoute]

    init(state: FeatureReadState<TodaySnapshot>) {
        toolbarRoutes = [.content(.library(initialSelection: .all))]
            + (state.presentation.value == nil ? [.mainHistory] : [])
    }
}
