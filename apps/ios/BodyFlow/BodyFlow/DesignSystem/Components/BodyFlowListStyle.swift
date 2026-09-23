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
    /// A selected/emphasized row sits on the elevated surface so the choice
    /// is visible beyond its glyph; every other row keeps the secondary one.
    var isEmphasized: Bool = false

    static func backgroundRole(isEmphasized: Bool) -> BodyFlowColor.Role {
        isEmphasized ? .surfaceElevated : .backgroundSecondary
    }

    func body(content: Content) -> some View {
        content.listRowBackground(
            BodyFlowColor.color(Self.backgroundRole(isEmphasized: isEmphasized))
        )
    }
}

extension View {
    func bodyFlowList() -> some View {
        modifier(BodyFlowListStyle())
    }

    func bodyFlowListRow(isEmphasized: Bool = false) -> some View {
        modifier(BodyFlowListRowStyle(isEmphasized: isEmphasized))
    }
}
