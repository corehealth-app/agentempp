import SwiftUI

@MainActor
struct WelcomeStepView: View {
    let model: OnboardingFlowModel
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            OnboardingStepHeader(
                titleKey: "onboarding.welcome.title",
                titleFallback: "Boas-vindas",
                messageKey: "onboarding.welcome.message",
                messageFallback: "Confirme como quer ser chamado e o contexto do seu dia local."
            )

            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text(copy("onboarding.welcome.display-name.title"))
                    .font(BodyFlowTypography.headline)
                TextField(copy("onboarding.welcome.display-name.placeholder"), text: displayName)
                    .textContentType(.name)
                    .submitLabel(.done)
                    .bodyFlowField()
                    .accessibilityLabel(copy("onboarding.welcome.display-name.title"))
                    .accessibilityHint(
                        model.accessibilityHint(for: [.displayNameRequired])
                    )
                    .accessibilityIdentifier("onboarding.display-name")
                OnboardingFieldIssue(model: model, candidates: [.displayNameRequired])
            }

            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text(copy("onboarding.welcome.app-language.title"))
                    .font(BodyFlowTypography.headline)
                Text(model.draft.localeIdentifier == "pt-BR" ? "Português (Brasil)" : "English (US)")
                    .foregroundStyle(BodyFlowColor.secondaryText)
                Text(copy("onboarding.welcome.app-language.detail"))
                    .font(BodyFlowTypography.caption)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                OnboardingFieldIssue(model: model, candidates: [.localeUnsupported])
            }

            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text(copy("onboarding.welcome.country.title"))
                    .font(BodyFlowTypography.headline)
                NavigationLink {
                    CountrySelectionView(
                        selectedCode: model.draft.countryCode,
                        language: language
                    ) {
                        model.updateCountryCode($0)
                    }
                } label: {
                    selectionRow(countryName, detail: nil)
                }
                .buttonStyle(.bodyFlowRow)
                .accessibilityHint(
                    model.accessibilityHint(for: [.countryInvalid])
                )
                .accessibilityIdentifier("onboarding.country")
                OnboardingFieldIssue(model: model, candidates: [.countryInvalid])
            }

            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text(copy("onboarding.welcome.time-zone.title"))
                    .font(BodyFlowTypography.headline)
                NavigationLink {
                    TimeZoneSelectionView(
                        selectedIdentifier: model.draft.timeZoneIdentifier,
                        language: language
                    ) {
                        model.updateTimeZoneIdentifier($0)
                    }
                } label: {
                    selectionRow(timeZone.city, detail: timeZone.zoneName)
                }
                .buttonStyle(.bodyFlowRow)
                .accessibilityHint(
                    model.accessibilityHint(for: [.timeZoneInvalid])
                )
                .accessibilityIdentifier("onboarding.timezone")
                OnboardingFieldIssue(model: model, candidates: [.timeZoneInvalid])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.welcome")
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        OnboardingCopy.string(key, language: language)
    }

    private var displayName: Binding<String> {
        Binding(
            get: { model.draft.displayName ?? "" },
            set: { model.updateDisplayName($0) }
        )
    }

    private var countryName: String {
        OnboardingCountryPresentation.name(for: model.draft.countryCode, language: language)
    }

    private var timeZone: OnboardingTimeZonePresentation {
        OnboardingTimeZonePresentation(
            identifier: model.draft.timeZoneIdentifier,
            language: language
        )
    }

    private func selectionRow(_ title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: BodyFlowSpacing.sm) {
            // The detail sits under the title, so a long zone name wraps
            // instead of squeezing the city at large text sizes.
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                Text(title).foregroundStyle(BodyFlowColor.primaryText)
                if let detail {
                    Text(detail)
                        .font(BodyFlowTypography.callout)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                }
            }
            Spacer(minLength: BodyFlowSpacing.sm)
            Image(symbol: .chevron)
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)
        }
        .padding(BodyFlowSpacing.md)
        .frame(maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget)
        .background(
            BodyFlowColor.surface,
            in: RoundedRectangle(cornerRadius: BodyFlowRadius.card)
        )
    }
}

@MainActor
struct CountrySelectionView: View {
    let selectedCode: String
    let language: SupportedAppLanguage
    let onSelect: (String) -> Void
    @State private var query: String
    @Environment(\.dismiss) private var dismiss

    init(
        selectedCode: String,
        language: SupportedAppLanguage,
        initialQuery: String = "",
        onSelect: @escaping (String) -> Void
    ) {
        self.selectedCode = selectedCode
        self.language = language
        self.onSelect = onSelect
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        let regions = OnboardingCountryPresentation.regions(matching: query, language: language)
        List(regions, id: \.identifier) { region in
            Button {
                onSelect(region.identifier)
                dismiss()
            } label: {
                HStack {
                    Text(name(for: region.identifier))
                    Spacer()
                    if region.identifier == selectedCode {
                        Image(symbol: .confirm)
                            .accessibilityLabel(copy("onboarding.selection.selected"))
                    }
                }
            }
            .foregroundStyle(BodyFlowColor.primaryText)
            .accessibilityAddTraits(region.identifier == selectedCode ? .isSelected : [])
            .bodyFlowListRow()
        }
        .bodyFlowList()
        .overlay {
            if regions.isEmpty {
                OnboardingPickerEmptyMessage(
                    copy("onboarding.welcome.country-picker.empty"),
                    identifier: "onboarding.country-picker.empty"
                )
            }
        }
        .navigationTitle(copy("onboarding.welcome.country-picker.title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            prompt: copy("onboarding.welcome.country-picker.search")
        )
    }

    private func name(for code: String) -> String {
        OnboardingCountryPresentation.name(for: code, language: language)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        OnboardingCopy.string(key, language: language)
    }
}

@MainActor
struct TimeZoneSelectionView: View {
    let selectedIdentifier: String
    let language: SupportedAppLanguage
    let onSelect: (String) -> Void
    @State private var query: String
    @Environment(\.dismiss) private var dismiss

    init(
        selectedIdentifier: String,
        language: SupportedAppLanguage,
        initialQuery: String = "",
        onSelect: @escaping (String) -> Void
    ) {
        self.selectedIdentifier = selectedIdentifier
        self.language = language
        self.onSelect = onSelect
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        let zones = OnboardingTimeZonePresentation.zones(matching: query, language: language)
        List(zones) { zone in
            Button {
                onSelect(zone.identifier)
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                        Text(zone.city)
                        if let zoneName = zone.zoneName {
                            Text(zoneName)
                                .font(BodyFlowTypography.callout)
                                .foregroundStyle(BodyFlowColor.secondaryText)
                        }
                    }
                    Spacer()
                    if zone.identifier == selectedIdentifier {
                        Image(symbol: .confirm)
                            .accessibilityLabel(copy("onboarding.selection.selected"))
                    }
                }
            }
            .foregroundStyle(BodyFlowColor.primaryText)
            .accessibilityAddTraits(zone.identifier == selectedIdentifier ? .isSelected : [])
            .bodyFlowListRow()
        }
        .bodyFlowList()
        .overlay {
            if zones.isEmpty {
                OnboardingPickerEmptyMessage(
                    copy("onboarding.welcome.time-zone-picker.empty"),
                    identifier: "onboarding.timezone-picker.empty"
                )
            }
        }
        .navigationTitle(copy("onboarding.welcome.time-zone-picker.title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            prompt: copy("onboarding.welcome.time-zone-picker.search")
        )
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        OnboardingCopy.string(key, language: language)
    }
}

/// A search with no result says so instead of leaving a blank list.
@MainActor
private struct OnboardingPickerEmptyMessage: View {
    let message: String
    let identifier: String

    init(_ message: String, identifier: String) {
        self.message = message
        self.identifier = identifier
    }

    var body: some View {
        Text(message)
            .font(BodyFlowTypography.body)
            .foregroundStyle(BodyFlowColor.secondaryText)
            .multilineTextAlignment(.center)
            .padding(BodyFlowSpacing.lg)
            .accessibilityIdentifier(identifier)
    }
}

#if DEBUG
#Preview("Boas-vindas · Válido") {
    OnboardingContainerView(model: .preview(step: .welcome))
}

#Preview("Boas-vindas · Validação") {
    OnboardingContainerView(model: .preview(
        step: .welcome,
        validationIssues: [.displayNameRequired, .countryInvalid, .timeZoneInvalid]
    ))
    .dynamicTypeSize(.accessibility3)
}

#Preview("Boas-vindas · Erro ao salvar") {
    OnboardingContainerView(model: .preview(
        step: .welcome,
        operationState: .failed(.serviceUnavailable)
    ))
}
#endif
