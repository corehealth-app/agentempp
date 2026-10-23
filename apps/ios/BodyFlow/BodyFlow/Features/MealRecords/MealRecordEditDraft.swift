import Foundation

/// Separate confirmed-record form. The existing pending proposal form is
/// untouched. Numbers use its established strict PT/EN parser.
struct MealRecordEditItem: Equatable, Identifiable, Sendable {
    let original: MealRecordItemSnapshot
    var foodName: String {
        didSet {
            let reference = original.quantityDisplay?.validated(for: original.foodName)
            if reference?.validated(for: oldValue) != reference?.validated(for: foodName),
               quantityText != nil { quantityText = "" }
        }
    }
    var quantityPresentation: MealQuantityValue {
        MealQuantityValue(grams: original.quantityG, metadata: original.quantityDisplay?.validated(for: original.foodName), name: foodName)
    }
    var quantityText: String?
    var manualKcalText: String?
    var id: String { original.id }

    init(_ original: MealRecordItemSnapshot) {
        self.original = original
        foodName = original.foodName
    }

    func quantityDisplay(language: SupportedAppLanguage) -> String {
        quantityText ?? quantityPresentation.displayText(language: language)
    }

    func manualKcalDisplay(language: SupportedAppLanguage) -> String {
        // This is a NEW explicit override field, not the stored row's kcal.
        // Leaving it blank delegates same-item quantity reconciliation to the server.
        manualKcalText ?? ""
    }

    func request(language: SupportedAppLanguage) -> MealProposalItemRequest? {
        // The server trims the name and accepts 1 to 160 UTF-16 units.
        let name = foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf16.count <= MealDraftReview.maximumNameLength else { return nil }
        let quantity: Decimal?
        if let quantityText {
            quantity = quantityPresentation.grams(from: quantityText, language: language)
        } else {
            quantity = original.quantityG
        }
        guard let quantity, quantity > 0, quantity <= MealProposalEditorDraft.maximumQuantityG else { return nil }
        let kcal: Decimal?
        if let manualKcalText,
           !manualKcalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let value = MealProposalNumberParser.parse(manualKcalText, language: language),
                  value >= 0, value <= MealProposalEditorDraft.maximumManualKcal else { return nil }
            kcal = value
        } else {
            kcal = nil
        }
        return MealProposalItemRequest(foodName: foodName, quantityG: quantity, userKcal: kcal)
    }

}

struct MealRecordEditDraft: Equatable, Sendable {
    let expectedVersion: String
    let itemIDs: [String]
    let recordID: String
    var items: [MealRecordEditItem]

    init(_ snapshot: MealRecordSnapshot) {
        expectedVersion = snapshot.expectedVersion
        itemIDs = snapshot.itemIDs
        recordID = snapshot.recordID
        items = snapshot.items.map(MealRecordEditItem.init)
    }

    /// True once the person changed the name or typed a quantity or calories.
    var hasTypedFields: Bool {
        items.contains { item in
            item.quantityText != nil || item.manualKcalText != nil || item.foodName != item.original.foodName
        }
    }

    func patchBody(language: SupportedAppLanguage) -> MealRecordPatchBody? {
        guard !items.isEmpty, items.map(\.id) == itemIDs else { return nil }
        let selected = items.filter { $0.id == recordID }
        guard selected.count == 1, let request = selected[0].request(language: language) else { return nil }
        return MealRecordPatchBody(expectedVersion: expectedVersion, itemIDs: [recordID], items: [request])
    }
}
