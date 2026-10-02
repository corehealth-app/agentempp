import SwiftUI

/// Two kinds of feedback, both following the patient's own finger:
/// - result feedback for operations they triggered (confirmed registration,
///   routine action, saved preference, a failure worth noticing);
/// - a light tap on the primary actions and a selection tick on the tab bar
///   (Eduardo, 02/10: touches must answer). Never on refresh, filtering or
///   content arriving on its own.
///
/// Haptics survive Reduce Motion (they are not movement); the app never
/// uses them as the only channel: results are also shown as a status line
/// and taps also scale the control.
enum BodyFlowHaptics {
    enum Tap {
        /// The primary role answers with a light impact on touch down; the
        /// quieter roles rely on their visual press state only.
        static func feedback(for role: BodyFlowButtonRole) -> SensoryFeedback? {
            role == .primary ? .impact(weight: .light) : nil
        }

        /// The central brand action and the Flow shortcut.
        static let action: SensoryFeedback = .impact(weight: .light)
        /// Changing the selected tab.
        static let selection: SensoryFeedback = .selection
    }

    enum Result: Equatable, Sendable {
        case success
        case warning
        case failure

        var feedback: SensoryFeedback {
            switch self {
            case .success: .success
            case .warning: .warning
            case .failure: .error
            }
        }
    }
}

extension View {
    /// Plays the result feedback when `trigger` becomes non-nil with a new
    /// value; a nil result stays silent.
    func bodyFlowResultFeedback<Trigger: Equatable>(
        _ result: @escaping (Trigger) -> BodyFlowHaptics.Result?,
        trigger: Trigger
    ) -> some View {
        modifier(BodyFlowResultFeedbackModifier(result: result, trigger: trigger))
    }
}

private struct BodyFlowResultFeedbackEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// A visible operation coordinator can own feedback instead of nested summaries.
    var bodyFlowResultFeedbackEnabled: Bool {
        get { self[BodyFlowResultFeedbackEnabledKey.self] }
        set { self[BodyFlowResultFeedbackEnabledKey.self] = newValue }
    }
}

private struct BodyFlowResultFeedbackModifier<Trigger: Equatable>: ViewModifier {
    @Environment(\.bodyFlowResultFeedbackEnabled) private var enabled
    let result: (Trigger) -> BodyFlowHaptics.Result?
    let trigger: Trigger

    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: trigger) { _, value in
            enabled ? result(value)?.feedback : nil
        }
    }
}
