import SwiftUI

/// The review of a plan draft: what Flow proposed or what the document said,
/// for the patient to correct, complete, confirm or discard.
@MainActor
struct PlanDraftReviewView: View {
    @State private var model: PlanDraftReviewModel
    @State private var askingToConfirm = false
    @State private var askingToDiscard = false
    @State private var removal: PlanDraftDocument.Path?
    @FocusState private var focusedField: String?
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    init(model: PlanDraftReviewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                    // Said in every state of the screen, not only while
                    // reviewing.
                    notices
                    content
                }
                .padding(BodyFlowSpacing.md)
            }
        }
        .bodyFlowScreenChrome(title: copy(PlanDraftCopy.navigationTitleKey(imported: model.snapshot?.isImported)))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { focusedField = nil } label: {
                    Text(copy("keyboard.done"))
                        .frame(
                            minWidth: BodyFlowSpacing.minimumTapTarget,
                            minHeight: BodyFlowSpacing.minimumTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("keyboard.done")
            }
        }
        .accessibilityIdentifier("screen.plan.draft")
        .task { await model.load() }
        .onDisappear { model.invalidate() }
        .confirmationDialog(
            copy(model.snapshot?.replacesCurrentPlan == true
                ? "plan.draft.confirm.replace.title" : "plan.draft.confirm.add.title"),
            isPresented: $askingToConfirm,
            titleVisibility: .visible
        ) {
            Button(copy(model.snapshot?.replacesCurrentPlan == true
                ? "plan.draft.confirm.replace.action" : "plan.draft.confirm.add.action")) {
                Task { await model.confirm() }
            }
            .accessibilityIdentifier("plan.draft.confirm.accept")
            Button(copy("plan.draft.confirm.cancel"), role: .cancel) {}
        } message: {
            Text(copy("plan.draft.notice.not-reviewed"))
        }
        .confirmationDialog(
            copy("plan.draft.remove.title"),
            isPresented: Binding(
                get: { removal != nil },
                set: { if !$0 { removal = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(copy("plan.draft.remove.action"), role: .destructive) {
                if let path = removal {
                    Task { await model.remove(path, language: language) }
                }
                removal = nil
            }
            .accessibilityIdentifier("plan.draft.remove.accept")
            Button(copy("plan.draft.confirm.cancel"), role: .cancel) { removal = nil }
        } message: {
            Text(copy("plan.draft.remove.message"))
        }
        .confirmationDialog(
            copy(PlanDraftCopy.discardTitleKey(imported: isImported)),
            isPresented: $askingToDiscard,
            titleVisibility: .visible
        ) {
            Button(copy("plan.draft.discard.action"), role: .destructive) {
                Task { await model.discard() }
            }
            .accessibilityIdentifier("plan.draft.discard.accept")
            Button(copy("plan.draft.confirm.cancel"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            progress(copy("plan.draft.loading"))
        case .inProgress:
            progress(copy(model.snapshot?.isImported == true
                ? "plan.draft.in-progress.reading" : "plan.draft.in-progress.generating"))
            discardButton
        case .review:
            review
        case .confirmed:
            outcome(
                title: copy("plan.draft.confirmed.title"),
                detail: copy("plan.draft.notice.confirmed"),
                kind: .success,
                identifier: "plan.draft.confirmed"
            )
        case .discarded:
            outcome(
                title: copy(PlanDraftCopy.discardedTitleKey(imported: isImported)),
                detail: nil,
                kind: .info,
                identifier: "plan.draft.discarded"
            )
        case let .closed(status, failureCode):
            outcome(
                title: copy(PlanDraftCopy.closedKey(status, failureCode: failureCode)),
                detail: nil,
                kind: .error,
                identifier: "plan.draft.closed"
            )
        case let .failed(failure):
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                BodyFlowStatusLine(copy(PlanDraftCopy.failureKey(failure)), kind: .error)
                    .accessibilityIdentifier("plan.draft.failure")
                button("state.retry", role: .secondary, id: "plan.draft.retry") {
                    Task { await model.load() }
                }
            }
        }
    }

    /// A draft is not a plan, and the patient's confirmation is not a
    /// professional review.
    private var notices: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            if model.phase == .confirmed {
                EmptyView()
            } else {
                BodyFlowStatusLine(copy("plan.draft.notice.draft"), kind: .info)
                    .accessibilityIdentifier("plan.draft.notice.draft")
                BodyFlowStatusLine(copy("plan.draft.notice.not-reviewed"), kind: .warning)
                    .accessibilityIdentifier("plan.draft.notice.not-reviewed")
            }
            if model.snapshot?.mentionsMedications == true {
                BodyFlowStatusLine(copy("plan.draft.notice.medications"), kind: .warning)
                    .accessibilityIdentifier("plan.draft.notice.medications")
            }
        }
    }

    @ViewBuilder
    private var review: some View {
        if let snapshot = model.snapshot, let document = model.document {
            header(snapshot)

            let planDetails = document.planDetails(language: language)
            if !planDetails.isEmpty {
                BodyFlowCard {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                        Text(copy("plan.draft.details.title"))
                            .font(BodyFlowTypography.sectionTitle)
                            .foregroundStyle(BodyFlowColor.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        detailRows(planDetails)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("plan.draft.details")
            }

            ForEach(document.sections) { section in
                sectionCard(section)
            }

            let shopping = document.shoppingList(language: language)
            if !shopping.isEmpty {
                BodyFlowCard {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                        Text(copy("plan.draft.shopping.title"))
                            .font(BodyFlowTypography.sectionTitle)
                            .foregroundStyle(BodyFlowColor.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(shopping) { item in
                            Text(verbatim: item.text)
                                .font(BodyFlowTypography.callout)
                                .foregroundStyle(BodyFlowColor.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("plan.draft.shopping")
            }

            if model.droppedEdits {
                BodyFlowStatusLine(copy("plan.draft.notice.edits-dropped"), kind: .warning)
                    .accessibilityIdentifier("plan.draft.notice.edits-dropped")
            }
            if document.hasUnreadableContent {
                BodyFlowStatusLine(copy("plan.draft.blocker.unreadable"), kind: .warning)
                    .accessibilityIdentifier("plan.draft.blocker.unreadable")
            }

            if !snapshot.unrecognizedSegments.isEmpty {
                unrecognized(snapshot)
            }

            if let failure = model.actionFailure {
                BodyFlowStatusLine(copy(PlanDraftCopy.failureKey(failure)), kind: .error)
                    .accessibilityIdentifier("plan.draft.action-failure")
            }
            if model.hasInvalidEdits(language: language) {
                BodyFlowStatusLine(copy("plan.draft.blocker.invalid"), kind: .warning)
                    .accessibilityIdentifier("plan.draft.blocker")
            } else if model.hasUnsavedChanges {
                BodyFlowStatusLine(copy("plan.draft.blocker.unsaved"), kind: .info)
                    .accessibilityIdentifier("plan.draft.blocker")
            } else if !snapshot.canConfirm {
                BodyFlowStatusLine(copy("plan.draft.blocker.incomplete"), kind: .warning)
                    .accessibilityIdentifier("plan.draft.blocker")
            }

            VStack(spacing: BodyFlowSpacing.sm) {
                if model.hasUnsavedChanges {
                    Button {
                        Task { await model.save(language: language) }
                    } label: {
                        label("plan.draft.save")
                    }
                    .buttonStyle(BodyFlowButtonStyle(role: .primary, isLoading: model.isWorking))
                    .disabled(!model.canSave(language: language))
                    .accessibilityIdentifier("plan.draft.save")
                } else {
                    Button {
                        askingToConfirm = true
                    } label: {
                        label("plan.draft.confirm")
                    }
                    .buttonStyle(BodyFlowButtonStyle(role: .primary, isLoading: model.isWorking))
                    .disabled(!model.canConfirm)
                    .accessibilityIdentifier("plan.draft.confirm")
                }
                discardButton
            }
        }
    }

    private func header(_ snapshot: PlanDraftSnapshot) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Text(PlanDraftCopy.domainTitle(snapshot.domain, language: language))
                .font(BodyFlowTypography.screenTitle)
                .foregroundStyle(BodyFlowColor.primaryText)
                .accessibilityAddTraits(.isHeader)
            Text(copy(PlanDraftCopy.originKey(imported: snapshot.isImported)))
                .font(BodyFlowTypography.callout)
                .foregroundStyle(BodyFlowColor.secondaryText)
            if snapshot.replacesCurrentPlan, snapshot.domain == .training {
                BodyFlowStatusLine(copy("plan.draft.notice.replaces"), kind: .warning)
                    .accessibilityIdentifier("plan.draft.notice.replaces")
            }
        }
    }

    private func sectionCard(_ section: PlanDraftDocument.Section) -> some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                ForEach(section.fields) { field in
                    fieldView(field)
                }
                detailRows(section.details)
                ForEach(section.rows) { row in
                    Divider()
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                        ForEach(row.fields) { field in
                            fieldView(field)
                        }
                        if let note = row.note {
                            BodyFlowStatusLine(
                                copy("plan.draft.portion.note") + " " + note,
                                kind: .info
                            )
                        }
                        detailRows(row.details)
                        if let reason = model.uncertainty(ofRow: row) {
                            BodyFlowStatusLine(
                                copy(PlanDraftCopy.uncertaintyKey(
                                    reason == "supplement" && model.snapshot?.isImported == true
                                        ? "supplement_imported" : reason
                                )),
                                kind: .warning
                            )
                            .accessibilityIdentifier("plan.draft.uncertain\(row.id)")
                        }
                        removeButton("plan.draft.remove.row", path: row.path, name: row.title)
                    }
                }
                Divider()
                removeButton(
                    "plan.draft.remove.section",
                    path: section.path,
                    name: section.fields.first.map { model.text(of: $0, language: language) } ?? ""
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.draft.section\(section.id)")
    }

    @ViewBuilder
    private func fieldView(_ field: PlanDraftDocument.Field) -> some View {
        let title = copy(PlanDraftCopy.fieldKey(field.key))
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
            Text(title)
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .accessibilityHidden(true)
            if field.kind == .mealType {
                Picker(title, selection: binding(field)) {
                    Text(copy("plan.draft.meal.unknown")).tag("")
                    ForEach(PlanDraftDocument.mealTypes, id: \.self) { value in
                        Text(copy(PlanDraftCopy.mealTypeKey(value))).tag(value)
                    }
                }
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                .disabled(model.isWorking)
                .accessibilityIdentifier("plan.draft.field\(field.pointer)")
            } else {
                TextField(title, text: binding(field), axis: .vertical)
                    .lineLimit(1...3)
                    .keyboardType(keyboard(for: field.kind))
                    .focused($focusedField, equals: field.pointer)
                    .bodyFlowField()
                    .disabled(model.isWorking)
                    .accessibilityLabel(title)
                    .accessibilityIdentifier("plan.draft.field\(field.pointer)")
            }
            if model.isInvalid(field, language: language) {
                BodyFlowStatusLine(copy("plan.draft.uncertain.invalid"), kind: .warning)
            } else if let reason = model.uncertainty(of: field) {
                BodyFlowStatusLine(copy(PlanDraftCopy.uncertaintyKey(reason)), kind: .warning)
                    .accessibilityIdentifier("plan.draft.uncertain\(field.pointer)")
            }
        }
    }

    private func unrecognized(_ snapshot: PlanDraftSnapshot) -> some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                Text(copy("plan.draft.unrecognized.title"))
                    .font(BodyFlowTypography.sectionTitle)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(copy("plan.draft.unrecognized.detail"))
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(snapshot.unrecognizedSegments.enumerated()), id: \.offset) { _, text in
                    Text(verbatim: text)
                        .font(BodyFlowTypography.callout)
                        .foregroundStyle(BodyFlowColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.draft.unrecognized")
    }

    /// What Flow created is a "sugestão"; what came from the patient's own
    /// photo or PDF is an imported plan, never called a suggestion.
    private var isImported: Bool { model.snapshot?.isImported == true }

    private var discardButton: some View {
        Button {
            askingToDiscard = true
        } label: {
            label(PlanDraftCopy.discardKey(imported: isImported))
        }
        .buttonStyle(BodyFlowButtonStyle(role: .tertiary))
        .disabled(!model.canDiscard)
        .accessibilityIdentifier("plan.draft.discard")
    }

    /// Values of the draft the screen shows and does not edit.
    @ViewBuilder
    private func detailRows(_ details: [PlanDraftDocument.Detail]) -> some View {
        ForEach(details) { detail in
            FixtureMetricRow(
                title: copy(PlanDraftCopy.detailKey(detail.key)),
                value: PlanDraftCopy.detailValue(
                    key: detail.key,
                    text: detail.text,
                    language: language
                )
            )
            .accessibilityIdentifier("plan.draft.detail\(detail.id)")
        }
    }

    private func removeButton(
        _ key: String.LocalizationValue,
        path: PlanDraftDocument.Path,
        name: String
    ) -> some View {
        Button {
            removal = path
        } label: {
            Label(verbatim: copy(key), symbol: .remove)
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(BodyFlowButtonStyle(role: .tertiary))
        .disabled(model.isWorking || model.hasInvalidEdits(language: language))
        .accessibilityLabel(name.isEmpty ? copy(key) : copy(key) + ": " + name)
        .accessibilityIdentifier("plan.draft.remove\(PlanDraftDocument.pointer(path))")
    }

    private func outcome(
        title: String,
        detail: String?,
        kind: BodyFlowStatusLine.Kind,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            BodyFlowStatusLine(title, kind: kind, font: BodyFlowTypography.headline)
            if let detail {
                Text(detail)
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            button("plan.draft.close", role: .secondary, id: "plan.draft.close") { dismiss() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func progress(_ message: String) -> some View {
        HStack(spacing: BodyFlowSpacing.sm) {
            BodyFlowDelayedProgress()
                .tint(BodyFlowColor.accent)
                .accessibilityHidden(true)
            Text(verbatim: message)
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plan.draft.progress")
    }

    private func button(
        _ key: String.LocalizationValue,
        role: BodyFlowButtonRole,
        id: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) { label(key) }
            .buttonStyle(BodyFlowButtonStyle(role: role))
            .accessibilityIdentifier(id)
    }

    private func label(_ key: String.LocalizationValue) -> some View {
        Text(copy(key))
            .frame(maxWidth: .infinity)
            .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
    }

    private func keyboard(for kind: PlanDraftDocument.FieldKind) -> UIKeyboardType {
        switch kind {
        case .integer: .numberPad
        case .decimal: .decimalPad
        case .text, .mealType: .default
        }
    }

    private func binding(_ field: PlanDraftDocument.Field) -> Binding<String> {
        Binding(
            get: { model.text(of: field, language: language) },
            set: { model.setText($0, of: field, language: language) }
        )
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        PlanDraftCopy.string(key, language: language)
    }
}
