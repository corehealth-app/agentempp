import SwiftUI

/// The route entry owns the one documented Today-origin list read. The detail
/// view itself only observes its list model and never receives a provider.
@MainActor
struct RoutineDetailRouteView: View {
    let route: RoutineRoute
    let dependencies: AppDependencies
    let invalidationCenter: FeatureInvalidationCenter
    @State private var entry: RoutineDetailEntry

    init(
        route: RoutineRoute,
        dependencies: AppDependencies,
        invalidationCenter: FeatureInvalidationCenter
    ) {
        self.route = route
        self.dependencies = dependencies
        self.invalidationCenter = invalidationCenter
        _entry = State(initialValue: RoutineDetailEntry(
            kind: route.kind,
            itemID: route.itemID ?? "",
            provider: dependencies.routine
        ))
    }

    var body: some View {
        RoutineDetailView(
            entry: entry,
            dependencies: dependencies,
            invalidationCenter: invalidationCenter
        )
        .task(id: invalidationCenter.revision(for: .routineList(kind: route.kind))) {
            await entry.loadFromToday(revision: invalidationCenter.revision(
                for: .routineList(kind: route.kind)
            ))
        }
    }
}

@MainActor
struct RoutineDetailView: View {
    @Environment(\.locale) private var locale
    let dependencies: AppDependencies
    let invalidationCenter: FeatureInvalidationCenter
    let model: RoutineDetailViewModel
    @State private var actionModel: RoutineActionModel?
    @State private var appliedActionConfiguration: RoutineActionConfiguration?
    @State private var selectedAction: RoutineActionSheetItem?
    @AccessibilityFocusState private var operationFocus: RoutineAccessibilityFocusTarget?

    init(
        entry: RoutineDetailEntry,
        dependencies: AppDependencies,
        invalidationCenter: FeatureInvalidationCenter
    ) {
        self.dependencies = dependencies
        self.invalidationCenter = invalidationCenter
        model = entry.detailModel
    }

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            content
        }
        .navigationTitle(copy("routine.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedAction, onDismiss: {
            configureActionModel()
        }) { item in
            RoutineActionSheet(
                selection: $selectedAction,
                model: item.model,
                allowsRetry: item.allowsRetry
            )
        }
        .onAppear {
            configureActionModel()
        }
        .onChange(of: actionConfiguration) { _, _ in
            configureActionModel()
        }
        .onChange(of: actionModel?.isSubmitting) { _, isSubmitting in
            guard isSubmitting != true else { return }
            configureActionModel()
        }
        .onChange(of: actionModel?.accessibilityFocusTarget) { _, target in
            guard let target, let actionModel else { return }
            operationFocus = target
            actionModel.consumeAccessibilityFocus()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let item = model.item {
            ScrollView {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                    BodyFlowCard {
                        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                            Text(item.name)
                                .font(BodyFlowTypography.title)
                                .fontWeight(.semibold)
                            ForEach(item.schedules, id: \.id) { schedule in
                                VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                                    Text(schedule.localTime)
                                    if let occurrence = schedule.occurrence {
                                        Text(RoutineCopy.status(
                                            occurrence.status,
                                            language: language
                                        ))
                                            .foregroundStyle(BodyFlowColor.secondaryText)
                                    }
                                }
                                .font(BodyFlowTypography.body)
                            }
                        }
                    }

                    if actionModel != nil, actionConfiguration.context != nil {
                        actionButtons
                    }

                    NavigationLink(value: AppRoute.routine(RoutineRoute(
                        kind: model.kind,
                        itemID: model.itemID,
                        destination: .history
                    ))) {
                        Label(
                            copy("routine.history.title"),
                            systemImage: "clock.arrow.circlepath"
                        )
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("routine.history")

                    if let actionModel {
                        RoutineActionSummary(
                            model: actionModel,
                            allowsRetry: actionConfiguration.context != nil
                        ) {
                            Task { await actionModel.retry() }
                        }
                        .accessibilityFocused($operationFocus, equals: .operationSummary)
                    }
                }
                .padding(BodyFlowSpacing.md)
            }
        } else {
            ScreenStateView(state: .unavailable, retryAction: {})
        }
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(copy("routine.actions.title"))
                .font(BodyFlowTypography.headline)
            VStack(alignment: .leading) {
                actionButton(.taken, title: copy("routine.action.taken"))
                actionButton(.snoozed, title: copy("routine.action.snooze"))
                actionButton(.skipped, title: copy("routine.action.skip"))
            }
        }
    }

    private func actionButton(
        _ status: RoutineActionStatus,
        title: String
    ) -> some View {
        Button {
            guard let actionModel else { return }
            selectedAction = RoutineActionSheetItem(
                status: status,
                model: actionModel,
                allowsRetry: actionConfiguration.context != nil
            )
        } label: {
            Text(title)
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("routine.action.\(status.rawValue)")
        .disabled(actionModel?.isSubmitting ?? true)
    }

    private func configureActionModel() {
        guard selectedAction == nil else { return }
        let configuration = actionConfiguration
        guard configuration.shouldApply(
            over: appliedActionConfiguration,
            isSubmitting: actionModel?.isSubmitting ?? false
        ) else { return }
        appliedActionConfiguration = configuration
        guard let context = configuration.context else { return }
        actionModel = RoutineActionModel(
            provider: dependencies.routine,
            timeProvider: dependencies.timeProvider,
            keyProvider: dependencies.idempotencyKeyProvider,
            invalidationCenter: invalidationCenter,
            patientTimeZone: dependencies.patientTimeZone,
            context: context
        )
    }

    private var actionConfiguration: RoutineActionConfiguration {
        RoutineActionConfiguration(
            kind: model.kind,
            itemID: model.itemID,
            schedules: model.item?.schedules ?? []
        )
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RoutineCopy.string(key, language: language)
    }
}
