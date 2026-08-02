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
            .navigationTitle("Confirmar ação")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
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
                Text(selection.status == .taken ? "Marcar como tomado" : "Marcar como pulado")
                    .font(BodyFlowTypography.title)
                    .fontWeight(.semibold)
                Button("Confirmar") {
                    Task { await model.submit(status: selection.status) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isSubmitting)
                .accessibilityIdentifier("routine.action.submit")
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
            }
            }
        } else {
            EmptyView()
        }
    }
}

@MainActor
struct RoutineActionSummary: View {
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
                            Text("Tentar novamente")
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
        case .unavailable: "Indisponível nesta versão"
        case .failed: "Não foi possível concluir. Tente novamente."
        case .idle, .submitting: nil
        }
    }
}
