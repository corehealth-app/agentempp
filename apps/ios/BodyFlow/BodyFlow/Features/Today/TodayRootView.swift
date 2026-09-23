import Foundation
import SwiftUI

struct TodayPresentation: Equatable, Sendable {
    let header: TodayHeaderDescriptor
    let attention: TodayAttentionDescriptor
    let energy: TodayEnergyDescriptor
    let protein: TodayProteinDescriptor
    let meals: [TodayMealDescriptor]
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
            protocolName: snapshot.protocolName,
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
            if section.availability != "available" {
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
    let invalidationCenter: FeatureInvalidationCenter
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        model: TodayViewModel,
        recommendations: TodayRecommendationsViewModel? = nil,
        mascot: MascotExperienceViewModel? = nil,
        invalidationCenter: FeatureInvalidationCenter
    ) {
        self.model = model
        self.recommendations = recommendations
        self.mascot = mascot
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
            await model.load(revision: revision)
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
            if model.state.presentation.value != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: retry) {
                        Label(copy("today.refresh"), systemImage: "arrow.clockwise")
                            .frame(
                                width: BodyFlowSpacing.minimumTapTarget + 1,
                                height: BodyFlowSpacing.minimumTapTarget + 1
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.refresh")
                }
            } else if navigation.toolbarRoutes.contains(.mainHistory) {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: AppRoute.mainHistory) {
                        Label(copy("today.history.title"), systemImage: "clock.arrow.circlepath")
                    }
                    .accessibilityIdentifier("today.history")
                }
            }
        }
    }

    /// Flow and Library entries. Side by side while both labels fit on one
    /// line; otherwise (large and accessibility text sizes) each entry takes
    /// the full row width so its label reflows across the width instead of
    /// wrapping word by word inside a narrow column.
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
                systemImage: "bubble.left.and.text.bubble.right",
                expands: expands
            )
        }
        .accessibilityLabel(copy("flow.open"))
        .accessibilityIdentifier("today.flow-chat")
    }

    private func libraryNavigationLink(route: AppRoute, expands: Bool) -> some View {
        NavigationLink(value: route) {
            shortcutLabel(
                copy("today.library"),
                systemImage: "books.vertical",
                expands: expands
            )
        }
        .accessibilityLabel(copy("today.library"))
        .accessibilityIdentifier("today.library")
    }

    private func shortcutLabel(
        _ title: String,
        systemImage: String,
        expands: Bool
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(BodyFlowTypography.headline)
            .foregroundStyle(BodyFlowColor.accent)
            .fixedSize(horizontal: false, vertical: true)
            .frame(
                maxWidth: expands ? .infinity : nil,
                minHeight: BodyFlowSpacing.minimumTapTarget,
                alignment: .leading
            )
            .padding(.horizontal, BodyFlowSpacing.sm)
            .padding(.vertical, BodyFlowSpacing.xs)
            .background(
                BodyFlowColor.surface,
                in: RoundedRectangle(cornerRadius: BodyFlowRadius.field, style: .continuous)
            )
            .accessibilityRepresentation { EmptyView() }
    }

    @ViewBuilder
    private var stateContent: some View {
        let presentation = model.state.presentation
        if let fullScreenState = presentation.fullScreenState {
            ScreenStateView(
                state: fullScreenState,
                retryAction: retry
            )
        } else if let snapshot = presentation.value {
            loadedContent(
                TodayPresentation(snapshot: snapshot, language: language),
                showsStaleBanner: presentation.showsStaleBanner
            )
        }
    }

    private func loadedContent(
        _ presentation: TodayPresentation,
        showsStaleBanner: Bool
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                if showsStaleBanner {
                    FeatureStaleRecovery(retry: retry)
                }

                // Day summary first: compact day context, Energy (both
                // official meanings), then Protein and Hydration paired.
                TodayHeaderSection(descriptor: presentation.header)
                TodayEnergySection(
                    descriptor: presentation.energy,
                    completionMessage: presentation.completionMessage(for: language)
                )
                nutritionSummaryPair(presentation)

                // Next actions: Flow/Library entries, then pending items.
                todayShortcuts
                TodayAttentionSection(descriptor: presentation.attention)

                if let recommendations {
                    TodayRecommendationsSection(
                        model: recommendations,
                        catalogRevision: invalidationCenter.revision(for: .contentCatalog)
                    )
                }
                TodayRoutineSectionView(
                    collections: presentation.routineCollections
                )
                TodayRecordsSection(
                    meals: presentation.meals,
                    workouts: presentation.workouts
                )

                NavigationLink(value: AppRoute.mainHistory) {
                    BodyFlowCard {
                        FeatureActionLabel(
                            title: copy("today.history.title"),
                            detail: copy("today.history.detail"),
                            systemImage: "clock.arrow.circlepath"
                        )
                    }
                }
                .buttonStyle(.bodyFlowRow)
                .accessibilityIdentifier("today.history")

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
                            systemImage: "doc.text.magnifyingglass"
                        )
                    }
                }
                .buttonStyle(.bodyFlowRow)
                .accessibilityIdentifier("today.next-action")
            }
            .padding(BodyFlowSpacing.md)
        }
        .refreshable {
            await model.retry()
            if let mascot {
                await mascot.retry()
            }
        }
    }

    /// Protein and Hydration as two equal-height tiles at regular text sizes;
    /// stacked at accessibility sizes so neither is squeezed into a column.
    @ViewBuilder
    private func nutritionSummaryPair(_ presentation: TodayPresentation) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                    TodayProteinSection(descriptor: presentation.protein)
                    TodayHydrationSection(descriptor: presentation.hydration)
                }
            } else {
                HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                    TodayProteinSection(descriptor: presentation.protein)
                    TodayHydrationSection(descriptor: presentation.hydration)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func retry() {
        Task {
            await model.retry()
        }
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
