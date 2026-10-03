import SwiftUI

/// Carbohydrate and fat as received for the day (no targets exist for them,
/// so they are shown as grams only, never as a fraction).
struct TodayMacrosDescriptor: Equatable, Sendable {
    let carbsG: Decimal
    let fatG: Decimal
}

struct TodayProteinDescriptor: Equatable, Sendable {
    let consumedG: Decimal
    let targetG: Decimal?
    let remainingG: Decimal?
    let percentage: Int?
    let status: String
}

/// Leading-aligned disclosure title. A plain string title is laid out centred
/// by the system disclosure style once it wraps at accessibility sizes.
@MainActor
struct TodayDisclosureLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
