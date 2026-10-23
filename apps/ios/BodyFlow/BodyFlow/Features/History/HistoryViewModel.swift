import Foundation
import Observation

struct HistoryPresentation: Equatable, Sendable {
    let meals: [HistoryMealLogRow]
    let workouts: [HistoryWorkoutLogRow]
    let language: SupportedAppLanguage

    init(
        snapshot: HistorySnapshot,
        language: SupportedAppLanguage = .portugueseBrazil
    ) {
        meals = snapshot.meals
        workouts = snapshot.workouts
        self.language = language
    }

    var isGloballyEmpty: Bool {
        meals.isEmpty && workouts.isEmpty
    }

    var sectionTitles: [String] {
        [
            HistoryCopy.string("history.meals.title", language: language),
            HistoryCopy.string("history.workouts.title", language: language),
        ]
    }
}

struct HistoryValuePresentation: Equatable, Sendable {
    let language: SupportedAppLanguage

    func quantity(_ value: Decimal?, metadata: MealQuantityDisplay? = nil, name: String = "") -> String? {
        let presentation = MealQuantityValue(grams: value, metadata: metadata, name: name)
        if presentation.usesReference { return presentation.label(language: language) }
        return decimal(value, key: "history.meal.quantity-format")
    }

    func energy(_ value: Decimal?) -> String? {
        decimal(value, key: "history.meal.energy-format")
    }

    func duration(_ value: Int?) -> String? {
        integer(value, key: "history.workout.duration-format")
    }

    func estimatedEnergy(_ value: Int?) -> String? {
        integer(value, key: "history.workout.energy-format")
    }

    /// The stored workout type as a label ("musculacao" reads "Musculação").
    func workoutType(_ stored: String?) -> String? {
        stored.map { RegistrationCopy.workoutTypeTitle(stored: $0, language: language) }
    }

    private func decimal(
        _ value: Decimal?,
        key: String.LocalizationValue
    ) -> String? {
        guard let value else { return nil }
        return String(
            format: HistoryCopy.string(key, language: language),
            locale: language.formattingLocale,
            NSDecimalNumber(decimal: value).stringValue
        )
    }

    private func integer(
        _ value: Int?,
        key: String.LocalizationValue
    ) -> String? {
        guard let value else { return nil }
        return String(
            format: HistoryCopy.string(key, language: language),
            locale: language.formattingLocale,
            value
        )
    }
}

enum HistoryCopy {
    static func string(
        _ key: String.LocalizationValue,
        language: SupportedAppLanguage
    ) -> String {
        (try? AppLocalization.string(key, for: language)) ?? String(localized: key)
    }
}

@MainActor
@Observable
final class HistoryViewModel {
    private let provider: any HistoryProviding
    private let controller = FeatureRevisionLoadController<HistoryResponse>()

    private(set) var state: FeatureReadState<HistorySnapshot> = .idle

    init(provider: any HistoryProviding) {
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
                try await provider.history(.firstPage)
            },
            publish: publish
        )
    }

    func retry() async {
        await controller.retry(
            revision: currentRevision,
            operation: { [provider] in
                try await provider.history(.firstPage)
            },
            publish: publish
        )
    }

    func mealLogRow(id: String) -> HistoryMealLogRow? {
        currentSnapshot?.meals.first { $0.id == id }
    }

    func workoutLogRow(id: String) -> HistoryWorkoutLogRow? {
        currentSnapshot?.workouts.first { $0.id == id }
    }

    var currentSnapshot: HistorySnapshot? {
        switch state {
        case let .loaded(snapshot),
             let .offline(previousValue: snapshot?),
             let .failed(previousValue: snapshot?, error: _):
            snapshot
        case .idle, .loading, .empty, .offline(previousValue: nil),
             .failed(previousValue: nil, error: _), .unavailable:
            nil
        }
    }

    private var currentRevision = 0

    private func publish(_ completion: FeatureLoadCompletion<HistoryResponse>) {
        switch completion {
        case let .value(response):
            state = response.data.meals.isEmpty && response.data.workouts.isEmpty
                ? .empty
                : .loaded(response.data)
        case let .failure(error):
            state = Self.readState(for: error, previousValue: currentSnapshot)
        }
    }

    private static func readState(
        for error: any Error,
        previousValue: HistorySnapshot?
    ) -> FeatureReadState<HistorySnapshot> {
        switch error as? BodyFlowCapabilityError ?? .serviceUnavailable {
        case .operationUnavailable:
            .unavailable
        case .offline:
            .offline(previousValue: previousValue)
        default:
            .failed(
                previousValue: previousValue,
                error: error as? BodyFlowCapabilityError ?? .serviceUnavailable
            )
        }
    }
}
