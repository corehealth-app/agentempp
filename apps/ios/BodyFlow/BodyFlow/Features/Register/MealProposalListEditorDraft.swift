import Foundation

/// One local working copy of the same pending proposal. Stable local IDs
/// distinguish repeated foods; they are never sent as server identities.
struct MealProposalListEditorDraft: Equatable, Sendable {
    struct Entry: Identifiable, Equatable, Sendable {
        let id: UUID
        let order: Int
        let original: MealProposalItemSnapshot?
        var draft: MealProposalEditorDraft
    }

    enum Blocker: Equatable, Sendable {
        case noItems
        case tooManyItems
        case invalidName(UUID)
        case item(UUID, MealProposalEditorBlocker)
    }

    private(set) var entries: [Entry]
    private(set) var removedEntries: [Entry] = []
    var mealType: MealType
    var consumedAt: Date
    let source: MealProposalSource?
    let initialEntryID: UUID?
    private var nextOrder: Int
    static let maximumItems = 30

    init(registration: RegistrationSnapshot, consumedAt: Date, editedIndex: Int = 0) {
        let seed = MealProposalEditorSeed(registration: registration,
            initialConsumedAt: consumedAt, editedIndex: editedIndex)
        mealType = seed.mealType
        self.consumedAt = consumedAt
        source = seed.source
        nextOrder = seed.items.count
        entries = seed.items.enumerated().map { index, item in
            Entry(id: UUID(), order: index, original: item, draft: .init(seed: .init(item: item,
                mealType: seed.mealType, consumedAt: consumedAt, source: seed.source)))
        }
        initialEntryID = entries.indices.contains(seed.editedIndex) ? entries[seed.editedIndex].id : nil
    }

    var canAdd: Bool { entries.count < Self.maximumItems }
    var canUndoRemoval: Bool { canAdd && !removedEntries.isEmpty }
    func entry(id: UUID) -> Entry? { entries.first { $0.id == id } }
    mutating func updateEntry(_ id: UUID, _ edit: (inout MealProposalEditorDraft) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        edit(&entries[index].draft)
    }
    @discardableResult
    mutating func addIngredient() -> UUID? {
        guard canAdd else { return nil }
        // This is a blank local field, not a calculated zero or a share of
        // the rejected dish. A name/weight or explicit supported household
        // measure is needed; the latter remains approximate and editable.
        let item = MealProposalItemSnapshot(name: "", quantityG: 0,
            kcal: nil, proteinG: nil, carbsG: nil, fatG: nil)
        var draft = MealProposalEditorDraft(seed: .init(item: item,
            mealType: mealType, consumedAt: consumedAt, source: source))
        draft.prepareNewIngredient()
        let entry = Entry(id: UUID(), order: nextOrder, original: nil, draft: draft)
        nextOrder += 1
        entries.append(entry)
        return entry.id
    }

    mutating func remove(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        removedEntries.append(entries.remove(at: index))
    }

    @discardableResult
    mutating func undoRemoval(_ id: UUID? = nil) -> UUID? {
        guard canUndoRemoval,
              let index = id.flatMap({ target in removedEntries.firstIndex { $0.id == target } })
                ?? (id == nil ? removedEntries.indices.last : nil)
        else { return nil }
        let entry = removedEntries.remove(at: index)
        // A stable ordinal, rather than an index at removal time, preserves
        // order even when removals are undone in a different order.
        let insertion = entries.firstIndex { $0.order > entry.order } ?? entries.endIndex
        entries.insert(entry, at: insertion)
        return entry.id
    }

    static func isValidName(_ name: String) -> Bool {
        // Match the server's string limit, including UTF-16 surrogate pairs.
        (1...160).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count)
    }

    func blocker(language: SupportedAppLanguage) -> Blocker? {
        if entries.isEmpty { return .noItems }
        if entries.count > Self.maximumItems { return .tooManyItems }
        for entry in entries {
            if !Self.isValidName(entry.draft.foodName) { return .invalidName(entry.id) }
            if let reason = entry.draft.blocker(language: language) { return .item(entry.id, reason) }
        }
        return nil
    }

    func request(language: SupportedAppLanguage) -> MealProposalRequest? {
        guard blocker(language: language) == nil else { return nil }
        var items: [MealProposalItemRequest] = []
        for entry in entries {
            guard let request = entry.draft.request(language: language), request.items.count == 1,
                  let item = request.items.first else { return nil }
            items.append(.init(foodName: item.foodName.trimmingCharacters(in: .whitespacesAndNewlines),
                quantityG: item.quantityG, userKcal: item.userKcal,
                quantityBasis: item.quantityBasis, candidateID: item.candidateID,
                usesNutritionLabel: item.usesNutritionLabel))
        }
        return MealProposalRequest(mealType: mealType, items: items,
            consumedAt: APITimestamp(value: consumedAt), source: source)
    }
}
