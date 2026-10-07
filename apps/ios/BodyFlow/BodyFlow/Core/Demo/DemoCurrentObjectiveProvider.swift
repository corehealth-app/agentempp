#if DEBUG
import Foundation

/// Explicit local scenarios only; the dependency factory never installs this in Release.
actor DemoCurrentObjectiveProvider: CurrentObjectiveProviding {
    enum Scenario { case loaded, empty, offline, long }
    private let scenario: Scenario
    private let locale: String
    private var reads = 0

    init(scenario: Scenario, locale: String) {
        self.scenario = scenario
        self.locale = locale
    }

    static func scenario(arguments: [String]) -> Scenario? {
        if arguments.contains("--ui-testing-current-objective-empty") { return .empty }
        if arguments.contains("--ui-testing-current-objective-offline") { return .offline }
        if arguments.contains("--ui-testing-current-objective-long") { return .long }
        return arguments.contains("--ui-testing-current-objective") ? .loaded : nil
    }

    func currentObjective() async throws -> CurrentObjectiveSnapshot {
        reads += 1
        if scenario == .offline, reads == 1 { throw BodyFlowCapabilityError.offline }
        if scenario == .empty { return .init(currentProtocol: nil, targets: nil, welcome: nil) }
        var paragraphs = scenario == .long
            ? OnboardingPreviewRepository.welcomeParagraphs(locale: locale)
            : [locale == "en-US"
                ? "This is the synthetic entry message for your current objective."
                : "Esta é a mensagem de entrada sintética do seu objetivo atual."]
        if scenario == .long {
            paragraphs[paragraphs.count - 1] = locale == "en-US"
                ? "End of the synthetic message for your current objective."
                : "Fim da mensagem sintética do seu objetivo atual."
        }
        return .init(currentProtocol: .maintenance,
            targets: .init(calories: Decimal(string: "2123.45"), proteinG: Decimal(string: "123.45")),
            welcome: .init(protocol: .maintenance, paragraphs: paragraphs))
    }
}
#endif
