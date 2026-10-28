import SwiftUI

@MainActor
struct ClinicalFullEntryCard: View {
    let model: ClinicalFullModel
    @Environment(\.locale) private var locale
    private var language: SupportedAppLanguage { BodyFlowPresentationLanguage.resolve(locale) }
    var body: some View {
        BodyFlowCard {
            VStack(alignment:.leading,spacing:BodyFlowSpacing.md) {
                Text(copy("full.title")).font(BodyFlowTypography.sectionTitle)
                if let entry = model.entry {
                    if let clock = entry.clock { Text(String(format:copy("full.due"),clock.dueDate)) }
                    if entry.availability == .available || model.scope != nil || model.hasUncertainMutation {
                        NavigationLink(copy("full.open")) { ClinicalFullView(model:model) }
                            .buttonStyle(BodyFlowButtonStyle(role:.primary))
                    } else { Text(copy("full.entry." + (entry.unavailableReason?.rawValue ?? "unavailable"))) }
                    if entry.canOfferEarlyFull, model.scope == nil, !model.hasUncertainMutation {
                        NavigationLink(copy("full.early")) { ClinicalFullView(model:model,startReason:.notWellWithPlan) }
                            .buttonStyle(BodyFlowButtonStyle(role:.secondary))
                    }
                } else if model.isBusy { ProgressView(copy("full.loading")) }
                else { Text(copy("full.unavailable")) }
                if model.error != nil || model.entry == nil && !model.isBusy {
                    Button(copy("full.refresh")) { Task { await model.retry() } }
                        .buttonStyle(BodyFlowButtonStyle(role:.secondary)).disabled(model.isBusy)
                }
            }
        }
        .accessibilityIdentifier("full.entry")
        .task { await model.loadEntry() }
    }
    private func copy(_ key:String) -> String { ProgressCopy.string(String.LocalizationValue(key),language:language) }
}

/// Renders only the descriptor and clinical choices returned by the server.
/// Closing/reopening this view preserves the shell-owned model and intention.
@MainActor
struct ClinicalFullView: View {
    let model: ClinicalFullModel
    var startReason: ClinicalFullStartReason? = nil
    var photoAction: (@MainActor () -> Void)? = nil
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    private var language: SupportedAppLanguage {
        if let token = model.questionnaire?.locale, let value = SupportedAppLanguage(rawValue:token) { return value }
        return BodyFlowPresentationLanguage.resolve(locale)
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:BodyFlowSpacing.lg) {
                if let confirmation = model.confirmation {
                    Text(copy("full.completed")).font(BodyFlowTypography.sectionTitle)
                    Text(String(format:copy("full.due"),confirmation.nextDueDate))
                    Button(copy("full.done")) { Task { model.closeCompleted(); await model.loadEntry(); dismiss() } }
                        .buttonStyle(BodyFlowButtonStyle(role:.primary)).disabled(model.isBusy)
                } else if let preview = model.preview { previewCard(preview) }
                else if let form = model.questionnaire, let draft = model.draft {
                    formContent(form,draft:draft)
                    if let assessment = model.assessment { assessmentCard(assessment) }
                }
                if model.isBusy { ProgressView(copy("full.loading")) }
                if let error = model.error {
                    Text(copy(errorKey(error))).foregroundStyle(BodyFlowColor.secondaryText)
                        .accessibilityIdentifier("full.error")
                    Button(copy("full.retry")) { Task { await model.retry() } }
                        .buttonStyle(BodyFlowButtonStyle(role:.secondary)).disabled(model.isBusy)
                } else if model.questionnaire == nil, model.preview == nil, model.confirmation == nil, !model.isBusy {
                    Text(copy("full.unavailable"))
                    Button(copy("full.refresh")) { Task { await model.retry() } }
                        .buttonStyle(BodyFlowButtonStyle(role:.secondary))
                }
            }.padding(BodyFlowSpacing.md)
        }
        .background(BodyFlowColor.background)
        .navigationTitle(copy("full.title")).navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.clinical-full")
        .task {
            if model.scope == nil, model.preview == nil, model.confirmation == nil, !model.hasUncertainMutation { await model.start(reason:startReason) }
        }
    }
    private func formContent(_ form:ClinicalFullQuestionnaire,draft:ClinicalFullDraft) -> some View {
        VStack(alignment:.leading,spacing:BodyFlowSpacing.lg) {
            if let support = form.supportText { Text(support) }
            if let purposes = form.purposeOptions, purposes.count > 1 {
                Picker(copy("full.purpose"),selection:Binding(get:{ draft.activityPurpose },set:{ value in Task { await model.changePurpose(value) } })) {
                    ForEach(purposes,id:\.rawValue) { Text(copy("full.purpose."+$0.rawValue)).tag($0) }
                }.disabled(!model.canEdit)
            }
            if form.photoRequirement.required { photosCard(form,draft:draft) }
            ForEach(form.questions) { question in
                BodyFlowCard { questionContent(question,draft:draft) }
            }
            if form.questions.contains(where:{ $0.key == .weightKg }), draft.answers.weightKg != nil {
                Toggle(copy("full.measure-confirmed"),isOn:Binding(get:{ draft.measureConfirmed },set:{ selected in model.edit { $0.measureConfirmed = selected } }))
                    .disabled(!model.canEdit)
            }
            if let preference = form.preferenceQuestion { preferenceCard(preference,form:form) }
            Button(copy("full.assess")) { Task { await model.assess() } }
                .buttonStyle(BodyFlowButtonStyle(role:.primary))
                .disabled(!model.canEdit || model.inputs.hasInvalidValues)
                .accessibilityIdentifier("full.assess")
        }
    }
    private func photosCard(_ form:ClinicalFullQuestionnaire,draft:ClinicalFullDraft) -> some View {
        BodyFlowCard {
            VStack(alignment:.leading,spacing:BodyFlowSpacing.md) {
                Text(copy("full.photos.title")).font(BodyFlowTypography.sectionTitle)
                Text(copy("full.photos.required"))
                if form.bodyFat.status == .ready, let percent = form.bodyFat.percent {
                    Text(MealProposalNumberParser.format(percent,language:language)+"%")
                        .font(BodyFlowTypography.headline).accessibilityIdentifier("full.body-fat")
                    Toggle(copy("full.body-fat.accept"),isOn:Binding(get:{ draft.acceptedBodyFat != nil },set:{ selected in
                        model.edit { if selected { $0.acceptBodyFat(from:form) } else { $0.revokeBodyFatAcceptance() } }
                    })).disabled(!model.canEdit)
                }
                if let photos = model.photos {
                    NavigationLink(copy(form.bodyFat.status == .ready ? "full.photos.replace" : "full.photos.open")) { ReevaluationPhotosView(model:photos) }
                        .buttonStyle(BodyFlowButtonStyle(role:.secondary)).disabled(!model.canOpenPhotos)
                        .accessibilityIdentifier("full.photos.open")
                } else if let photoAction {
                    Button(copy(form.bodyFat.status == .ready ? "full.photos.replace" : "full.photos.open"),action:photoAction)
                        .buttonStyle(BodyFlowButtonStyle(role:.secondary)).disabled(!model.canEdit)
                } else if form.bodyFat.status != .ready { Text(copy("full.photos.unavailable")) }
                Button(copy("full.refresh")) { Task { await model.reloadForm() } }
                    .buttonStyle(BodyFlowButtonStyle(role:.secondary)).disabled(!model.canOpenPhotos)
            }
        }
    }
    @ViewBuilder private func questionContent(_ question:ClinicalFullQuestion,draft:ClinicalFullDraft) -> some View {
        VStack(alignment:.leading,spacing:BodyFlowSpacing.sm) {
            Text(question.label).font(BodyFlowTypography.headline)
            if let hint = question.hint { Text(hint).font(BodyFlowTypography.callout) }
            switch question.inputKind {
            case .decimal, .integer, .text:
                TextField(question.unit.map { copy("full.unit."+$0) } ?? question.label,text:Binding(get:{ model.inputs.text[question.key] ?? "" },set:{ model.setText($0,question:question,language:language) }))
                    .keyboardType(question.inputKind == .text ? .default : .decimalPad).bodyFlowField()
                    .accessibilityIdentifier("full.answer."+question.key.rawValue)
                if model.inputs.invalid.contains(question.key) { Text(copy("full.invalid")).foregroundStyle(.red) }
                Button(question.optOutLabel) { model.setText("",question:question,language:language) }
            case .singleChoice, .boolean:
                Picker(question.label,selection:Binding(get:{ ClinicalFullInputState.selected(question.key,draft:draft) },set:{ model.selectOption($0,question:question) })) {
                    Text(question.optOutLabel).tag(Optional<ClinicalFullOptionValue>.none)
                    ForEach(question.options ?? [],id:\.value) { Text($0.label).tag(Optional($0.value)) }
                }.pickerStyle(.menu)
                if question.key == .activityLevel, draft.answers.activity?.activityLevel != nil {
                    Toggle(copy("full.activity-confirmed"),isOn:Binding(get:{ draft.answers.activity?.activityLevelConfirmed == true },set:{ value in model.edit { $0.answers.activity?.activityLevelConfirmed = value } }))
                }
            case .healthSelection:
                ForEach(question.options ?? [],id:\.value) { option in
                    if case .string(let token) = option.value {
                        Toggle(option.label,isOn:Binding(get:{ healthSelected(token,draft:draft) },set:{ selected in
                            model.edit {
                                if token == "none" { if selected { $0.selectNoHealthRisks() } else { $0.answers.healthCheck = nil } }
                                else if let code = ClinicalFullHealthRisk(rawValue:token) { $0.setHealthRisk(code,selected:selected) }
                            }
                        }))
                    }
                }
                Button(question.optOutLabel) { model.edit { $0.answers.healthCheck = nil } }
            }
        }.disabled(!model.canEdit)
    }
    private func preferenceCard(_ preference:ClinicalFullQuestionnaire.Preference,form:ClinicalFullQuestionnaire) -> some View {
        BodyFlowCard {
            VStack(alignment:.leading,spacing:BodyFlowSpacing.sm) {
                Picker(preference.label,selection:Binding(get:{ model.inputs.preferenceSelection },set:{ model.selectPreference($0,language:language) })) {
                    Text(copy("full.preference.unchanged")).tag("")
                    ForEach(preference.existingActions.filter { $0 != "change" },id:\.self) { Text(copy("full.preference."+$0)).tag($0) }
                    ForEach(preference.options,id:\.value) { option in
                        if case .string(let token) = option.value { Text(option.label).tag(token) }
                    }
                }
                if ["weight","body_fat"].contains(model.inputs.preferenceSelection) {
                    TextField(copy(model.inputs.preferenceSelection == "weight" ? "full.unit.kg" : "full.unit.percent"),text:Binding(get:{ model.inputs.preferenceText },set:{ model.setPreferenceText($0,language:language) }))
                        .keyboardType(.decimalPad).bodyFlowField()
                } else if model.inputs.preferenceSelection == "routine" {
                    Picker(preference.label,selection:Binding(get:{ model.inputs.preferenceRoutine },set:{ model.setPreferenceRoutine($0) })) {
                        Text(copy("full.select")).tag("")
                        ForEach(preference.routineOptions,id:\.value) { option in
                            if case .string(let token) = option.value { Text(option.label).tag(token) }
                        }
                    }
                }
                if model.inputs.invalidPreference { Text(copy("full.preference.invalid")).foregroundStyle(.red) }
            }.disabled(!model.canEdit)
        }
    }
    private func assessmentCard(_ value:ClinicalFullAssessment) -> some View {
        VStack(alignment:.leading,spacing:BodyFlowSpacing.md) {
            if let feedback = value.preference, feedback.status == .refused || feedback.status == .missing {
                Text(copy("full.preference.feedback."+(feedback.reason?.rawValue ?? "missing")))
            }
            if value.status == .available {
                ForEach(value.actions) { action in
                    Button(choiceLabel(action.choice)) { Task { await model.prepare(action.choice) } }
                        .buttonStyle(BodyFlowButtonStyle(role:.secondary)).disabled(!model.canEdit)
                }
            } else {
                Text(copy("full.assessment."+value.status.rawValue))
                if value.status == .healthDeclarationRequired {
                    Button(copy("full.health.declare")) { Task { await model.declareHealth() } }
                        .buttonStyle(BodyFlowButtonStyle(role:.primary)).disabled(!model.canEdit)
                }
            }
        }.accessibilityIdentifier("full.assessment")
    }
    private func previewCard(_ value:ClinicalFullPreview) -> some View {
        VStack(alignment:.leading,spacing:BodyFlowSpacing.md) {
            if value.status == .historicalDisplayUnavailable {
                Text(copy("full.historical-unavailable"))
            } else {
                if let choice = value.choice { Text(choiceLabel(choice)).font(BodyFlowTypography.sectionTitle) }
                if let phase = value.phase { Text(phase.onboardingLabel(for:language)) }
                if let calories = value.targets?.caloriesKcal { Text(copy("full.calories")+": "+TodayValueFormatter.mealKcal(Decimal(calories),language:language)) }
                if let protein = value.targets?.proteinG { Text(copy("full.protein")+": "+TodayValueFormatter.optionalGrams(protein,language:language)) }
                if value.professionalAssessmentRecommended == true { Text(copy("full.professional")) }
                if value.pauseWeightLossGuidance == true { Text(copy("full.pause-guidance")) }
                Button(copy(model.hasUncertainMutation ? "full.retry-confirm" : "full.confirm")) { Task { await model.confirm() } }
                    .buttonStyle(BodyFlowButtonStyle(role:.primary)).disabled(model.isBusy)
                    .accessibilityIdentifier("full.confirm")
            }
            if !model.hasUncertainMutation {
                Button(copy("full.back")) { model.backToDraft() }
                    .buttonStyle(BodyFlowButtonStyle(role:.secondary)).disabled(model.isBusy)
            }
        }
    }
    private func healthSelected(_ token:String,draft:ClinicalFullDraft) -> Bool {
        if token == "none" { return draft.answers.healthCheck == .noneReported }
        if case .risks(let values) = draft.answers.healthCheck, let code = ClinicalFullHealthRisk(rawValue:token) { return values.contains(code) }
        return false
    }
    private func choiceLabel(_ value:ClinicalFullChoice) -> String {
        if let phase = value.phase { return phase.onboardingLabel(for:language) }
        return copy("full.choice."+(value.action?.rawValue ?? value.kind.rawValue))
    }
    private func errorKey(_ value:ClinicalFullFailure) -> String {
        if model.hasUncertainMutation { return "full.uncertain" }
        switch value {
        case .offline: return "full.offline"
        case .changed: return "full.changed"
        case .busy: return "full.busy"
        case .invalidInput: return "full.invalid"
        default: return "full.unavailable"
        }
    }
    private func copy(_ key:String) -> String { ProgressCopy.string(String.LocalizationValue(key),language:language) }
}
