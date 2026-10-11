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
                Self.fill(isEnabled: isEnabled),
                in: RoundedRectangle(cornerRadius: BodyFlowRadius.field, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: BodyFlowRadius.field, style: .continuous)
                    .strokeBorder(BodyFlowColor.color(.controlBoundary), lineWidth: 1)
            }
    }

    /// The surface of a field. Whatever is laid over part of a field to
    /// cover it (the shown password over its secure field) takes this very
    /// colour, so it is never seen as a patch.
    static func fill(isEnabled: Bool) -> Color {
        BodyFlowColor.color(isEnabled ? .surfaceElevated : .disabledFill)
    }
}

extension View {
    func bodyFlowField() -> some View {
        modifier(BodyFlowFieldStyle())
    }
}
