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
            ScrollView {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                    actionContent
                    RoutineActionSummary(model: model, allowsRetry: allowsRetry) {
                        Task { await model.retry() }
                    }
                }
                .padding(BodyFlowSpacing.lg)
            }
            .navigationTitle(copy("routine.confirmation.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy("routine.action.close")) { dismiss() }
                }
            }
        }
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
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
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
            if let message {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text(message)
                    if case .failed = model.mutationState, allowsRetry {
                        Button(action: retry) {
                            Text(copy("app.retry"))
                                .frame(
                                    minHeight: BodyFlowSpacing.minimumTapTarget
                                )
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("routine.mutation.retry")
                    }
                }
                .font(BodyFlowTypography.callout)
                .foregroundStyle(BodyFlowColor.secondaryText)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("routine.operation.summary")
    }

    private var message: String? {
        switch model.mutationState {
        case let .succeeded(receipt): receipt.data.status
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
