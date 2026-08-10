import Foundation
import Testing

@testable import BodyFlow

@MainActor
@Suite("Coach persona editor model")
struct CoachPersonaEditorModelTests {
    @Test("validated server options preserve literal copy and response order")
    func preservesServerOptionCopyAndOrder() throws {
        let model = CoachPersonaEditorModel(
            userID: "fixture-user",
            repository: EditorPersonaRepository(selectedResult: .success(.focus)),
            serverOptions: [
                CoachPersonaOption(
                    code: .zen,
                    name: "Zênite remoto",
                    description: "Texto Z que não existe no aplicativo."
                ),
                CoachPersonaOption(
                    code: .focus,
                    name: "Precisão remota",
                    description: "Texto F que não existe no aplicativo."
                ),
                CoachPersonaOption(
                    code: .impulse,
                    name: "Ritmo remoto",
                    description: "Texto I que não existe no aplicativo."
                ),
            ]
        )

        let options = try #require(model.pickerOptions)
        #expect(options.map(\.persona) == [.zen, .focus, .impulse])
        #expect(options.map(\.name) == [
            "Zênite remoto",
            "Precisão remota",
            "Ritmo remoto",
        ])
        #expect(options.map(\.description) == [
            "Texto Z que não existe no aplicativo.",
            "Texto F que não existe no aplicativo.",
            "Texto I que não existe no aplicativo.",
        ])
        #expect(options.count == 3)
    }

    @Test("missing duplicate and empty server options fail closed")
    func invalidServerOptionsFailClosed() {
        let missing = CoachPersonaEditorModel(
            userID: "fixture-user",
            repository: EditorPersonaRepository(selectedResult: .success(.focus)),
            serverOptions: Array(Self.serverOptions.dropLast())
        )
        let duplicate = CoachPersonaEditorModel(
            userID: "fixture-user",
            repository: EditorPersonaRepository(selectedResult: .success(.focus)),
            serverOptions: [
                Self.serverOptions[0],
                Self.serverOptions[0],
                Self.serverOptions[2],
            ]
        )
        let empty = CoachPersonaEditorModel(
            userID: "fixture-user",
            repository: EditorPersonaRepository(selectedResult: .success(.focus)),
            serverOptions: []
        )

        #expect(missing.pickerOptions == nil)
        #expect(duplicate.pickerOptions == nil)
        #expect(empty.pickerOptions == nil)
    }

    @Test("late server options activate literal rows and invalid updates fail closed")
    func lateServerOptionsUpdatePickerRows() throws {
        let model = CoachPersonaEditorModel(
            userID: "fixture-user",
            repository: EditorPersonaRepository(selectedResult: .success(.focus))
        )

        #expect(model.pickerOptions == nil)

        model.updateServerOptions([
            Self.serverOptions[2],
            Self.serverOptions[0],
            Self.serverOptions[1],
        ])

        let options = try #require(model.pickerOptions)
        #expect(options.map(\.persona) == [.zen, .focus, .impulse])
        #expect(options.map(\.name) == ["Zen remoto", "Focus remoto", "Impulse remoto"])

        model.updateServerOptions(Array(Self.serverOptions.dropLast()))

        #expect(model.pickerOptions == nil)
    }

    @Test("balanced and unknown codes cannot become selectable picker rows")
    func unsupportedCodesFailBeforePickerInput() {
        for code in ["balanced", "future-persona"] {
            let json = Data(
                """
                {
                  "code": "\(code)",
                  "name": "Nome remoto",
                  "description": "Descrição remota."
                }
                """.utf8
            )

            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(CoachPersonaOption.self, from: json)
            }
        }
    }

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

    @Test("only a successful changed save records persona invalidation once")
    func successfulChangedSaveInvalidatesOnce() async {
        let repository = EditorPersonaRepository(selectedResult: .success(.focus))
        let center = FeatureInvalidationCenter()
        let model = CoachPersonaEditorModel(
            userID: "fixture-user",
            repository: repository,
            serverOptions: Self.serverOptions,
            onPersistedPersonaChanged: {
                center.record(.coachPersonaChanged)
            }
        )
        await model.load()
        model.select(.impulse)

        #expect(await model.save())
        #expect(center.revision(for: .coachExperience) == 1)
        #expect(center.revision(for: .contentCatalog) == 1)

        #expect(await model.save())
        #expect(center.revision(for: .coachExperience) == 1)
        #expect(center.revision(for: .contentCatalog) == 1)
    }

    @Test("failed and cancelled saves do not record persona invalidation")
    func unsuccessfulSavesDoNotInvalidate() async {
        let failedCenter = FeatureInvalidationCenter()
        let failed = CoachPersonaEditorModel(
            userID: "fixture-user",
            repository: EditorPersonaRepository(
                selectedResult: .success(.focus),
                saveResults: [.failure(.serviceUnavailable)]
            ),
            serverOptions: Self.serverOptions,
            onPersistedPersonaChanged: {
                failedCenter.record(.coachPersonaChanged)
            }
        )
        await failed.load()
        failed.select(.zen)

        #expect(!(await failed.save()))
        #expect(failedCenter.revision(for: .coachExperience) == 0)
        #expect(failedCenter.revision(for: .contentCatalog) == 0)

        let cancelledCenter = FeatureInvalidationCenter()
        let suspendedRepository = SuspendedEditorPersonaRepository(selected: .focus)
        let cancelled = CoachPersonaEditorModel(
            userID: "fixture-user",
            repository: suspendedRepository,
            serverOptions: Self.serverOptions,
            onPersistedPersonaChanged: {
                cancelledCenter.record(.coachPersonaChanged)
            }
        )
        await cancelled.load()
        cancelled.select(.impulse)
        let save = Task { await cancelled.save() }
        await suspendedRepository.waitUntilSaveSuspends()
        cancelled.cancelActiveOperation()
        await suspendedRepository.resumeSave()

        #expect(!(await save.value))
        #expect(cancelledCenter.revision(for: .coachExperience) == 0)
        #expect(cancelledCenter.revision(for: .contentCatalog) == 0)
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
    private static let serverOptions = [
        CoachPersonaOption(
            code: .focus,
            name: "Focus remoto",
            description: "Descrição Focus remota."
        ),
        CoachPersonaOption(
            code: .impulse,
            name: "Impulse remoto",
            description: "Descrição Impulse remota."
        ),
        CoachPersonaOption(
            code: .zen,
            name: "Zen remoto",
            description: "Descrição Zen remota."
        ),
    ]
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
