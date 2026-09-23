import SwiftUI

/// Brand-backed grouped list: the system grouped gray is replaced by the
/// primary background and rows sit on the secondary surface. Applies to
/// `List` and `Form` alike; rows/sections opt in with `bodyFlowListRow()`
/// because row backgrounds are read per row, not from the list itself.
struct BodyFlowListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(BodyFlowColor.color(.backgroundPrimary))
    }
}

struct BodyFlowListRowStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.listRowBackground(BodyFlowColor.color(.backgroundSecondary))
    }
}

extension View {
    func bodyFlowList() -> some View {
        modifier(BodyFlowListStyle())
    }

    func bodyFlowListRow() -> some View {
        modifier(BodyFlowListRowStyle())
    }
}
