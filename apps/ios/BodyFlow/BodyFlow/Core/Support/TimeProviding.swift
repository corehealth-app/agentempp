import Foundation

protocol TimeProviding: Sendable {
    var now: Date { get }
}

struct SystemTimeProvider: TimeProviding {
    var now: Date {
        Date()
    }
}
