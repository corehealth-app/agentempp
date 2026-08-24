import Auth
import Foundation

struct DiscardingSupabaseAuthStorage: AuthLocalStorage,
    CustomStringConvertible, CustomReflectable {
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws {}

    var description: String { "DiscardingSupabaseAuthStorage(redacted)" }

    var customMirror: Mirror {
        Mirror(self, children: [:], displayStyle: .struct)
    }
}
