import Observation

@MainActor
@Observable
final class MascotExperienceViewModel {
    private let provider: any CoachExperienceProviding
    private let controller = FeatureRevisionLoadController<CoachExperienceResponse>()
    private var currentRevision = 0

    private(set) var state: FeatureReadState<MascotExperiencePresentation> = .idle

    init(provider: any CoachExperienceProviding) {
        self.provider = provider
    }

    func load(revision: Int) async {
        guard !Task.isCancelled else { return }
        currentRevision = max(currentRevision, revision)
        if case .idle = state {
            state = .loading
        }

        await controller.load(
            revision: revision,
            operation: { [provider] in
                try await provider.coachExperience()
            },
            publish: publish
        )
    }

    func retry() async {
        await controller.retry(
            revision: currentRevision,
            operation: { [provider] in
                try await provider.coachExperience()
            },
            publish: publish
        )
    }

    private func publish(
        _ completion: FeatureLoadCompletion<CoachExperienceResponse>
    ) {
        switch completion {
        case let .value(response):
            guard let snapshot = CoachExperienceV1PresentationContract
                .validatedSnapshot(from: response),
                  Self.isConsistent(snapshot)
            else {
                state = .failed(
                    previousValue: currentPresentation,
                    error: .unsupportedCoachContract
                )
                return
            }

            state = .loaded(MascotExperiencePresentation(snapshot: snapshot))
        case let .failure(error):
            state = Self.readState(
                for: error,
                previousValue: currentPresentation
            )
        }
    }

    private static func isConsistent(
        _ snapshot: CoachExperienceSnapshot
    ) -> Bool {
        let optionCodes = snapshot.options.map(\.code)
        guard optionCodes.count == 3,
              optionCodes.filter({ $0 == .focus }).count == 1,
              optionCodes.filter({ $0 == .impulse }).count == 1,
              optionCodes.filter({ $0 == .zen }).count == 1
        else {
            return false
        }

        switch snapshot.selected {
        case .none:
            return snapshot.effective == .balanced
        case .focus:
            return snapshot.effective == .focus
        case .impulse:
            return snapshot.effective == .impulse
        case .zen:
            return snapshot.effective == .zen
        }
    }

    private static func readState(
        for error: any Error,
        previousValue: MascotExperiencePresentation?
    ) -> FeatureReadState<MascotExperiencePresentation> {
        let capabilityError = error as? BodyFlowCapabilityError
            ?? .serviceUnavailable

        switch capabilityError {
        case .operationUnavailable:
            return .unavailable
        case .offline:
            return .offline(previousValue: previousValue)
        default:
            return .failed(
                previousValue: previousValue,
                error: capabilityError
            )
        }
    }

    private var currentPresentation: MascotExperiencePresentation? {
        state.presentation.value
    }
}
