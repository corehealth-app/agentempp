import SwiftUI

struct BodyFlowFieldStyle: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .padding(BodyFlowSpacing.md)
            .frame(minWidth: BodyFlowSpacing.minimumTapTarget,
                   minHeight: BodyFlowSpacing.minimumTapTarget)
            .foregroundStyle(BodyFlowColor.color(isEnabled ? .textPrimary : .disabledText))
            .background(
                BodyFlowColor.color(isEnabled ? .surfaceElevated : .disabledFill),
                in: RoundedRectangle(cornerRadius: BodyFlowRadius.field, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: BodyFlowRadius.field, style: .continuous)
                    .strokeBorder(BodyFlowColor.color(.controlBoundary), lineWidth: 1)
            }
    }
}

extension View {
    func bodyFlowField() -> some View {
        modifier(BodyFlowFieldStyle())
    }
}
