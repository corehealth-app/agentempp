import Foundation
import Testing

@testable import BodyFlow

@Suite("Mascot accessible composition")
@MainActor
struct MascotAccessibilityModelTests {
    @Test("card and detail preserve server persona and state semantics across visual variants")
    func semanticContentIsIndependentFromVisualVariant() throws {
        let cases: [(EffectiveCoachPersona, String, MascotPersonalityGeometry)] = [
            (.focus, "Nome remoto Focus", .stable),
            (.impulse, "Nome remoto Impulse", .energetic),
            (.zen, "Nome remoto Zen", .calm),
            (.balanced, "Equilibrada", .neutral),
        ]

        for (persona, expectedName, expectedGeometry) in cases {
            let presentation = MascotExperiencePresentation(
                snapshot: Self.snapshot(effective: persona, state: .active)
            )
            let card = MascotViewCompositionDescriptor(
                presentation: presentation,
                surface: .card,
                reduceMotion: false
            )
            let detail = MascotViewCompositionDescriptor(
                presentation: presentation,
                surface: .detail,
                reduceMotion: false
            )

            #expect(card.personaName == expectedName)
            #expect(card.personaText == "Personalidade: \(expectedName)")
            #expect(card.stateText == "Ativo")
            #expect(card.accessibilityAnnouncement ==
                "Mascote BodyFlow, personalidade \(expectedName), estado Ativo")
            #expect(detail.personaText == card.personaText)
            #expect(detail.stateText == card.stateText)
            #expect(detail.accessibilityAnnouncement == card.accessibilityAnnouncement)
            #expect(card.artwork.geometry == expectedGeometry)
            #expect(card.artworkAccessibilityHidden)
        }
    }

    @Test("evolving and unknown remain explicit neutral announcements")
    func unsupportedStatesRemainExplicit() {
        for state in [MascotWireState.evolving, .unknown("future-value")] {
            let descriptor = MascotViewCompositionDescriptor(
                presentation: MascotExperiencePresentation(
                    snapshot: Self.snapshot(effective: .focus, state: state)
                ),
                surface: .detail,
                reduceMotion: false
            )

            #expect(descriptor.stateText == "Estado do mascote em atualização")
            #expect(descriptor.accessibilityAnnouncement ==
                "Mascote BodyFlow, personalidade Nome remoto Focus, estado Estado do mascote em atualização")
            #expect(descriptor.artwork.semanticState == .unsupported)
        }
    }

    @Test("reduce motion removes repetition without removing meaning")
    func reduceMotionStopsRepeatingAnimation() {
        let presentation = MascotExperiencePresentation(
            snapshot: Self.snapshot(effective: .impulse, state: .reactivating)
        )
        let animated = MascotViewCompositionDescriptor(
            presentation: presentation,
            surface: .card,
            reduceMotion: false
        )
        let reduced = MascotViewCompositionDescriptor(
            presentation: presentation,
            surface: .card,
            reduceMotion: true
        )

        #expect(animated.usesRepeatingMotion)
        #expect(!reduced.usesRepeatingMotion)
        #expect(reduced.personaText == animated.personaText)
        #expect(reduced.stateText == animated.stateText)
        #expect(reduced.accessibilityAnnouncement == animated.accessibilityAnnouncement)
    }

    @Test("card and detail remain semantically complete when temporary art is absent")
    func artIsOptional() {
        let presentation = MascotExperiencePresentation(
            snapshot: Self.snapshot(effective: .zen, state: .inactive)
        )

        for surface in [MascotViewSurface.card, .detail] {
            let descriptor = MascotViewCompositionDescriptor(
                presentation: presentation,
                surface: surface,
                reduceMotion: false,
                temporaryArtworkAvailable: false
            )

            #expect(!descriptor.showsTemporaryArtwork)
            #expect(descriptor.title == "Mascote BodyFlow")
            #expect(descriptor.personaText == "Personalidade: Nome remoto Zen")
            #expect(descriptor.stateText == "Em repouso")
            #expect(!descriptor.primaryActionTitle.isEmpty)
        }
    }

    @Test("a fresh detail model reloads once for each coach revision")
    func detailReloadsCoachSnapshotByRevision() async throws {
        let provider = AccessibilityMascotProvider(responses: [
            Self.response(effective: .focus, state: .inactive, requestID: "first"),
            Self.response(effective: .zen, state: .active, requestID: "second"),
        ])
        let detailModel = MascotExperienceViewModel(provider: provider)

        await detailModel.load(revision: 0)
        #expect(try #require(detailModel.state.presentation.value).effective == .focus)

        await detailModel.load(revision: 1)
        #expect(try #require(detailModel.state.presentation.value).effective == .zen)
        #expect(await provider.calls == 2)
    }

    @Test("a newer profile load owns publication when an older load completes late")
    func newerProfileLoadSupersedesOlderCompletion() async {
        let source = SuspendedProfilePersonaSource()
        let harness = ProfilePersonaLoadOwnershipHarness()

        let loadA = Task { @MainActor in
            await harness.load(
                requestID: "A",
                userID: "fixture-user",
                source: source
            )
        }
        await source.waitUntilStarted("A")

        let loadB = Task { @MainActor in
            await harness.load(
                requestID: "B",
                userID: "fixture-user",
                source: source
            )
        }
        await source.waitUntilStarted("B")

        await source.complete("B", value: "snapshot-B")
        await loadB.value
        await source.complete("A", value: "snapshot-A")
        await loadA.value

        #expect(harness.publishedSnapshots == ["snapshot-B"])
    }

    @Test("profile two-phase loads publish only one atomic result from the newest intent")
    func profileTwoPhaseLoadCommitsAtomically() async {
        let controller = ProfilePersonaLoadController()
        let repositoryA = SuspendedProfilePersonaRepository()
        let providerA = SuspendedProfileCoachProvider()
        let repositoryB = SuspendedProfilePersonaRepository()
        let providerB = SuspendedProfileCoachProvider()
        let previousOptions = Self.profileOptions(prefix: "Anterior")
        let nextOptions = Self.profileOptions(prefix: "Novo")
        var committed = ProfilePersonaLoadController.Publication(
            selectedPersona: .focus,
            serverOptions: previousOptions
        )
        var commits: [ProfilePersonaLoadController.Publication] = []

        let loadA = Task { @MainActor in
            await controller.load(
                userID: "fixture-user",
                previous: committed,
                repository: repositoryA,
                provider: providerA
            ) { publication in
                committed = publication
                commits.append(publication)
            }
        }
        await repositoryA.waitUntilStarted()
        await repositoryA.complete(with: .zen)
        await providerA.waitUntilStarted()

        #expect(commits.isEmpty)
        #expect(committed == ProfilePersonaLoadController.Publication(
            selectedPersona: .focus,
            serverOptions: previousOptions
        ))

        let loadB = Task { @MainActor in
            await controller.load(
                userID: "fixture-user",
                previous: committed,
                repository: repositoryB,
                provider: providerB
            ) { publication in
                committed = publication
                commits.append(publication)
            }
        }
        await repositoryB.waitUntilStarted()
        await repositoryB.complete(with: .impulse)
        await providerB.waitUntilStarted()
        await providerB.complete(with: Self.profileResponse(
            selected: .impulse,
            effective: .impulse,
            options: nextOptions,
            requestID: "B"
        ))
        await loadB.value

        await providerA.complete(with: Self.profileResponse(
            selected: .zen,
            effective: .zen,
            options: previousOptions,
            requestID: "A"
        ))
        await loadA.value

        let expected = ProfilePersonaLoadController.Publication(
            selectedPersona: .impulse,
            serverOptions: nextOptions
        )
        #expect(committed == expected)
        #expect(commits == [expected])
    }

    @Test("profile load never reuses stale options without a valid current remote snapshot")
    func profileLoadFailsClosedWithoutCurrentRemoteOptions() async {
        let previous = ProfilePersonaLoadController.Publication(
            selectedPersona: .focus,
            serverOptions: Self.profileOptions(prefix: "Anterior")
        )
        let invalidResponse = Self.profileResponse(
            selected: .zen,
            effective: .zen,
            options: [],
            requestID: "invalid-options"
        )
        let providers: [(any CoachExperienceProviding)?] = [
            nil,
            AccessibilityMascotProvider(responses: []),
            AccessibilityMascotProvider(responses: [invalidResponse]),
        ]

        for provider in providers {
            let controller = ProfilePersonaLoadController()
            let repository = ImmediateProfilePersonaRepository(selected: .impulse)
            var commits: [ProfilePersonaLoadController.Publication] = []

            await controller.load(
                userID: "fixture-user",
                previous: previous,
                repository: repository,
                provider: provider
            ) { publication in
                commits.append(publication)
            }

            #expect(commits == [ProfilePersonaLoadController.Publication(
                selectedPersona: .impulse,
                serverOptions: nil
            )])
        }
    }

    @Test("cancelled and identity-mismatched profile loads cannot publish")
    func cancelledOrReidentifiedProfileLoadCannotPublish() {
        var ownership = ProfilePersonaLoadOwnership()
        let userAToken = ownership.begin(for: "user-a")

        #expect(!ownership.canPublish(
            userAToken,
            activeUserID: "user-a",
            isCancelled: true
        ))

        let userBToken = ownership.begin(for: "user-b")

        #expect(!ownership.canPublish(
            userAToken,
            activeUserID: "user-b",
            isCancelled: false
        ))
        #expect(ownership.canPublish(
            userBToken,
            activeUserID: "user-b",
            isCancelled: false
        ))

        ownership.invalidate()

        #expect(!ownership.canPublish(
            userBToken,
            activeUserID: "user-b",
            isCancelled: false
        ))
    }

    private static let options = [
        CoachPersonaOption(
            code: .focus,
            name: "Nome remoto Focus",
            description: "Descrição remota Focus."
        ),
        CoachPersonaOption(
            code: .impulse,
            name: "Nome remoto Impulse",
            description: "Descrição remota Impulse."
        ),
        CoachPersonaOption(
            code: .zen,
            name: "Nome remoto Zen",
            description: "Descrição remota Zen."
        ),
    ]

    private static func snapshot(
        effective: EffectiveCoachPersona,
        state: MascotWireState
    ) -> CoachExperienceSnapshot {
        CoachExperienceSnapshot(
            selected: selectedPersona(for: effective),
            effective: effective,
            options: options,
            mascot: MascotSnapshot(
                state: state,
                changedAt: APITimestamp(
                    value: Date(timeIntervalSince1970: 1_784_502_900)
                )
            ),
            contractVersion: "bodyflow.coach-persona.v1"
        )
    }

    private static func selectedPersona(
        for effective: EffectiveCoachPersona
    ) -> SelectableCoachPersona? {
        switch effective {
        case .focus: .focus
        case .impulse: .impulse
        case .zen: .zen
        case .balanced: nil
        }
    }

    private static func response(
        effective: EffectiveCoachPersona,
        state: MascotWireState,
        requestID: String
    ) -> CoachExperienceResponse {
        CoachExperienceResponse(
            data: snapshot(effective: effective, state: state),
            meta: MobileResponseMetadata(apiVersion: "1", requestID: requestID)
        )
    }

    private static func profileOptions(prefix: String) -> [CoachPersonaOption] {
        [
            CoachPersonaOption(
                code: .focus,
                name: "\(prefix) Focus",
                description: "\(prefix) descrição Focus."
            ),
            CoachPersonaOption(
                code: .impulse,
                name: "\(prefix) Impulse",
                description: "\(prefix) descrição Impulse."
            ),
            CoachPersonaOption(
                code: .zen,
                name: "\(prefix) Zen",
                description: "\(prefix) descrição Zen."
            ),
        ]
    }

    private static func profileResponse(
        selected: SelectableCoachPersona,
        effective: EffectiveCoachPersona,
        options: [CoachPersonaOption],
        requestID: String
    ) -> CoachExperienceResponse {
        CoachExperienceResponse(
            data: CoachExperienceSnapshot(
                selected: selected,
                effective: effective,
                options: options,
                mascot: MascotSnapshot(
                    state: .active,
                    changedAt: APITimestamp(
                        value: Date(timeIntervalSince1970: 1_784_502_900)
                    )
                ),
                contractVersion: CoachExperienceV1PresentationContract.version
            ),
            meta: MobileResponseMetadata(
                apiVersion: "1",
                requestID: requestID
            )
        )
    }
}

@MainActor
private final class ProfilePersonaLoadOwnershipHarness {
    private var ownership = ProfilePersonaLoadOwnership()
    private(set) var publishedSnapshots: [String] = []

    func load(
        requestID: String,
        userID: String,
        source: SuspendedProfilePersonaSource
    ) async {
        let token = ownership.begin(for: userID)
        let snapshot = await source.value(for: requestID)
        guard ownership.canPublish(
            token,
            activeUserID: userID,
            isCancelled: Task.isCancelled
        ) else {
            return
        }
        publishedSnapshots.append(snapshot)
    }
}

private actor SuspendedProfilePersonaSource {
    private var startedRequests: Set<String> = []
    private var continuations: [String: CheckedContinuation<String, Never>] = [:]

    func value(for requestID: String) async -> String {
        startedRequests.insert(requestID)
        return await withCheckedContinuation { continuation in
            continuations[requestID] = continuation
        }
    }

    func waitUntilStarted(_ requestID: String) async {
        while !startedRequests.contains(requestID) {
            await Task.yield()
        }
    }

    func complete(_ requestID: String, value: String) {
        continuations.removeValue(forKey: requestID)?.resume(returning: value)
    }
}

private actor SuspendedProfilePersonaRepository: CoachPersonaRepository {
    private var started = false
    private var continuation: CheckedContinuation<CoachPersona?, Never>?

    func selectedPersona(for userID: String) async throws -> CoachPersona? {
        _ = userID
        started = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func setPersona(_ persona: CoachPersona, for userID: String) async throws {
        _ = persona
        _ = userID
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func complete(with persona: CoachPersona?) {
        continuation?.resume(returning: persona)
        continuation = nil
    }
}

private actor ImmediateProfilePersonaRepository: CoachPersonaRepository {
    private let selected: CoachPersona?

    init(selected: CoachPersona?) {
        self.selected = selected
    }

    func selectedPersona(for userID: String) async throws -> CoachPersona? {
        _ = userID
        return selected
    }

    func setPersona(_ persona: CoachPersona, for userID: String) async throws {
        _ = persona
        _ = userID
    }
}

private actor SuspendedProfileCoachProvider: CoachExperienceProviding {
    private var started = false
    private var continuation: CheckedContinuation<CoachExperienceResponse, Never>?

    func coachExperience() async throws -> CoachExperienceResponse {
        started = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func complete(with response: CoachExperienceResponse) {
        continuation?.resume(returning: response)
        continuation = nil
    }
}

private actor AccessibilityMascotProvider: CoachExperienceProviding {
    private var responses: [CoachExperienceResponse]
    private(set) var calls = 0

    init(responses: [CoachExperienceResponse]) {
        self.responses = responses
    }

    func coachExperience() async throws -> CoachExperienceResponse {
        calls += 1
        guard !responses.isEmpty else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        return responses.removeFirst()
    }
}
