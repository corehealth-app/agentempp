import Foundation

enum DemoStateStoreError: Error, Equatable, Sendable {
    case invalidPayload
    case secureStorageUnavailable
}

struct DemoStateStore: Sendable {
    private let secureStore: any SecureStoring

    init(secureStore: any SecureStoring) {
        self.secureStore = secureStore
    }

    func loadSession() async throws -> AuthSession? {
        try await load(AuthSession.self, forKey: DemoStateKey.session)
    }

    func saveSession(_ session: AuthSession) async throws {
        try await save(session, forKey: DemoStateKey.session)
    }

    func loadOnboardingDraft() async throws -> OnboardingDraft? {
        try await load(OnboardingDraft.self, forKey: DemoStateKey.onboardingDraft)
    }

    func saveOnboardingDraft(_ draft: OnboardingDraft) async throws {
        try await save(draft, forKey: DemoStateKey.onboardingDraft)
    }

    func loadCoachPersona() async throws -> CoachPersona? {
        try await load(CoachPersona.self, forKey: DemoStateKey.coachPersona)
    }

    func saveCoachPersona(_ persona: CoachPersona) async throws {
        try await save(persona, forKey: DemoStateKey.coachPersona)
    }

    func clearSession() async throws {
        try await removeData(forKey: DemoStateKey.session)
    }

    func clearOnboardingDraft() async throws {
        try await removeData(forKey: DemoStateKey.onboardingDraft)
    }

    func clearAll() async throws {
        try await removeData(forKey: DemoStateKey.session)
        try await removeData(forKey: DemoStateKey.onboardingDraft)
        try await removeData(forKey: DemoStateKey.coachPersona)
    }

    private func load<Value: Decodable>(
        _ type: Value.Type,
        forKey key: String
    ) async throws -> Value? {
        let data: Data?

        do {
            data = try await secureStore.data(forKey: key)
        } catch {
            throw DemoStateStoreError.secureStorageUnavailable
        }

        guard let data else {
            return nil
        }

        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            throw DemoStateStoreError.invalidPayload
        }
    }

    private func save<Value: Encodable>(
        _ value: Value,
        forKey key: String
    ) async throws {
        let data: Data

        do {
            data = try encoder.encode(value)
        } catch {
            throw DemoStateStoreError.invalidPayload
        }

        do {
            try await secureStore.store(data, forKey: key)
        } catch {
            throw DemoStateStoreError.secureStorageUnavailable
        }
    }

    private func removeData(forKey key: String) async throws {
        do {
            try await secureStore.removeData(forKey: key)
        } catch {
            throw DemoStateStoreError.secureStorageUnavailable
        }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private enum DemoStateKey {
    static let session = "bodyflow.demo.session.v1"
    static let onboardingDraft = "bodyflow.demo.onboarding-draft.v1"
    static let coachPersona = "bodyflow.demo.coach-persona.v1"
}
