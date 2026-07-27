import Testing

@testable import BodyFlow

@MainActor
@Suite("Coach persona editor model")
struct CoachPersonaEditorModelTests {
    @Test("load publishes the persisted selection for the same user")
    func loadsPersistedSelection() async {
        let repository = EditorPersonaRepository(selectedResult: .success(.zen))
        let model = CoachPersonaEditorModel(
            userID: "fixture-user",
            repository: repository
        )

        #expect(model.operationState == .loading)

        await model.load()

        #expect(model.selected == .zen)
        #expect(model.persisted == .zen)
        #expect(model.operationState == .idle)
        #expect(await repository.loadedUserIDs == ["fixture-user"])
    }

    @Test("load failure is recoverable and publishes no selection")
    func handlesLoadFailure() async {
        let repository = EditorPersonaRepository(
            selectedResult: .failure(.serviceUnavailable)
        )
        let model = CoachPersonaEditorModel(
            userID: "fixture-user",
            repository: repository
        )

        await model.load()

        #expect(model.selected == nil)
        #expect(model.persisted == nil)
        #expect(model.operationState == .failed(.serviceUnavailable))
    }

    @Test("successful save updates persisted and permits dismissal")
    func savesSelection() async {
        let repository = EditorPersonaRepository(selectedResult: .success(.focus))
        let model = CoachPersonaEditorModel(
            userID: "fixture-user",
            repository: repository
        )
        await model.load()
        model.select(.impulse)

        let shouldDismiss = await model.save()

        #expect(shouldDismiss)
        #expect(model.selected == .impulse)
        #expect(model.persisted == .impulse)
        #expect(model.operationState == .idle)
        #expect(await repository.writes == [.init(
            userID: "fixture-user",
            persona: .impulse
        )])
    }

    @Test("save failure restores the persisted selection")
    func failedSavePreservesPersistedSelection() async {
        let repository = EditorPersonaRepository(
            selectedResult: .success(.focus),
            saveResults: [.failure(.storageUnavailable)]
        )
        let model = CoachPersonaEditorModel(
            userID: "fixture-user",
            repository: repository
        )
        await model.load()
        model.select(.zen)

        let shouldDismiss = await model.save()

        #expect(!shouldDismiss)
        #expect(model.selected == .focus)
        #expect(model.persisted == .focus)
        #expect(model.operationState == .failed(.storageUnavailable))
    }

    @Test("double tap starts one save")
    func suppressesConcurrentSave() async {
        let repository = SuspendedEditorPersonaRepository(selected: .focus)
        let model = CoachPersonaEditorModel(
            userID: "fixture-user",
            repository: repository
        )
        await model.load()
        model.select(.impulse)
        let first = Task { await model.save() }
        await repository.waitUntilSaveSuspends()

        let secondResult = await model.save()

        #expect(!secondResult)
        #expect(model.operationState == .saving)
        #expect(await repository.saveCount == 1)

        await repository.resumeSave()
        #expect(await first.value)
        #expect(model.persisted == .impulse)
    }

    @Test("dismissal stays blocked until a retry succeeds")
    func dismissesOnlyAfterConfirmedSave() async {
        let repository = EditorPersonaRepository(
            selectedResult: .success(.focus),
            saveResults: [
                .failure(.serviceUnavailable),
                .success(()),
            ]
        )
        let model = CoachPersonaEditorModel(
            userID: "fixture-user",
            repository: repository
        )
        await model.load()
        model.select(.zen)

        #expect(await model.save() == false)
        #expect(model.selected == .focus)
        #expect(model.persisted == .focus)
        model.select(.zen)
        #expect(await model.save() == true)
        #expect(model.persisted == .zen)
    }
}

private actor EditorPersonaRepository: CoachPersonaRepository {
    struct Write: Equatable, Sendable {
        let userID: String
        let persona: CoachPersona
    }

    private let selectedResult: Result<CoachPersona?, CoachPersonaRepositoryError>
    private var saveResults: [Result<Void, CoachPersonaRepositoryError>]
    private(set) var loadedUserIDs: [String] = []
    private(set) var writes: [Write] = []

    init(
        selectedResult: Result<CoachPersona?, CoachPersonaRepositoryError>,
        saveResults: [Result<Void, CoachPersonaRepositoryError>] = []
    ) {
        self.selectedResult = selectedResult
        self.saveResults = saveResults
    }

    func selectedPersona(for userID: String) async throws -> CoachPersona? {
        loadedUserIDs.append(userID)
        return try selectedResult.get()
    }

    func setPersona(_ persona: CoachPersona, for userID: String) async throws {
        writes.append(Write(userID: userID, persona: persona))
        guard !saveResults.isEmpty else { return }
        try saveResults.removeFirst().get()
    }
}

private actor SuspendedEditorPersonaRepository: CoachPersonaRepository {
    private let selected: CoachPersona?
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var saveCount = 0

    init(selected: CoachPersona?) {
        self.selected = selected
    }

    func selectedPersona(for userID: String) async throws -> CoachPersona? {
        selected
    }

    func setPersona(_ persona: CoachPersona, for userID: String) async throws {
        saveCount += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilSaveSuspends() async {
        while continuation == nil { await Task.yield() }
    }

    func resumeSave() {
        continuation?.resume()
        continuation = nil
    }
}
