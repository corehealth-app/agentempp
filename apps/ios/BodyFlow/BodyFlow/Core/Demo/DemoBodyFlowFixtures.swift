#if DEBUG
import Foundation

enum DemoBodyFlowFixtures {
    private static let instant = Date(timeIntervalSince1970: 1_784_589_300)
    private static let timestamp = APITimestamp(value: instant)

    static let loadedToday = TodayResponse(
        data: TodaySnapshot(
            localDate: "2026-07-20",
            protocolName: "recomposicao",
            targets: TodayTargets(
                caloriesKcal: 1_935,
                proteinG: nil,
                source: "daily_snapshot",
                caloriesSource: "daily_snapshot",
                proteinSource: nil
            ),
            consumed: TodayConsumed(
                caloriesKcal: 1_200,
                proteinG: 90.5,
                carbsG: 110.25,
                fatG: 42.75,
                source: "daily_snapshot"
            ),
            remainingFoodKcal: 731,
            foodExcessKcal: 17,
            exerciseKcal: 419,
            dailyBalanceKcal: -83,
            dailyBalanceStatus: "provisional",
            proteinStatus: TodayProteinStatus(
                consumedG: 90.5,
                targetG: nil,
                remainingG: nil,
                percentage: nil,
                status: "unavailable"
            ),
            meals: [
                TodayMeal(
                    id: "meal-z",
                    mealType: "jantar",
                    foodName: "Item sintético Z",
                    quantityG: 125.5,
                    kcal: 407,
                    proteinG: 31.25,
                    carbsG: 48.5,
                    fatG: 9.75,
                    consumedAt: apiTimestamp(1_784_578_500),
                    nutritionSource: "future_catalog_v99"
                ),
                TodayMeal(
                    id: "meal-a",
                    mealType: "cafe",
                    foodName: "Item sintético A",
                    quantityG: 80,
                    kcal: 211,
                    proteinG: 12,
                    carbsG: 16,
                    fatG: 11,
                    consumedAt: apiTimestamp(1_784_538_000),
                    nutritionSource: "canonical_exact"
                ),
            ],
            workouts: [
                TodayWorkout(
                    id: "workout-z",
                    workoutType: "musculacao",
                    durationMin: 40,
                    estimatedKcal: 301,
                    intensity: "moderada",
                    performedAt: apiTimestamp(1_784_572_200)
                ),
                TodayWorkout(
                    id: "workout-a",
                    workoutType: "caminhada",
                    durationMin: 25,
                    estimatedKcal: 118,
                    intensity: "leve",
                    performedAt: apiTimestamp(1_784_532_600)
                ),
            ],
            hydration: TodayHydration(
                consumedML: 1_250,
                targetML: nil,
                remainingML: nil,
                percentage: nil,
                status: "tracked_without_target"
            ),
            supplements: TodayRoutineSection(
                availability: "available",
                items: [todaySupplement]
            ),
            medications: TodayRoutineSection(
                availability: "not_configured",
                items: []
            ),
            pendingActions: TodayPendingActions(
                registrations: [
                    TodayPendingRegistration(
                        id: "pending-z",
                        kind: "meal",
                        mealType: "jantar",
                        createdAt: apiTimestamp(1_784_556_120),
                        expiresAt: apiTimestamp(1_784_563_200)
                    ),
                    TodayPendingRegistration(
                        id: "pending-a",
                        kind: "workout",
                        mealType: nil,
                        createdAt: apiTimestamp(1_784_556_060),
                        expiresAt: apiTimestamp(1_784_563_260)
                    ),
                ],
                mealGaps: TodayMealGaps(
                    expected: ["cafe", "almoco", "jantar"],
                    registered: ["cafe", "almoco"],
                    skipped: [],
                    open: ["jantar"],
                    reliable: true,
                    source: "personalized_pattern",
                    activeDays: 10
                )
            ),
            block7700: TodayBlock7700(
                enabled: true,
                availability: "available",
                targetKcal: 7_700,
                currentKcal: 2_500,
                percentage: 32,
                completedBlocks: 1,
                totalCreditedKcal: 10_200,
                source: "user_progress"
            ),
            completionStatus: TodayCompletionStatus(
                status: "pending_information",
                dayClosed: false,
                hasSufficientData: nil
            ),
            sources: loadedSources,
            calculationVersion: "bodyflow.daily-state.v2",
            updatedAt: nil,
            generatedAt: apiTimestamp(1_784_559_600)
        ),
        meta: metadata("request-today-contract-0001")
    )

    static let emptyToday = TodayResponse(
        data: TodaySnapshot(
            localDate: "2026-07-20",
            protocolName: nil,
            targets: TodayTargets(
                caloriesKcal: nil,
                proteinG: nil,
                source: "unavailable",
                caloriesSource: nil,
                proteinSource: nil
            ),
            consumed: TodayConsumed(
                caloriesKcal: 0,
                proteinG: 0,
                carbsG: 0,
                fatG: 0,
                source: "confirmed_meal_logs"
            ),
            remainingFoodKcal: 0,
            foodExcessKcal: 0,
            exerciseKcal: 0,
            dailyBalanceKcal: 0,
            dailyBalanceStatus: "unavailable",
            proteinStatus: TodayProteinStatus(
                consumedG: 0,
                targetG: nil,
                remainingG: nil,
                percentage: nil,
                status: "unavailable"
            ),
            meals: [],
            workouts: [],
            hydration: TodayHydration(
                consumedML: 0,
                targetML: nil,
                remainingML: nil,
                percentage: nil,
                status: "tracked_without_target"
            ),
            supplements: emptyRoutineSection,
            medications: emptyRoutineSection,
            pendingActions: emptyPendingActions,
            block7700: nil,
            completionStatus: TodayCompletionStatus(
                status: "no_records",
                dayClosed: false,
                hasSufficientData: false
            ),
            sources: emptySources,
            calculationVersion: "demo.prompt13.v1",
            updatedAt: nil,
            generatedAt: timestamp
        ),
        meta: metadata("demo-today-empty")
    )

    static let incompleteToday = TodayResponse(
        data: TodaySnapshot(
            localDate: "2026-07-20",
            protocolName: "Protocolo sintético",
            targets: TodayTargets(
                caloriesKcal: nil,
                proteinG: nil,
                source: "insufficient_data",
                caloriesSource: nil,
                proteinSource: nil
            ),
            consumed: TodayConsumed(
                caloriesKcal: 320,
                proteinG: 18,
                carbsG: 42,
                fatG: 9,
                source: "confirmed_meal_logs"
            ),
            remainingFoodKcal: 0,
            foodExcessKcal: 0,
            exerciseKcal: 0,
            dailyBalanceKcal: 0,
            dailyBalanceStatus: "insufficient_data",
            proteinStatus: TodayProteinStatus(
                consumedG: 18,
                targetG: nil,
                remainingG: nil,
                percentage: nil,
                status: "insufficient_data"
            ),
            meals: [],
            workouts: [],
            hydration: TodayHydration(
                consumedML: 450,
                targetML: nil,
                remainingML: nil,
                percentage: nil,
                status: "tracked_without_target"
            ),
            supplements: emptyRoutineSection,
            medications: emptyRoutineSection,
            pendingActions: emptyPendingActions,
            block7700: nil,
            completionStatus: TodayCompletionStatus(
                status: "insufficient_data",
                dayClosed: false,
                hasSufficientData: false
            ),
            sources: emptySources,
            calculationVersion: "demo.prompt13.v1",
            updatedAt: timestamp,
            generatedAt: timestamp
        ),
        meta: metadata("demo-today-incomplete")
    )

    static let loadedPlan = PlanResponse(
        data: PlanSnapshot(
            training: TrainingPlanSnapshot(
                id: "demo-training-plan-1",
                planType: "strength",
                daysPerWeek: 4,
                equipmentSummary: "Halteres e peso corporal",
                generatedAt: timestamp,
                validUntil: APITimestamp(
                    value: Date(timeIntervalSince1970: 1_787_151_600)
                ),
                version: 3,
                notes: "Plano sintético para demonstração"
            ),
            nutrition: [
                NutritionPrescriptionSnapshot(
                    id: "demo-nutrition-plan-1",
                    type: "macro_targets",
                    payload: .object([
                        "opaque": .boolean(true),
                        "version": .string("future-v1"),
                    ]),
                    generatedAt: timestamp,
                    validUntil: APITimestamp(
                        value: Date(timeIntervalSince1970: 1_787_151_600)
                    ),
                    version: 2,
                    notes: "Payload opaco sintético"
                ),
            ]
        ),
        meta: metadata("demo-plan-loaded")
    )

    static let emptyPlan = PlanResponse(
        data: PlanSnapshot(training: nil, nutrition: []),
        meta: metadata("demo-plan-empty")
    )

    static let loadedProgress = ProgressResponse(
        data: ProgressSnapshot(
            xpTotal: 7_420,
            level: 7,
            currentStreak: 12,
            longestStreak: 19,
            blocksCompleted: 2,
            deficitBlock: 6_999,
            currentWeight: 78.4,
            currentBodyFatPercent: 18.2,
            badgesEarned: ["first_week", "consistency"],
            lastActiveDate: "2026-07-20",
            nextReevaluation: "2026-07-29",
            updatedAt: timestamp
        ),
        meta: metadata("demo-progress-loaded")
    )

    static let emptyProgress = ProgressResponse(
        data: ProgressSnapshot(
            xpTotal: 0,
            level: 0,
            currentStreak: 0,
            longestStreak: 0,
            blocksCompleted: 0,
            deficitBlock: nil,
            currentWeight: nil,
            currentBodyFatPercent: nil,
            badgesEarned: [],
            lastActiveDate: nil,
            nextReevaluation: nil,
            updatedAt: timestamp
        ),
        meta: metadata("demo-progress-empty")
    )

    static let loadedHistory = HistoryResponse(
        data: HistorySnapshot(
            meals: [
                HistoryMealLogRow(
                    id: "demo-history-meal-row-1",
                    mealType: "almoco",
                    foodName: "Arroz integral sintético",
                    quantityG: 150,
                    kcal: 240,
                    proteinG: 6,
                    carbsG: 48,
                    fatG: 2,
                    consumedAt: timestamp
                ),
                HistoryMealLogRow(
                    id: "demo-history-meal-row-2",
                    mealType: "almoco",
                    foodName: "Feijão sintético",
                    quantityG: 100,
                    kcal: 130,
                    proteinG: 8,
                    carbsG: 22,
                    fatG: 1,
                    consumedAt: timestamp
                ),
            ],
            workouts: [
                HistoryWorkoutLogRow(
                    id: "demo-history-workout-1",
                    workoutType: "corrida",
                    durationMin: 35,
                    estimatedKcal: 287,
                    intensity: "moderada",
                    performedAt: timestamp
                ),
            ],
            pagination: HistoryPaginationMetadata(limit: 30, before: nil)
        ),
        meta: metadata("demo-history-loaded")
    )

    static let emptyHistory = HistoryResponse(
        data: HistorySnapshot(
            meals: [],
            workouts: [],
            pagination: HistoryPaginationMetadata(limit: 30, before: nil)
        ),
        meta: metadata("demo-history-empty")
    )

    static let loadedSupplementList = RoutineListResponse(
        data: RoutineListSnapshot(
            localDate: "2026-07-20",
            items: [supplement]
        ),
        meta: metadata("demo-supplement-list-loaded")
    )

    static let loadedMedicationList = RoutineListResponse(
        data: RoutineListSnapshot(
            localDate: "2026-07-20",
            items: []
        ),
        meta: metadata("demo-medication-list-loaded")
    )

    static let emptyRoutineList = RoutineListResponse(
        data: RoutineListSnapshot(localDate: "2026-07-20", items: []),
        meta: metadata("demo-routine-list-empty")
    )

    static let loadedSupplementHistory = RoutineHistoryPage(
        data: RoutineHistorySnapshot(
            items: [
                RoutineHistoryItem(
                    id: "routine-history-rule-20",
                    routineItemID: "supplement-1",
                    kind: .supplement,
                    status: "snoozed",
                    reminderRuleID: "rule-20",
                    scheduledFor: apiTimestamp(1_784_588_400),
                    occurredAt: apiTimestamp(1_784_588_460),
                    snoozedUntil: apiTimestamp(1_784_590_260),
                    source: "patient",
                    supersedesLogID: nil,
                    createdAt: apiTimestamp(1_784_588_460)
                ),
            ],
            nextCursor: nil
        ),
        meta: metadata("demo-supplement-history-loaded")
    )

    static let loadedMedicationHistory = RoutineHistoryPage(
        data: RoutineHistorySnapshot(items: [], nextCursor: nil),
        meta: metadata("demo-medication-history-loaded")
    )

    static let emptyRoutineHistory = RoutineHistoryPage(
        data: RoutineHistorySnapshot(items: [], nextCursor: nil),
        meta: metadata("demo-routine-history-empty")
    )

    private static let todaySupplement = TodayRoutineItem(
        id: "supplement-1",
        name: "Item informado",
        doseText: nil,
        origin: nil,
        remindersEnabled: true,
        schedules: [
            TodayRoutineSchedule(
                id: "rule-20",
                localTime: "20:00",
                weekdays: [1, 3, 5]
            ),
            TodayRoutineSchedule(
                id: "rule-08",
                localTime: "08:00",
                weekdays: [1, 3, 5]
            ),
        ],
        occurrences: [
            TodayRoutineOccurrence(
                reminderRuleID: "rule-20",
                scheduledFor: apiTimestamp(1_784_588_400),
                status: "snoozed",
                lastActionAt: apiTimestamp(1_784_588_460),
                snoozedUntil: apiTimestamp(1_784_590_260)
            ),
            TodayRoutineOccurrence(
                reminderRuleID: "rule-08",
                scheduledFor: apiTimestamp(1_784_545_200),
                status: "pending",
                lastActionAt: nil,
                snoozedUntil: nil
            ),
        ]
    )

    private static let supplement = RoutineItemSnapshot(
        id: "supplement-1",
        kind: .supplement,
        name: "Item informado",
        doseText: "",
        origin: "",
        remindersEnabled: true,
        active: true,
        archivedAt: nil,
        version: 1,
        createdAt: timestamp,
        updatedAt: timestamp,
        frequencySummary: RoutineFrequencySummary(timesPerWeek: 6),
        schedules: [
            RoutineScheduleSnapshot(
                id: "rule-20",
                localTime: "20:00",
                weekdays: [1, 3, 5],
                occurrence: RoutineOccurrenceSnapshot(
                    scheduledFor: apiTimestamp(1_784_588_400),
                    status: "snoozed",
                    lastActionAt: apiTimestamp(1_784_588_460),
                    snoozedUntil: apiTimestamp(1_784_590_260)
                )
            ),
            RoutineScheduleSnapshot(
                id: "rule-08",
                localTime: "08:00",
                weekdays: [1, 3, 5],
                occurrence: RoutineOccurrenceSnapshot(
                    scheduledFor: apiTimestamp(1_784_545_200),
                    status: "pending",
                    lastActionAt: nil,
                    snoozedUntil: nil
                )
            ),
        ]
    )

    private static let emptyRoutineSection = TodayRoutineSection(
        availability: "available",
        items: []
    )

    private static let emptyPendingActions = TodayPendingActions(
        registrations: [],
        mealGaps: TodayMealGaps(
            expected: [],
            registered: [],
            skipped: [],
            open: [],
            reliable: false,
            source: "unavailable",
            activeDays: 0
        )
    )

    private static let loadedSources = TodaySources(
        targets: "daily_snapshot",
        consumed: "daily_snapshot",
        exercise: "daily_snapshot",
        meals: "meal_logs",
        workouts: "workout_logs",
        hydration: "daily_snapshot",
        hydrationTarget: "unavailable",
        supplements: "routine_items_and_adherence_logs",
        medications: "routine_items_and_adherence_logs",
        pendingActions: "pending_registrations_and_meal_pattern",
        block7700: "user_progress"
    )

    private static let emptySources = TodaySources(
        targets: "unavailable",
        consumed: "meal_logs",
        exercise: "workout_logs",
        meals: "meal_logs",
        workouts: "workout_logs",
        hydration: "hydration_logs",
        hydrationTarget: "unavailable",
        supplements: "routine_items",
        medications: "routine_items",
        pendingActions: "registrations",
        block7700: "unavailable"
    )

    private static func metadata(_ requestID: String) -> MobileResponseMetadata {
        MobileResponseMetadata(apiVersion: "v1", requestID: requestID)
    }

    private static func apiTimestamp(_ interval: TimeInterval) -> APITimestamp {
        APITimestamp(value: Date(timeIntervalSince1970: interval))
    }
}
#endif
