import Foundation

#if DEBUG
/// UI-test scenario for plan drafts (Debug builds only): one synthetic
/// imported training draft with missing values and a medication line, kept in
/// memory. No server, no media, no real data.
enum DemoPlanDraftScenario {
    static let argument = "--ui-testing-plan-drafts"
    static let draftID = "0d0d0d0d-1111-4222-8333-444455556666"

    static func isEnabled(arguments: [String]) -> Bool {
        arguments.contains(argument)
    }
}

actor DemoPlanDraftProvider: PlanDraftProviding {
    private var status = "needs_completion"
    private var version = 1
    private var payload: JSONValue = .object([
        "plan_type": .string("full_body"),
        "weekly_schedule": .array([
            .object([
                "day": .string("Treino A"),
                "focus": .string("Inferiores"),
                "duration_min": .number(60),
                "exercises": .array([
                    .object([
                        "name": .string("Agachamento livre"),
                        "muscle_group": .string("pernas"),
                        "sets": .number(4),
                        "reps_range": .string("8-12"),
                        "rest_seconds": .number(90),
                    ]),
                    .object([
                        "name": .string("Leg press"),
                        "muscle_group": .string("pernas"),
                        "sets": .number(3),
                        "reps_range": .string("10"),
                        "rest_seconds": .null,
                    ]),
                ]),
            ]),
        ]),
    ])

    private var missing: [PlanDraftUncertainField] {
        guard case let .object(root) = payload,
              case let .array(days)? = root["weekly_schedule"]
        else {
            return []
        }
        var fields: [PlanDraftUncertainField] = []
        for (dayIndex, day) in days.enumerated() {
            guard case let .object(dayObject) = day,
                  case let .array(exercises)? = dayObject["exercises"]
            else {
                continue
            }
            for (index, exercise) in exercises.enumerated() {
                guard case let .object(fieldsOfExercise) = exercise else { continue }
                if fieldsOfExercise["rest_seconds"] == .null
                    || fieldsOfExercise["rest_seconds"] == nil {
                    fields.append(PlanDraftUncertainField(
                        pointer: "/weekly_schedule/\(dayIndex)/exercises/\(index)/rest_seconds",
                        reason: "missing"
                    ))
                }
            }
        }
        return fields
    }

    private func snapshot(alreadyConfirmed: Bool? = nil) -> PlanDraftSnapshot {
        PlanDraftSnapshot(
            id: DemoPlanDraftScenario.draftID,
            domain: .training,
            origin: "imported_pdf",
            status: status,
            payloadVersion: version,
            payload: payload,
            uncertainFields: status == "confirmed" ? [] : missing,
            unrecognizedSegments: ["Tomar creatina 5 g após o treino."],
            replacesCurrentPlan: true,
            canConfirm: status == "ready_for_review",
            notices: ["not_professionally_reviewed", "medications_not_imported"],
            failureCode: nil,
            confirmedPlanID: status == "confirmed" ? "0d0d0d0d-aaaa-4bbb-8ccc-ddddeeeeffff" : nil,
            alreadyConfirmed: alreadyConfirmed
        )
    }

    func openDrafts() -> [PlanDraftSummary] {
        guard status == "needs_completion" || status == "ready_for_review" else { return [] }
        return [PlanDraftSummary(
            id: DemoPlanDraftScenario.draftID,
            domain: .training,
            origin: "imported_pdf",
            status: status,
            payloadVersion: version,
            createdAt: APITimestamp(value: Date(timeIntervalSince1970: 1_790_000_000))
        )]
    }

    func draft(id: String) throws -> PlanDraftSnapshot {
        guard id == DemoPlanDraftScenario.draftID else { throw PlanDraftFailure.notFound }
        return snapshot()
    }

    func update(_ attempt: MutationAttempt<PlanDraftEdit>) throws -> PlanDraftSnapshot {
        guard attempt.payload.draftID == DemoPlanDraftScenario.draftID else {
            throw PlanDraftFailure.notFound
        }
        guard attempt.payload.payloadVersion == version else { throw PlanDraftFailure.draftChanged }
        payload = attempt.payload.payload
        version += 1
        status = missing.isEmpty ? "ready_for_review" : "needs_completion"
        return snapshot()
    }

    func confirm(
        _ attempt: MutationAttempt<PlanDraftConfirmation>
    ) throws -> PlanDraftSnapshot {
        if status == "confirmed" { return snapshot(alreadyConfirmed: true) }
        guard status == "ready_for_review" else { throw PlanDraftFailure.incomplete }
        guard attempt.payload.payloadVersion == version else { throw PlanDraftFailure.draftChanged }
        status = "confirmed"
        return snapshot(alreadyConfirmed: false)
    }

    func discard(_ attempt: MutationAttempt<PlanDraftCommand>) throws -> PlanDraftSnapshot {
        guard status != "confirmed" else { throw PlanDraftFailure.notReviewable }
        status = "discarded"
        return snapshot()
    }

    func startImport(
        _ attempt: MutationAttempt<PlanImportRequest>
    ) throws -> PlanImportReceipt {
        throw PlanDraftFailure.unavailable
    }
}
#endif
