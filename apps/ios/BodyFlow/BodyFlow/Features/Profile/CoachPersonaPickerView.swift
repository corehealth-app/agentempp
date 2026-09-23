import SwiftUI

@MainActor
struct CoachPersonaPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    let model: CoachPersonaEditorModel

    @State private var saveTask: Task<Void, Never>?
    /// Counts persisted saves so the success feedback plays once per save.
    @State private var savedSelections = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BodyFlowBrandHeader()

                ZStack {
                    BodyFlowColor.background.ignoresSafeArea()
                    content
                }
            }
            .navigationTitle(copy("profile.persona.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // No width floor on the whole cancellation item: the bar
                // measures its leading item with a zero-width proposal, so a
                // `frame(minWidth: 44)` resolved to exactly 44 pt and clipped
                // "Cancelar" to "ancela" (hierarchy: host `{20,82,44,36}`,
                // button `{20,78,44,44}`; the trailing Save, measured with a
                // fitting proposal, came out at its natural 73 pt). The text
                // now sizes naturally (91.7 pt); only the glyph shown at
                // accessibility sizes keeps the 44 pt width floor, and the
                // 44 pt height floor stays on the item.
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        if dynamicTypeSize.isAccessibilitySize {
                            Image(symbol: .close)
                                .frame(minWidth: BodyFlowSpacing.minimumTapTarget)
                        } else {
                            Text(copy("profile.persona.cancel"))
                        }
                    }
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
                    .disabled(isSaving)
                    .accessibilityLabel(copy("profile.persona.cancel"))
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveSelection()
                    } label: {
                        if dynamicTypeSize.isAccessibilitySize {
                            Image(symbol: .confirm)
                        } else {
                            Text(copy("profile.persona.save"))
                        }
                    }
                    .frame(
                        minWidth: BodyFlowSpacing.minimumTapTarget,
                        minHeight: BodyFlowSpacing.minimumTapTarget
                    )
                    .contentShape(Rectangle())
                    .disabled(!canSave)
                    .accessibilityLabel(copy("profile.persona.save"))
                    .accessibilityIdentifier("persona.save")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.profile.coach-persona")
        // The saved state is shown in the row and in the Profile; the
        // feedback only confirms the patient's own save.
        .bodyFlowResultFeedback({ $0 > 0 ? .success : nil }, trigger: savedSelections)
        .interactiveDismissDisabled(isSaving)
        .task {
            guard model.operationState == .loading else { return }
            await model.load()
        }
        .onDisappear {
            saveTask?.cancel()
            saveTask = nil
            model.cancelActiveOperation()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.operationState {
        case .loading:
            ProgressView(copy("profile.persona.loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .idle, .saving:
            personaList
        case .failed(let error):
            personaList(error: error)
        }
    }

    private var personaList: some View {
        personaList(error: nil)
    }

    private func personaList(error: AppPresentationError?) -> some View {
        List {
            Section {
                Text(copy("profile.persona.explanation"))
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            }
            .bodyFlowListRow()

            if let error {
                Section {
                    AuthFieldMessage(error: error)

                    if model.persisted == nil {
                        FeatureRetryButton {
                            Task { await model.load() }
                        }
                    }
                }
                .bodyFlowListRow()
            }

            Section(copy("profile.persona.options.section")) {
                if let options = model.pickerOptions {
                    ForEach(options) { option in
                        personaRow(option)
                    }
                } else {
                    ContentUnavailableView(
                        copy("profile.persona.unavailable"),
                        systemImage: BodyFlowSymbol.unavailable.systemName
                    )
                    .accessibilityIdentifier("persona.options.unavailable")
                    .bodyFlowListRow()
                }
            }
        }
        .bodyFlowList()
        .overlay {
            if isSaving {
                ProgressView(copy("profile.persona.saving"))
                    .padding(BodyFlowSpacing.md)
                    .background(savingSurface, in: savingShape)
                    .overlay {
                        savingShape.strokeBorder(
                            BodyFlowColor.color(.borderSubtle),
                            lineWidth: reduceTransparency ? 2 : 1
                        )
                    }
            }
        }
    }

    /// Opaque in both settings (no material behind the list), with a
    /// heavier outline under Reduce Transparency so the badge still stands
    /// apart from the rows without relying on translucency.
    private var savingSurface: Color {
        BodyFlowColor.color(.surfaceElevated)
    }

    private var savingShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: BodyFlowRadius.field, style: .continuous)
    }

    private func personaRow(
        _ option: CoachPersonaPickerOption
    ) -> some View {
        let persona = option.persona
        let isSelected = model.selected == persona
        return Button {
            model.select(persona)
        } label: {
            HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                Image(symbol: isSelected ? .selected : .unselected)
                    .foregroundStyle(BodyFlowColor.accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                    Text(option.name)
                        .font(BodyFlowTypography.headline)
                        .foregroundStyle(BodyFlowColor.primaryText)

                    Text(option.description)
                        .font(BodyFlowTypography.callout)
                        .foregroundStyle(BodyFlowColor.secondaryText)

                    Text(
                        model.selected == persona
                            ? copy("profile.persona.selected")
                            : copy("profile.persona.not-selected")
                    )
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bodyFlowRow)
        .disabled(isSaving || isUnresolvedLoadFailure)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("persona.\(option.id)")
        .bodyFlowListRow(isEmphasized: isSelected)
    }

    private var isSaving: Bool {
        model.operationState == .saving
    }

    private var isUnresolvedLoadFailure: Bool {
        if case .failed = model.operationState {
            return model.persisted == nil
        }
        return false
    }

    private var canSave: Bool {
        !isSaving
            && !isUnresolvedLoadFailure
            && model.pickerOptions != nil
            && model.selected != nil
            && model.selected != model.persisted
    }

    private func saveSelection() {
        guard saveTask == nil, canSave else { return }
        saveTask = Task { @MainActor in
            let shouldDismiss = await model.save()
            guard !Task.isCancelled else {
                saveTask = nil
                return
            }
            saveTask = nil
            if shouldDismiss {
                savedSelections += 1
                dismiss()
            }
        }
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        ProfileCopy.string(key, language: language)
    }
}

#if DEBUG
private let profilePersonaPreviewOptions = [
    CoachPersonaOption(
        code: .focus,
        name: "Focus",
        description: "Direto, firme e objetivo."
    ),
    CoachPersonaOption(
        code: .impulse,
        name: "Impulse",
        description: "Motivador, positivo e energético."
    ),
    CoachPersonaOption(
        code: .zen,
        name: "Zen",
        description: "Calmo, didático e acolhedor."
    ),
]

private actor ProfilePersonaPreviewRepository: CoachPersonaRepository {
    let persona: CoachPersona?

    init(persona: CoachPersona?) {
        self.persona = persona
    }

    func selectedPersona(for userID: String) async throws -> CoachPersona? {
        persona
    }

    func setPersona(_ persona: CoachPersona, for userID: String) async throws {}
}

#Preview("Coach no Perfil · Normal") {
    CoachPersonaPickerView(model: CoachPersonaEditorModel(
        userID: "preview-user",
        repository: ProfilePersonaPreviewRepository(persona: .focus),
        serverOptions: profilePersonaPreviewOptions,
        initialSelected: .focus,
        initialPersisted: .focus,
        initialOperationState: .idle
    ))
}

#Preview("Coach no Perfil · Salvando") {
    CoachPersonaPickerView(model: CoachPersonaEditorModel(
        userID: "preview-user",
        repository: ProfilePersonaPreviewRepository(persona: .focus),
        serverOptions: profilePersonaPreviewOptions,
        initialSelected: .zen,
        initialPersisted: .focus,
        initialOperationState: .saving
    ))
}

#Preview("Coach no Perfil · Erro recuperável") {
    CoachPersonaPickerView(model: CoachPersonaEditorModel(
        userID: "preview-user",
        repository: ProfilePersonaPreviewRepository(persona: .focus),
        serverOptions: profilePersonaPreviewOptions,
        initialSelected: .focus,
        initialPersisted: .focus,
        initialOperationState: .failed(.storageUnavailable)
    ))
}
#endif
