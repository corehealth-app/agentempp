import SwiftUI

/// Current eligibility and group membership come from GET. One food item is
/// editable per PATCH; explicit DELETE selection never implies grouping.
/// What is drawn is decided by `MealRecordDetailPresentation`; every sentence
/// comes from the catalog through `MealRecordCopy`.
struct MealRecordDetailView: View {
    @Bindable var model: MealRecordModel
    /// The row History already holds for this record: shown read-only while
    /// the official read loads and when it fails.
    var localRow: HistoryMealLogRow? = nil
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var asksToDelete = false
    @FocusState private var focusedField: Field?

    var body: some View {
        let presentation = MealRecordDetailPresentation.make(model: model, localRow: localRow)
        Form {
            receipt
            previousConfirmations
            content(presentation.content)
            notices(presentation.content)
            progress
        }
        .bodyFlowList()
        .scrollDismissesKeyboard(.interactively)
        .bodyFlowScreenChrome(title: copy("confirmed-meal.title"))
        .accessibilityIdentifier("screen.meal-record")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { focusedField = nil } label: {
                    Text(copy("keyboard.done"))
                        .frame(minWidth: BodyFlowSpacing.minimumTapTarget,
                               minHeight: BodyFlowSpacing.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("keyboard.done")
            }
        }
        .task {
            model.beginPresentation()
            await model.load()
        }
        .onDisappear { model.discardPresentation() }
        .confirmationDialog(
            MealRecordCopy.deleteConfirmationTitle(count: model.deletionSelection.count, language: language),
            isPresented: $asksToDelete, titleVisibility: .visible
        ) {
            Button(copy("confirmed-meal.delete.confirm"), role: .destructive) { Task { await model.delete() } }
            Button(copy("confirmed-meal.delete.cancel"), role: .cancel) {}
        } message: {
            Text(MealRecordCopy.deleteConfirmationMessage(count: model.deletionSelection.count,
                                                          language: language))
        }
    }

    // MARK: Saved changes

    @ViewBuilder
    private var receipt: some View {
        if let receipt = model.confirmedReceipt {
            Section {
                Text(copy(model.hasCompletedCurrentPresentation
                    ? "confirmed-meal.saved.title" : "confirmed-meal.saved.previous"))
                    .font(BodyFlowTypography.sectionTitle)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .accessibilityAddTraits(.isHeader)
                LabeledContent(copy("confirmed-meal.saved.daily-consumption")) {
                    Text(kcal(receipt.data.snapshot.caloriesConsumed))
                }
                if receipt.data.nextRecordID != nil {
                    Button(copy("confirmed-meal.saved.refresh")) { Task { await model.load() } }
                        .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                        .accessibilityIdentifier("meal-record.refresh")
                }
            }
            .bodyFlowListRow()
            .accessibilityIdentifier("meal-record.saved")
        }
    }

    @ViewBuilder
    private var previousConfirmations: some View {
        if model.completedMutations.count > 1 {
            Section(copy("confirmed-meal.history.title")) {
                ForEach(Array(model.completedMutations.dropLast().enumerated()), id: \.offset) { entry in
                    LabeledContent(copy(entry.element.receipt.data.operation == .updated
                        ? "confirmed-meal.history.updated" : "confirmed-meal.history.deleted")) {
                        Text(kcal(entry.element.receipt.data.snapshot.caloriesConsumed))
                    }
                }
            }
            .bodyFlowListRow()
        }
    }

    // MARK: Record

    @ViewBuilder
    private func content(_ content: MealRecordDetailPresentation.Content) -> some View {
        switch content {
        case .nothing:
            EmptyView()
        case let .localRow(row):
            localRowBlock(row)
        case let .readOnly(items):
            heading(isForm: false)
            ForEach(items) { item in
                Section(item.foodName) { savedValues(item) }
                    .bodyFlowListRow()
            }
        case let .form(rows):
            heading(isForm: true)
            formRows(rows)
            formActions
        }
    }

    /// History's own row, as History shows it; nothing here can be changed.
    private func localRowBlock(_ row: HistoryMealLogRow) -> some View {
        let values = HistoryValuePresentation(language: language)
        return Section {
            Text(row.foodName)
                .font(BodyFlowTypography.sectionTitle)
                .foregroundStyle(BodyFlowColor.primaryText)
                .accessibilityAddTraits(.isHeader)
            if let mealType = row.mealType {
                Text(RegistrationCopy.mealTypeTitle(code: mealType, language: language))
                    .foregroundStyle(BodyFlowColor.secondaryText)
            }
            if let quantity = values.quantity(row.quantityG) { Text(quantity) }
            if let energy = values.energy(row.kcal) { Text(energy) }
        }
        .bodyFlowListRow()
        .accessibilityIdentifier("meal-record.local-row")
    }

    @ViewBuilder
    private func heading(isForm: Bool) -> some View {
        if let detail = model.detail?.data {
            Section {
                Text(copy(detail.scope == .group ? "confirmed-meal.scope.group" : "confirmed-meal.scope.item"))
                    .font(BodyFlowTypography.sectionTitle)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .accessibilityAddTraits(.isHeader)
                if isForm {
                    Text(copy("confirmed-meal.one-at-a-time"))
                        .font(BodyFlowTypography.callout)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                } else if !model.hasCompletedCurrentPresentation {
                    BodyFlowStatusLine(copy("confirmed-meal.read-only"), kind: .info)
                        .accessibilityIdentifier("meal-record.read-only")
                }
            }
            .bodyFlowListRow()
        }
    }

    private func formRows(_ rows: [MealRecordDetailPresentation.Row]) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            Section {
                savedValues(row.official)
                if let draftIndex = row.draftIndex {
                    editFields(index: draftIndex)
                        .disabled(!model.canEditDraft)
                }
                Toggle(copy("confirmed-meal.item.select-for-deletion"), isOn: deletionBinding(row.id))
                    .disabled(!model.canStartMutation)
                    .accessibilityIdentifier("meal-record.delete-selection.\(row.id)")
            } header: {
                Text(row.official.foodName)
                    .accessibilityIdentifier("meal-record.item.\(index)")
            }
            .bodyFlowListRow()
        }
    }

    private var formActions: some View {
        Section {
            Button(copy("confirmed-meal.action.save")) {
                focusedField = nil
                Task { await model.save(language: language) }
            }
            .buttonStyle(BodyFlowButtonStyle(role: .primary, isLoading: model.isSubmitting))
            .disabled(!MealRecordDetailPresentation.offersSave(model: model, language: language))
            .accessibilityIdentifier("meal-record.patch")
            Button(copy("confirmed-meal.action.delete")) {
                focusedField = nil
                asksToDelete = true
            }
            .buttonStyle(BodyFlowButtonStyle(role: .destructive))
            .disabled(!model.canStartMutation || model.deletionSelection.isEmpty)
            .accessibilityIdentifier("meal-record.delete")
        }
        .bodyFlowListRow()
    }

    /// The values the current official read holds for one food item.
    @ViewBuilder
    private func savedValues(_ item: MealRecordItemSnapshot) -> some View {
        if let quantity = item.quantityG {
            LabeledContent(copy("confirmed-meal.item.saved-quantity")) {
                Text(MealProposalNumberParser.format(quantity, language: language))
            }
        }
        if let mealType = item.mealType {
            Text(RegistrationCopy.mealTypeTitle(code: mealType, language: language))
        }
        Text(kcal(item.kcal))
    }

    @ViewBuilder
    private func editFields(index: Int) -> some View {
        caption("confirmed-meal.field.name")
        TextField(copy("confirmed-meal.field.name"), text: binding(index, field: .food), axis: .vertical)
            .lineLimit(1...3)
            .focused($focusedField, equals: .food)
            .bodyFlowField()
            .accessibilityLabel(copy("confirmed-meal.field.name"))
            .accessibilityIdentifier("meal-record.field.name")
        caption("confirmed-meal.field.quantity")
        TextField(copy("confirmed-meal.field.quantity"), text: binding(index, field: .quantity))
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: .quantity)
            .bodyFlowField()
            .accessibilityLabel(copy("confirmed-meal.field.quantity"))
            .accessibilityIdentifier("meal-record.field.quantity")
        caption("confirmed-meal.field.kcal")
        TextField(copy("confirmed-meal.field.kcal"), text: binding(index, field: .kcal))
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: .kcal)
            .bodyFlowField()
            .accessibilityLabel(copy("confirmed-meal.field.kcal"))
            .accessibilityIdentifier("meal-record.field.kcal")
        Text(copy("confirmed-meal.field.kcal.footer"))
            .font(BodyFlowTypography.callout)
            .foregroundStyle(BodyFlowColor.secondaryText)
    }

    private func caption(_ key: String) -> some View {
        Text(copy(key))
            .font(BodyFlowTypography.caption)
            .foregroundStyle(BodyFlowColor.secondaryText)
            .accessibilityHidden(true)
    }

    // MARK: Notices

    @ViewBuilder
    private func notices(_ content: MealRecordDetailPresentation.Content) -> some View {
        if MealRecordDetailPresentation.isRecordUnavailable(model: model) {
            unavailableRecordBlock
        } else {
            if let failure = model.failure {
                failureBlock(failure)
            } else if isForm(content), model.requiresReviewOfCurrentData {
                reviewBlock
            } else if isForm(content), let reason = model.rejectedInputBlock(language: language) {
                rejectedInputBlock(reason)
            }
            if model.canRestoreArchivedFields, model.archivedDraft?.hasTypedFields == true {
                restoreBlock
            }
            if model.readFailure != nil {
                readFailureBlock(showsLocalRow: showsLocalRow(content))
            }
        }
    }

    private var unavailableRecordBlock: some View {
        Section {
            BodyFlowStatusLine(copy("confirmed-meal.failure.not-found"), kind: .info)
                .accessibilityIdentifier("meal-record.unavailable")
            Button(copy("content.action.back")) { dismiss() }
                .buttonStyle(BodyFlowButtonStyle(role: .primary))
                .accessibilityIdentifier("meal-record.back")
        }
        .bodyFlowListRow()
    }

    private func failureBlock(_ failure: MealRecordFailure) -> some View {
        Section {
            BodyFlowStatusLine(
                MealRecordCopy.failureMessage(failure, hasTypedFields: hasTypedFields, language: language),
                kind: failure.mayRetrySameAttempt ? .warning : .error
            )
            .accessibilityIdentifier("meal-record.failure")
            if failure.mayRetrySameAttempt {
                Button(copy("confirmed-meal.action.retry-send")) { Task { await model.retry() } }
                    .buttonStyle(BodyFlowButtonStyle(role: .primary, isLoading: model.isSubmitting))
                    .disabled(model.isSubmitting || model.isLoading)
                    .accessibilityIdentifier("meal-record.retry-same-attempt")
            } else {
                if model.canCorrectRejectedInput && !model.isCorrectingRejectedInput {
                    Button(copy("confirmed-meal.action.correct-fields")) {
                        model.beginCorrectingRejectedInput()
                    }
                    .buttonStyle(BodyFlowButtonStyle(role: .primary))
                    .accessibilityIdentifier("meal-record.correct-rejected-input")
                }
                Button(copy("confirmed-meal.action.load-current")) { Task { await model.load() } }
                    .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                    .accessibilityIdentifier("meal-record.load-current")
                Button(copy("confirmed-meal.action.review-current")) { model.reviewLatest() }
                    .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                    .disabled(!model.canReviewLatest)
                    .accessibilityIdentifier("meal-record.review-current")
            }
        }
        .bodyFlowListRow()
    }

    /// The official read is newer than the typed form and nothing failed:
    /// the way to the current data is offered on its own.
    private var reviewBlock: some View {
        Section {
            BodyFlowStatusLine(copy("confirmed-meal.review-needed"), kind: .warning)
                .accessibilityIdentifier("meal-record.review-needed")
            Button(copy("confirmed-meal.action.review-current")) { model.reviewLatest() }
                .buttonStyle(BodyFlowButtonStyle(role: .primary))
                .disabled(!model.canReviewLatest)
                .accessibilityIdentifier("meal-record.review-current")
        }
        .bodyFlowListRow()
    }

    /// Why saving is unavailable although the form is open: these same
    /// fields were already declined.
    private func rejectedInputBlock(_ reason: MealRecordFailure) -> some View {
        Section {
            BodyFlowStatusLine(
                copy("confirmed-meal.rejected-input") + " " + copy(MealRecordCopy.failureKey(reason)),
                kind: .info
            )
            .accessibilityIdentifier("meal-record.rejected-input")
        }
        .bodyFlowListRow()
    }

    private var restoreBlock: some View {
        Section {
            Button(copy("confirmed-meal.action.restore-fields")) { model.restoreArchivedFields() }
                .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                .accessibilityIdentifier("meal-record.restore-attempted-fields")
        }
        .bodyFlowListRow()
    }

    private func readFailureBlock(showsLocalRow: Bool) -> some View {
        Section {
            BodyFlowStatusLine(
                MealRecordCopy.readFailureMessage(hasReceipt: model.confirmedReceipt != nil,
                    hasOfficialRead: model.detail != nil, hasTypedFields: hasTypedFields,
                    showsLocalRow: showsLocalRow, language: language),
                kind: .warning
            )
            .accessibilityIdentifier("meal-record.read-failure")
            Button(copy("confirmed-meal.action.retry-read")) { Task { await model.load() } }
                .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                .disabled(model.isLoading || model.isSubmitting)
                .accessibilityIdentifier("meal-record.retry-read")
        }
        .bodyFlowListRow()
    }

    @ViewBuilder
    private var progress: some View {
        if model.isLoading || model.isSubmitting {
            Section {
                BodyFlowDelayedProgress(
                    label: copy(model.isSubmitting ? "confirmed-meal.sending" : "confirmed-meal.loading")
                )
                .font(BodyFlowTypography.callout)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .accessibilityIdentifier("meal-record.progress")
            }
            .bodyFlowListRow()
        }
    }

    // MARK: Support

    private enum Field: Hashable { case food, quantity, kcal }

    private func binding(_ index: Int, field: Field) -> Binding<String> {
        Binding(get: {
            guard let draft = model.draft, draft.items.indices.contains(index) else { return "" }
            let item = draft.items[index]
            switch field {
            case .food: return item.foodName
            case .quantity: return item.quantityDisplay(language: language)
            case .kcal: return item.manualKcalDisplay(language: language)
            }
        }, set: { text in
            guard model.canEditDraft, var value = model.draft, value.items.indices.contains(index),
                  value.items[index].id == model.recordID else { return }
            switch field {
            case .food: value.items[index].foodName = text
            case .quantity: value.items[index].quantityText = text
            case .kcal: value.items[index].manualKcalText = text
            }
            model.draft = value
        })
    }

    private func deletionBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { model.deletionSelection.contains(id) },
                set: { model.selectForDeletion(id: id, selected: $0) })
    }

    private func isForm(_ content: MealRecordDetailPresentation.Content) -> Bool {
        if case .form = content { return true }
        return false
    }

    private func showsLocalRow(_ content: MealRecordDetailPresentation.Content) -> Bool {
        if case .localRow = content { return true }
        return false
    }

    private var hasTypedFields: Bool { model.draft?.hasTypedFields == true }
    private var language: SupportedAppLanguage { BodyFlowPresentationLanguage.resolve(locale) }
    private func copy(_ key: String) -> String { MealRecordCopy.string(key, language: language) }
    private func kcal(_ value: Decimal?) -> String {
        MealProposalEditorPresentation.officialKcalText(value, language: language)
    }
}
