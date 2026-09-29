import SwiftUI

struct RoutineActionSheetItem: Identifiable {
    let status: RoutineActionStatus
    let model: RoutineActionModel
    let allowsRetry: Bool

    var id: String { status.rawValue }
}

@MainActor
struct RoutineActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Binding var selection: RoutineActionSheetItem?
    let model: RoutineActionModel
    let allowsRetry: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                BodyFlowColor.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                        actionContent
                        RoutineActionSummary(model: model, allowsRetry: allowsRetry) {
                            Task { await model.retry() }
                        }
                    }
                    .padding(BodyFlowSpacing.md)
                }
            }
            .navigationTitle(copy("routine.confirmation.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy("routine.action.close")) { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        // Result feedback for the patient's own action; the summary line is
        // always the primary channel.
        .bodyFlowResultFeedback(
            RoutineActionSummary.feedback,
            trigger: RoutineActionSummary.kind(for: model.mutationState)
        )
    }

    @ViewBuilder
    private var actionContent: some View {
        if let selection {
            switch selection.status {
        case .snoozed:
            RoutineSnoozeView(model: model) { snooze in
                Task { await model.submit(status: .snoozed, selection: snooze) }
            }
        case .taken, .skipped:
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                Text(selection.status == .taken
                    ? copy("routine.confirmation.taken")
                    : copy("routine.confirmation.skipped"))
                    .font(BodyFlowTypography.title)
                    .fontWeight(.semibold)
                Button {
                    Task { await model.submit(status: selection.status) }
                } label: {
                    Text(copy("routine.action.confirm"))
                        .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                }
                .buttonStyle(BodyFlowButtonStyle(role: .primary, isLoading: model.isSubmitting))
                .disabled(model.isSubmitting)
                .accessibilityIdentifier("routine.action.submit")
            }
            }
        } else {
            EmptyView()
        }
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RoutineCopy.string(key, language: language)
    }
}

@MainActor
struct RoutineActionSummary: View {
    @Environment(\.locale) private var locale
    let model: RoutineActionModel
    let allowsRetry: Bool
    let retry: @MainActor () -> Void

    var body: some View {
        Group {
            if let message, let kind = Self.kind(for: model.mutationState) {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    BodyFlowStatusLine(message, kind: kind, font: BodyFlowTypography.callout)
                    if case .failed = model.mutationState, allowsRetry {
                        Button(action: retry) {
                            Text(copy("app.retry"))
                                .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                        }
                        .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                        .accessibilityIdentifier("routine.mutation.retry")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("routine.operation.summary")
    }

    /// The status line kind for a mutation outcome; idle and submitting
    /// show nothing.
    static func kind(for state: RoutineMutationState) -> BodyFlowStatusLine.Kind? {
        switch state {
        case .succeeded: .success
        case .unavailable: .unavailable
        case .failed: .error
        case .idle, .submitting: nil
        }
    }

    /// Only the two terminal outcomes speak; unavailable stays silent.
    static func feedback(for kind: BodyFlowStatusLine.Kind?) -> BodyFlowHaptics.Result? {
        switch kind {
        case .success: .success
        case .error: .failure
        case .info, .warning, .pending, .empty, .unavailable, nil: nil
        }
    }

    private var message: String? {
        switch model.mutationState {
        case let .succeeded(receipt):
            String(
                format: copy("routine.action.recorded-format"),
                locale: language.formattingLocale,
                RoutineCopy.status(receipt.data.status, language: language)
            )
        case .unavailable: copy("routine.action.unavailable")
        case .failed: copy("routine.action.failed")
        case .idle, .submitting: nil
        }
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RoutineCopy.string(key, language: language)
    }
}
