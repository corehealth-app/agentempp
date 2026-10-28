import Foundation
import Observation

@MainActor @Observable
final class ClinicalFullModel {
    private(set) var entry: ClinicalFullEntry?
    private(set) var scope: ClinicalFullScope?
    private(set) var questionnaire: ClinicalFullQuestionnaire?
    private(set) var draft: ClinicalFullDraft?
    private(set) var assessment: ClinicalFullAssessment?
    private(set) var preview: ClinicalFullPreview?
    private(set) var confirmation: ClinicalFullConfirmation?
    private(set) var healthReceipt: ClinicalFullHealthReceipt?
    private(set) var error: ClinicalFullFailure?
    private(set) var isBusy = false
    private(set) var inputs = ClinicalFullInputState()
    private var ended = false
    private var needsReentry = false
    private var mutationUncertain = false
    private let userID: String
    private let source: any ClinicalFullProviding
    private let keys: any IdempotencyKeyProviding
    private var provider: (any ClinicalFullProviding)?
    private struct Start { let reason: ClinicalFullStartReason?; let key: IdempotencyKey }
    private struct Prepare { let scope: ClinicalFullScope; let draft: ClinicalFullDraft; let choice: ClinicalFullChoice; let key: IdempotencyKey }
    private struct Confirm { let input: Prepare; let preview: ClinicalFullPreview; let key: IdempotencyKey }
    private struct Health { let items: [ClinicalFullHealthRisk]; let key: IdempotencyKey }
    private var pendingStart: Start?
    private var pendingPrepare: Prepare?
    private var pendingConfirm: Confirm?
    private var pendingHealth: Health?
    private let photoCapability:ReevaluationPhotoCaptureCapability?
    private(set) var photos:ReevaluationPhotoModel?
    private var photoRefreshRequired = false
    private var photoMutationEpoch = UUID()
    var hasUncertainMutation: Bool { pendingStart != nil || (pendingPrepare != nil && preview == nil) || pendingConfirm != nil || pendingHealth != nil }
    var canOpenPhotos:Bool { !ended && !isBusy && !hasUncertainMutation && preview == nil && confirmation == nil && questionnaire != nil }
    var canEdit: Bool { canOpenPhotos && !photoRefreshRequired && photos?.hasBlockingWork != true }
    init(userID: String, provider: any ClinicalFullProviding, keyProvider: any IdempotencyKeyProviding,photoCapability:ReevaluationPhotoCaptureCapability? = nil) {
        self.userID = userID; source = provider; keys = keyProvider; self.photoCapability = photoCapability
    }
    private func scoped() async throws -> any ClinicalFullProviding {
        guard !ended else { throw ClinicalFullFailure.sessionEnded }
        if let provider { return provider }
        let bound = try await source.scoped(for:userID)
        guard !ended else { throw CancellationError() }
        provider = bound; return bound
    }
    func loadEntry() async {
        guard !ended, !isBusy, !hasUncertainMutation else { return }
        isBusy = true; error = nil; defer { isBusy = false }
        do {
            let provider = try await scoped(), value = try await provider.entry().validated()
            try await provider.publish { [self] in guard !ended else { throw CancellationError() }; entry = value }
        } catch { await failed(error) }
    }
    /// A resume has a NEW stable key with no claimed early reason. SQL may
    /// return the existing EARLY occurrence or promote it to REGULAR.
    func start(reason: ClinicalFullStartReason? = nil) async {
        guard !ended, !isBusy, pendingPrepare == nil, pendingConfirm == nil, pendingHealth == nil, confirmation == nil else { return }
        if let pendingStart, pendingStart.reason != reason { return }
        isBusy = true; error = nil; defer { isBusy = false }
        do {
            if pendingStart == nil { pendingStart = Start(reason:reason,key:try keys.nextKey()); mutationUncertain = false }
            guard let attempt = pendingStart else { return }
            let provider = try await scoped(), value = try await provider.start(reason:attempt.reason,key:attempt.key).validated()
            try await provider.publish { [self] in
                guard !ended else { throw CancellationError() }
                entry = value; pendingStart = nil; needsReentry = false; mutationUncertain = false
                guard value.availability == .available, let actual = value.cycle?.scope else {
                    photos?.invalidate(); photos = nil; photoRefreshRequired = false
                    scope = nil; questionnaire = nil; draft = nil; assessment = nil; preview = nil; return
                }
                if scope != actual { draft = nil; inputs = ClinicalFullInputState(); photos?.invalidate(); photos = nil; photoRefreshRequired = false }
                scope = actual; questionnaire = nil; assessment = nil; preview = nil
            }
            if let scope { try await readForm(provider,scope:scope) }
        } catch { await failed(error) }
    }
    private func readForm(_ provider: any ClinicalFullProviding, scope: ClinicalFullScope) async throws {
        let photoEpoch = photoMutationEpoch
        let purpose = draft?.activityPurpose ?? .normal
        let form = try await provider.describe(scope:scope,purpose:purpose).validated()
        guard scope.matches(kind:form.kind,cycleID:form.cycleID), form.activityPurpose == purpose else { throw ClinicalFullFailure.invalidResponse }
        var next = draft ?? ClinicalFullDraft(questionnaire:form)
        try next.refresh(from:form)
        let updated = next
        try await provider.publish { [self] in
            guard !ended else { throw CancellationError() }
            questionnaire = form; draft = updated; inputs.refresh(form); assessment = nil
            configurePhotos(provider,scope:scope,required:form.photoRequirement.required)
            if photoMutationEpoch == photoEpoch && photos?.hasPendingIntent != true { photoRefreshRequired = false }
        }
    }
    private func configurePhotos(_ provider:any ClinicalFullProviding,scope:ClinicalFullScope,required:Bool) {
        guard required, scope.kind.requiresNewPhotos, let cycle = scope.cycleID, let photoCapability else {
            photos?.invalidate(); photos = nil; return
        }
        if photos?.cycleID == cycle { return }
        photos?.invalidate()
        let original = ReevaluationPhotoCaptureCapability { [weak self] user,requestedCycle in
            let validate:@MainActor @Sendable () throws -> Void = { [weak self] in
                guard let self, !self.ended, self.scope == scope, user == self.userID, requestedCycle == cycle else { throw CancellationError() }
            }
            // Check the parent's ORIGINAL lease before and after binding. A
            // fresh A session cannot become this older form's photo authority.
            try await provider.publish(validate)
            let bound = try await photoCapability.scoped(user,requestedCycle)
            try await provider.publish(validate)
            return bound
        }
        photos = ReevaluationPhotoModel(userID:userID,cycleID:cycle,capability:original,keys:keys,
            onMutation:{ [weak self] in
                guard let self, !self.ended, self.scope == scope else { return }
                self.photoRefreshRequired = true; self.photoMutationEpoch = UUID()
                self.draft?.revokeBodyFatAcceptance(); self.assessment = nil
            },onReconciled:{ [weak self] in await self?.reloadForm() })
    }
    func reloadForm() async {
        guard !ended, !isBusy, !hasUncertainMutation, preview == nil, confirmation == nil, let scope else { return }
        isBusy = true; error = nil; defer { isBusy = false }
        do { let provider = try await scoped(); try await readForm(provider,scope:scope) } catch { await failed(error) }
    }
    func edit(_ change: (inout ClinicalFullDraft) -> Void) {
        guard canEdit, var next = draft else { return }
        change(&next); draft = next; assessment = nil; error = nil
    }
    func setText(_ text: String, question: ClinicalFullQuestion, language: SupportedAppLanguage) {
        guard canEdit, questionnaire?.questions.contains(question) == true, var draft else { return }
        inputs.setText(text,question:question,draft:&draft,language:language)
        self.draft = draft; assessment = nil; error = nil
    }
    func selectOption(_ option: ClinicalFullOptionValue?, question: ClinicalFullQuestion) {
        guard questionnaire?.questions.contains(question) == true else { return }
        edit { ClinicalFullInputState.select(option,question:question,draft:&$0) }
    }
    func selectPreference(_ token: String, language: SupportedAppLanguage) {
        guard canEdit, let questionnaire, var draft else { return }
        inputs.selectPreference(token,form:questionnaire,draft:&draft,language:language)
        self.draft = draft; assessment = nil; error = nil
    }
    func setPreferenceText(_ text: String, language: SupportedAppLanguage) {
        guard canEdit, var draft else { return }
        inputs.setPreferenceText(text,draft:&draft,language:language)
        self.draft = draft; assessment = nil; error = nil
    }
    func setPreferenceRoutine(_ token: String) {
        guard canEdit, let questionnaire, var draft else { return }
        inputs.setPreferenceRoutine(token,form:questionnaire,draft:&draft)
        self.draft = draft; assessment = nil; error = nil
    }
    func changePurpose(_ purpose: ClinicalFullPurpose) async {
        guard canEdit, let scope, let questionnaire,
              (questionnaire.purposeOptions ?? [questionnaire.activityPurpose]).contains(purpose) else { return }
        isBusy = true; error = nil; defer { isBusy = false }
        do {
            let provider = try await scoped(), form = try await provider.describe(scope:scope,purpose:purpose).validated()
            guard scope.matches(kind:form.kind,cycleID:form.cycleID), form.activityPurpose == purpose else { throw ClinicalFullFailure.invalidResponse }
            var updated = draft ?? ClinicalFullDraft(questionnaire:form)
            try updated.refresh(from:form)
            let value = updated
            try await provider.publish { [self] in guard !ended else { throw CancellationError() }; self.questionnaire = form; draft = value; inputs.refresh(form); assessment = nil }
        } catch { await failed(error) }
    }
    func assess() async {
        guard canEdit, !inputs.hasInvalidValues, let scope, let draft else { return }
        isBusy = true; error = nil; defer { isBusy = false }
        do {
            let provider = try await scoped(), value = try await provider.assess(scope:scope,draft:draft).validated()
            try await provider.publish { [self] in guard !ended else { throw CancellationError() }; assessment = value }
        } catch { await failed(error) }
    }
    func prepare(_ choice: ClinicalFullChoice) async {
        guard !ended, !isBusy, pendingStart == nil, pendingHealth == nil, pendingConfirm == nil, confirmation == nil, preview == nil else { return }
        if let pendingPrepare { guard pendingPrepare.choice == choice else { return } }
        else { guard assessment?.status == .available, assessment?.actions.contains(where:{ $0.choice == choice }) == true else { return } }
        isBusy = true; error = nil; defer { isBusy = false }
        do {
            if pendingPrepare == nil, let scope, let draft { pendingPrepare = Prepare(scope:scope,draft:draft,choice:choice,key:try keys.nextKey()); mutationUncertain = false }
            guard let attempt = pendingPrepare else { return }
            let provider = try await scoped(), value = try await provider.prepare(scope:attempt.scope,draft:attempt.draft,choice:attempt.choice,key:attempt.key).validated()
            guard attempt.scope.matches(kind:value.kind,cycleID:value.cycleID), value.status != .ready || value.choice == attempt.choice else { throw ClinicalFullFailure.invalidResponse }
            try await provider.publish { [self] in guard !ended else { throw CancellationError() }; preview = value; mutationUncertain = false }
        } catch { await failed(error) }
    }
    func confirm() async {
        guard !ended, !isBusy, confirmation == nil, let preview, preview.status == .ready, let prepared = pendingPrepare,
              pendingStart == nil, pendingHealth == nil else { return }
        isBusy = true; error = nil; defer { isBusy = false }
        do {
            if pendingConfirm == nil { pendingConfirm = Confirm(input:prepared,preview:preview,key:try keys.nextKey()); mutationUncertain = false }
            guard let attempt = pendingConfirm else { return }
            let provider = try await scoped(), input = attempt.input
            let value = try await provider.confirm(scope:input.scope,draft:input.draft,choice:input.choice,preview:attempt.preview,key:attempt.key).validated()
            guard value.reviewID.lowercased() == attempt.preview.previewID.lowercased(), value.kind == input.scope.kind,
                  input.scope.kind == .safety || value.cycleID?.lowercased() == input.scope.cycleID else { throw ClinicalFullFailure.invalidResponse }
            try await provider.publish { [self] in guard !ended else { throw CancellationError() }; confirmation = value; pendingConfirm = nil; mutationUncertain = false }
        } catch { await failed(error) }
    }
    func declareHealth() async {
        guard !ended, !isBusy, preview == nil, confirmation == nil, pendingStart == nil, pendingPrepare == nil, pendingConfirm == nil else { return }
        if pendingHealth == nil {
            guard questionnaire?.questions.contains(where:{ $0.key == .healthCheck }) == true,
                  assessment?.status == .healthDeclarationRequired, case .risks(let items) = draft?.answers.healthCheck else { return }
            do { pendingHealth = Health(items:ClinicalFullHealthRisk.allCases.filter { items.contains($0) },key:try keys.nextKey()); mutationUncertain = false }
            catch { await failed(error); return }
        }
        isBusy = true; error = nil; defer { isBusy = false }
        do {
            guard let attempt = pendingHealth else { return }
            let provider = try await scoped(), value = try await provider.declareHealth(items:attempt.items,key:attempt.key).validated()
            try await provider.publish { [self] in guard !ended else { throw CancellationError() }; healthReceipt = value; pendingHealth = nil; assessment = nil; mutationUncertain = false }
            if let scope { try await readForm(provider,scope:scope) }
        } catch { await failed(error) }
    }
    func backToDraft() {
        guard !ended, !isBusy, !hasUncertainMutation, confirmation == nil else { return }
        preview = nil; pendingPrepare = nil; assessment = nil; error = nil; mutationUncertain = false
    }
    func retry() async {
        if let pendingStart { await start(reason:pendingStart.reason) }
        else if pendingHealth != nil { await declareHealth() }
        else if pendingConfirm != nil { await confirm() }
        else if let pendingPrepare { await prepare(pendingPrepare.choice) }
        else if needsReentry { await start() }
        else if scope != nil, questionnaire == nil { await reloadForm() }
        else { await loadEntry() }
    }
    func closeCompleted() {
        guard !ended, !isBusy, !hasUncertainMutation, confirmation != nil else { return }
        photos?.invalidate(); photos = nil; photoRefreshRequired = false
        confirmation = nil; entry = nil; questionnaire = nil; draft = nil; assessment = nil; preview = nil; scope = nil; inputs = ClinicalFullInputState(); pendingPrepare = nil; mutationUncertain = false
    }
    func invalidate() {
        photos?.invalidate(); photos = nil; photoRefreshRequired = false
        ended = true; entry = nil; scope = nil; questionnaire = nil; draft = nil; assessment = nil; preview = nil; confirmation = nil; healthReceipt = nil; inputs = ClinicalFullInputState()
        pendingStart = nil; pendingPrepare = nil; pendingConfirm = nil; pendingHealth = nil; provider = nil; error = nil; mutationUncertain = false
    }
    private func failed(_ failure: any Error) async {
        if ended { return }
        // Cancellation can arrive after the server committed. Retain the exact
        // intent even if a later retry rejects its input; only a known conflict
        // or its original receipt resolves that uncertainty.
        if failure is CancellationError || Task.isCancelled {
            if hasUncertainMutation { mutationUncertain = true }
            return
        }
        if failure as? ClinicalFullFailure == .sessionEnded || failure is SessionLifecycleError { invalidate(); return }
        guard let provider else { error = failure as? ClinicalFullFailure ?? .unavailable; return }
        do {
            try await provider.publish { [self] in
                guard !ended else { throw CancellationError() }
                error = failure as? ClinicalFullFailure ?? .unavailable
                if error == .changed {
                    photos?.invalidate(); photos = nil; photoRefreshRequired = false
                    entry = nil; questionnaire = nil; assessment = nil; preview = nil
                    pendingStart = nil; pendingPrepare = nil; pendingConfirm = nil; pendingHealth = nil; needsReentry = true; mutationUncertain = false
                }
                if error == .invalidInput && !mutationUncertain {
                    pendingStart = nil; pendingPrepare = nil; pendingConfirm = nil; pendingHealth = nil; preview = nil; assessment = nil
                }
                if error != .changed && error != .invalidInput,
                   pendingStart != nil || pendingPrepare != nil || pendingConfirm != nil || pendingHealth != nil { mutationUncertain = true }
            }
        } catch { invalidate() }
    }
}
