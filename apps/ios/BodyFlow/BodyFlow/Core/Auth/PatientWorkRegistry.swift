import Foundation

actor PatientWorkRegistry {
    typealias Cancellation = @Sendable () -> Void

    private struct Entry: Sendable {
        let userID: String
        let generation: UInt64
        let cancel: Cancellation
    }

    private var entries: [UUID: Entry] = [:]
    private var highestRetiredGeneration: UInt64?

    var activeCount: Int { entries.count }

    func begin(
        userID: String,
        generation: UInt64,
        cancel: @escaping Cancellation
    ) -> UUID? {
        guard highestRetiredGeneration.map({ generation > $0 }) ?? true else {
            cancel()
            return nil
        }
        let id = UUID()
        entries[id] = Entry(
            userID: userID,
            generation: generation,
            cancel: cancel
        )
        return id
    }

    @discardableResult
    func finish(_ id: UUID) -> Bool {
        entries.removeValue(forKey: id) != nil
    }

    func cancelAll(userID: String, generation: UInt64) {
        highestRetiredGeneration = max(highestRetiredGeneration ?? 0, generation)
        let matching = entries.filter {
            $0.value.userID == userID && $0.value.generation == generation
        }
        for (id, entry) in matching {
            entries[id] = nil
            entry.cancel()
        }
    }
}
