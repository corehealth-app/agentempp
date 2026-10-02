import SwiftUI

/// Result feedback for operations the patient just triggered: a confirmed
/// registration, a routine action, a saved preference, a failure worth
/// noticing. Never used for navigation, refresh, filtering or arriving
/// content — feedback follows the patient's own action, not the app's.
///
/// Result haptics survive Reduce Motion (they are not movement); the app
/// never uses them as the only channel, since every case here is also shown
/// as a status line.
enum BodyFlowHaptics {
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
