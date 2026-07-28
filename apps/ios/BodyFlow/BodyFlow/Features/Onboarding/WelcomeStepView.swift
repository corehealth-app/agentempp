import SwiftUI

@MainActor
struct WelcomeStepView: View {
    let model: OnboardingFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            OnboardingStepHeader(
                title: "Boas-vindas",
                message: "Confirme como quer ser chamado e o contexto do seu dia local."
            )

            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text("Como você quer ser chamado?").font(BodyFlowTypography.headline)
                TextField("Seu nome", text: displayName)
                    .textContentType(.name)
                    .submitLabel(.next)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("onboarding.display-name")
                OnboardingFieldIssue(model: model, candidates: [.displayNameRequired])
            }

            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text("Idioma do app").font(BodyFlowTypography.headline)
                Text(model.draft.localeIdentifier == "pt-BR" ? "Português (Brasil)" : "English (US)")
                    .foregroundStyle(BodyFlowColor.secondaryText)
                Text("Sugerido a partir do idioma compatível do aparelho.")
                    .font(BodyFlowTypography.caption)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                OnboardingFieldIssue(model: model, candidates: [.localeUnsupported])
            }

            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text("País").font(BodyFlowTypography.headline)
                NavigationLink {
                    CountrySelectionView(selectedCode: model.draft.countryCode) {
                        model.updateCountryCode($0)
                    }
                } label: {
                    selectionRow(countryName, detail: model.draft.countryCode)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.country")
                OnboardingFieldIssue(model: model, candidates: [.countryInvalid])
            }

            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text("Fuso horário").font(BodyFlowTypography.headline)
                NavigationLink {
                    TimeZoneSelectionView(selectedIdentifier: model.draft.timeZoneIdentifier) {
                        model.updateTimeZoneIdentifier($0)
                    }
                } label: {
                    selectionRow(model.draft.timeZoneIdentifier, detail: "IANA")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.timezone")
                OnboardingFieldIssue(model: model, candidates: [.timeZoneInvalid])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.welcome")
    }

    private var displayName: Binding<String> {
        Binding(
            get: { model.draft.displayName ?? "" },
            set: { model.updateDisplayName($0) }
        )
    }

    private var countryName: String {
        Locale.current.localizedString(forRegionCode: model.draft.countryCode)
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
        .background(BodyFlowColor.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

@MainActor
private struct CountrySelectionView: View {
    let selectedCode: String
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
                        Image(systemName: "checkmark").accessibilityLabel("Selecionado")
                    }
                }
            }
            .foregroundStyle(BodyFlowColor.primaryText)
        }
        .navigationTitle("Selecionar país")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Buscar país ou código")
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
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}

@MainActor
private struct TimeZoneSelectionView: View {
    let selectedIdentifier: String
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
                        Image(systemName: "checkmark").accessibilityLabel("Selecionado")
                    }
                }
            }
            .foregroundStyle(BodyFlowColor.primaryText)
        }
        .navigationTitle("Selecionar fuso")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Buscar identificador IANA")
    }

    private var filteredIdentifiers: [String] {
        TimeZone.knownTimeZoneIdentifiers.filter {
            query.isEmpty || $0.localizedCaseInsensitiveContains(query)
        }
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
