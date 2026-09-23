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
                    .textFieldStyle(.roundedBorder)
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
                    selectionRow(countryName, detail: model.draft.countryCode)
                }
                .buttonStyle(.plain)
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
                    selectionRow(model.draft.timeZoneIdentifier, detail: "IANA")
                }
                .buttonStyle(.plain)
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
        language.formattingLocale.localizedString(forRegionCode: model.draft.countryCode)
            ?? model.draft.countryCode
    }

    private func selectionRow(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: BodyFlowSpacing.sm) {
            Text(title).foregroundStyle(BodyFlowColor.primaryText)
            Spacer(minLength: BodyFlowSpacing.sm)
            Text(detail).foregroundStyle(BodyFlowColor.secondaryText)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
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
private struct CountrySelectionView: View {
    let selectedCode: String
    let language: SupportedAppLanguage
    let onSelect: (String) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(filteredRegions, id: \.identifier) { region in
            Button {
                onSelect(region.identifier)
                dismiss()
            } label: {
                HStack {
                    Text(name(for: region.identifier))
                    Spacer()
                    Text(region.identifier).foregroundStyle(.secondary)
                    if region.identifier == selectedCode {
                        Image(systemName: "checkmark")
                            .accessibilityLabel(copy("onboarding.selection.selected"))
                    }
                }
            }
            .foregroundStyle(BodyFlowColor.primaryText)
            .bodyFlowListRow()
        }
        .bodyFlowList()
        .navigationTitle(copy("onboarding.welcome.country-picker.title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            prompt: copy("onboarding.welcome.country-picker.search")
        )
    }

    private var filteredRegions: [Locale.Region] {
        Locale.Region.isoRegions
            .filter { region in
                query.isEmpty
                    || region.identifier.localizedCaseInsensitiveContains(query)
                    || name(for: region.identifier).localizedCaseInsensitiveContains(query)
            }
            .sorted { name(for: $0.identifier) < name(for: $1.identifier) }
    }

    private func name(for code: String) -> String {
        language.formattingLocale.localizedString(forRegionCode: code) ?? code
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        OnboardingCopy.string(key, language: language)
    }
}

@MainActor
private struct TimeZoneSelectionView: View {
    let selectedIdentifier: String
    let language: SupportedAppLanguage
    let onSelect: (String) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(filteredIdentifiers, id: \.self) { identifier in
            Button {
                onSelect(identifier)
                dismiss()
            } label: {
                HStack {
                    Text(identifier)
                    Spacer()
                    if identifier == selectedIdentifier {
                        Image(systemName: "checkmark")
                            .accessibilityLabel(copy("onboarding.selection.selected"))
                    }
                }
            }
            .foregroundStyle(BodyFlowColor.primaryText)
            .bodyFlowListRow()
        }
        .bodyFlowList()
        .navigationTitle(copy("onboarding.welcome.time-zone-picker.title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            prompt: copy("onboarding.welcome.time-zone-picker.search")
        )
    }

    private var filteredIdentifiers: [String] {
        TimeZone.knownTimeZoneIdentifiers.filter {
            query.isEmpty || $0.localizedCaseInsensitiveContains(query)
        }
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        OnboardingCopy.string(key, language: language)
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
