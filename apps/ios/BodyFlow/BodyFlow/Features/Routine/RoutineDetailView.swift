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
    /// Bumped when an upcoming occurrence becomes due, so its actions open
    /// without leaving the screen.
    @State private var clockTick = 0
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
        .bodyFlowScreenChrome(title: copy("routine.detail.title"))
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
        .task(id: actionConfiguration.upcoming) {
            guard let upcoming = actionConfiguration.upcoming else { return }
            let wait = upcoming.scheduledFor.timeIntervalSince(dependencies.timeProvider.now)
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait + 1))
            }
            guard !Task.isCancelled else { return }
            clockTick &+= 1
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
                                .font(BodyFlowTypography.screenTitle)
                                .foregroundStyle(BodyFlowColor.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(item.schedules, id: \.id) { schedule in
                                VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                                    Label(verbatim: schedule.localTime, symbol: .clock)
                                        .foregroundStyle(BodyFlowColor.primaryText)
                                    if let occurrence = schedule.occurrence {
                                        Label(
                                            verbatim: RoutineCopy.status(
                                                occurrence.status,
                                                language: language
                                            ),
                                            symbol: .routineStatus(occurrence.status)
                                        )
                                        .foregroundStyle(BodyFlowColor.secondaryText)
                                    }
                                }
                                .font(BodyFlowTypography.body)
                            }
                        }
                    }

                    actionArea

                    NavigationLink(value: AppRoute.routine(RoutineRoute(
                        kind: model.kind,
                        itemID: model.itemID,
                        destination: .history
                    ))) {
                        BodyFlowCard {
                            HStack(spacing: BodyFlowSpacing.sm) {
                                Label(verbatim: copy("routine.history.title"), symbol: .history)
                                    .font(BodyFlowTypography.headline)
                                    .foregroundStyle(BodyFlowColor.primaryText)
                                Spacer(minLength: BodyFlowSpacing.xs)
                                Image(symbol: .chevron)
                                    .font(BodyFlowTypography.caption)
                                    .foregroundStyle(BodyFlowColor.secondaryText)
                                    .accessibilityHidden(true)
                            }
                            .frame(
                                maxWidth: .infinity,
                                minHeight: BodyFlowSpacing.minimumTapTarget,
                                alignment: .leading
                            )
                        }
                    }
                    .buttonStyle(.bodyFlowRow)
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
            ScreenStateView(state: model.missingItemState, retryAction: {})
        }
    }

    /// One reading of the clock per render: the buttons and the "from HH:mm"
    /// note can never both disappear at the instant the occurrence falls due.
    @ViewBuilder
    private var actionArea: some View {
        let configuration = actionConfiguration
        if actionModel != nil, configuration.context != nil {
            actionButtons
        } else if let upcoming = configuration.upcoming {
            Label(verbatim: availableAtText(upcoming), symbol: .clock)
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("routine.actions.available-at")
        }
    }

    // Taken is the expected outcome (primary); snoozing keeps the item alive
    // (secondary); skipping is the quiet exit (tertiary).
    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(copy("routine.actions.title"))
                .font(BodyFlowTypography.cardTitle)
                .foregroundStyle(BodyFlowColor.primaryText)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                actionButton(.taken, title: copy("routine.action.taken"), role: .primary)
                actionButton(.snoozed, title: copy("routine.action.snooze"), role: .secondary)
                actionButton(.skipped, title: copy("routine.action.skip"), role: .tertiary)
            }
        }
    }

    private func actionButton(
        _ status: RoutineActionStatus,
        title: String,
        role: BodyFlowButtonRole
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
        }
        .buttonStyle(BodyFlowButtonStyle(role: role))
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
        _ = clockTick
        return RoutineActionConfiguration(
            kind: model.kind,
            itemID: model.itemID,
            schedules: model.item?.schedules ?? [],
            now: dependencies.timeProvider.now
        )
    }

    private func availableAtText(_ upcoming: RoutineUpcomingOccurrence) -> String {
        String(
            format: copy("routine.actions.available-at-format"),
            locale: language.formattingLocale,
            upcoming.localTime
        )
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RoutineCopy.string(key, language: language)
    }
}
