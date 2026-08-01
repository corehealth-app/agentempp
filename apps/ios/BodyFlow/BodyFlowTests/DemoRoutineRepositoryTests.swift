#if DEBUG
import Foundation
import Testing

@testable import BodyFlow

@Suite("Demo Routine Repository")
struct DemoRoutineRepositoryTests {
    @Test("hydration selects a complete non-additive Today snapshot and exact replay does not transition twice")
    func hydrationSelectsCompleteSnapshotAndReplays() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let attempt = try hydrationAttempt(
            amountML: 250,
            key: "hydration-non-additive-0001"
        )
        let before = try await repository.today()

        #expect(before.data.hydration.consumedML == 1_250)
        let receipt = try await repository.record(attempt)
        let after = try await repository.today()

        #expect(receipt == DemoBodyFlowFixtures.hydrationReceipt)
        #expect(after == DemoBodyFlowFixtures.postHydrationToday)
        #expect(receipt.data.waterConsumedML == 2_111)
        #expect(after.data.hydration.consumedML == 2_111)
        #expect(after.data.hydration.consumedML != before.data.hydration.consumedML + 250)

        #expect(try await repository.record(attempt) == receipt)
        #expect(try await repository.today() == after)
    }

    @Test("hydration validates operation and the global ledger rejects payload or time changes")
    func hydrationValidatesAttemptAndGlobalReplayIdentity() async throws {
        let operationRepository = DemoBodyFlowRepository(scenario: .loaded)
        await #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try await operationRepository.record(hydrationAttempt(
                amountML: 250,
                key: "hydration-wrong-operation-0001",
                operation: .weight
            ))
        }

        let payloadRepository = DemoBodyFlowRepository(scenario: .loaded)
        let original = try hydrationAttempt(
            amountML: 250,
            key: "hydration-payload-conflict-0001"
        )
        _ = try await payloadRepository.record(original)
        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await payloadRepository.record(hydrationAttempt(
                amountML: 750,
                key: original.key.value
            ))
        }

        let dateRepository = DemoBodyFlowRepository(scenario: .loaded)
        let dated = try hydrationAttempt(
            amountML: 250,
            key: "hydration-time-conflict-0001"
        )
        _ = try await dateRepository.record(dated)
        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await dateRepository.record(hydrationAttempt(
                amountML: 250,
                key: dated.key.value,
                createdAt: actionDate.addingTimeInterval(1)
            ))
        }
    }

    @Test("hydration preserves all nine public registration confirmation states")
    func hydrationPreservesNineStateRegistrationFSM() async throws {
        #expect(ConfirmationSetup.allCases.count == 9)
        for setup in ConfirmationSetup.allCases {
            let repository = DemoBodyFlowRepository(scenario: .loaded)
            try await setup.apply(to: repository)

            let beforeHydration = try await repository.today()
            #expect(beforeHydration == setup.expectedToday)

            _ = try await repository.record(hydrationAttempt(
                amountML: 250,
                key: "matrix-\(setup.rawValue)-hydration-0001"
            ))
            let afterHydration = try await repository.today()

            assertHydrationOnlyTransition(
                before: beforeHydration,
                after: afterHydration,
                expectedRequestID: setup.hydratedRequestID
            )
        }
    }

    @Test("a registration proposal key reused for hydration conflicts through the global ledger")
    func proposalKeyCannotBeReusedForHydration() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let proposal = try proposalAttempt(
            payload: DemoBodyFlowFixtures.detectedTextMealRequest,
            key: "cross-port-proposal-key-0001"
        )
        _ = try await repository.propose(proposal)

        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await repository.record(hydrationAttempt(
                amountML: 250,
                key: proposal.key.value
            ))
        }
    }

    @Test("global replay identity stays typed across hydration weight routine and proposal ports")
    func replayIdentityIsCommonAcrossMutationPorts() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let hydration = try hydrationAttempt(
            amountML: 250,
            key: "common-replay-cross-port-0001"
        )
        let receipt = try await repository.record(hydration)

        #expect(try await repository.record(hydration) == receipt)
        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await repository.record(weightAttempt(
                weightKG: 81.25,
                key: hydration.key.value
            ))
        }
        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await repository.record(routineAttempt(
                status: .taken,
                key: hydration.key.value
            ))
        }
        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await repository.propose(proposalAttempt(
                payload: DemoBodyFlowFixtures.detectedTextMealRequest,
                key: hydration.key.value
            ))
        }
    }

    @Test("weight returns the approved local receipt and mutates no official snapshot")
    func weightIsLocalAndOfficialReadsStayEqual() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let attempt = try weightAttempt(
            weightKG: 78.4,
            key: "weight-local-only-0001"
        )
        let beforeToday = try await repository.today()
        let beforeProgress = try await repository.progress()
        let beforeHistory = try await repository.history(.firstPage)
        let beforeList = try await repository.list(
            kind: .supplement,
            includeArchived: false
        )

        let receipt = try await repository.record(attempt)

        #expect(receipt == DemoBodyFlowFixtures.weightReceipt)
        #expect(receipt.label == "Demonstração local; não sincronizado")
        #expect(try await repository.today() == beforeToday)
        #expect(try await repository.progress() == beforeProgress)
        #expect(try await repository.history(.firstPage) == beforeHistory)
        #expect(
            try await repository.list(kind: .supplement, includeArchived: false)
                == beforeList
        )
        #expect(try await repository.today().data.block7700 == beforeToday.data.block7700)
        #expect(try await repository.record(attempt) == receipt)
        #expect(try await repository.today() == beforeToday)
    }

    @Test("weight replay conflicts on changed payload time or operation")
    func weightReplayIdentityIsGlobalAndTyped() async throws {
        let payloadRepository = DemoBodyFlowRepository(scenario: .loaded)
        let original = try weightAttempt(
            weightKG: 78.4,
            key: "weight-payload-conflict-0001"
        )
        _ = try await payloadRepository.record(original)
        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await payloadRepository.record(weightAttempt(
                weightKG: 79.1,
                key: original.key.value
            ))
        }

        let dateRepository = DemoBodyFlowRepository(scenario: .loaded)
        let dated = try weightAttempt(
            weightKG: 78.4,
            key: "weight-time-conflict-0001"
        )
        _ = try await dateRepository.record(dated)
        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await dateRepository.record(weightAttempt(
                weightKG: 78.4,
                key: dated.key.value,
                createdAt: actionDate.addingTimeInterval(1)
            ))
        }

        let operationRepository = DemoBodyFlowRepository(scenario: .loaded)
        await #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try await operationRepository.record(weightAttempt(
                weightKG: 78.4,
                key: "weight-wrong-operation-0001",
                operation: .hydration
            ))
        }
    }

    @Test("weight accepts every valid command and returns its exact local-only values")
    func weightAcceptsBoundariesAndIntermediateValues() async throws {
        let cases: [(Double, Date, String)] = [
            (30, actionDate.addingTimeInterval(-120), "weight-boundary-low-0001"),
            (300, actionDate.addingTimeInterval(-60), "weight-boundary-high-0001"),
            (81.25, actionDate.addingTimeInterval(45), "weight-intermediate-0001"),
        ]

        for (weightKG, recordedAt, key) in cases {
            let repository = DemoBodyFlowRepository(scenario: .loaded)
            let beforeToday = try await repository.today()
            let beforeProgress = try await repository.progress()
            let beforeHistory = try await repository.history(.firstPage)
            let attempt = try weightAttempt(
                weightKG: weightKG,
                key: key,
                recordedAt: recordedAt
            )

            let receipt = try await repository.record(attempt)

            #expect(receipt.weightKG == weightKG)
            #expect(receipt.recordedAt == recordedAt)
            #expect(receipt.label == "Demonstração local; não sincronizado")
            #expect(try await repository.record(attempt) == receipt)
            #expect(try await repository.today() == beforeToday)
            #expect(try await repository.progress() == beforeProgress)
            #expect(try await repository.history(.firstPage) == beforeHistory)
        }
    }

    @Test("unavailable presentation rejects every Task 11 mutation without recording replay state")
    func unavailablePresentationRejectsMutationsWithoutLedger() async throws {
        let repository = DemoBodyFlowRepository(scenario: .unavailablePresentation)
        let hydration = try hydrationAttempt(
            amountML: 250,
            key: "unavailable-hydration-0001"
        )
        let weight = try weightAttempt(
            weightKG: 78.4,
            key: "unavailable-weight-0001"
        )
        let routine = try routineAttempt(
            status: .taken,
            key: "unavailable-routine-0001"
        )

        for _ in 0..<2 {
            await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
                try await repository.record(hydration)
            }
            await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
                try await repository.record(weight)
            }
            await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
                try await repository.record(routine)
            }
        }
    }

    @Test("hydration preserves complete empty and incomplete scenarios instead of promoting loaded data")
    func hydrationPreservesEmptyAndIncompleteScenarios() async throws {
        let cases: [(DemoBodyFlowScenario, String, String)] = [
            (.empty, "scenario-empty-hydration-0001", "demo-today-empty-after-hydration"),
            (
                .incompleteDay,
                "scenario-incomplete-hydration-0001",
                "demo-today-incomplete-after-hydration"
            ),
        ]

        for (scenario, key, expectedRequestID) in cases {
            let repository = DemoBodyFlowRepository(scenario: scenario)
            let before = try await repository.today()

            _ = try await repository.record(hydrationAttempt(
                amountML: 250,
                key: key
            ))
            let after = try await repository.today()

            assertHydrationOnlyTransition(
                before: before,
                after: after,
                expectedRequestID: expectedRequestID
            )
        }
    }

    @Test("empty and incomplete scenarios reject routine actions without changing their snapshots")
    func absentScenarioOccurrencesRejectRoutineActions() async throws {
        let cases: [(DemoBodyFlowScenario, String)] = [
            (.empty, "scenario-empty-routine-0001"),
            (.incompleteDay, "scenario-incomplete-routine-0001"),
        ]

        for (scenario, key) in cases {
            let repository = DemoBodyFlowRepository(scenario: scenario)
            let beforeToday = try await repository.today()
            let beforeList = try await repository.list(
                kind: .supplement,
                includeArchived: false
            )

            await #expect(throws: BodyFlowCapabilityError.routineTransitionInvalid) {
                try await repository.record(routineAttempt(status: .taken, key: key))
            }

            #expect(try await repository.today() == beforeToday)
            #expect(
                try await repository.list(kind: .supplement, includeArchived: false)
                    == beforeList
            )
        }
    }

    @Test("taken selects complete exact-occurrence list history and Today fixtures")
    func takenSelectsCompleteFixtures() async throws {
        try await assertRoutineTransition(
            status: .taken,
            key: "routine-taken-0001",
            expectedReceipt: DemoBodyFlowFixtures.routineTakenReceipt,
            expectedToday: DemoBodyFlowFixtures.postRoutineTakenToday,
            expectedList: DemoBodyFlowFixtures.postRoutineTakenSupplementList,
            expectedHistory: DemoBodyFlowFixtures.postRoutineTakenSupplementHistory
        )
    }

    @Test("skipped selects complete exact-occurrence list history and Today fixtures")
    func skippedSelectsCompleteFixtures() async throws {
        try await assertRoutineTransition(
            status: .skipped,
            key: "routine-skipped-0001",
            expectedReceipt: DemoBodyFlowFixtures.routineSkippedReceipt,
            expectedToday: DemoBodyFlowFixtures.postRoutineSkippedToday,
            expectedList: DemoBodyFlowFixtures.postRoutineSkippedSupplementList,
            expectedHistory: DemoBodyFlowFixtures.postRoutineSkippedSupplementHistory
        )
    }

    @Test("snoozed uses the Task 4 patient-timezone policy and selects complete fixtures")
    func snoozedSelectsCompleteFixtures() async throws {
        try await assertRoutineTransition(
            status: .snoozed,
            key: "routine-snoozed-0001",
            expectedReceipt: DemoBodyFlowFixtures.routineSnoozedReceipt,
            expectedToday: DemoBodyFlowFixtures.postRoutineSnoozedToday,
            expectedList: DemoBodyFlowFixtures.postRoutineSnoozedSupplementList,
            expectedHistory: DemoBodyFlowFixtures.postRoutineSnoozedSupplementHistory
        )
    }

    @Test("medication skipped uses the exact authored occurrence")
    func testMedicationSkippedUsesExactOccurrence() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let beforeSupplement = try await repository.list(
            kind: .supplement,
            includeArchived: false
        )

        let receipt = try await repository.record(routineAttempt(
            status: .skipped,
            key: "medication-skipped-0001",
            itemID: medicationItemID,
            kind: .medication,
            reminderRuleID: medicationReminderRuleID,
            scheduledFor: medicationSchedule
        ))

        #expect(receipt.data.kind == .medication)
        #expect(receipt.data.status == "skipped")
        let today = try await repository.today()
        let todayMedication = try #require(today.data.medications.items.first)
        let todayOccurrence = try #require(todayMedication.occurrences.first)
        #expect(todayMedication.id == medicationItemID)
        #expect(todayOccurrence.reminderRuleID == medicationReminderRuleID)
        #expect(todayOccurrence.scheduledFor.value == medicationSchedule)
        #expect(todayOccurrence.status == "skipped")

        let list = try await repository.list(
            kind: .medication,
            includeArchived: false
        )
        let listItem = try #require(list.data.items.first)
        let listOccurrence = try #require(listItem.schedules.first?.occurrence)
        #expect(listItem.id == medicationItemID)
        #expect(listOccurrence.scheduledFor.value == medicationSchedule)
        #expect(listOccurrence.status == "skipped")

        let history = try await repository.history(
            kind: .medication,
            itemID: medicationItemID,
            cursor: nil,
            limit: 20
        )
        let log = try #require(history.items.first)
        #expect(history.nextCursor == nil)
        #expect(log.routineItemID == medicationItemID)
        #expect(log.kind == .medication)
        #expect(log.reminderRuleID == medicationReminderRuleID)
        #expect(log.scheduledFor.value == medicationSchedule)
        #expect(log.status == "skipped")
        #expect(
            try await repository.list(kind: .supplement, includeArchived: false)
                == beforeSupplement
        )
    }

    @Test("medication adapter supports taken and snoozed authored states")
    func medicationSupportsTakenAndSnoozedStates() async throws {
        for status in [RoutineActionStatus.taken, .snoozed] {
            let repository = DemoBodyFlowRepository(scenario: .loaded)
            let receipt = try await repository.record(routineAttempt(
                status: status,
                key: "medication-\(status.rawValue)-0001",
                itemID: medicationItemID,
                kind: .medication,
                reminderRuleID: medicationReminderRuleID,
                scheduledFor: medicationSchedule
            ))

            #expect(receipt.data.kind == .medication)
            #expect(receipt.data.status == status.rawValue)
            let list = try await repository.list(
                kind: .medication,
                includeArchived: false
            )
            #expect(list.data.items[0].schedules[0].occurrence?.status == status.rawValue)
            let today = try await repository.today()
            #expect(today.data.medications.items[0].occurrences[0].status == status.rawValue)
            let history = try await repository.history(
                kind: .medication,
                itemID: medicationItemID,
                cursor: nil,
                limit: 20
            )
            #expect(history.nextCursor == nil)
        }
    }

    @Test("supplement and medication occurrence states coexist independently")
    func routineKindsDoNotEraseEachOther() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let baselineSupplement = try await repository.list(
            kind: .supplement,
            includeArchived: false
        )

        _ = try await repository.record(routineAttempt(
            status: .skipped,
            key: "independent-medication-skipped-0001",
            itemID: medicationItemID,
            kind: .medication,
            reminderRuleID: medicationReminderRuleID,
            scheduledFor: medicationSchedule
        ))
        let medicationAfterSkip = try await repository.list(
            kind: .medication,
            includeArchived: false
        )
        #expect(
            try await repository.list(kind: .supplement, includeArchived: false)
                == baselineSupplement
        )

        _ = try await repository.record(routineAttempt(
            status: .taken,
            key: "independent-supplement-taken-0001"
        ))

        #expect(
            try await repository.list(kind: .medication, includeArchived: false)
                == medicationAfterSkip
        )
        let today = try await repository.today()
        #expect(today.data.supplements.items[0].occurrences[1].status == "taken")
        #expect(today.data.medications.items[0].occurrences[0].status == "skipped")
    }

    @Test("snoozed occurrence appends each allowed follow-up intention")
    func snoozedOccurrenceAppendsAllowedTransitions() async throws {
        for nextStatus in [
            RoutineActionStatus.taken,
            .skipped,
            .snoozed,
        ] {
            let repository = DemoBodyFlowRepository(scenario: .loaded)
            let medicationBefore = try await repository.list(
                kind: .medication,
                includeArchived: false
            )
            let medicationHistoryBefore = try await repository.history(
                kind: .medication,
                itemID: medicationItemID,
                cursor: nil,
                limit: 20
            )
            let firstReceipt = try await repository.record(routineAttempt(
                status: .snoozed,
                key: "append-snoozed-\(nextStatus.rawValue)-0001"
            ))
            let secondReceipt = try await repository.record(routineAttempt(
                status: nextStatus,
                key: "append-\(nextStatus.rawValue)-0002"
            ))

            #expect(secondReceipt.data.adherenceLogID != firstReceipt.data.adherenceLogID)
            #expect(secondReceipt.data.occurrenceKey == firstReceipt.data.occurrenceKey)
            #expect(isLowercaseSHA256(firstReceipt.data.occurrenceKey))

            let history = try await repository.history(
                kind: .supplement,
                itemID: targetItemID,
                cursor: nil,
                limit: 20
            )
            #expect(history.items.count == 3)
            let newestLog = try #require(history.items.first)
            let priorLog = try #require(history.items.dropFirst().first)
            let baselineLog = try #require(history.items.dropFirst(2).first)
            #expect(newestLog.id == secondReceipt.data.adherenceLogID)
            #expect(newestLog.status == nextStatus.rawValue)
            #expect(newestLog.supersedesLogID == firstReceipt.data.adherenceLogID)
            #expect(priorLog.id == firstReceipt.data.adherenceLogID)
            #expect(priorLog.status == RoutineActionStatus.snoozed.rawValue)
            #expect(priorLog.supersedesLogID == nil)
            #expect(baselineLog == DemoBodyFlowFixtures.loadedSupplementHistory.items[0])

            let list = try await repository.list(
                kind: .supplement,
                includeArchived: false
            )
            #expect(list.data.items[0].schedules[1].occurrence?.status == nextStatus.rawValue)
            let today = try await repository.today()
            #expect(today.data.supplements.items[0].occurrences[1].status == nextStatus.rawValue)
            #expect(
                try await repository.list(kind: .medication, includeArchived: false)
                    == medicationBefore
            )
            #expect(
                try await repository.history(
                    kind: .medication,
                    itemID: medicationItemID,
                    cursor: nil,
                    limit: 20
                ) == medicationHistoryBefore
            )
        }
    }

    @Test("taken and skipped occurrences reject every new intention")
    func terminalOccurrenceStatesRejectNewTransitions() async throws {
        for terminalStatus in [RoutineActionStatus.taken, .skipped] {
            for nextStatus in [
                RoutineActionStatus.taken,
                .skipped,
                .snoozed,
            ] {
                let repository = DemoBodyFlowRepository(scenario: .loaded)
                _ = try await repository.record(routineAttempt(
                    status: terminalStatus,
                    key: "terminal-\(terminalStatus.rawValue)-\(nextStatus.rawValue)-0001"
                ))
                await #expect(throws: BodyFlowCapabilityError.routineTransitionInvalid) {
                    try await repository.record(routineAttempt(
                        status: nextStatus,
                        key: "terminal-\(terminalStatus.rawValue)-\(nextStatus.rawValue)-0002"
                    ))
                }
            }
        }
    }

    @Test("medication snoozed to skipped uses the same append-only occurrence FSM")
    func medicationSnoozedToSkippedIsAppendOnly() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let supplementBefore = try await repository.list(
            kind: .supplement,
            includeArchived: false
        )
        let snoozed = try await repository.record(routineAttempt(
            status: .snoozed,
            key: "medication-append-snoozed-0001",
            itemID: medicationItemID,
            kind: .medication,
            reminderRuleID: medicationReminderRuleID,
            scheduledFor: medicationSchedule
        ))
        let skipped = try await repository.record(routineAttempt(
            status: .skipped,
            key: "medication-append-skipped-0002",
            itemID: medicationItemID,
            kind: .medication,
            reminderRuleID: medicationReminderRuleID,
            scheduledFor: medicationSchedule
        ))

        #expect(skipped.data.adherenceLogID != snoozed.data.adherenceLogID)
        #expect(skipped.data.occurrenceKey == snoozed.data.occurrenceKey)
        #expect(isLowercaseSHA256(skipped.data.occurrenceKey))
        let history = try await repository.history(
            kind: .medication,
            itemID: medicationItemID,
            cursor: nil,
            limit: 20
        )
        #expect(history.nextCursor == nil)
        #expect(Array(history.items.map(\.id).prefix(2)) == [
            skipped.data.adherenceLogID,
            snoozed.data.adherenceLogID,
        ])
        #expect(history.items.first?.supersedesLogID == snoozed.data.adherenceLogID)
        #expect(
            try await repository.list(kind: .supplement, includeArchived: false)
                == supplementBefore
        )
    }

    @Test("provider occurrence keys are stable SHA-256 literals and absent from commands")
    func providerOccurrenceKeysStayProviderAuthored() throws {
        let supplementReceipts = [
            DemoBodyFlowFixtures.routineTakenReceipt,
            DemoBodyFlowFixtures.routineSkippedReceipt,
            DemoBodyFlowFixtures.routineSnoozedReceipt,
            DemoBodyFlowFixtures.routineSnoozedThenTakenReceipt,
            DemoBodyFlowFixtures.routineSnoozedThenSkippedReceipt,
            DemoBodyFlowFixtures.routineSnoozedThenSnoozedReceipt,
        ]
        let medicationReceipts = [
            DemoBodyFlowFixtures.medicationTakenReceipt,
            DemoBodyFlowFixtures.medicationSkippedReceipt,
            DemoBodyFlowFixtures.medicationSnoozedReceipt,
            DemoBodyFlowFixtures.medicationSnoozedThenTakenReceipt,
            DemoBodyFlowFixtures.medicationSnoozedThenSkippedReceipt,
            DemoBodyFlowFixtures.medicationSnoozedThenSnoozedReceipt,
        ]

        #expect(supplementReceipts.allSatisfy {
            isLowercaseSHA256($0.data.occurrenceKey)
                && $0.data.occurrenceKey == DemoBodyFlowFixtures.supplementOccurrenceKey
        })
        #expect(medicationReceipts.allSatisfy {
            isLowercaseSHA256($0.data.occurrenceKey)
                && $0.data.occurrenceKey == DemoBodyFlowFixtures.medicationOccurrenceKey
        })
        #expect(
            DemoBodyFlowFixtures.supplementOccurrenceKey
                != DemoBodyFlowFixtures.medicationOccurrenceKey
        )

        let command = try routineAttempt(
            status: .taken,
            key: "command-has-no-provider-key-0001"
        ).payload
        let encoded = try JSONEncoder().encode(command)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(!json.contains("occurrence_key"))
        #expect(!json.contains("occurrenceKey"))
    }

    @Test("routine rejects wrong operation item kind rule scheduled time and occurrence time with typed errors")
    func routineRejectsInvalidTargetAndAction() async throws {
        let invalidAttempts = [
            try routineAttempt(
                status: .taken,
                key: "routine-invalid-item-0001",
                itemID: "supplement-other"
            ),
            try routineAttempt(
                status: .taken,
                key: "routine-invalid-kind-0001",
                kind: .medication
            ),
            try routineAttempt(
                status: .taken,
                key: "routine-invalid-rule-0001",
                reminderRuleID: "rule-20"
            ),
            try routineAttempt(
                status: .taken,
                key: "routine-invalid-schedule-0001",
                scheduledFor: targetSchedule.addingTimeInterval(60)
            ),
            try routineAttempt(
                status: .taken,
                key: "routine-invalid-time-0001",
                occurredAt: actionDate.addingTimeInterval(60)
            ),
        ]

        for attempt in invalidAttempts {
            let repository = DemoBodyFlowRepository(scenario: .loaded)
            await #expect(throws: BodyFlowCapabilityError.routineTransitionInvalid) {
                try await repository.record(attempt)
            }
        }

        let operationRepository = DemoBodyFlowRepository(scenario: .loaded)
        await #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try await operationRepository.record(routineAttempt(
                status: .taken,
                key: "routine-invalid-operation-0001",
                operation: .hydration
            ))
        }
    }

    @Test("routine rejects invalid snooze times through the Task 4 patient-timezone policy")
    func routineRejectsInvalidSnoozeTimes() async throws {
        let beforeOccurredAt = try routineAttempt(
            status: .snoozed,
            key: "routine-invalid-snooze-before-0001",
            snoozedUntil: actionDate.addingTimeInterval(-60)
        )
        let crossingDate = try routineAttempt(
            status: .snoozed,
            key: "routine-invalid-snooze-date-0001",
            snoozedUntil: Date(timeIntervalSince1970: 1_784_604_600)
        )

        for attempt in [beforeOccurredAt, crossingDate] {
            let repository = DemoBodyFlowRepository(scenario: .loaded)
            await #expect(throws: BodyFlowCapabilityError.routineSnoozeInvalid) {
                try await repository.record(attempt)
            }
        }
    }

    @Test("routine checks replay before terminal state and rejects a new terminal transition")
    func routineReplayPrecedesTerminalValidation() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let taken = try routineAttempt(
            status: .taken,
            key: "routine-terminal-taken-0001"
        )
        let receipt = try await repository.record(taken)

        #expect(try await repository.record(taken) == receipt)
        await #expect(throws: BodyFlowCapabilityError.routineTransitionInvalid) {
            try await repository.record(routineAttempt(
                status: .skipped,
                key: "routine-terminal-skipped-0001"
            ))
        }
    }

    @Test("routine global replay conflicts on changed payload time or operation")
    func routineReplayIdentityIsGlobalAndTyped() async throws {
        let payloadRepository = DemoBodyFlowRepository(scenario: .loaded)
        let taken = try routineAttempt(
            status: .taken,
            key: "routine-payload-conflict-0001"
        )
        _ = try await payloadRepository.record(taken)
        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await payloadRepository.record(routineAttempt(
                status: .skipped,
                key: taken.key.value
            ))
        }

        let dateRepository = DemoBodyFlowRepository(scenario: .loaded)
        let dated = try routineAttempt(
            status: .taken,
            key: "routine-time-conflict-0001"
        )
        _ = try await dateRepository.record(dated)
        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await dateRepository.record(routineAttempt(
                status: .taken,
                key: dated.key.value,
                createdAt: actionDate.addingTimeInterval(1)
            ))
        }
    }

    @Test("routine conflict once exposes authored reload fixtures without applying the requested action")
    func routineConflictOnceReloadsListAndHistory() async throws {
        let repository = DemoBodyFlowRepository(scenario: .routineConflictOnce)
        let attempt = try routineAttempt(
            status: .taken,
            key: "routine-conflict-once-0001"
        )
        let beforeToday = try await repository.today()

        await #expect(throws: BodyFlowCapabilityError.routineTransitionInvalid) {
            try await repository.record(attempt)
        }
        #expect(try await repository.today() == beforeToday)
        let reloadedList = try await repository.list(
            kind: .supplement,
            includeArchived: false
        )
        #expect(reloadedList == DemoBodyFlowFixtures.routineConflictSupplementList)
        let reloadedItem = try #require(reloadedList.data.items.first)
        let terminalOccurrences = try reloadedItem.schedules.map { schedule in
            try #require(schedule.occurrence)
        }
        #expect(terminalOccurrences.map(\.status) == ["taken", "taken"])
        #expect(terminalOccurrences.map(\.snoozedUntil) == [nil, nil])
        #expect(
            try await repository.history(
                kind: .supplement,
                itemID: targetItemID,
                cursor: nil,
                limit: 20
            ) == DemoBodyFlowFixtures.routineConflictSupplementHistory
        )

        #expect(try await repository.record(attempt) == DemoBodyFlowFixtures.routineTakenReceipt)
        #expect(
            try await repository.list(kind: .supplement, includeArchived: false)
                == DemoBodyFlowFixtures.postRoutineTakenSupplementList
        )
    }

    @Test("routine history accepts only the documented opaque base64url token byte for byte")
    func routineHistoryPassesOpaqueCursorByteForByte() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let first = try await repository.history(
            kind: .supplement,
            itemID: targetItemID,
            cursor: nil,
            limit: 20
        )

        #expect(first == DemoBodyFlowFixtures.loadedSupplementHistory)
        #expect(first.nextCursor == documentedOpaqueCursor)
        let second = try await repository.history(
            kind: .supplement,
            itemID: targetItemID,
            cursor: documentedOpaqueCursor,
            limit: 20
        )
        #expect(second == DemoBodyFlowFixtures.secondSupplementHistoryPage)

        await #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try await repository.history(
                kind: .supplement,
                itemID: targetItemID,
                cursor: documentedOpaqueCursor + "=",
                limit: 20
            )
        }
    }

    @Test(
        "supplement action history preserves its documented page-two cursor",
        arguments: SupplementHistoryActionPath.allCases
    )
    func supplementActionHistoryPreservesPageTwoCursor(
        path: SupplementHistoryActionPath
    ) async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        for (index, status) in path.statuses.enumerated() {
            _ = try await repository.record(routineAttempt(
                status: status,
                key: "history-cursor-\(path.rawValue)-\(index)-0001"
            ))
        }

        let first = try await repository.history(
            kind: .supplement,
            itemID: targetItemID,
            cursor: nil,
            limit: 20
        )
        #expect(first.nextCursor == documentedOpaqueCursor)
        #expect(
            first.nextCursor
                == DemoBodyFlowFixtures.documentedRoutineHistoryCursor
        )

        let returnedCursor = try #require(first.nextCursor)
        let second = try await repository.history(
            kind: .supplement,
            itemID: targetItemID,
            cursor: returnedCursor,
            limit: 20
        )
        #expect(second == DemoBodyFlowFixtures.secondSupplementHistoryPage)

        await #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try await repository.history(
                kind: .supplement,
                itemID: targetItemID,
                cursor: returnedCursor + "=",
                limit: 20
            )
        }
    }

    private func assertRoutineTransition(
        status: RoutineActionStatus,
        key: String,
        expectedReceipt: RoutineActionResponse,
        expectedToday: TodayResponse,
        expectedList: RoutineListResponse,
        expectedHistory: RoutineHistoryPage
    ) async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let beforeToday = try await repository.today()
        let beforeList = try await repository.list(
            kind: .supplement,
            includeArchived: false
        )
        let attempt = try routineAttempt(status: status, key: key)

        let receipt = try await repository.record(attempt)

        #expect(receipt == expectedReceipt)
        #expect(try await repository.today() == expectedToday)
        #expect(
            try await repository.list(kind: .supplement, includeArchived: false)
                == expectedList
        )
        #expect(
            try await repository.history(
                kind: .supplement,
                itemID: targetItemID,
                cursor: nil,
                limit: 20
            ) == expectedHistory
        )

        let beforeItem = try #require(beforeList.data.items.first)
        let afterItem = try #require(expectedList.data.items.first)
        #expect(beforeItem.id == targetItemID)
        #expect(afterItem.id == targetItemID)
        #expect(afterItem.schedules[0] == beforeItem.schedules[0])
        #expect(afterItem.schedules[1].id == targetReminderRuleID)
        #expect(beforeToday.data.targets == expectedToday.data.targets)
        #expect(beforeToday.data.consumed == expectedToday.data.consumed)
        #expect(beforeToday.data.meals == expectedToday.data.meals)
        #expect(beforeToday.data.workouts == expectedToday.data.workouts)
        #expect(beforeToday.data.hydration == expectedToday.data.hydration)
        #expect(beforeToday.data.pendingActions == expectedToday.data.pendingActions)
        #expect(beforeToday.data.block7700 == expectedToday.data.block7700)

        #expect(try await repository.record(attempt) == receipt)
        #expect(try await repository.today() == expectedToday)
    }
}

enum SupplementHistoryActionPath: String, CaseIterable {
    case taken
    case skipped
    case snoozed
    case snoozedThenTaken
    case snoozedThenSkipped
    case snoozedThenSnoozed

    var statuses: [RoutineActionStatus] {
        switch self {
        case .taken:
            [.taken]
        case .skipped:
            [.skipped]
        case .snoozed:
            [.snoozed]
        case .snoozedThenTaken:
            [.snoozed, .taken]
        case .snoozedThenSkipped:
            [.snoozed, .skipped]
        case .snoozedThenSnoozed:
            [.snoozed, .snoozed]
        }
    }
}

private enum ConfirmationSetup: String, CaseIterable {
    case none
    case mealInitial
    case mealEdited
    case workoutInitial
    case workoutEdited
    case mealInitialWorkoutInitial
    case mealEditedWorkoutInitial
    case mealInitialWorkoutEdited
    case mealEditedWorkoutEdited

    var expectedToday: TodayResponse {
        switch self {
        case .none:
            DemoBodyFlowFixtures.loadedToday
        case .mealInitial:
            DemoBodyFlowFixtures.postMealConfirmationToday
        case .mealEdited:
            DemoBodyFlowFixtures.postEditedMealConfirmationToday
        case .workoutInitial:
            DemoBodyFlowFixtures.postWorkoutConfirmationToday
        case .workoutEdited:
            DemoBodyFlowFixtures.postEditedWorkoutConfirmationToday
        case .mealInitialWorkoutInitial:
            DemoBodyFlowFixtures.postInitialMealInitialWorkoutConfirmationToday
        case .mealEditedWorkoutInitial:
            DemoBodyFlowFixtures.postEditedMealInitialWorkoutConfirmationToday
        case .mealInitialWorkoutEdited:
            DemoBodyFlowFixtures.postInitialMealEditedWorkoutConfirmationToday
        case .mealEditedWorkoutEdited:
            DemoBodyFlowFixtures.postEditedMealEditedWorkoutConfirmationToday
        }
    }

    var hydratedRequestID: String {
        switch self {
        case .none:
            "demo-today-after-hydration"
        case .mealInitial:
            "demo-today-authored-mealInitial-true-baseline-baseline"
        case .mealEdited:
            "demo-today-authored-mealEdited-true-baseline-baseline"
        case .workoutInitial:
            "demo-today-authored-workoutInitial-true-baseline-baseline"
        case .workoutEdited:
            "demo-today-authored-workoutEdited-true-baseline-baseline"
        case .mealInitialWorkoutInitial:
            "demo-today-authored-mealInitialWorkoutInitial-true-baseline-baseline"
        case .mealEditedWorkoutInitial:
            "demo-today-authored-mealEditedWorkoutInitial-true-baseline-baseline"
        case .mealInitialWorkoutEdited:
            "demo-today-authored-mealInitialWorkoutEdited-true-baseline-baseline"
        case .mealEditedWorkoutEdited:
            "demo-today-after-edited-meal-edited-workout-hydration"
        }
    }

    func apply(to repository: DemoBodyFlowRepository) async throws {
        if includesMeal {
            let meal = try await repository.propose(proposalAttempt(
                payload: DemoBodyFlowFixtures.detectedTextMealRequest,
                key: "matrix-\(rawValue)-meal-propose"
            ))
            if editsMeal {
                _ = try await repository.edit(editAttempt(
                    id: meal.data.id,
                    proposal: DemoBodyFlowFixtures.detectedPhotoMealRequest,
                    key: "matrix-\(rawValue)-meal-edit"
                ))
            }
            _ = try await repository.confirm(confirmationAttempt(
                id: meal.data.id,
                key: "matrix-\(rawValue)-meal-confirm"
            ))
        }

        if includesWorkout {
            let workout = try await repository.propose(proposalAttempt(
                payload: workoutRequest,
                key: "matrix-\(rawValue)-workout-propose"
            ))
            if editsWorkout {
                _ = try await repository.edit(editAttempt(
                    id: workout.data.id,
                    proposal: workoutRequest,
                    key: "matrix-\(rawValue)-workout-edit"
                ))
            }
            _ = try await repository.confirm(confirmationAttempt(
                id: workout.data.id,
                key: "matrix-\(rawValue)-workout-confirm"
            ))
        }
    }

    private var includesMeal: Bool {
        switch self {
        case .mealInitial,
             .mealEdited,
             .mealInitialWorkoutInitial,
             .mealEditedWorkoutInitial,
             .mealInitialWorkoutEdited,
             .mealEditedWorkoutEdited:
            true
        case .none, .workoutInitial, .workoutEdited:
            false
        }
    }

    private var editsMeal: Bool {
        switch self {
        case .mealEdited, .mealEditedWorkoutInitial, .mealEditedWorkoutEdited:
            true
        default:
            false
        }
    }

    private var includesWorkout: Bool {
        switch self {
        case .workoutInitial,
             .workoutEdited,
             .mealInitialWorkoutInitial,
             .mealEditedWorkoutInitial,
             .mealInitialWorkoutEdited,
             .mealEditedWorkoutEdited:
            true
        case .none, .mealInitial, .mealEdited:
            false
        }
    }

    private var editsWorkout: Bool {
        switch self {
        case .workoutEdited, .mealInitialWorkoutEdited, .mealEditedWorkoutEdited:
            true
        default:
            false
        }
    }
}

private let targetItemID = "supplement-1"
private let targetReminderRuleID = "rule-08"
private let targetSchedule = Date(timeIntervalSince1970: 1_784_545_200)
private let medicationItemID = "medication-1"
private let medicationReminderRuleID = "medication-rule-09"
private let medicationSchedule = Date(timeIntervalSince1970: 1_784_548_800)
private let actionDate = Date(timeIntervalSince1970: 1_784_589_300)
private let authoredSnoozeDate = Date(timeIntervalSince1970: 1_784_591_100)
private let documentedOpaqueCursor =
    "AbC_-09+/=.%2F?keep-byte-for-byte"

private func isLowercaseSHA256(_ value: String) -> Bool {
    value.count == 64
        && value.allSatisfy { $0.isNumber || ("a"..."f").contains(String($0)) }
}

private let workoutRequest = RegistrationProposalRequest.workout(
    WorkoutProposalRequest(
        workoutType: "musculacao",
        durationMin: 47,
        intensity: .moderate,
        performedAt: APITimestamp(value: actionDate)
    )
)

private func hydrationAttempt(
    amountML: Int,
    key: String,
    operation: MutationOperation = .hydration,
    createdAt: Date = actionDate
) throws -> MutationAttempt<HydrationCommand> {
    MutationAttempt(
        operation: operation,
        key: try IdempotencyKey(validating: key),
        payload: try HydrationCommand(
            amountML: amountML,
            occurredAt: APITimestamp(value: actionDate)
        ),
        createdAt: createdAt
    )
}

private func weightAttempt(
    weightKG: Double,
    key: String,
    operation: MutationOperation = .weight,
    recordedAt: Date = actionDate,
    createdAt: Date = actionDate
) throws -> MutationAttempt<WeightCommand> {
    MutationAttempt(
        operation: operation,
        key: try IdempotencyKey(validating: key),
        payload: try WeightCommand(weightKG: weightKG, recordedAt: recordedAt),
        createdAt: createdAt
    )
}

private func assertHydrationOnlyTransition(
    before: TodayResponse,
    after: TodayResponse,
    expectedRequestID: String
) {
    #expect(after.meta.apiVersion == "v1")
    #expect(after.meta.requestID == expectedRequestID)
    #expect(after.data.localDate == before.data.localDate)
    #expect(after.data.protocolName == before.data.protocolName)
    #expect(after.data.targets == before.data.targets)
    #expect(after.data.consumed == before.data.consumed)
    #expect(after.data.remainingFoodKcal == before.data.remainingFoodKcal)
    #expect(after.data.foodExcessKcal == before.data.foodExcessKcal)
    #expect(after.data.exerciseKcal == before.data.exerciseKcal)
    #expect(after.data.dailyBalanceKcal == before.data.dailyBalanceKcal)
    #expect(after.data.dailyBalanceStatus == before.data.dailyBalanceStatus)
    #expect(after.data.proteinStatus == before.data.proteinStatus)
    #expect(after.data.meals == before.data.meals)
    #expect(after.data.workouts == before.data.workouts)
    #expect(after.data.hydration.consumedML == 2_111)
    #expect(after.data.hydration.targetML == nil)
    #expect(after.data.hydration.remainingML == nil)
    #expect(after.data.hydration.percentage == nil)
    #expect(after.data.hydration.status == "tracked_without_target")
    #expect(after.data.supplements == before.data.supplements)
    #expect(after.data.medications == before.data.medications)
    #expect(after.data.pendingActions == before.data.pendingActions)
    #expect(after.data.block7700 == before.data.block7700)
    #expect(after.data.completionStatus == before.data.completionStatus)
    #expect(after.data.sources == before.data.sources)
    #expect(after.data.calculationVersion == before.data.calculationVersion)
    #expect(after.data.updatedAt == APITimestamp(value: actionDate))
    #expect(after.data.generatedAt.value == actionDate)
}

private func routineAttempt(
    status: RoutineActionStatus,
    key: String,
    itemID: String = targetItemID,
    kind: RoutineItemKind = .supplement,
    reminderRuleID: String = targetReminderRuleID,
    scheduledFor: Date = targetSchedule,
    occurredAt: Date = actionDate,
    snoozedUntil: Date? = nil,
    operation: MutationOperation = .routineAction,
    createdAt: Date = actionDate
) throws -> MutationAttempt<RoutineActionCommand> {
    let resolvedSnooze = status == .snoozed
        ? snoozedUntil ?? authoredSnoozeDate
        : nil
    return MutationAttempt(
        operation: operation,
        key: try IdempotencyKey(validating: key),
        payload: try RoutineActionCommand(
            kind: kind,
            itemID: itemID,
            status: status,
            reminderRuleID: reminderRuleID,
            scheduledFor: APITimestamp(value: scheduledFor),
            occurredAt: APITimestamp(value: occurredAt),
            snoozedUntil: resolvedSnooze.map(APITimestamp.init(value:))
        ),
        createdAt: createdAt
    )
}

private func proposalAttempt(
    payload: RegistrationProposalRequest,
    key: String
) throws -> MutationAttempt<RegistrationProposalRequest> {
    MutationAttempt(
        operation: .proposalCreate,
        key: try IdempotencyKey(validating: key),
        payload: payload,
        createdAt: actionDate
    )
}

private func editAttempt(
    id: String,
    proposal: RegistrationProposalRequest,
    key: String
) throws -> MutationAttempt<RegistrationEditCommand> {
    MutationAttempt(
        operation: .proposalEdit,
        key: try IdempotencyKey(validating: key),
        payload: RegistrationEditCommand(
            registrationID: id,
            proposal: proposal
        ),
        createdAt: actionDate
    )
}

private func confirmationAttempt(
    id: String,
    key: String
) throws -> MutationAttempt<RegistrationIDCommand> {
    MutationAttempt(
        operation: .proposalConfirm,
        key: try IdempotencyKey(validating: key),
        payload: RegistrationIDCommand(registrationID: id),
        createdAt: actionDate
    )
}
#endif
