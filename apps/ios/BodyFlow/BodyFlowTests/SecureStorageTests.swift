import Foundation
import Testing

@testable import BodyFlow

@Suite("Secure Storage Boundary")
struct SecureStorageTests {
    @Test("stores, reads, and removes data only in memory")
    func storesReadsAndRemovesData() async {
        let store = InMemorySecureStore()
        let expected = Data([1, 2, 3])

        await store.store(expected, forKey: "fixture-key")
        let stored = await store.data(forKey: "fixture-key")
        #expect(stored == expected)

        await store.removeData(forKey: "fixture-key")
        let removed = await store.data(forKey: "fixture-key")
        #expect(removed == nil)
    }
}
