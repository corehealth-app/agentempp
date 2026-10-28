import Foundation

/// Dedicated public requests, scoped once to the shell's original Auth subject.
/// Targets, phase origin, clinical proof, mean and owner are never request fields.
struct MobileClinicalFullRepository: ClinicalFullProviding {
    let transport: any MobileAPIExecuting
    let lifecycle: any SessionLifecycleProviding
    private var lease: SessionLease?
    static let base = "/api/mobile/v1/reevaluation"
    init(transport: any MobileAPIExecuting, lifecycle: any SessionLifecycleProviding) { self.transport = transport; self.lifecycle = lifecycle; lease = nil }
    func scoped(for userID: String) async throws -> any ClinicalFullProviding {
        if let lease { guard lease.userID == userID else { throw ClinicalFullFailure.sessionEnded }; try await lifecycle.validate(lease); return self }
        let lease = try await lifecycle.leaseForRequest()
        guard lease.userID == userID else { throw ClinicalFullFailure.sessionEnded }
        try await lifecycle.validate(lease)
        var copy = self
        if let mobile = transport as? MobileAPITransport { copy = .init(transport:mobile.scoped(to:lease),lifecycle:lifecycle) }
        copy.lease = lease; return copy
    }
    func entry() async throws -> ClinicalFullEntry {
        let value: ClinicalFullEntry = try await request(MobileAPIRequest(method:.get,path:Self.base))
        return try value.validated()
    }
    func start(reason: ClinicalFullStartReason?, key: IdempotencyKey) async throws -> ClinicalFullEntry {
        struct Input: Encodable {
            let reason: ClinicalFullStartReason?
            private enum CodingKeys: String,CodingKey { case reason }
            func encode(to encoder: any Encoder) throws { var c = encoder.container(keyedBy:CodingKeys.self); try c.encode(reason,forKey:.reason) }
        }
        try validKey(key)
        let value: ClinicalFullEntry = try await request(MobileAPIRequest(method:.post,path:Self.base+"/start",body:JSONEncoder().encode(Input(reason:reason)),idempotencyKey:key))
        // The actual kind can differ: resuming an EARLY at due promotes it.
        return try value.validated()
    }
    func describe(scope: ClinicalFullScope, purpose: ClinicalFullPurpose) async throws -> ClinicalFullQuestionnaire {
        struct Input: Encodable {
            let scope: ClinicalFullScope; let activityPurpose: ClinicalFullPurpose
            private enum CodingKeys: String,CodingKey { case kind, cycleId, activityPurpose }
            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy:CodingKeys.self)
                try c.encode(scope.kind,forKey:.kind); try c.encode(scope.cycleID,forKey:.cycleId); try c.encode(activityPurpose,forKey:.activityPurpose)
            }
        }
        _ = try scope.validated()
        let value: ClinicalFullQuestionnaire = try await request(MobileAPIRequest(method:.post,path:Self.base+"/form",body:JSONEncoder().encode(Input(scope:scope,activityPurpose:purpose))))
        guard value.kind == scope.kind, value.cycleID?.lowercased() == scope.cycleID?.lowercased(), value.activityPurpose == purpose else { throw ClinicalFullFailure.invalidResponse }
        return try value.validated()
    }
    private struct Command: Encodable {
        let draft: ClinicalFullDraft; let choice: ClinicalFullChoice?
        func encode(to encoder: any Encoder) throws { try draft.encode(to:encoder,choice:choice) }
    }
    private struct Input: Encodable {
        let scope: ClinicalFullScope; let input: Command; var previewID: String? = nil
        private enum CodingKeys: String,CodingKey { case kind, cycleId, input, previewId }
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy:CodingKeys.self)
            try c.encode(scope.kind,forKey:.kind); try c.encode(scope.cycleID,forKey:.cycleId); try c.encode(input,forKey:.input)
            if let previewID { try c.encode(previewID,forKey:.previewId) }
        }
    }
    private func input(scope: ClinicalFullScope, draft: ClinicalFullDraft, choice: ClinicalFullChoice? = nil, preview: ClinicalFullPreview? = nil) throws -> Data {
        _ = try scope.validated(); if let choice { _ = try choice.validated() }
        guard draft.belongs(to:scope) else { throw ClinicalFullFailure.changed }
        do { return try JSONEncoder().encode(Input(scope:scope,input:Command(draft:draft,choice:choice),previewID:preview?.previewID)) }
        catch { throw ClinicalFullFailure.invalidInput }
    }
    func assess(scope: ClinicalFullScope, draft: ClinicalFullDraft) async throws -> ClinicalFullAssessment {
        let value: ClinicalFullAssessment = try await request(MobileAPIRequest(method:.post,path:Self.base+"/assess",body:input(scope:scope,draft:draft)))
        return try value.validated()
    }
    func prepare(scope: ClinicalFullScope, draft: ClinicalFullDraft, choice: ClinicalFullChoice, key: IdempotencyKey) async throws -> ClinicalFullPreview {
        try validKey(key)
        let value: ClinicalFullPreview = try await request(MobileAPIRequest(method:.post,path:Self.base+"/preview",body:input(scope:scope,draft:draft,choice:choice),idempotencyKey:key))
        guard value.kind == scope.kind, value.cycleID?.lowercased() == scope.cycleID?.lowercased(), value.status != .ready || value.choice == choice else { throw ClinicalFullFailure.invalidResponse }
        return try value.validated()
    }
    func confirm(scope: ClinicalFullScope, draft: ClinicalFullDraft, choice: ClinicalFullChoice, preview: ClinicalFullPreview, key: IdempotencyKey) async throws -> ClinicalFullConfirmation {
        try validKey(key); _ = try preview.validated()
        guard preview.status == .ready, scope.matches(kind:preview.kind,cycleID:preview.cycleID), preview.choice == choice else { throw ClinicalFullFailure.invalidResponse }
        let value: ClinicalFullConfirmation = try await request(MobileAPIRequest(method:.post,path:Self.base+"/confirm",body:input(scope:scope,draft:draft,choice:choice,preview:preview),idempotencyKey:key))
        guard value.reviewID.lowercased() == preview.previewID.lowercased(), value.kind == scope.kind,
              scope.kind == .safety || value.cycleID?.lowercased() == scope.cycleID else { throw ClinicalFullFailure.invalidResponse }
        return try value.validated()
    }
    func declareHealth(items: [ClinicalFullHealthRisk], key: IdempotencyKey) async throws -> ClinicalFullHealthReceipt {
        struct Input: Encodable { let items: [ClinicalFullHealthRisk] }
        try validKey(key)
        guard !items.isEmpty, Set(items).count == items.count else { throw ClinicalFullFailure.invalidResponse }
        let ordered = ClinicalFullHealthRisk.allCases.filter { items.contains($0) }
        let value: ClinicalFullHealthReceipt = try await request(MobileAPIRequest(method:.post,path:Self.base+"/health",body:JSONEncoder().encode(Input(items:ordered)),idempotencyKey:key))
        return try value.validated()
    }
    func publish(_ operation: @MainActor @Sendable () throws -> Void) async throws {
        guard let lease else { throw ClinicalFullFailure.sessionEnded }
        try await lifecycle.performVisiblePatientStateOperation(lease:lease,operation:operation)
    }
    private func validKey(_ key: IdempotencyKey) throws { guard ClinicalFirstPhaseChoices.validID(key.value) else { throw ClinicalFullFailure.invalidResponse } }
    private func request<T: Decodable & Sendable>(_ request: MobileAPIRequest<T>) async throws -> T {
        guard let lease else { throw ClinicalFullFailure.sessionEnded }
        try await lifecycle.validate(lease); try Task.checkCancellation()
        let work = Task { try await transport.execute(request) }
        let workID: UUID
        do { workID = try await lifecycle.beginPatientWork(lease:lease,cancel:{ work.cancel() }) }
        catch { work.cancel(); throw ClinicalFullFailure.sessionEnded }
        do {
            let value = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            try Task.checkCancellation(); try await lifecycle.validate(lease); await lifecycle.finishPatientWork(workID)
            return value
        } catch {
            work.cancel(); await lifecycle.finishPatientWork(workID)
            if error is CancellationError { throw CancellationError() }
            do { try await lifecycle.validate(lease) } catch { throw ClinicalFullFailure.sessionEnded }
            if let value = error as? ClinicalFullFailure { throw value }
            if let value = error as? MobileAPITransportError {
                switch value {
                case .network, .timeout: throw ClinicalFullFailure.offline
                case .sessionSuperseded, .missingSession: throw ClinicalFullFailure.sessionEnded
                case .validation: throw ClinicalFullFailure.invalidInput
                case .http(let status,_,_) where [400,413,415].contains(status): throw ClinicalFullFailure.invalidInput
                case .conflict(let code,_):
                    if ["mobile_clinical_full_changed","mobile_health_hold_state_changed","mobile_reevaluation_state_changed"].contains(code) { throw ClinicalFullFailure.changed }
                    if code == "mobile_clinical_full_busy" { throw ClinicalFullFailure.busy }
                    fallthrough
                default: throw ClinicalFullFailure.unavailable
                }
            }
            throw ClinicalFullFailure.unavailable
        }
    }
}
