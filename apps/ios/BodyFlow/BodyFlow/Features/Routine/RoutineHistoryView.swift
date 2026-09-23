import SwiftUI

@MainActor
struct RoutineHistoryView: View {
    @Environment(\.locale) private var locale
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
        .bodyFlowScreenChrome(title: copy("routine.history.title"))
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
                    let presentation = RoutineHistoryRowPresentation(
                        row: row,
                        patientTimeZone: dependencies.patientTimeZone,
                        language: language
                    )
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                        Label(
                            verbatim: presentation.statusLabel,
                            symbol: .routineStatus(presentation.rawStatus)
                        )
                        .font(BodyFlowTypography.headline)
                        .foregroundStyle(BodyFlowColor.primaryText)
                        Text(
                            presentation.scheduledForLabel
                                ?? copy("routine.history.time-unavailable")
                        )
                            .font(BodyFlowTypography.callout)
                            .foregroundStyle(BodyFlowColor.secondaryText)
                    }
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("routine.history.row.\(row.id)")
                    .bodyFlowListRow()
                }
                if model.nextCursor != nil {
                    Button {
                        Task { await model.loadMore() }
                    } label: {
                        Text(copy("routine.history.load-more"))
                            .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                    }
                    .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                    .accessibilityIdentifier("routine.history.load-more")
                    .bodyFlowListRow()
                }
            }
            .bodyFlowList()
            .accessibilityIdentifier("routine.history")
        }
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RoutineCopy.string(key, language: language)
    }
}
