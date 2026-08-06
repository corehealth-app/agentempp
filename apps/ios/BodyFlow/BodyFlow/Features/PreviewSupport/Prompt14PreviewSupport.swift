#if DEBUG
import SwiftUI

enum Prompt14PreviewSurface: String, CaseIterable, Hashable, Sendable {
    case library
    case detail
    case recommendations
    case mascot
    case progress
}

struct Prompt14PreviewDefinition: Identifiable, Sendable {
    let id: String
    let title: String
    let surface: Prompt14PreviewSurface
    let scenario: DemoPrompt14Scenario
    let launchArguments: [String]

    init(
        title: String,
        surface: Prompt14PreviewSurface,
        scenario: DemoPrompt14Scenario,
        launchArgument: String
    ) {
        id = "\(surface.rawValue).\(title)"
        self.title = title
        self.surface = surface
        self.scenario = scenario
        launchArguments = ["--ui-testing", launchArgument]
    }
}

@MainActor
struct Prompt14PreviewContext {
    let dependencies: AppDependencies
    let sessionOwner: Prompt14SessionOwner
}

enum Prompt14PreviewSupport {
    static let definitions: [Prompt14PreviewDefinition] = [
        definition("Library · Loaded", .library, .loaded),
        definition("Library · Empty", .library, .empty),
        definition("Library · Offline", .library, .offline),
        definition("Library · Error", .library, .error),
        definition("Library · Unavailable", .library, .unavailable),
        definition("Detail · Loaded", .detail, .loaded),
        definition("Detail · Not Found", .detail, .contentNotFound),
        definition(
            "Detail · Subscription Required",
            .detail,
            .subscriptionRequired
        ),
        definition("Detail · Invalid Markdown", .detail, .markdownInvalid),
        definition("Recommendations · Loaded", .recommendations, .loaded),
        definition("Recommendations · Empty", .recommendations, .empty),
        definition("Recommendations · Offline", .recommendations, .offline),
        definition("Recommendations · Error", .recommendations, .error),
        definition(
            "Recommendations · Unavailable",
            .recommendations,
            .unavailable
        ),
        definition("Mascot · Variants", .mascot, .mascotVariants),
        definition("Mascot · Unavailable", .mascot, .unavailable),
        definition("Progress · Loaded", .progress, .loaded),
        definition("Progress · Empty", .progress, .progressEmpty),
        definition("Progress · Minimum", .progress, .progressMinimum),
        definition("Progress · Streak Zero", .progress, .streakZero),
        definition("Progress · Unavailable", .progress, .unavailable),
    ]

    @MainActor
    static func context(
        for scenario: DemoPrompt14Scenario
    ) -> Prompt14PreviewContext {
        let configuration = AppLaunchConfiguration.resolve(
            arguments: ["--ui-testing", launchArgument(for: scenario)],
            buildFlavor: .debug
        )
        let dependencies = AppDependencies.make(configuration: configuration)
        return Prompt14PreviewContext(
            dependencies: dependencies,
            sessionOwner: Prompt14SessionOwner(
                userID: "prompt14-preview-user",
                dependencies: dependencies
            )
        )
    }

    private static func definition(
        _ title: String,
        _ surface: Prompt14PreviewSurface,
        _ scenario: DemoPrompt14Scenario
    ) -> Prompt14PreviewDefinition {
        Prompt14PreviewDefinition(
            title: title,
            surface: surface,
            scenario: scenario,
            launchArgument: launchArgument(for: scenario)
        )
    }

    private static func launchArgument(
        for scenario: DemoPrompt14Scenario
    ) -> String {
        switch scenario {
        case .loaded: "--ui-testing-prompt14-loaded"
        case .loading: "--ui-testing-prompt14-loading"
        case .empty: "--ui-testing-prompt14-empty"
        case .offline: "--ui-testing-prompt14-offline"
        case .error: "--ui-testing-prompt14-error"
        case .stale: "--ui-testing-prompt14-stale"
        case .unavailable: "--ui-testing-prompt14-unavailable"
        case .openedError: "--ui-testing-prompt14-opened-error"
        case .contentNotFound:
            "--ui-testing-prompt14-content-not-found"
        case .subscriptionRequired:
            "--ui-testing-prompt14-subscription-required"
        case .markdownInvalid:
            "--ui-testing-prompt14-markdown-invalid"
        case .coverInvalid: "--ui-testing-prompt14-cover-invalid"
        case .mascotVariants:
            "--ui-testing-prompt14-mascot-variants"
        case .progressEmpty: "--ui-testing-prompt14-progress-empty"
        case .progressMinimum:
            "--ui-testing-prompt14-progress-minimum"
        case .streakZero: "--ui-testing-prompt14-streak-zero"
        case .conflict: "--ui-testing-prompt14-conflict"
        case .reduceMotion: "--ui-testing-prompt14-reduce-motion"
        case .differentiateWithoutColor:
            "--ui-testing-prompt14-differentiate-without-color"
        }
    }
}

@MainActor
private struct Prompt14LibraryPreview: View {
    private let context: Prompt14PreviewContext
    @State private var invalidationCenter = FeatureInvalidationCenter()

    init(scenario: DemoPrompt14Scenario) {
        context = Prompt14PreviewSupport.context(for: scenario)
    }

    var body: some View {
        NavigationStack {
            LibraryRootView(
                initialSelection: .all,
                sessionOwner: context.sessionOwner,
                dependencies: context.dependencies,
                invalidationCenter: invalidationCenter
            )
        }
        .environment(AppRouter())
        .environment(
            \.contentCoverEnvironment,
            ContentCoverEnvironment.make(
                loader: context.sessionOwner.coverLoader,
                session: ContentCoverSessionToken(),
                invalidationCenter: invalidationCenter
            )
        )
        .installAppDependencies(context.dependencies)
    }
}

@MainActor
private struct Prompt14DetailPreview: View {
    private let context: Prompt14PreviewContext
    @State private var invalidationCenter = FeatureInvalidationCenter()

    init(scenario: DemoPrompt14Scenario) {
        context = Prompt14PreviewSupport.context(for: scenario)
    }

    var body: some View {
        NavigationStack {
            PublishedContentDetailView(
                publicationID: DemoPrompt14Fixtures.firstSummary.publicationID,
                origin: .library,
                detailProvider: context.sessionOwner.contentDetail,
                stateRecorder: context.sessionOwner.contentState,
                keyProvider: context.dependencies.idempotencyKeyProvider,
                timeProvider: context.dependencies.timeProvider,
                invalidationCenter: invalidationCenter,
                coverLoader: context.sessionOwner.coverLoader
            )
        }
        .environment(AppRouter())
        .environment(
            \.contentCoverEnvironment,
            ContentCoverEnvironment.make(
                loader: context.sessionOwner.coverLoader,
                session: ContentCoverSessionToken(),
                invalidationCenter: invalidationCenter
            )
        )
        .installAppDependencies(context.dependencies)
    }
}

@MainActor
private struct Prompt14RecommendationsPreview: View {
    private let context: Prompt14PreviewContext
    private let model: TodayRecommendationsViewModel
    @State private var invalidationCenter: FeatureInvalidationCenter

    init(scenario: DemoPrompt14Scenario) {
        let context = Prompt14PreviewSupport.context(for: scenario)
        let invalidationCenter = FeatureInvalidationCenter()
        self.context = context
        self.invalidationCenter = invalidationCenter
        model = TodayRecommendationsViewModel(
            listing: context.sessionOwner.contentListing,
            stateRecorder: context.sessionOwner.contentState,
            keyProvider: context.dependencies.idempotencyKeyProvider,
            timeProvider: context.dependencies.timeProvider,
            invalidationCenter: invalidationCenter,
            coverLoader: context.sessionOwner.coverLoader
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                TodayRecommendationsSection(
                    model: model,
                    catalogRevision: 0
                )
                .padding(BodyFlowSpacing.md)
            }
            .background(BodyFlowColor.background)
            .navigationTitle("Hoje")
        }
        .environment(AppRouter())
        .environment(
            \.contentCoverEnvironment,
            ContentCoverEnvironment.make(
                loader: context.sessionOwner.coverLoader,
                session: ContentCoverSessionToken(),
                invalidationCenter: invalidationCenter
            )
        )
        .installAppDependencies(context.dependencies)
        .task {
            await model.load(catalogRevision: 0)
        }
    }
}

@MainActor
private struct Prompt14MascotPreview: View {
    private let context: Prompt14PreviewContext
    @State private var invalidationCenter = FeatureInvalidationCenter()

    init(scenario: DemoPrompt14Scenario) {
        context = Prompt14PreviewSupport.context(for: scenario)
    }

    var body: some View {
        NavigationStack {
            MascotDetailView(
                provider: context.sessionOwner.coachExperience,
                invalidationCenter: invalidationCenter
            )
        }
        .installAppDependencies(context.dependencies)
    }
}

@MainActor
private struct Prompt14ProgressPreview: View {
    private let context: Prompt14PreviewContext
    @State private var model: ProgressViewModel
    @State private var selectedTab = AppTab.progress

    init(scenario: DemoPrompt14Scenario) {
        let context = Prompt14PreviewSupport.context(for: scenario)
        self.context = context
        _model = State(
            initialValue: ProgressViewModel(
                provider: context.sessionOwner.progress
            )
        )
    }

    var body: some View {
        NavigationStack {
            ProgressRootView(
                model: model,
                selectedTab: $selectedTab
            )
        }
        .environment(AppRouter())
        .installAppDependencies(context.dependencies)
    }
}

#Preview("Prompt 14 · Library Loaded") {
    Prompt14LibraryPreview(scenario: .loaded)
}

#Preview("Prompt 14 · Library Empty") {
    Prompt14LibraryPreview(scenario: .empty)
}

#Preview("Prompt 14 · Library Offline") {
    Prompt14LibraryPreview(scenario: .offline)
}

#Preview("Prompt 14 · Library Error") {
    Prompt14LibraryPreview(scenario: .error)
}

#Preview("Prompt 14 · Library Unavailable") {
    Prompt14LibraryPreview(scenario: .unavailable)
}

#Preview("Prompt 14 · Detail Loaded") {
    Prompt14DetailPreview(scenario: .loaded)
}

#Preview("Prompt 14 · Detail Not Found") {
    Prompt14DetailPreview(scenario: .contentNotFound)
}

#Preview("Prompt 14 · Detail Subscription Required") {
    Prompt14DetailPreview(scenario: .subscriptionRequired)
}

#Preview("Prompt 14 · Detail Invalid Markdown") {
    Prompt14DetailPreview(scenario: .markdownInvalid)
}

#Preview("Prompt 14 · Recommendations Loaded") {
    Prompt14RecommendationsPreview(scenario: .loaded)
}

#Preview("Prompt 14 · Recommendations Empty") {
    Prompt14RecommendationsPreview(scenario: .empty)
}

#Preview("Prompt 14 · Recommendations Offline") {
    Prompt14RecommendationsPreview(scenario: .offline)
}

#Preview("Prompt 14 · Recommendations Error") {
    Prompt14RecommendationsPreview(scenario: .error)
}

#Preview("Prompt 14 · Recommendations Unavailable") {
    Prompt14RecommendationsPreview(scenario: .unavailable)
}

#Preview("Prompt 14 · Mascot Variants") {
    Prompt14MascotPreview(scenario: .mascotVariants)
}

#Preview("Prompt 14 · Mascot Unavailable") {
    Prompt14MascotPreview(scenario: .unavailable)
}

#Preview("Prompt 14 · Progress Loaded") {
    Prompt14ProgressPreview(scenario: .loaded)
}

#Preview("Prompt 14 · Progress Empty") {
    Prompt14ProgressPreview(scenario: .progressEmpty)
}

#Preview("Prompt 14 · Progress Minimum") {
    Prompt14ProgressPreview(scenario: .progressMinimum)
}

#Preview("Prompt 14 · Progress Streak Zero") {
    Prompt14ProgressPreview(scenario: .streakZero)
}

#Preview("Prompt 14 · Progress Unavailable") {
    Prompt14ProgressPreview(scenario: .unavailable)
}
#endif
