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
    enum Result: Sendable {
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
        sensoryFeedback(trigger: trigger) { _, newValue in
            result(newValue)?.feedback
        }
    }
}
