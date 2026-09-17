import SwiftUI

enum BodyFlowButtonRole: CaseIterable, Sendable {
    case primary, secondary, tertiary, destructive

    func foregroundRole(isEnabled: Bool) -> BodyFlowColor.Role {
        guard isEnabled else { return .disabledText }
        switch self {
        case .primary: return .onPrimary
        case .secondary, .tertiary: return .brandPrimary
        case .destructive: return .feedbackDestructive
        }
    }

    func backgroundRole(isEnabled: Bool) -> BodyFlowColor.Role? {
        guard isEnabled else { return .disabledFill }
        switch self {
        case .primary: return .brandPrimary
        case .secondary, .destructive: return .surfaceElevated
        case .tertiary: return nil
        }
    }
}

struct BodyFlowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let role: BodyFlowButtonRole

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BodyFlowTypography.button)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, BodyFlowSpacing.md)
            .padding(.vertical, BodyFlowSpacing.sm)
            .frame(minWidth: BodyFlowSpacing.minimumTapTarget,
                   maxWidth: .infinity,
                   minHeight: BodyFlowSpacing.minimumTapTarget)
            .foregroundStyle(BodyFlowColor.color(role.foregroundRole(isEnabled: isEnabled)))
            .background {
                if let background = role.backgroundRole(isEnabled: isEnabled) {
                    shape.fill(BodyFlowColor.color(background))
                }
            }
            .overlay {
                if isEnabled && (role == .secondary || role == .destructive || configuration.isPressed) {
                    shape.strokeBorder(
                        BodyFlowColor.color(borderRole),
                        lineWidth: configuration.isPressed ? 2 : 1
                    )
                }
            }
            .contentShape(shape)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: BodyFlowRadius.field, style: .continuous)
    }

    private var borderRole: BodyFlowColor.Role {
        switch role {
        case .primary: .onPrimary
        case .secondary: .controlBoundary
        case .tertiary: .brandPrimary
        case .destructive: .feedbackDestructive
        }
    }
}
