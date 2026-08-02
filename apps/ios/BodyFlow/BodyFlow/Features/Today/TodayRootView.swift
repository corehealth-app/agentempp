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
    let completionMessage: String?
    let sectionOrder: [TodaySectionKind]

    init(snapshot: TodaySnapshot) {
        header = TodayHeaderDescriptor(
            localDate: snapshot.localDate,
            protocolName: snapshot.protocolName,
            updatedAt: snapshot.updatedAt
        )
        attention = TodayAttentionDescriptor(
            pending: snapshot.pendingActions.registrations.map { registration in
                TodayPendingDescriptor(
                    id: registration.id,
                    title: registration.kind == "meal"
                        ? "Proposta de refeição"
                        : "Proposta de treino",
                    detail: registration.mealType ?? "Confirmação pendente"
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
                    for: meal.nutritionSource
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
        completionMessage = snapshot.completionStatus.status == "insufficient_data"
            ? "Dados insuficientes para fechar o dia"
            : nil
        sectionOrder = [
            .attention,
            .pending,
            .energy,
            .protein,
            .meals,
            .workouts,
            .hydration,
            .routines,
            .block,
            .history,
        ]
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
    let invalidationCenter: FeatureInvalidationCenter
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            stateContent
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AppTab.today.rootAccessibilityIdentifier)
#if DEBUG
        .accessibilityValue(colorScheme == .dark ? "dark" : "light")
#endif
        .navigationTitle("Hoje")
        .task(id: invalidationCenter.revision(for: .today)) {
            let revision = invalidationCenter.revision(for: .today)
            await model.load(revision: revision)
        }
        .toolbar {
            if model.state.presentation.value != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: retry) {
                        Label("Atualizar", systemImage: "arrow.clockwise")
                            .frame(
                                width: BodyFlowSpacing.minimumTapTarget,
                                height: BodyFlowSpacing.minimumTapTarget
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.refresh")
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: AppRoute.mainHistory) {
                        Label("Histórico", systemImage: "clock.arrow.circlepath")
                    }
                    .accessibilityIdentifier("today.history")
                }
            }
        }
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
                TodayPresentation(snapshot: snapshot),
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
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                        StaleDataBanner()
                        Button(action: retry) {
                            Text("Tentar novamente")
                                .font(BodyFlowTypography.headline)
                                .frame(
                                    minHeight: BodyFlowSpacing.minimumTapTarget
                                )
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("state.retry")
                    }
                }

                TodayHeaderSection(descriptor: presentation.header)
                TodayAttentionSection(descriptor: presentation.attention)
                TodayEnergySection(
                    descriptor: presentation.energy,
                    completionMessage: presentation.completionMessage
                )
                TodayProteinSection(descriptor: presentation.protein)
                TodayRecordsSection(
                    meals: presentation.meals,
                    workouts: presentation.workouts
                )
                TodayHydrationSection(descriptor: presentation.hydration)
                TodayRoutineSectionView(
                    collections: presentation.routineCollections
                )
                TodayBlockCard(descriptor: presentation.block)

                NavigationLink(value: AppRoute.mainHistory) {
                    BodyFlowCard {
                        FeatureActionLabel(
                            title: "Histórico",
                            detail: "Refeições e treinos confirmados",
                            systemImage: "clock.arrow.circlepath"
                        )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.history")

                NavigationLink(
                    value: AppRoute.detail(tab: .today, id: "daily-summary")
                ) {
                    BodyFlowCard {
                        FeatureActionLabel(
                            title: "Resumo do dia",
                            detail: "Consultar detalhes recebidos",
                            systemImage: "doc.text.magnifyingglass"
                        )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.next-action")
            }
            .padding(BodyFlowSpacing.md)
        }
        .refreshable {
            await model.retry()
        }
    }

    private func retry() {
        Task {
            await model.retry()
        }
    }
}
