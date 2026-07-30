#if DEBUG
import Foundation

enum DemoBodyFlowFixtures {
    private static let instant = Date(timeIntervalSince1970: 1_784_589_300)
    private static let timestamp = APITimestamp(value: instant)

    static let detectedTextMealRequest = RegistrationProposalRequest.meal(
        MealProposalRequest(
            mealType: .lunch,
            items: [
                MealProposalItemRequest(
                    foodName: "Refeição textual de demonstração",
                    quantityG: 180,
                    userKcal: nil
                )
            ],
            consumedAt: timestamp
        )
    )

    static let detectedPhotoMealRequest = RegistrationProposalRequest.meal(
        MealProposalRequest(
            mealType: .dinner,
            items: [
                MealProposalItemRequest(
                    foodName: "Amostra fotográfica de demonstração",
                    quantityG: 210,
                    userKcal: nil
                )
            ],
            consumedAt: timestamp
        )
    )

    static let detectedAudioMealRequest = RegistrationProposalRequest.meal(
        MealProposalRequest(
            mealType: .snack,
            items: [
                MealProposalItemRequest(
                    foodName: "Amostra de áudio de demonstração",
                    quantityG: 95,
                    userKcal: nil
                )
            ],
            consumedAt: timestamp
        )
    )

    static let pendingMealRegistration = registrationResponse(
        id: "demo-registration-meal-1",
        status: "pending",
        resolvedAt: nil,
        proposal: pendingMealProposal,
        requestID: "demo-registration-meal-pending"
    )

    static let editedMealRegistration = registrationResponse(
        id: "demo-registration-meal-1",
        status: "pending",
        resolvedAt: nil,
        proposal: editedMealProposal,
        requestID: "demo-registration-meal-edited"
    )

    static let cancelledMealRegistration = registrationResponse(
        id: "demo-registration-meal-1",
        status: "cancelled",
        resolvedAt: resolvedTimestamp,
        proposal: pendingMealProposal,
        requestID: "demo-registration-meal-cancelled"
    )

    static let cancelledEditedMealRegistration = registrationResponse(
        id: "demo-registration-meal-1",
        status: "cancelled",
        resolvedAt: resolvedTimestamp,
        proposal: editedMealProposal,
        requestID: "demo-registration-meal-edited-cancelled"
    )

    static let confirmedMealRegistration = confirmationResponse(
        id: "demo-registration-meal-1",
        proposal: pendingMealProposal,
        requestID: "demo-registration-meal-confirmed"
    )

    static let confirmedEditedMealRegistration = confirmationResponse(
        id: "demo-registration-meal-1",
        proposal: editedMealProposal,
        requestID: "demo-registration-meal-edited-confirmed"
    )

    static let pendingWorkoutRegistration = registrationResponse(
        id: "demo-registration-workout-1",
        status: "pending",
        resolvedAt: nil,
        proposal: pendingWorkoutProposal,
        requestID: "demo-registration-workout-pending"
    )

    static let editedWorkoutRegistration = registrationResponse(
        id: "demo-registration-workout-1",
        status: "pending",
        resolvedAt: nil,
        proposal: editedWorkoutProposal,
        requestID: "demo-registration-workout-edited"
    )

    static let cancelledWorkoutRegistration = registrationResponse(
        id: "demo-registration-workout-1",
        status: "cancelled",
        resolvedAt: resolvedTimestamp,
        proposal: pendingWorkoutProposal,
        requestID: "demo-registration-workout-cancelled"
    )

    static let cancelledEditedWorkoutRegistration = registrationResponse(
        id: "demo-registration-workout-1",
        status: "cancelled",
        resolvedAt: resolvedTimestamp,
        proposal: editedWorkoutProposal,
        requestID: "demo-registration-workout-edited-cancelled"
    )

    static let confirmedWorkoutRegistration = confirmationResponse(
        id: "demo-registration-workout-1",
        proposal: pendingWorkoutProposal,
        requestID: "demo-registration-workout-confirmed"
    )

    static let confirmedEditedWorkoutRegistration = confirmationResponse(
        id: "demo-registration-workout-1",
        proposal: editedWorkoutProposal,
        requestID: "demo-registration-workout-edited-confirmed"
    )

    static let postMealConfirmationToday = postConfirmationToday(
        consumedCalories: 1_777,
        remainingFoodCalories: 123,
        foodExcessCalories: 91,
        exerciseCalories: 419,
        dailyBalanceCalories: -222,
        meals: [confirmedMealToday, loadedMealZ, loadedMealA],
        workouts: [loadedWorkoutZ, loadedWorkoutA],
        requestID: "demo-today-after-meal-confirmation"
    )

    static let postEditedMealConfirmationToday = postConfirmationToday(
        consumedCalories: 1_812,
        remainingFoodCalories: 88,
        foodExcessCalories: 126,
        exerciseCalories: 419,
        dailyBalanceCalories: -257,
        meals: [confirmedEditedMealToday, loadedMealZ, loadedMealA],
        workouts: [loadedWorkoutZ, loadedWorkoutA],
        requestID: "demo-today-after-edited-meal-confirmation"
    )

    static let postWorkoutConfirmationToday = postConfirmationToday(
        consumedCalories: 1_111,
        remainingFoodCalories: 654,
        foodExcessCalories: 44,
        exerciseCalories: 777,
        dailyBalanceCalories: -456,
        meals: [loadedMealZ, loadedMealA],
        workouts: [confirmedWorkoutToday, loadedWorkoutZ, loadedWorkoutA],
        requestID: "demo-today-after-workout-confirmation"
    )

    static let postEditedWorkoutConfirmationToday = postConfirmationToday(
        consumedCalories: 1_111,
        remainingFoodCalories: 654,
        foodExcessCalories: 44,
        exerciseCalories: 888,
        dailyBalanceCalories: -567,
        meals: [loadedMealZ, loadedMealA],
        workouts: [confirmedEditedWorkoutToday, loadedWorkoutZ, loadedWorkoutA],
        requestID: "demo-today-after-edited-workout-confirmation"
    )

    static let postInitialMealInitialWorkoutConfirmationToday = postConfirmationToday(
        consumedCalories: 2_010,
        remainingFoodCalories: 101,
        foodExcessCalories: 130,
        exerciseCalories: 777,
        dailyBalanceCalories: -333,
        meals: [confirmedMealToday, loadedMealZ, loadedMealA],
        workouts: [confirmedWorkoutToday, loadedWorkoutZ, loadedWorkoutA],
        requestID: "demo-today-after-initial-meal-initial-workout-confirmation"
    )

    static let postEditedMealInitialWorkoutConfirmationToday = postConfirmationToday(
        consumedCalories: 2_133,
        remainingFoodCalories: 76,
        foodExcessCalories: 155,
        exerciseCalories: 777,
        dailyBalanceCalories: -400,
        meals: [confirmedEditedMealToday, loadedMealZ, loadedMealA],
        workouts: [confirmedWorkoutToday, loadedWorkoutZ, loadedWorkoutA],
        requestID: "demo-today-after-edited-meal-initial-workout-confirmation"
    )

    static let postInitialMealEditedWorkoutConfirmationToday = postConfirmationToday(
        consumedCalories: 2_010,
        remainingFoodCalories: 101,
        foodExcessCalories: 130,
        exerciseCalories: 888,
        dailyBalanceCalories: -444,
        meals: [confirmedMealToday, loadedMealZ, loadedMealA],
        workouts: [confirmedEditedWorkoutToday, loadedWorkoutZ, loadedWorkoutA],
        requestID: "demo-today-after-initial-meal-edited-workout-confirmation"
    )

    static let postEditedMealEditedWorkoutConfirmationToday = postConfirmationToday(
        consumedCalories: 2_133,
        remainingFoodCalories: 76,
        foodExcessCalories: 155,
        exerciseCalories: 888,
        dailyBalanceCalories: -511,
        meals: [confirmedEditedMealToday, loadedMealZ, loadedMealA],
        workouts: [confirmedEditedWorkoutToday, loadedWorkoutZ, loadedWorkoutA],
        requestID: "demo-today-after-edited-meal-edited-workout-confirmation"
    )

    static let postMealConfirmationHistory = postConfirmationHistory(
        meals: [confirmedMealHistory, loadedHistoryMealRow1, loadedHistoryMealRow2],
        workouts: [loadedHistoryWorkout],
        requestID: "demo-history-after-meal-confirmation"
    )

    static let postEditedMealConfirmationHistory = postConfirmationHistory(
        meals: [
            confirmedEditedMealHistory,
            loadedHistoryMealRow1,
            loadedHistoryMealRow2,
        ],
        workouts: [loadedHistoryWorkout],
        requestID: "demo-history-after-edited-meal-confirmation"
    )

    static let postWorkoutConfirmationHistory = postConfirmationHistory(
        meals: [loadedHistoryMealRow1, loadedHistoryMealRow2],
        workouts: [confirmedWorkoutHistory, loadedHistoryWorkout],
        requestID: "demo-history-after-workout-confirmation"
    )

    static let postEditedWorkoutConfirmationHistory = postConfirmationHistory(
        meals: [loadedHistoryMealRow1, loadedHistoryMealRow2],
        workouts: [confirmedEditedWorkoutHistory, loadedHistoryWorkout],
        requestID: "demo-history-after-edited-workout-confirmation"
    )

    static let postInitialMealInitialWorkoutConfirmationHistory = postConfirmationHistory(
        meals: [confirmedMealHistory, loadedHistoryMealRow1, loadedHistoryMealRow2],
        workouts: [confirmedWorkoutHistory, loadedHistoryWorkout],
        requestID: "demo-history-after-initial-meal-initial-workout-confirmation"
    )

    static let postEditedMealInitialWorkoutConfirmationHistory = postConfirmationHistory(
        meals: [
            confirmedEditedMealHistory,
            loadedHistoryMealRow1,
            loadedHistoryMealRow2,
        ],
        workouts: [confirmedWorkoutHistory, loadedHistoryWorkout],
        requestID: "demo-history-after-edited-meal-initial-workout-confirmation"
    )

    static let postInitialMealEditedWorkoutConfirmationHistory = postConfirmationHistory(
        meals: [confirmedMealHistory, loadedHistoryMealRow1, loadedHistoryMealRow2],
        workouts: [confirmedEditedWorkoutHistory, loadedHistoryWorkout],
        requestID: "demo-history-after-initial-meal-edited-workout-confirmation"
    )

    static let postEditedMealEditedWorkoutConfirmationHistory = postConfirmationHistory(
        meals: [
            confirmedEditedMealHistory,
            loadedHistoryMealRow1,
            loadedHistoryMealRow2,
        ],
        workouts: [confirmedEditedWorkoutHistory, loadedHistoryWorkout],
        requestID: "demo-history-after-edited-meal-edited-workout-confirmation"
    )

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

    private static let expiresTimestamp = apiTimestamp(1_784_592_900)
    private static let resolvedTimestamp = apiTimestamp(1_784_589_420)

    private static let pendingMealProposal = RegistrationProposalSnapshot.meal(
        MealProposalSnapshot(
            mealType: "almoco",
            items: [
                MealProposalItemSnapshot(
                    name: "Refeição textual de demonstração",
                    quantityG: 180,
                    kcal: 389,
                    proteinG: 27,
                    carbsG: 45,
                    fatG: 11
                )
            ],
            totals: MealProposalTotalsSnapshot(
                kcal: 389,
                proteinG: 27,
                carbsG: 45,
                fatG: 11
            ),
            warnings: ["Valores sintéticos; confirme antes de registrar."]
        )
    )

    private static let editedMealProposal = RegistrationProposalSnapshot.meal(
        MealProposalSnapshot(
            mealType: "jantar",
            items: [
                MealProposalItemSnapshot(
                    name: "Substituição completa predefinida",
                    quantityG: 205,
                    kcal: 512,
                    proteinG: 33,
                    carbsG: 52,
                    fatG: 19
                )
            ],
            totals: MealProposalTotalsSnapshot(
                kcal: 512,
                proteinG: 33,
                carbsG: 52,
                fatG: 19
            ),
            warnings: ["Resposta completa substituída."]
        )
    )

    private static let pendingWorkoutProposal = RegistrationProposalSnapshot.workout(
        WorkoutProposalSnapshot(
            workoutType: "musculacao",
            durationMin: 47,
            estimatedKcal: 333,
            intensity: "moderada"
        )
    )

    private static let editedWorkoutProposal = RegistrationProposalSnapshot.workout(
        WorkoutProposalSnapshot(
            workoutType: "ciclismo",
            durationMin: 61,
            estimatedKcal: 444,
            intensity: "alta"
        )
    )

    private static let confirmedMealToday = TodayMeal(
        id: "demo-confirmed-meal-row-1",
        mealType: "almoco",
        foodName: "Refeição confirmada predefinida",
        quantityG: 180,
        kcal: 389,
        proteinG: 27,
        carbsG: 45,
        fatG: 11,
        consumedAt: timestamp,
        nutritionSource: "llm_estimate"
    )

    private static let confirmedEditedMealToday = TodayMeal(
        id: "demo-confirmed-meal-edited-row-1",
        mealType: "jantar",
        foodName: "Substituição completa predefinida",
        quantityG: 205,
        kcal: 512,
        proteinG: 33,
        carbsG: 52,
        fatG: 19,
        consumedAt: timestamp,
        nutritionSource: "llm_estimate"
    )

    private static let confirmedWorkoutToday = TodayWorkout(
        id: "demo-confirmed-workout-1",
        workoutType: "musculacao",
        durationMin: 47,
        estimatedKcal: 333,
        intensity: "moderada",
        performedAt: timestamp
    )

    private static let confirmedEditedWorkoutToday = TodayWorkout(
        id: "demo-confirmed-workout-edited-1",
        workoutType: "ciclismo",
        durationMin: 61,
        estimatedKcal: 444,
        intensity: "alta",
        performedAt: timestamp
    )

    private static let loadedMealZ = TodayMeal(
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
    )

    private static let loadedMealA = TodayMeal(
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
    )

    private static let loadedWorkoutZ = TodayWorkout(
        id: "workout-z",
        workoutType: "musculacao",
        durationMin: 40,
        estimatedKcal: 301,
        intensity: "moderada",
        performedAt: apiTimestamp(1_784_572_200)
    )

    private static let loadedWorkoutA = TodayWorkout(
        id: "workout-a",
        workoutType: "caminhada",
        durationMin: 25,
        estimatedKcal: 118,
        intensity: "leve",
        performedAt: apiTimestamp(1_784_532_600)
    )

    private static let loadedHistoryMealRow1 = HistoryMealLogRow(
        id: "demo-history-meal-row-1",
        mealType: "almoco",
        foodName: "Arroz integral sintético",
        quantityG: 150,
        kcal: 240,
        proteinG: 6,
        carbsG: 48,
        fatG: 2,
        consumedAt: timestamp
    )

    private static let loadedHistoryMealRow2 = HistoryMealLogRow(
        id: "demo-history-meal-row-2",
        mealType: "almoco",
        foodName: "Feijão sintético",
        quantityG: 100,
        kcal: 130,
        proteinG: 8,
        carbsG: 22,
        fatG: 1,
        consumedAt: timestamp
    )

    private static let loadedHistoryWorkout = HistoryWorkoutLogRow(
        id: "demo-history-workout-1",
        workoutType: "corrida",
        durationMin: 35,
        estimatedKcal: 287,
        intensity: "moderada",
        performedAt: timestamp
    )

    private static let confirmedMealHistory = HistoryMealLogRow(
        id: "demo-confirmed-meal-row-1",
        mealType: "almoco",
        foodName: "Refeição confirmada predefinida",
        quantityG: 180,
        kcal: 389,
        proteinG: 27,
        carbsG: 45,
        fatG: 11,
        consumedAt: timestamp
    )

    private static let confirmedEditedMealHistory = HistoryMealLogRow(
        id: "demo-confirmed-meal-edited-row-1",
        mealType: "jantar",
        foodName: "Substituição completa predefinida",
        quantityG: 205,
        kcal: 512,
        proteinG: 33,
        carbsG: 52,
        fatG: 19,
        consumedAt: timestamp
    )

    private static let confirmedWorkoutHistory = HistoryWorkoutLogRow(
        id: "demo-confirmed-workout-1",
        workoutType: "musculacao",
        durationMin: 47,
        estimatedKcal: 333,
        intensity: "moderada",
        performedAt: timestamp
    )

    private static let confirmedEditedWorkoutHistory = HistoryWorkoutLogRow(
        id: "demo-confirmed-workout-edited-1",
        workoutType: "ciclismo",
        durationMin: 61,
        estimatedKcal: 444,
        intensity: "alta",
        performedAt: timestamp
    )

    private static func registrationResponse(
        id: String,
        status: String,
        resolvedAt: APITimestamp?,
        proposal: RegistrationProposalSnapshot,
        requestID: String
    ) -> RegistrationProposalResponse {
        RegistrationProposalResponse(
            data: RegistrationSnapshot(
                id: id,
                status: status,
                createdAt: timestamp,
                expiresAt: expiresTimestamp,
                resolvedAt: resolvedAt,
                proposal: proposal
            ),
            meta: metadata(requestID)
        )
    }

    private static func confirmationResponse(
        id: String,
        proposal: RegistrationProposalSnapshot,
        requestID: String
    ) -> RegistrationConfirmationResponse {
        RegistrationConfirmationResponse(
            data: RegistrationConfirmationSnapshot(
                demoRegistration: RegistrationSnapshot(
                    id: id,
                    status: "confirmed",
                    createdAt: timestamp,
                    expiresAt: expiresTimestamp,
                    resolvedAt: resolvedTimestamp,
                    proposal: proposal
                ),
                alreadyConfirmed: false,
                deduped: false
            ),
            meta: metadata(requestID)
        )
    }

    private static func postConfirmationToday(
        consumedCalories: Int,
        remainingFoodCalories: Int,
        foodExcessCalories: Int,
        exerciseCalories: Int,
        dailyBalanceCalories: Int,
        meals: [TodayMeal],
        workouts: [TodayWorkout],
        requestID: String
    ) -> TodayResponse {
        TodayResponse(
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
                    caloriesKcal: consumedCalories,
                    proteinG: 101.5,
                    carbsG: 163.25,
                    fatG: 61.75,
                    source: "daily_snapshot"
                ),
                remainingFoodKcal: remainingFoodCalories,
                foodExcessKcal: foodExcessCalories,
                exerciseKcal: exerciseCalories,
                dailyBalanceKcal: dailyBalanceCalories,
                dailyBalanceStatus: "predefined",
                proteinStatus: TodayProteinStatus(
                    consumedG: 101.5,
                    targetG: nil,
                    remainingG: nil,
                    percentage: nil,
                    status: "unavailable"
                ),
                meals: meals,
                workouts: workouts,
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
                pendingActions: preservedLoadedPendingActions,
                block7700: TodayBlock7700(
                    enabled: true,
                    availability: "available",
                    targetKcal: 7_700,
                    currentKcal: 3_333,
                    percentage: 43,
                    completedBlocks: 1,
                    totalCreditedKcal: 11_033,
                    source: "user_progress"
                ),
                completionStatus: TodayCompletionStatus(
                    status: "pending_information",
                    dayClosed: false,
                    hasSufficientData: true
                ),
                sources: loadedSources,
                calculationVersion: "bodyflow.daily-state.v2",
                updatedAt: resolvedTimestamp,
                generatedAt: resolvedTimestamp
            ),
            meta: metadata(requestID)
        )
    }

    private static func postConfirmationHistory(
        meals: [HistoryMealLogRow],
        workouts: [HistoryWorkoutLogRow],
        requestID: String
    ) -> HistoryResponse {
        HistoryResponse(
            data: HistorySnapshot(
                meals: meals,
                workouts: workouts,
                pagination: HistoryPaginationMetadata(limit: 30, before: nil)
            ),
            meta: metadata(requestID)
        )
    }

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

    private static let preservedLoadedPendingActions = TodayPendingActions(
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

private extension RegistrationConfirmationSnapshot {
    init(
        demoRegistration: RegistrationSnapshot,
        alreadyConfirmed: Bool,
        deduped: Bool?
    ) {
        registration = demoRegistration
        self.alreadyConfirmed = alreadyConfirmed
        self.deduped = deduped
    }
}
#endif
