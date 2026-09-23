import SwiftUI

@MainActor
struct RoutineListView: View {
    @Environment(\.locale) private var locale
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
        .bodyFlowScreenChrome(title: title)
        .task(id: invalidationCenter.revision(for: .routineList(kind: kind))) {
            await model.load(
                revision: invalidationCenter.revision(
                    for: .routineList(kind: kind)
                )
            )
        }
    }

    private var title: String {
        copy(kind == .supplement
            ? "routine.supplements.title"
            : "routine.medications.title")
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
                    RoutineItemRow(item: item, language: language)
                }
                .accessibilityIdentifier("routine.\(item.id)")
                .bodyFlowListRow()
            }
            .bodyFlowList()
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
private struct RoutineItemRow: View {
    let item: RoutineItemSnapshot
    let language: SupportedAppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
            Text(item.name)
                .font(BodyFlowTypography.headline)
                .foregroundStyle(BodyFlowColor.primaryText)
            ForEach(item.schedules, id: \.id) { schedule in
                HStack(spacing: BodyFlowSpacing.sm) {
                    Label(verbatim: schedule.localTime, symbol: .clock)
                    if let status = schedule.occurrence?.status {
                        Label(
                            verbatim: RoutineCopy.status(status, language: language),
                            symbol: .routineStatus(status)
                        )
                    }
                }
                .font(BodyFlowTypography.callout)
                .foregroundStyle(BodyFlowColor.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
