import SwiftUI
import UIKit

/// Turn reminders on for this iPhone, see the permission, how far the
/// schedule reaches and what was left out and why. Nothing here changes a
/// schedule, a dose or an occurrence on the server.
@MainActor
struct LocalRemindersView: View {
    let model: LocalReminderModel
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                BodyFlowStatusLine(statusMessage, kind: statusKind)
                    .accessibilityIdentifier("reminders.status")
                if let coverageText {
                    Text(coverageText)
                        .font(BodyFlowTypography.supporting)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                        .accessibilityIdentifier("reminders.coverage")
                }
            }
            .bodyFlowListRow()

            Section {
                actions
            }
            .bodyFlowListRow()

            if !skippedRows.isEmpty {
                Section {
                    ForEach(skippedRows, id: \.id) { row in
                        FixtureMetricRow(title: row.title, value: row.value)
                            .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                            .accessibilityIdentifier("reminders.skipped.\(row.id)")
                    }
                } header: {
                    Text(copy("reminders.skipped.section"))
                        .foregroundStyle(BodyFlowColor.primaryText)
                }
                .bodyFlowListRow()
            }

            Section {
                if let privacyText {
                    Text(privacyText)
                        .accessibilityIdentifier("reminders.privacy")
                }
                Text(copy("reminders.coverage.sync-note"))
                Text(copy("reminders.silenced.note"))
            }
            .font(BodyFlowTypography.supporting)
            .foregroundStyle(BodyFlowColor.secondaryText)
            .bodyFlowListRow()
        }
        .bodyFlowList()
        .bodyFlowScreenChrome(title: copy("reminders.screen.title"))
        .accessibilityIdentifier("screen.local-reminders")
        .task { await model.refresh() }
    }

    @ViewBuilder
    private var actions: some View {
        switch model.status {
        case .loading:
            EmptyView()
        case .notEnabled:
            Button {
                Task { await model.activate() }
            } label: {
                Text(copy("reminders.action.activate"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BodyFlowButtonStyle(role: .primary, isLoading: model.isWorking))
            .disabled(model.isWorking)
            .accessibilityIdentifier("reminders.activate")
        case .permissionDenied:
            Button {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text(copy("reminders.action.open-settings"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BodyFlowButtonStyle(role: .secondary))
            .accessibilityIdentifier("reminders.open-settings")
            deactivateButton
        case .preferencesOff, .timeZoneMissing, .scheduled, .unavailable:
            Button {
                Task { await model.refresh() }
            } label: {
                Text(copy("reminders.action.refresh"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BodyFlowButtonStyle(role: .secondary, isLoading: model.isWorking))
            .disabled(model.isWorking)
            .accessibilityIdentifier("reminders.refresh")
            deactivateButton
        }
    }

    private var deactivateButton: some View {
        Button {
            Task { await model.deactivate() }
        } label: {
            Text(copy("reminders.action.deactivate"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(BodyFlowButtonStyle(role: .tertiary))
        .disabled(model.isWorking)
        .accessibilityIdentifier("reminders.deactivate")
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        LocalReminderPresentation.string(key, language: language)
    }

    private var statusMessage: String {
        LocalReminderPresentation.statusMessage(model.status, language: language)
    }

    private var statusKind: BodyFlowStatusLine.Kind {
        switch model.status {
        case .loading: .pending
        case .notEnabled: .info
        case .permissionDenied, .preferencesOff, .timeZoneMissing: .warning
        case let .scheduled(coverage): coverage.scheduledCount > 0 ? .success : .empty
        case .unavailable: .unavailable
        }
    }

    private var coverageText: String? {
        guard case let .scheduled(coverage) = model.status else { return nil }
        return LocalReminderPresentation.coverageText(coverage, language: language)
    }

    private var privacyText: String? {
        guard case let .scheduled(coverage) = model.status else { return nil }
        return LocalReminderPresentation.privacyText(coverage.previewMode, language: language)
    }

    private var skippedRows: [LocalReminderPresentation.SkippedRow] {
        guard case let .scheduled(coverage) = model.status else { return [] }
        return LocalReminderPresentation.skippedRows(coverage, language: language)
    }
}

/// Copy for the reminders screen and the Profile row, kept testable.
enum LocalReminderPresentation {
    struct SkippedRow: Equatable {
        let id: String
        let title: String
        let value: String
    }

    static func string(_ key: String.LocalizationValue, language: SupportedAppLanguage) -> String {
        (try? AppLocalization.string(key, for: language)) ?? String(localized: key)
    }

    static func statusMessage(_ status: LocalReminderStatus, language: SupportedAppLanguage) -> String {
        switch status {
        case .loading:
            return string("reminders.status.loading", language: language)
        case .notEnabled:
            return string("reminders.status.not-enabled", language: language)
        case .permissionDenied:
            return string("reminders.status.permission-denied", language: language)
        case .preferencesOff:
            return string("reminders.status.preferences-off", language: language)
        case .timeZoneMissing:
            return string("reminders.status.time-zone-missing", language: language)
        case .unavailable:
            return string("reminders.status.unavailable", language: language)
        case let .scheduled(coverage):
            guard coverage.scheduledCount > 0 else {
                return string("reminders.status.none", language: language)
            }
            return String(
                format: string("reminders.status.scheduled", language: language),
                locale: language.formattingLocale,
                coverage.scheduledCount
            )
        }
    }

    /// Only a schedule the system holds is reported; the renewal notice is
    /// promised only when it was kept too.
    static func coverageText(_ coverage: LocalReminderCoverage, language: SupportedAppLanguage) -> String? {
        guard coverage.scheduledCount > 0, let end = coverage.coverageEnd else { return nil }
        let formatter = DateFormatter()
        formatter.locale = language.formattingLocale
        formatter.timeZone = TimeZone(identifier: coverage.timeZoneIdentifier)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return String(
            format: string("reminders.coverage.until", language: language),
            locale: language.formattingLocale,
            formatter.string(from: end)
        )
    }

    static func privacyText(_ mode: RoutinePreviewMode, language: SupportedAppLanguage) -> String {
        switch mode {
        case .private: string("reminders.privacy.private", language: language)
        case .name: string("reminders.privacy.name", language: language)
        case .nameAndDose: string("reminders.privacy.name_and_dose", language: language)
        }
    }

    static func skippedRows(_ coverage: LocalReminderCoverage, language: SupportedAppLanguage) -> [SkippedRow] {
        var rows = LocalReminderSkipReason.allCases.compactMap { reason -> SkippedRow? in
            guard let count = coverage.skipped[reason], count > 0 else { return nil }
            return SkippedRow(
                id: reason.rawValue,
                title: string(skippedKey(reason), language: language),
                value: count.formatted(.number.locale(language.formattingLocale))
            )
        }
        if coverage.notAccepted > 0 {
            rows.append(SkippedRow(
                id: "not_accepted",
                title: string("reminders.skipped.not_accepted", language: language),
                value: coverage.notAccepted.formatted(.number.locale(language.formattingLocale))
            ))
        }
        return rows
    }

    private static func skippedKey(_ reason: LocalReminderSkipReason) -> String.LocalizationValue {
        switch reason {
        case .beyondBudget: "reminders.skipped.beyond_budget"
        case .quietHours: "reminders.skipped.quiet_hours"
        case .dailyLimit: "reminders.skipped.daily_limit"
        case .nonexistentLocalTime: "reminders.skipped.nonexistent_local_time"
        case .noReevaluationDate: "reminders.skipped.no_reevaluation_date"
        }
    }

    /// The Profile row's one-line state.
    static func summary(_ status: LocalReminderStatus, language: SupportedAppLanguage) -> String {
        switch status {
        case .loading: string("reminders.summary.checking", language: language)
        case .notEnabled: string("reminders.summary.off", language: language)
        case .permissionDenied: string("reminders.summary.denied", language: language)
        case .preferencesOff, .timeZoneMissing, .unavailable:
            string("reminders.summary.attention", language: language)
        case let .scheduled(coverage):
            coverage.scheduledCount > 0
                ? string("reminders.summary.on", language: language)
                : string("reminders.summary.none", language: language)
        }
    }
}
