import Foundation

#if DEBUG
/// UI-test scenario for plan drafts (Debug builds only): one synthetic
/// imported training draft with missing values and a medication line, kept in
/// memory. No server, no media, no real data.
enum DemoPlanDraftScenario {
    static let argument = "--ui-testing-plan-drafts"
    static let manyDraftsArgument = "--ui-testing-plan-drafts-many"
    static let draftID = "0d0d0d0d-1111-4222-8333-444455556666"

    /// With the drafts: one complete training draft WRITTEN BY FLOW, with
    /// the longer texts the server may send (a phrase of 40 characters in
    /// the effort and in the repetitions, long names).
    static let longTextArgument = "--ui-testing-plan-drafts-long-text"
    /// The same content as a plan imported from the person's document.
    static let longTextImportedArgument = "--ui-testing-plan-drafts-long-text-imported"

    static let longFocus = "Músculos de trás da coxa/Glúteos"
    static let longExerciseName = "Elevação pélvica com barra (Hip Thrust)"
    static let longestExerciseName = "Elevação pélvica com barra apoiando as costas no banco com os pés na largura do quadril e pausa de dois segundos no topo"
    static let repetitionsPhrase = "8 a 10, parando 2 antes de não aguentar."
    static let effortPhrase = "Pare 2 repetições antes de não aguentar."

    static func isEnabled(arguments: [String]) -> Bool {
        arguments.contains(argument)
    }

    static func variant(arguments: [String]) -> DemoPlanDraftProvider.Variant {
        if arguments.contains(longTextImportedArgument) { return .longText(imported: true) }
        if arguments.contains(longTextArgument) { return .longText(imported: false) }
        return .standard
    }
}

actor DemoPlanDraftProvider: PlanDraftProviding {
    enum Variant: Equatable, Sendable {
        /// The imported draft with a missing value (every older test).
        case standard
        /// A complete draft with the longer texts; `imported` says whose
        /// words they are.
        case longText(imported: Bool)
    }

    private let openDraftCount: Int
    private let origin: String
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

    init(openDraftCount: Int = 1, variant: Variant = .standard) {
        self.openDraftCount = openDraftCount
        switch variant {
        case .standard:
            origin = "imported_pdf"
        case let .longText(imported):
            origin = imported ? "imported_pdf" : "flow_generated"
            status = "ready_for_review"
            payload = Self.longTextPayload
        }
    }

    private static let longTextPayload: JSONValue = .object([
        "plan_type": .string("full_body"),
        "weekly_schedule": .array([
            .object([
                "day": .string("Treino A"),
                "focus": .string(DemoPlanDraftScenario.longFocus),
                "duration_min": .number(60),
                "exercises": .array([
                    .object([
                        "name": .string(DemoPlanDraftScenario.longExerciseName),
                        "muscle_group": .string(DemoPlanDraftScenario.longFocus),
                        "sets": .number(4),
                        "reps_range": .string(DemoPlanDraftScenario.repetitionsPhrase),
                        "rest_seconds": .number(90),
                        "rpe_target": .string("9"),
                    ]),
                    .object([
                        "name": .string(DemoPlanDraftScenario.longestExerciseName),
                        "muscle_group": .string("pernas"),
                        "sets": .number(3),
                        "reps_range": .string("10"),
                        "rest_seconds": .number(60),
                        "rpe_target": .string(DemoPlanDraftScenario.effortPhrase),
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
            origin: origin,
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
        return (1...openDraftCount).map { index in
            PlanDraftSummary(
                id: index == 1 ? DemoPlanDraftScenario.draftID
                    : String(format: "0d0d0d0d-1111-4222-8333-%012d", index),
                domain: .training,
                origin: origin,
                status: status,
                payloadVersion: version,
                createdAt: APITimestamp(value: Date(timeIntervalSince1970: 1_790_000_000))
            )
        }
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

/// Gives the layout scenario the real import route while refusing every
/// media operation. A UI test can open the screen; no file can leave the app.
struct DemoPlanDraftImportUnavailable: MealMediaProviding, StorageUploading {
    func create(_ attempt: MutationAttempt<MediaUploadRequest>) throws -> MediaCreateSnapshot {
        throw MealCaptureFailure.unavailable
    }
    func complete(_ attempt: MutationAttempt<MediaAssetCommand>) throws -> MediaAssetSnapshot {
        throw MealCaptureFailure.unavailable
    }
    func requestProcessing(_ attempt: MutationAttempt<MediaAssetCommand>) throws -> MediaAssetSnapshot {
        throw MealCaptureFailure.unavailable
    }
    func asset(id: String) throws -> MediaAssetSnapshot { throw MealCaptureFailure.unavailable }
    func delete(_ attempt: MutationAttempt<MediaAssetCommand>) throws { throw MealCaptureFailure.unavailable }
    func upload(_ media: StagedMedia, with ticket: MediaUploadTicket) throws {
        throw MealCaptureFailure.unavailable
    }
}
#endif
