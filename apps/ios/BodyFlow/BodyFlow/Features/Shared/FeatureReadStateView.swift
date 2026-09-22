import SwiftUI

@MainActor
struct FeatureReadStateView<
    Value: Equatable & Sendable,
    Content: View
>: View {
    let state: FeatureReadState<Value>
    private let retryAction: @MainActor () -> Void
    private let content: (Value) -> Content
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion

    init(
        state: FeatureReadState<Value>,
        retryAction: @escaping @MainActor () -> Void,
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.state = state
        self.retryAction = retryAction
        self.content = content
    }

    var body: some View {
        let presentation = state.presentation
        let transition = BodyFlowMotion.stateTransition(reduceMotion: reduceMotion)

        // Full-screen state ↔ loaded content cross-fades (≤200 ms) instead
        // of popping; Reduce Motion makes the replacement immediate.
        Group {
            if let fullScreenState = presentation.fullScreenState {
                ScreenStateView(
                    state: fullScreenState,
                    retryAction: retryAction
                )
                .transition(transition)
            } else if let value = presentation.value {
                FeatureStateContentStack(
                    showsStaleBanner: presentation.showsStaleBanner
                ) {
                    content(value)
                }
                .transition(transition)
            } else {
                EmptyView()
            }
        }
        .animation(
            BodyFlowMotion.animation(.content, reduceMotion: reduceMotion),
            value: presentation.fullScreenState == nil
        )
    }
}
