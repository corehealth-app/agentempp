import SwiftUI

@MainActor
struct RoutineListView: View {
    let kind: RoutineItemKind
    let dependencies: AppDependencies
    let invalidationCenter: FeatureInvalidationCenter
    @State private var model: RoutineListViewModel

    init(
        kind: RoutineItemKind,
        dependencies: AppDependencies,
        invalidationCenter: FeatureInvalidationCenter
    ) {
        self.kind = kind
        self.dependencies = dependencies
        self.invalidationCenter = invalidationCenter
        _model = State(initialValue: RoutineListViewModel(
            kind: kind,
            provider: dependencies.routine
        ))
    }

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            content
        }
        .navigationTitle(title)
        .task(id: invalidationCenter.revision(for: .routineList(kind: kind))) {
            await model.load(
                revision: invalidationCenter.revision(
                    for: .routineList(kind: kind)
                )
            )
        }
    }

    private var title: String {
        kind == .supplement ? "Suplementos" : "Medicamentos"
    }

    @ViewBuilder
    private var content: some View {
        let presentation = model.state.presentation
        if let screenState = presentation.fullScreenState {
            ScreenStateView(state: screenState) { Task { await model.retry(
                revision: invalidationCenter.revision(for: .routineList(kind: kind))
            ) } }
        } else if let snapshot = presentation.value {
            List(snapshot.items, id: \.id) { item in
                NavigationLink {
                    RoutineDetailView(
                        entry: RoutineDetailEntry(
                            kind: kind,
                            itemID: item.id,
                            listModel: model
                        ),
                        dependencies: dependencies,
                        invalidationCenter: invalidationCenter
                    )
                } label: {
                    RoutineItemRow(item: item)
                }
                .accessibilityIdentifier("routine.\(item.id)")
            }
            .listStyle(.insetGrouped)
        }
    }
}

@MainActor
private struct RoutineItemRow: View {
    let item: RoutineItemSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
            Text(item.name)
                .font(BodyFlowTypography.headline)
                .foregroundStyle(BodyFlowColor.primaryText)
            ForEach(item.schedules, id: \.id) { schedule in
                Text(schedule.localTime)
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
