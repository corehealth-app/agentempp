import SwiftUI
import Observation

@MainActor
struct WorkoutStrengthQuestionConfiguration {
    struct Identity: Hashable { let context: ObjectIdentifier; let workoutID: String }
    let workoutID: String
    let identity: Identity
    private let session: WorkoutStrengthQuestionSession
    private let timeProvider: any TimeProviding
    private let keyProvider: any IdempotencyKeyProviding
    private let invalidationCenter: FeatureInvalidationCenter

    init(workoutID: String, identity: Identity, session: WorkoutStrengthQuestionSession,
         timeProvider: any TimeProviding, keyProvider: any IdempotencyKeyProviding,
         invalidationCenter: FeatureInvalidationCenter) {
        self.workoutID = workoutID
        self.identity = identity
        self.session = session
        self.timeProvider = timeProvider
        self.keyProvider = keyProvider
        self.invalidationCenter = invalidationCenter
    }
    func attach() throws -> WorkoutStrengthQuestionPresentation {
        try session.attach(workoutID: workoutID, timeProvider: timeProvider,
            keyProvider: keyProvider, invalidationCenter: invalidationCenter)
    }
}

@MainActor
enum WorkoutStrengthQuestionFactory {
    static func configuration(workoutID: String?, dependencies: AppDependencies,
                              context: WorkoutRegistrationReadyContext?,
                              invalidationCenter: FeatureInvalidationCenter) -> WorkoutStrengthQuestionConfiguration? {
        guard dependencies.presentsRealAccountIdentity, let workoutID,
              let id = WorkoutStrengthWire.uuid(workoutID), let context, context.isActive,
              context.registrationProtocol == .uiV1, let session = context.strengthQuestionSession() else { return nil }
        return WorkoutStrengthQuestionConfiguration(workoutID: id,
            identity: .init(context: ObjectIdentifier(context), workoutID: id), session: session,
            timeProvider: dependencies.timeProvider, keyProvider: dependencies.idempotencyKeyProvider,
            invalidationCenter: invalidationCenter)
    }
}

enum WorkoutStrengthQuestionAction: Equatable {
    case answer(WorkoutStrengthAnswer), refresh, retry, cancelWait
}

/// Owns every branch, including capacity recovery. Queued actions capture the
/// original appearance and lease before scheduling, so departure withdraws them.
@MainActor
@Observable
final class WorkoutStrengthQuestionHostState {
    let configuration: WorkoutStrengthQuestionConfiguration
    private(set) var presentation: WorkoutStrengthQuestionPresentation?
    private(set) var capacityUnavailable = false
    private var active = false
    private var appearance = UUID()
    private var actionTask: Task<Void, Never>?
    init(configuration: WorkoutStrengthQuestionConfiguration) { self.configuration = configuration }

    func open() async {
        guard !Task.isCancelled else { return }
        close()
        active = true
        let token = UUID()
        appearance = token
        await attach(appearance: token)
    }
    func close() {
        active = false
        appearance = UUID()
        actionTask?.cancel()
        actionTask = nil
        presentation?.end()
        presentation = nil
        capacityUnavailable = false
    }
    private func attach(appearance token: UUID) async {
        guard active, appearance == token, !Task.isCancelled else { return }
        do {
            let lease = try configuration.attach()
            presentation = lease
            capacityUnavailable = false
            await lease.refresh()
        } catch WorkoutStrengthQuestionSessionError.capacityUnavailable {
            guard active, appearance == token, !Task.isCancelled else { return }
            capacityUnavailable = true
        } catch { /* Invalid/retired context never retargets a question. */ }
    }
    @discardableResult
    func retryAttachment() -> Task<Void, Never>? {
        guard active, capacityUnavailable else { return nil }
        let token = appearance
        actionTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.attach(appearance: token)
        }
        actionTask = task
        return task
    }
    @discardableResult
    func perform(_ action: WorkoutStrengthQuestionAction, lease: WorkoutStrengthQuestionPresentation) -> Task<Void, Never>? {
        guard active, presentation === lease, lease.isCurrent else { return nil }
        if action == .cancelWait {
            lease.cancelWait()
            actionTask?.cancel()
            return nil
        }
        guard !lease.model.isBusy else { return nil }
        let token = appearance
        actionTask?.cancel()
        let task = Task { [weak self] in
            guard let self, self.active, self.appearance == token,
                  self.presentation === lease, lease.isCurrent, !Task.isCancelled else { return }
            switch action {
            case let .answer(value): await lease.answer(value)
            case .refresh: await lease.refresh()
            case .retry: await lease.retryAnswer()
            case .cancelWait: break
            }
        }
        actionTask = task
        return task
    }
}

@MainActor
struct WorkoutStrengthQuestionHost: View {
    let configuration: WorkoutStrengthQuestionConfiguration
    var showsRegistrationFeedback = false
    var body: some View {
        WorkoutStrengthQuestionActiveHost(configuration: configuration,
            showsRegistrationFeedback: showsRegistrationFeedback).id(configuration.identity)
    }
}

@MainActor
private struct WorkoutStrengthQuestionActiveHost: View {
    @State private var state: WorkoutStrengthQuestionHostState
    let showsRegistrationFeedback: Bool
    @Environment(\.locale) private var locale
    init(configuration: WorkoutStrengthQuestionConfiguration, showsRegistrationFeedback: Bool) {
        self.showsRegistrationFeedback = showsRegistrationFeedback
        _state = State(initialValue: WorkoutStrengthQuestionHostState(configuration: configuration))
    }
    var body: some View {
        VStack(spacing: BodyFlowSpacing.md) {
            if let lease = state.presentation {
                if showsRegistrationFeedback, let feedback = lease.historyFeedback {
                    BodyFlowCard { OriginalRegistrationFeedbackView(feedback: feedback) }
                }
                WorkoutStrengthQuestionCard(presentation: lease) { _ = state.perform($0, lease: lease) }
            } else if state.capacityUnavailable {
                BodyFlowCard {
                    VStack(spacing: BodyFlowSpacing.sm) {
                        BodyFlowStatusLine(copy("workout.strength.capacity"), kind: .error)
                        Button(copy("workout.strength.refresh")) { _ = state.retryAttachment() }
                            .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                    }
                }
            }
        }
        .task { await state.open() }
        .onDisappear { state.close() }
    }
    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(key, language: BodyFlowPresentationLanguage.resolve(locale))
    }
}

/// The card consumes this descriptor directly. It contains only presentation,
/// never authority, client-side classification or a mutation side effect.
@MainActor
struct WorkoutStrengthQuestionDescriptor {
    struct Message { let text: String; let kind: BodyFlowStatusLine.Kind }
    struct Action {
        let id: String
        let title: String
        let value: WorkoutStrengthQuestionAction
        let role: BodyFlowButtonRole
        let enabled: Bool
    }
    let title: String
    let note: String
    private(set) var question: String?
    private(set) var messages: [Message] = []
    private(set) var actions: [Action] = []
    let isHidden: Bool

    init(presentation: WorkoutStrengthQuestionPresentation, language: SupportedAppLanguage) {
        func copy(_ key: String.LocalizationValue) -> String { RegistrationCopy.string(key, language: language) }
        let model = presentation.model
        title = copy("workout.strength.title")
        note = copy("workout.strength.saved")
        let negative: Bool
        switch model.snapshot { case .notApplicable?, .unavailable?: negative = true; default: negative = false }
        isHidden = !presentation.isCurrent || model.failure == .disabled || (negative && model.failure == nil)
        guard !isHidden else { return }
        func button(_ key: String.LocalizationValue, _ id: String, _ value: WorkoutStrengthQuestionAction,
                    _ role: BodyFlowButtonRole = .primary, enabled: Bool = true) -> Action {
            Action(id: "workout.strength.\(id)", title: copy(key), value: value, role: role, enabled: enabled)
        }
        var errors: [Message] = []
        if let failure = model.failure {
            let key: String.LocalizationValue = switch failure {
            case .contextUnavailable: "workout.strength.context-changed"
            case .answerConflict: "workout.strength.conflict"
            case .disabled, .capability: "workout.strength.error"
            }
            errors = [Message(text: copy(key), kind: .error)]
        }
        if model.isBusy {
            messages = [Message(text: copy(model.isSubmitting ? "workout.strength.saving" : "workout.strength.loading"), kind: .pending),
                        Message(text: copy("workout.strength.cancel-hint"), kind: .info)]
            actions = [button("workout.strength.cancel", "cancel", .cancelWait, .tertiary)]
        } else if !presentation.isReady {
            messages = errors.isEmpty ? [Message(text: copy("workout.strength.read-required"), kind: .info)] : errors
            actions = [button("workout.strength.refresh", "refresh", .refresh)]
        } else if model.pendingAttempt != nil {
            messages = [Message(text: copy("workout.strength.uncertain"), kind: .warning)] + errors
            actions = [button("workout.strength.refresh", "refresh", .refresh)]
            if presentation.canRetryAnswer { actions.append(button("workout.strength.retry", "retry", .retry, .secondary)) }
        } else if case let .answered(receipt) = model.snapshot {
            messages = [Message(text: copy(receipt.answer == .yes ? "workout.strength.answer-yes" : "workout.strength.answer-no"), kind: .success)]
        } else if case .unanswered = model.snapshot {
            question = copy("workout.strength.question")
            messages = errors
            actions = [button("workout.strength.yes", "yes", .answer(.yes), .secondary, enabled: presentation.canAnswer),
                       button("workout.strength.no", "no", .answer(.no), .secondary, enabled: presentation.canAnswer)]
            if model.failure != nil { actions.append(button("workout.strength.refresh", "refresh", .refresh)) }
        }
    }
}

@MainActor
struct WorkoutStrengthQuestionCard: View {
    let presentation: WorkoutStrengthQuestionPresentation
    let action: (WorkoutStrengthQuestionAction) -> Void
    @Environment(\.locale) private var locale
    var body: some View {
        let descriptor = WorkoutStrengthQuestionDescriptor(presentation: presentation,
            language: BodyFlowPresentationLanguage.resolve(locale))
        if !descriptor.isHidden {
            BodyFlowCard {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    Text(verbatim: descriptor.title).font(BodyFlowTypography.cardTitle)
                        .foregroundStyle(BodyFlowColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    Text(verbatim: descriptor.note).font(BodyFlowTypography.supporting)
                        .foregroundStyle(BodyFlowColor.secondaryText).fixedSize(horizontal: false, vertical: true)
                    if let question = descriptor.question {
                        Text(verbatim: question).font(BodyFlowTypography.body)
                            .foregroundStyle(BodyFlowColor.primaryText).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("workout.strength.question")
                    }
                    ForEach(Array(descriptor.messages.enumerated()), id: \.offset) { _, message in
                        BodyFlowStatusLine(message.text, kind: message.kind)
                    }
                    ForEach(descriptor.actions, id: \.id) { item in
                        Button(item.title) { action(item.value) }
                            .buttonStyle(BodyFlowButtonStyle(role: item.role))
                            .disabled(!item.enabled).accessibilityLabel(item.title).accessibilityIdentifier(item.id)
                    }
                }
            }
            .accessibilityElement(children: .contain).accessibilityIdentifier("workout.strength")
        }
    }
}
