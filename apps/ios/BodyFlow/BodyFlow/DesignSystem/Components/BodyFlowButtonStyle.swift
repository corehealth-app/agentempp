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

    /// A submitting button is disabled to block duplicate submits but keeps
    /// its role colors so the progress indicator reads as "in progress",
    /// not as an unavailable control.
    func presentedBackgroundRole(isEnabled: Bool, isLoading: Bool) -> BodyFlowColor.Role? {
        backgroundRole(isEnabled: isEnabled || isLoading)
    }

    func presentedForegroundRole(isEnabled: Bool, isLoading: Bool) -> BodyFlowColor.Role {
        foregroundRole(isEnabled: isEnabled || isLoading)
    }
}

struct BodyFlowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let role: BodyFlowButtonRole
    var isLoading: Bool = false
    /// Compact buttons (icon-only actions such as the chat composer) keep the
    /// 44 pt floor and the same vertical padding, but hug their content
    /// instead of stretching to the full width.
    var isCompact: Bool = false

    init(role: BodyFlowButtonRole, isLoading: Bool = false, isCompact: Bool = false) {
        self.role = role
        self.isLoading = isLoading
        self.isCompact = isCompact
    }

    func makeBody(configuration: Configuration) -> some View {
        let foreground = BodyFlowColor.color(
            role.presentedForegroundRole(isEnabled: isEnabled, isLoading: isLoading)
        )
        HStack(spacing: BodyFlowSpacing.xs) {
            if isLoading {
                // Takes the role's foreground (white on teal, near-black on
                // mint) so it stays visible in both color schemes.
                ProgressView()
                    .tint(foreground)
                    .accessibilityHidden(true)
            }
            configuration.label
        }
            .font(BodyFlowTypography.button)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, isCompact ? BodyFlowSpacing.sm : BodyFlowSpacing.md)
            .padding(.vertical, BodyFlowSpacing.sm)
            .frame(minWidth: BodyFlowSpacing.minimumTapTarget,
                   maxWidth: isCompact ? nil : .infinity,
                   minHeight: BodyFlowSpacing.minimumTapTarget)
            .foregroundStyle(foreground)
            .background {
                if let background = role.presentedBackgroundRole(isEnabled: isEnabled, isLoading: isLoading) {
                    shape.fill(BodyFlowColor.color(background))
                }
            }
            .overlay {
                if (isEnabled || isLoading) && (role == .secondary || role == .destructive || configuration.isPressed) {
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
