import SwiftUI

struct TodayHydrationDescriptor: Equatable, Sendable {
    let consumedML: Int
    let targetML: Int?
    let remainingML: Int?
    let percentage: Int?
    let status: String

    var targetText: String {
        TodayValueFormatter.optionalMilliliters(targetML)
    }

    var remainingText: String {
        TodayValueFormatter.optionalMilliliters(remainingML)
    }
}

