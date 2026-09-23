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
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        if dynamicTypeSize.isAccessibilitySize {
                            Image(systemName: "xmark")
                        } else {
                            Text(copy("profile.persona.cancel"))
                        }
                    }
                    .frame(
                        minWidth: BodyFlowSpacing.minimumTapTarget,
                        minHeight: BodyFlowSpacing.minimumTapTarget
                    )
                    .contentShape(Rectangle())
                    .disabled(isSaving)
                    .accessibilityLabel(copy("profile.persona.cancel"))
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveSelection()
                    } label: {
                        if dynamicTypeSize.isAccessibilitySize {
                            Image(systemName: "checkmark")
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
                        Button(copy("state.retry")) {
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
                        systemImage: "nosign"
                    )
                    .accessibilityIdentifier("persona.options.unavailable")
                }
            }
            .bodyFlowListRow()
        }
        .bodyFlowList()
        .overlay {
            if isSaving {
                ProgressView(copy("profile.persona.saving"))
                    .padding(BodyFlowSpacing.md)
                    .background(
                        savingSurface,
                        in: RoundedRectangle(
                            cornerRadius: BodyFlowRadius.field,
                            style: .continuous
                        )
                    )
            }
        }
    }

    private var savingSurface: AnyShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(BodyFlowColor.color(.surfaceElevated))
            : AnyShapeStyle(.regularMaterial)
    }

    private func personaRow(
        _ option: CoachPersonaPickerOption
    ) -> some View {
        let persona = option.persona
        return Button {
            model.select(persona)
        } label: {
            HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                Image(systemName: model.selected == persona ? "checkmark.circle.fill" : "circle")
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
        .buttonStyle(.plain)
        .disabled(isSaving || isUnresolvedLoadFailure)
        .accessibilityAddTraits(model.selected == persona ? .isSelected : [])
        .accessibilityIdentifier("persona.\(option.id)")
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
