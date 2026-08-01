import SwiftUI

@MainActor
struct RoutineHistoryView: View {
    let kind: RoutineItemKind
    let itemID: String
    let dependencies: AppDependencies
    let invalidationCenter: FeatureInvalidationCenter
    @State private var model: RoutineHistoryViewModel

    init(
        kind: RoutineItemKind,
        itemID: String,
        dependencies: AppDependencies,
        invalidationCenter: FeatureInvalidationCenter
    ) {
        self.kind = kind
        self.itemID = itemID
        self.dependencies = dependencies
        self.invalidationCenter = invalidationCenter
        _model = State(initialValue: RoutineHistoryViewModel(
            kind: kind,
            itemID: itemID,
            provider: dependencies.routine
        ))
    }

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            content
        }
        .navigationTitle("Histórico")
        .task(id: invalidationCenter.revision(
            for: .routineHistory(kind: kind, itemID: itemID)
        )) {
            await model.load(revision: invalidationCenter.revision(
                for: .routineHistory(kind: kind, itemID: itemID)
            ))
        }
    }

    @ViewBuilder
    private var content: some View {
        let presentation = model.state.presentation
        if let screenState = presentation.fullScreenState {
            ScreenStateView(state: screenState) { Task { await model.retry(
                revision: invalidationCenter.revision(
                    for: .routineHistory(kind: kind, itemID: itemID)
                )
            ) } }
        } else if !model.items.isEmpty {
            List {
                ForEach(model.items, id: \.id) { row in
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                        Text(row.status)
                            .font(BodyFlowTypography.headline)
                        Text(row.scheduledFor.value.formatted(date: .abbreviated, time: .shortened))
                            .font(BodyFlowTypography.callout)
                            .foregroundStyle(BodyFlowColor.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                }
                if model.nextCursor != nil {
                    Button("Carregar mais") {
                        Task { await model.loadMore() }
                    }
                    .accessibilityIdentifier("routine.history.load-more")
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("routine.history")
        }
    }
}
