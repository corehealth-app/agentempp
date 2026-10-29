import SwiftUI

struct MealProposalEditorSeed {
    let mealType: MealType
    /// Every item of the pending proposal, in the server's order.
    let items: [MealProposalItemSnapshot]
    let consumedAt: Date
    /// The item being edited; every other item is sent back as it came.
    let editedIndex: Int
    /// The meal's origin, sent back with every edit so it is never lost.
    let source: MealProposalSource?

    init(registration: RegistrationSnapshot, initialConsumedAt: Date, editedIndex: Int = 0) {
        let proposal: MealProposalSnapshot
        switch registration.proposal {
        case let .meal(value): proposal = value
        case .workout, .unknown:
            proposal = MealProposalSnapshot(
                mealType: "outro",
                items: [],
                totals: nil,
                warnings: []
            )
        }
        mealType = MealType(rawValue: proposal.mealType) ?? .other
        items = proposal.items
        consumedAt = initialConsumedAt
        source = proposal.source?.requestSource
        self.editedIndex = proposal.items.indices.contains(editedIndex) ? editedIndex : 0
    }

    /// An entry in the list owns only its own calorie provenance and units.
    /// The list, rather than this single-entry draft, preserves the other foods.
    init(item: MealProposalItemSnapshot, mealType: MealType, consumedAt: Date,
         source: MealProposalSource?) {
        self.mealType = mealType
        items = [item]
        self.consumedAt = consumedAt
        editedIndex = 0
        self.source = source
    }

    var editedItem: MealProposalItemSnapshot? {
        items.indices.contains(editedIndex) ? items[editedIndex] : nil
    }

    var foodName: String { editedItem?.name ?? "" }
    var quantityG: Decimal? { editedItem?.quantityG }
    /// The server's current value for the edited item, shown read-only; an
    /// item without calculation has none.
    var officialKcal: Decimal? {
        editedItem?.needsClarification == true ? nil : editedItem?.kcal
    }
    var firstItemKcalOrigin: MealItemKcalOrigin { editedItem?.kcalOrigin ?? .official }
    /// True when any item came without its calorie provenance.
    var hasUnknownKcalOrigin: Bool { items.contains { $0.kcalOrigin == .unknown } }
}

enum MealProposalEditorKcalInput: Equatable, Sendable {
    /// Nothing typed: `user_kcal` is omitted and the server calculates.
    case official
    /// A value the patient typed, sent as `user_kcal` (reported by them).
    case manual(Decimal)
    /// Typed but not a readable calorie value; saving is blocked.
    case invalid
    /// A value the patient had reported was erased without choosing the
    /// server calculation; saving is blocked.
    case clearedReportedValue
}

enum MealProposalEditorBlocker: Equatable, Sendable {
    case unknownKcalOrigin
    case noItems
    case invalidQuantity
    case invalidKcal
    case clearedReportedKcal
}

/// Reads a number typed in the editor by the app language, with no partial
/// reads: `Decimal(string:)` turns "140,5" into 140 and blank text into 0.
/// Digits with at most one separator; "," and "." are both accepted as the
/// decimal mark (the keyboard's may differ from the app language), except the
/// language's grouping mark followed by exactly three digits ("1.234" in
/// pt-BR, "1,234" in en), which is refused as ambiguous rather than guessed.
enum MealProposalNumberParser {
    static func parse(_ text: String, language: SupportedAppLanguage) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.allSatisfy({ ($0.isASCII && $0.isNumber) || $0 == "," || $0 == "." })
        else {
            return nil
        }
        let separators = trimmed.filter { $0 == "," || $0 == "." }
        guard separators.count <= 1 else { return nil }
        let parts = trimmed.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "," || $0 == "." }
        )
        guard let whole = parts.first, !whole.isEmpty else { return nil }
        var canonical = String(whole)
        if parts.count == 2 {
            let fraction = parts[1]
            guard !fraction.isEmpty else { return nil }
            if separators.first == groupingSeparator(language), fraction.count == 3 {
                return nil
            }
            canonical += ".\(fraction)"
        }
        return Decimal(string: canonical, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// The language's own decimal mark and no grouping, so a shown value
    /// always reads back as itself.
    static func format(_ value: Decimal, language: SupportedAppLanguage) -> String {
        let formatter = NumberFormatter()
        formatter.locale = language.formattingLocale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }

    private static func groupingSeparator(_ language: SupportedAppLanguage) -> Character {
        language.formattingLocale.groupingSeparator?.first ?? ","
    }
}

/// The editor's working copy and the only place its edit request is built.
/// One item is editable at a time (the first by default); every other item is
/// sent back as it came, in the server's order, with a patient-reported calorie
/// kept and a calculated one left to the server.
struct MealProposalEditorDraft: Equatable, Sendable {
    let items: [MealProposalItemSnapshot]
    let editedIndex: Int
    let hasUnknownKcalOrigin: Bool
    let source: MealProposalSource?
    var mealType: MealType
    private var isNewIngredient = false
    var foodName: String {
        didSet {
            if isNewIngredient {
                let oldReference = NamedWheyPortion.parse(oldValue)?.metadata
                let newReference = NamedWheyPortion.parse(foodName)?.metadata
                if oldReference != newReference, quantityEntry.typedUsingReference,
                   quantityText != nil { quantityText = "" }
                return
            }
            let reference = editedItem?.quantityDisplay?.validated(for: editedItem?.name ?? "")
            if reference?.validated(for: oldValue) != reference?.validated(for: foodName),
               quantityText != nil { quantityText = "" }
        }
    }
    var quantityReference: MealQuantityValue {
        if isNewIngredient {
            let portion = NamedWheyPortion.parse(foodName)
            return MealQuantityValue(grams: portion?.grams, metadata: portion?.metadata,
                name: portion?.canonicalName ?? foodName)
        }
        return MealQuantityValue(grams: editedItem?.quantityG, metadata: editedItem?.quantityDisplay?.validated(for: editedItem?.name ?? ""), name: foodName)
    }
    var quantityPresentation: MealQuantityValue { quantityEntry.presentation(quantityReference) }
    var consumedAt: Date
    /// nil until the patient edits the field: the server's quantity is sent
    /// exactly, never re-read from formatted text.
    private var quantityEntry = MealQuantityEntry()
    var quantityText: String? {
        get { quantityEntry.text }
        set { quantityEntry.setText(newValue, usesReference: quantityPresentation.usesReference) }
    }
    /// nil until the patient edits the field.
    var manualKcalText: String?
    private(set) var usesServerCalculation = false

    /// The BFF accepts `user_kcal` in 0…20 000 and `quantity_g` in (0, 9 999].
    static let maximumManualKcal = Decimal(20_000)
    static let maximumQuantityG = Decimal(9_999)

    init(seed: MealProposalEditorSeed) {
        items = seed.items
        editedIndex = seed.editedIndex
        hasUnknownKcalOrigin = seed.hasUnknownKcalOrigin
        source = seed.source
        mealType = seed.mealType
        foodName = seed.foodName
        consumedAt = seed.consumedAt
    }

    /// Only addIngredient calls this. nil text distinguishes an untouched new
    /// field from a deliberately cleared/invalid quantity, which stays blocked.
    mutating func prepareNewIngredient() {
        isNewIngredient = true
        quantityEntry = MealQuantityEntry()
    }

    private var editedItem: MealProposalItemSnapshot? {
        items.indices.contains(editedIndex) ? items[editedIndex] : nil
    }

    private var firstItemOrigin: MealItemKcalOrigin {
        editedItem?.kcalOrigin ?? .official
    }

    /// Preparations the server asked the patient to choose from.
    var preparationOptions: [String] {
        editedItem?.needsClarification == true ? (editedItem?.preparationOptions ?? []) : []
    }

    /// Writes the chosen preparation into the name the server will read
    /// ("Feijão carioca" -> "Feijão carioca cozido"); choosing another one
    /// replaces the previous choice. The calculation stays on the server.
    mutating func choosePreparation(_ option: String) {
        var words = foodName.split(separator: " ").map(String.init)
        if let last = words.last, preparationOptions.contains(last) {
            words.removeLast()
        }
        words.append(option)
        foodName = words.joined(separator: " ")
    }

    private var keptReportedKcal: Decimal? {
        guard !usesServerCalculation,
              case let .patientReported(value) = firstItemOrigin
        else {
            return nil
        }
        return value
    }

    /// The only way back to the server calculation for a reported value.
    mutating func useServerCalculation() {
        usesServerCalculation = true
        manualKcalText = ""
    }

    var offersServerCalculation: Bool {
        keptReportedKcal != nil
            || (items.count == 1 && firstItemOrigin == .unknown && !usesServerCalculation)
    }

    func quantityDisplay(language: SupportedAppLanguage) -> String {
        quantityEntry.display(quantityReference, language: language)
    }

    mutating func setQuantityText(_ text: String, language: SupportedAppLanguage) {
        guard text != quantityDisplay(language: language) else { return }
        quantityText = text
    }

    mutating func toggleQuantityUnit(language: SupportedAppLanguage) {
        quantityEntry.toggle(quantityReference, language: language)
    }

    func canToggleQuantityUnit(language: SupportedAppLanguage) -> Bool {
        quantityEntry.canToggle(quantityReference, language: language)
    }

    func manualKcalDisplay(language: SupportedAppLanguage) -> String {
        if let manualKcalText { return manualKcalText }
        return keptReportedKcal.map {
            MealProposalNumberParser.format($0, language: language)
        } ?? ""
    }

    func quantityValue(language: SupportedAppLanguage) -> Decimal? {
        quantityEntry.grams(quantityReference, language: language)
    }

    func kcalInput(language: SupportedAppLanguage) -> MealProposalEditorKcalInput {
        guard let manualKcalText else {
            return keptReportedKcal.map { .manual($0) } ?? .official
        }
        if manualKcalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return keptReportedKcal == nil ? .official : .clearedReportedValue
        }
        guard let value = MealProposalNumberParser.parse(manualKcalText, language: language),
              value >= 0, value <= Self.maximumManualKcal
        else {
            return .invalid
        }
        return .manual(value)
    }

    /// A reported value kept while the quantity changed deserves a second look.
    func asksToReviewReportedKcal(language: SupportedAppLanguage) -> Bool {
        guard manualKcalText == nil, keptReportedKcal != nil,
              let quantity = quantityValue(language: language)
        else {
            return false
        }
        return quantity != editedItem?.quantityG
    }

    func blocker(language: SupportedAppLanguage) -> MealProposalEditorBlocker? {
        // A singleton draft can consciously recalculate that one item. A
        // multi-item legacy draft cannot erase unknown values in other rows.
        if hasUnknownKcalOrigin && !(items.count == 1 && usesServerCalculation) {
            return .unknownKcalOrigin
        }
        if items.isEmpty { return .noItems }
        if quantityValue(language: language) == nil { return .invalidQuantity }
        switch kcalInput(language: language) {
        case .invalid: return .invalidKcal
        case .clearedReportedValue: return .clearedReportedKcal
        case .official, .manual: return nil
        }
    }

    func request(language: SupportedAppLanguage) -> MealProposalRequest? {
        guard blocker(language: language) == nil,
              let quantity = quantityValue(language: language)
        else {
            return nil
        }
        let firstItemKcal: Decimal? = if case let .manual(value) = kcalInput(language: language) {
            value
        } else {
            nil
        }
        let namedPortion = isNewIngredient ? NamedWheyPortion.parse(foodName) : nil
        let requestItems = items.enumerated().map { index, item in
            index == editedIndex
                ? MealProposalItemRequest(
                    foodName: namedPortion?.canonicalName ?? foodName,
                    quantityG: quantity,
                    userKcal: firstItemKcal,
                    // A quantity the patient typed is theirs from then on.
                    quantityBasis: namedPortion != nil && quantityText == nil ? .portionReference
                        : quantity == item.quantityG ? Self.keptBasis(of: item)
                        : (quantityEntry.typedUsingReference ? .portionReference : .stated),
                    usesNutritionLabel: firstItemKcal == nil
                        && foodName == item.name
                        && keepsNutritionLabel(of: item)
                )
                : MealProposalItemRequest(
                    foodName: item.name,
                    quantityG: item.quantityG,
                    userKcal: Self.keptKcal(of: item),
                    quantityBasis: Self.keptBasis(of: item),
                    usesNutritionLabel: keepsNutritionLabel(of: item)
                )
        }
        return MealProposalRequest(
            mealType: mealType,
            items: requestItems,
            consumedAt: APITimestamp(value: consumedAt),
            source: source
        )
    }

    private static func keptBasis(of item: MealProposalItemSnapshot) -> MealQuantityBasis? {
        item.quantityBasis.flatMap(MealQuantityBasis.init(rawValue:))
    }

    /// An item the server priced from the photographed label keeps that
    /// choice; the server reads the label again from the same photo.
    private func keepsNutritionLabel(of item: MealProposalItemSnapshot) -> Bool {
        item.nutritionSource == "product_label" && source?.channel.isPhoto == true
    }

    /// A calorie the server applied from the patient is re-sent; a calculated
    /// one never is.
    private static func keptKcal(of item: MealProposalItemSnapshot) -> Decimal? {
        if case let .patientReported(value) = item.kcalOrigin { value } else { nil }
    }
}

enum MealProposalEditorPresentation {
    /// The server's value as it came, formatted for the language; never a
    /// zero standing in for a missing value.
    static func officialKcalText(
        _ value: Decimal?,
        language: SupportedAppLanguage
    ) -> String {
        guard let value else {
            return RegistrationCopy.string(
                "registration.editor.official-kcal.unavailable",
                language: language
            )
        }
        return RegistrationMetricPresentation.text(
            label: "",
            value: value,
            unit: .kilocalories,
            language: language
        )
    }
}

private enum MealProposalEditorField: Hashable { case name, quantity, calories }

struct MealProposalEditorView: View {
    private let save: @MainActor (MealProposalRequest) -> Void
    private let isSubmitting: Bool
    @State private var list: MealProposalListEditorDraft
    @State private var selectedEntryID: UUID?
    @FocusState private var focusedField: MealProposalEditorField?
    @Environment(\.locale) private var locale

    init(registration: RegistrationSnapshot, initialConsumedAt: Date,
         isSubmitting: Bool, editedIndex: Int = 0,
         save: @escaping @MainActor (MealProposalRequest) -> Void) {
        let list = MealProposalListEditorDraft(registration: registration,
            consumedAt: initialConsumedAt, editedIndex: editedIndex)
        _list = State(initialValue: list)
        _selectedEntryID = State(initialValue: list.initialEntryID)
        self.isSubmitting = isSubmitting
        self.save = save
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                if let entry = selectedEntry {
                    MealProposalItemEditorFields(draft: binding(for: entry),
                        header: itemHeader(entry), isNew: entry.original == nil,
                        focusedField: $focusedField)
                        .id(entry.id)
                        .id("selected-item-fields")
                }
                if let reason = list.blocker(language: language) {
                    Section {
                        BodyFlowStatusLine(blockerText(reason), kind: .warning)
                            .accessibilityIdentifier("registration.proposal.edit.blocked")
                        if let id = blockedEntryID(reason), id != selectedEntryID,
                           let entry = list.entry(id: id) {
                            Button(formatted("registration.editor.list.correct-item", entryTitle(entry))) {
                                focusedField = nil
                                selectedEntryID = id
                            }
                            .accessibilityIdentifier("registration.proposal.edit.correct-blocked-item")
                        }
                    }.bodyFlowListRow()
                }
                Section(copy("registration.editor.meal")) {
                    Menu {
                        ForEach(MealType.allCases, id: \.self) { type in
                            Button(mealTypeTitle(type)) { list.mealType = type }
                        }
                    } label: { Text(mealTypeTitle(list.mealType)) }
                    .accessibilityIdentifier("registration.proposal.edit.meal-type")
                    DatePicker(copy("registration.editor.time"), selection: $list.consumedAt)
                        .accessibilityIdentifier("registration.proposal.edit.consumed-at")
                }.bodyFlowListRow()
                if let entry = selectedEntry {
                    Section {
                        LabeledContent(serverValueTitle(entry)) {
                            Text(MealProposalEditorPresentation.officialKcalText(
                                entry.original?.needsClarification == true ? nil : entry.original?.kcal,
                                language: language))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("registration.proposal.edit.official-kcal")
                    } footer: { Text(copy("registration.editor.user-kcal.footer")) }
                    .bodyFlowListRow()
                }
                Section(copy("registration.editor.list.title")) {
                    ForEach(list.entries) { entry in
                        Button {
                            focusedField = nil
                            selectedEntryID = entry.id
                        } label: {
                            HStack {
                                Text(entryTitle(entry)).multilineTextAlignment(.leading)
                                Spacer(minLength: BodyFlowSpacing.sm)
                                if entry.id == selectedEntryID { Image(systemName: "pencil") }
                            }.frame(minHeight: 44)
                        }
                        .accessibilityAddTraits(entry.id == selectedEntryID ? [.isSelected] : [])
                        .accessibilityIdentifier("registration.proposal.edit.select.\(entry.id)")
                    }
                    Button(copy("registration.editor.list.add")) { addIngredient() }
                        .disabled(!list.canAdd)
                        .accessibilityIdentifier("registration.proposal.edit.add-ingredient")
                    if let entry = selectedEntry {
                        Button(role: .destructive) { remove(entry) } label: {
                            Text(formatted("registration.editor.list.remove", entryTitle(entry)))
                        }
                        .accessibilityIdentifier("registration.proposal.edit.remove-ingredient")
                    }
                    if !list.canAdd {
                        Text(copy("registration.editor.list.limit"))
                            .font(BodyFlowTypography.callout).foregroundStyle(BodyFlowColor.secondaryText)
                    }
                }.bodyFlowListRow()
                if !list.removedEntries.isEmpty {
                    Section(copy("registration.editor.list.removed")) {
                        ForEach(list.removedEntries) { entry in
                            Button(formatted("registration.editor.list.undo", entryTitle(entry))) {
                                focusedField = nil
                                selectedEntryID = list.undoRemoval(entry.id) ?? selectedEntryID
                            }
                            .disabled(!list.canUndoRemoval)
                            .accessibilityIdentifier("registration.proposal.edit.undo.\(entry.id)")
                        }
                        if !list.canUndoRemoval { Text(copy("registration.editor.list.limit")) }
                    }.bodyFlowListRow()
                }
            }
            .disabled(isSubmitting)
            .bodyFlowList()
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("registration.proposal.editor")
            .onChange(of: selectedEntryID) { _, _ in
                proxy.scrollTo("selected-item-fields", anchor: .top)
            }
        }
        .navigationTitle(copy("registration.editor.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(copy("registration.editor.save"), action: saveProposal)
                    .disabled(isSubmitting || list.request(language: language) == nil)
                    .accessibilityIdentifier("registration.proposal.edit.save")
            }
            // A single destination-level toolbar: attaching it to a Section
            // duplicates the keyboard item for each Form row.
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
    }

    private var selectedEntry: MealProposalListEditorDraft.Entry? {
        selectedEntryID.flatMap { list.entry(id: $0) }
    }

    private func binding(for entry: MealProposalListEditorDraft.Entry) -> Binding<MealProposalEditorDraft> {
        // Capture identity, never an array position that could refer to a
        // different food after a removal or an undo.
        Binding(get: { list.entry(id: entry.id)?.draft ?? entry.draft },
            set: { value in list.updateEntry(entry.id) { $0 = value } })
    }

    private func addIngredient() {
        guard !isSubmitting else { return }
        focusedField = nil
        selectedEntryID = list.addIngredient() ?? selectedEntryID
    }

    private func remove(_ entry: MealProposalListEditorDraft.Entry) {
        guard !isSubmitting, let index = list.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        focusedField = nil
        list.remove(entry.id)
        selectedEntryID = list.entries.isEmpty ? nil : list.entries[min(index, list.entries.count - 1)].id
    }

    private func saveProposal() {
        guard !isSubmitting, let request = list.request(language: language) else { return }
        save(request)
    }

    private func entryTitle(_ entry: MealProposalListEditorDraft.Entry) -> String {
        let name = entry.draft.foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? copy("registration.editor.list.new") : name
    }

    private func itemHeader(_ entry: MealProposalListEditorDraft.Entry) -> String {
        let index = list.entries.firstIndex { $0.id == entry.id } ?? 0
        return index == 0 ? copy("registration.editor.first-item")
            : String(format: copy("registration.editor.item-number"), locale: language.formattingLocale, index + 1)
    }

    private func serverValueTitle(_ entry: MealProposalListEditorDraft.Entry) -> String {
        switch entry.original?.kcalOrigin ?? .official {
        case .official: copy("registration.editor.kcal.calculated")
        case .patientReported: copy("registration.editor.kcal.reported")
        case .unknown: copy("registration.editor.official-kcal")
        }
    }

    private func blockedEntryID(_ reason: MealProposalListEditorDraft.Blocker) -> UUID? {
        switch reason {
        case let .invalidName(id), let .item(id, _): id
        case .noItems, .tooManyItems: nil
        }
    }

    private func blockerText(_ reason: MealProposalListEditorDraft.Blocker) -> String {
        switch reason {
        case .noItems: return copy("registration.editor.list.empty")
        case .tooManyItems: return copy("registration.editor.list.limit")
        case let .invalidName(id):
            return formatted("registration.editor.list.name-invalid", list.entry(id: id).map(entryTitle) ?? "")
        case let .item(id, blocker):
            let name = list.entry(id: id).map(entryTitle) ?? ""
            let key: String.LocalizationValue = switch blocker {
            case .unknownKcalOrigin: "registration.editor.list.origin-unknown"
            case .invalidQuantity: "registration.editor.list.quantity-invalid"
            case .invalidKcal: "registration.editor.list.kcal-invalid"
            case .clearedReportedKcal: "registration.editor.list.kcal-cleared"
            case .noItems: "registration.editor.list.quantity-invalid"
            }
            return formatted(key, name)
        }
    }

    static func decimalText(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
    private var language: SupportedAppLanguage { BodyFlowPresentationLanguage.resolve(locale) }
    private func copy(_ key: String.LocalizationValue) -> String { RegistrationCopy.string(key, language: language) }
    private func formatted(_ key: String.LocalizationValue, _ name: String) -> String {
        String(format: copy(key), locale: language.formattingLocale, name)
    }
    private func mealTypeTitle(_ type: MealType) -> String { RegistrationCopy.mealTypeTitle(type, language: language) }
}

/// The selected entry's fields keep the same native controls and unit logic.
/// Only the UUID-selected binding changes when another food is chosen.
private struct MealProposalItemEditorFields: View {
    @Binding var draft: MealProposalEditorDraft
    let header: String
    let isNew: Bool
    let focusedField: FocusState<MealProposalEditorField?>.Binding
    @Environment(\.locale) private var locale

    var body: some View {
        Section {
            if draft.blocker(language: language) == .unknownKcalOrigin {
                BodyFlowStatusLine(copy("registration.editor.list.recalculate-origin"), kind: .warning)
                    .accessibilityIdentifier("registration.proposal.edit.origin-unknown")
            }
            TextField(copy("registration.editor.food"), text: $draft.foodName)
                .focused(focusedField, equals: .name)
                .accessibilityIdentifier("registration.proposal.edit.food-name")
            if !MealProposalListEditorDraft.isValidName(draft.foodName) {
                BodyFlowStatusLine(copy("registration.editor.list.name-hint"), kind: .error)
            }
            if !draft.preparationOptions.isEmpty {
                Text(copy("registration.editor.preparation"))
                    .font(BodyFlowTypography.callout).foregroundStyle(BodyFlowColor.secondaryText)
                ForEach(draft.preparationOptions, id: \.self) { option in
                    Button(option) { draft.choosePreparation(option) }
                        .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                        .accessibilityIdentifier("registration.proposal.edit.preparation.\(option)")
                }
            }
            TextField(copy(draft.quantityPresentation.captionKey), text: quantityBinding)
                .focused(focusedField, equals: .quantity)
                .accessibilityLabel(copy(draft.quantityPresentation.captionKey))
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("registration.proposal.edit.quantity")
            MealQuantityReferenceControls(reference: draft.quantityReference,
                currentGrams: draft.quantityValue(language: language), showingGrams: !draft.quantityPresentation.usesReference,
                canToggle: draft.canToggleQuantityUnit(language: language), language: language,
                identifier: "registration.proposal.edit") { draft.toggleQuantityUnit(language: language) }
            if draft.quantityValue(language: language) == nil {
                BodyFlowStatusLine(copy(draft.quantityPresentation.invalidKey), kind: .error)
                    .accessibilityIdentifier("registration.proposal.edit.quantity.invalid")
            }
            TextField(copy("registration.editor.user-kcal"), text: manualKcalBinding)
                .focused(focusedField, equals: .calories)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("registration.proposal.edit.user-kcal")
            switch draft.kcalInput(language: language) {
            case .invalid:
                BodyFlowStatusLine(copy("registration.editor.user-kcal.invalid"), kind: .error)
                    .accessibilityIdentifier("registration.proposal.edit.user-kcal.invalid")
            case .clearedReportedValue:
                BodyFlowStatusLine(copy("registration.editor.user-kcal.cleared"), kind: .warning)
                    .accessibilityIdentifier("registration.proposal.edit.user-kcal.cleared")
            case .official, .manual: EmptyView()
            }
            if draft.asksToReviewReportedKcal(language: language) {
                BodyFlowStatusLine(copy("registration.editor.user-kcal.check-quantity"), kind: .info)
                    .accessibilityIdentifier("registration.proposal.edit.user-kcal.check-quantity")
            }
            if draft.offersServerCalculation {
                Button(copy("registration.editor.use-server-calculation")) { draft.useServerCalculation() }
                    .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                    .accessibilityIdentifier("registration.proposal.edit.use-server-calculation")
            }
        } header: { Text(header) }
        .bodyFlowListRow()
        .onAppear { if isNew { focusedField.wrappedValue = .name } }
    }

    private var language: SupportedAppLanguage { BodyFlowPresentationLanguage.resolve(locale) }
    private func copy(_ key: String.LocalizationValue) -> String { RegistrationCopy.string(key, language: language) }
    private var quantityBinding: Binding<String> {
        Binding(get: { draft.quantityDisplay(language: language) },
            set: { draft.setQuantityText($0, language: language) })
    }
    private var manualKcalBinding: Binding<String> {
        Binding(get: { draft.manualKcalDisplay(language: language) }, set: { draft.manualKcalText = $0 })
    }
}
