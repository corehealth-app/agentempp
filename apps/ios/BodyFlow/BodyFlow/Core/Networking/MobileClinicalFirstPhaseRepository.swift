import Foundation

/// Dedicated public DTOs only; client requests contain a choice/opaque preview,
/// never calories, formula inputs, health answers or private context hashes.
struct MobileClinicalFirstPhaseRepository: ClinicalFirstPhaseProviding {
    let transport: any MobileAPIExecuting
    let lifecycle: any SessionLifecycleProviding
    private var lease: SessionLease?
    init(transport: any MobileAPIExecuting, lifecycle: any SessionLifecycleProviding) {
        self.transport = transport; self.lifecycle = lifecycle; lease = nil
    }
    func scoped(for userID: String) async throws -> any ClinicalFirstPhaseProviding {
        if let lease {
            guard lease.userID == userID else { throw ClinicalFirstPhaseFailure.sessionEnded }
            try await lifecycle.validate(lease)
            return self
        }
        let lease = try await lifecycle.leaseForRequest()
        guard lease.userID == userID else { throw ClinicalFirstPhaseFailure.sessionEnded }
        try await lifecycle.validate(lease)
        var copy = self
        if let mobile = transport as? MobileAPITransport { copy = .init(transport: mobile.scoped(to: lease), lifecycle: lifecycle) }
        copy.lease = lease
        return copy
    }
    func choices() async throws -> ClinicalFirstPhaseChoices {
        let value: ClinicalFirstPhaseChoices = try await request(MobileAPIRequest(method: .get, path: Self.base))
        return try value.validated()
    }
    func prepare(phase: BodyFlowObjective, key: IdempotencyKey) async throws -> ClinicalFirstPhasePreview {
        struct Input: Encodable { let phase: BodyFlowObjective }
        guard ClinicalFirstPhaseChoices.validID(key.value) else { throw ClinicalFirstPhaseFailure.invalidResponse }
        let value: ClinicalFirstPhasePreview = try await request(MobileAPIRequest(method: .post, path: Self.base + "/preview",
            body: JSONEncoder().encode(Input(phase: phase)), idempotencyKey: key))
        guard value.phase == phase else { throw ClinicalFirstPhaseFailure.invalidResponse }
        return try value.validated()
    }
    func confirm(preview: ClinicalFirstPhasePreview, key: IdempotencyKey) async throws -> ClinicalFirstPhaseConfirmation {
        struct Input: Encodable { let preview_id: String; let phase: BodyFlowObjective }
        _ = try preview.validated()
        guard ClinicalFirstPhaseChoices.validID(key.value) else { throw ClinicalFirstPhaseFailure.invalidResponse }
        let value: ClinicalFirstPhaseConfirmation = try await request(MobileAPIRequest(method: .post, path: Self.base + "/confirm",
            body: JSONEncoder().encode(Input(preview_id: preview.previewID, phase: preview.phase)), idempotencyKey: key))
        guard value.confirmationID == preview.previewID, value.phase == preview.phase,
              value.effectiveDate == preview.effectiveDate else { throw ClinicalFirstPhaseFailure.invalidResponse }
        return try value.validated()
    }
    func publish(_ operation: @MainActor @Sendable () throws -> Void) async throws {
        guard let lease else { throw ClinicalFirstPhaseFailure.sessionEnded }
        try await lifecycle.performVisiblePatientStateOperation(lease: lease, operation: operation)
    }
    private static let base = "/api/mobile/v1/protocol/first-phase"
    private func request<T: Decodable & Sendable>(_ request: MobileAPIRequest<T>) async throws -> T {
        guard let lease else { throw ClinicalFirstPhaseFailure.sessionEnded }
        try await lifecycle.validate(lease)
        try Task.checkCancellation()
        let work = Task { try await transport.execute(request) }
        let workID: UUID
        do { workID = try await lifecycle.beginPatientWork(lease: lease, cancel: { work.cancel() }) }
        catch { work.cancel(); throw ClinicalFirstPhaseFailure.sessionEnded }
        do {
            let value = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            try Task.checkCancellation(); try await lifecycle.validate(lease)
            await lifecycle.finishPatientWork(workID)
            return value
        } catch {
            work.cancel(); await lifecycle.finishPatientWork(workID)
            if error is CancellationError { throw CancellationError() }
            do { try await lifecycle.validate(lease) } catch { throw ClinicalFirstPhaseFailure.sessionEnded }
            if let failure = error as? ClinicalFirstPhaseFailure { throw failure }
            if let failure = error as? MobileAPITransportError {
                switch failure {
                case .network, .timeout: throw ClinicalFirstPhaseFailure.offline
                case .sessionSuperseded, .missingSession: throw ClinicalFirstPhaseFailure.sessionEnded
                case .conflict(let code, _):
                    if code == "mobile_clinical_first_phase_changed" { throw ClinicalFirstPhaseFailure.changed }
                    if code == "mobile_clinical_first_phase_busy" { throw ClinicalFirstPhaseFailure.busy }
                    fallthrough
                default: throw ClinicalFirstPhaseFailure.unavailable
                }
            }
            throw ClinicalFirstPhaseFailure.unavailable
        }
    }
}
