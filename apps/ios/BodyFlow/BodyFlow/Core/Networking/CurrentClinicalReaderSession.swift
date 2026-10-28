import Foundation

/// One original Auth scope for all read surfaces in a clinical shell. A new
/// authentication activation creates a new bundle; an old bundle never rebinds.
struct CurrentClinicalReaderSession: Sendable {
    let userID: String
    let today: any TodayProviding
    let history: any HistoryProviding
    let plan: any PlanProviding
    let progress: any ProgressProviding
    let me: any MeProviding
    let currentObjective: any CurrentObjectiveProviding
}

struct CurrentClinicalReaderSessionFactory: Sendable {
    let bind: @Sendable (String) async throws -> CurrentClinicalReaderSession

    static func live(transport: MobileAPITransport,
                     lifecycle: any SessionLifecycleProviding) -> Self {
        Self { userID in
            try Task.checkCancellation()
            let lease = try await lifecycle.leaseForRequest()
            guard lease.userID == userID else { throw SessionLifecycleError.sessionSuperseded }
            try await lifecycle.validate(lease)
            let scoped = transport.scoped(to: lease)
            try await scoped.validateCurrentClinicalSession()
            let reads = MobileBodyFlowRepository(transport: scoped, clinicalRepresentation: .currentV1)
            let session = CurrentClinicalReaderSession(userID: userID, today: reads, history: reads,
                plan: MobileBodyFlowRepository(transport: scoped.withResponseBodyLimit(
                    MobileAPITransport.planResponseBodyLimit), clinicalRepresentation: .currentV1),
                progress: reads, me: reads,
                currentObjective: MobileCurrentObjectiveRepository(transport: scoped,
                    clinicalRepresentation: .currentV1))
            try await lifecycle.validate(lease)
            try Task.checkCancellation()
            return session
        }
    }
}
