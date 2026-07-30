import SwiftUI

@MainActor
struct FeatureReadStateView<
    Value: Equatable & Sendable,
    Content: View
>: View {
    let state: FeatureReadState<Value>
    private let retryAction: @MainActor () -> Void
    private let content: (Value) -> Content

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

        if let fullScreenState = presentation.fullScreenState {
            ScreenStateView(
                state: fullScreenState,
                retryAction: retryAction
            )
        } else if let value = presentation.value {
            FeatureStateContentStack(
                showsStaleBanner: presentation.showsStaleBanner
            ) {
                content(value)
            }
        } else {
            EmptyView()
        }
    }
}
