import SwiftUI

@MainActor
struct CoachPersonaPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let model: CoachPersonaEditorModel

    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                BodyFlowColor.background.ignoresSafeArea()

                content
            }
            .navigationTitle("Personalidade do coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        saveSelection()
                    }
                    .disabled(!canSave)
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
            ProgressView("Carregando personalidade…")
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
                Text("A personalidade muda o estilo da conversa, sem alterar cálculos ou orientações.")
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            }

            if let error {
                Section {
                    AuthFieldMessage(error: error)

                    if model.persisted == nil {
                        Button("Tentar novamente") {
                            Task { await model.load() }
                        }
                    }
                }
            }

            Section("Escolha uma opção") {
                ForEach(CoachPersona.allCases, id: \.self) { persona in
                    Button {
                        model.select(persona)
                    } label: {
                        HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                            Image(systemName: model.selected == persona ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(BodyFlowColor.accent)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                                Text(persona.displayName)
                                    .font(BodyFlowTypography.headline)
                                    .foregroundStyle(BodyFlowColor.primaryText)

                                Text(persona.summary)
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
                    .accessibilityIdentifier("persona.\(persona.id)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(BodyFlowColor.background)
        .overlay {
            if isSaving {
                ProgressView("Salvando…")
                    .padding(BodyFlowSpacing.md)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
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
}

#if DEBUG
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
        initialSelected: .focus,
        initialPersisted: .focus,
        initialOperationState: .idle
    ))
}

#Preview("Coach no Perfil · Salvando") {
    CoachPersonaPickerView(model: CoachPersonaEditorModel(
        userID: "preview-user",
        repository: ProfilePersonaPreviewRepository(persona: .focus),
        initialSelected: .zen,
        initialPersisted: .focus,
        initialOperationState: .saving
    ))
}

#Preview("Coach no Perfil · Erro recuperável") {
    CoachPersonaPickerView(model: CoachPersonaEditorModel(
        userID: "preview-user",
        repository: ProfilePersonaPreviewRepository(persona: .focus),
        initialSelected: .focus,
        initialPersisted: .focus,
        initialOperationState: .failed(.storageUnavailable)
    ))
}
#endif
