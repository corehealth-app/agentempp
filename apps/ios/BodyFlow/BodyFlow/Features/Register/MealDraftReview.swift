import Foundation

/// The patient's working copy of the candidates the server read. Nothing
/// here is nutrition: names and quantities only, and the request is built in
/// one place. A quantity the app did not get from the patient or the server
/// never exists — a candidate without one blocks the proposal.
struct MealDraftReview: Equatable, Sendable {
    struct Item: Identifiable, Equatable, Sendable {
        let candidate: MealDraftCandidate
        var name: String {
            didSet {
                let reference = candidate.quantityDisplay?.validated(for: candidate.name)
                if reference?.validated(for: oldValue) != reference?.validated(for: name),
                   quantityText != nil { quantityText = "" }
            }
        }
        var quantityReference: MealQuantityValue {
            MealQuantityValue(grams: serverQuantity, metadata: candidate.quantityDisplay?.validated(for: candidate.name), name: name)
        }
        var quantityValue: MealQuantityValue { quantityEntry.presentation(quantityReference) }
        /// nil until the patient edits the field: the server's quantity is
        /// sent exactly, never re-read from formatted text.
        private var quantityEntry = MealQuantityEntry()
        var quantityText: String? {
            get { quantityEntry.text }
            set { quantityEntry.setText(newValue, usesReference: quantityValue.usesReference) }
        }
        /// The patient's explicit "this is right" for an approximate portion
        /// or a name read with doubt.
        var isConfirmed = false

        var id: String { candidate.candidateID }

        init(candidate: MealDraftCandidate) {
            self.candidate = candidate
            name = candidate.name
        }

        var trimmedName: String {
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var hasTypedQuantity: Bool {
            quantityText != nil
        }

        /// The server's quantity, when it is one a proposal can carry.
        var serverQuantity: Decimal? {
            guard let quantity = candidate.quantityG,
                  quantity > 0, quantity <= MealDraftReview.maximumQuantityG
            else {
                return nil
            }
            return quantity
        }

        /// A quantity the patient did not state and has not replaced by
        /// their own figure: a reference portion, a visual estimate, or any
        /// basis this app does not know.
        var hasApproximateQuantity: Bool {
            guard !hasTypedQuantity, serverQuantity != nil else { return false }
            return candidate.requestBasis != .stated
        }

        /// The server asked for a second look and the patient changed
        /// nothing yet.
        private var isFlaggedAndUntouched: Bool {
            candidate.needsReview && !hasTypedQuantity && trimmedName == candidate.name
                && serverQuantity != nil
        }

        /// A name the server read with doubt and the patient has not changed.
        var hasDoubtfulName: Bool {
            guard trimmedName == candidate.name else { return false }
            return candidate.reviewReason == "ambiguous"
                || candidate.reviewReason == "low_confidence"
        }

        var requiresConfirmation: Bool {
            hasApproximateQuantity || hasDoubtfulName || isFlaggedAndUntouched
        }

        /// What the patient typed; typing the server's own figure back (or
        /// erasing what was typed) is not a statement of theirs.
        mutating func setQuantityText(_ text: String, language: SupportedAppLanguage) {
            // A text value converted only for display remains untouched when
            // SwiftUI echoes it; don't turn six formatted decimals into mass.
            guard text != quantityDisplay(language: language) else { return }
            quantityText = text == quantityValue.displayText(language: language) ? nil : text
        }

        mutating func toggleQuantityUnit(language: SupportedAppLanguage) {
            quantityEntry.toggle(quantityReference, language: language)
        }

        func canToggleQuantityUnit(language: SupportedAppLanguage) -> Bool {
            quantityEntry.canToggle(quantityReference, language: language)
        }

        func quantity(language: SupportedAppLanguage) -> Decimal? {
            quantityEntry.grams(quantityReference, language: language)
        }

        func quantityDisplay(language: SupportedAppLanguage) -> String {
            quantityEntry.display(quantityReference, language: language)
        }

        /// A typed quantity is the patient's statement; an untouched one
        /// keeps the basis the server gave it.
        var basis: MealQuantityBasis? {
            hasTypedQuantity ? (quantityEntry.typedUsingReference ? .portionReference : .stated) : candidate.requestBasis
        }
    }

    enum Blocker: Equatable, Sendable {
        case noItems
        case invalidName(id: String)
        case missingQuantity(id: String)
        case invalidQuantity(id: String)
        case unconfirmed(id: String)
    }

    static let maximumQuantityG = Decimal(9_999)
    static let maximumNameLength = 160
    static let maximumItems = 30

    var items: [Item]
    var mealType: MealType
    let source: MealProposalSource
    let transcript: String?
    let contextNote: String?
    let nutritionLabel: MealDraftNutritionLabel?
    /// The item the patient tied the photographed label to; never preselected.
    private(set) var labelledItemID: String?

    init(draft: MealDraftSnapshot, source: MealProposalSource, mealType: MealType) {
        // One row per candidate: a repeated identity would make two rows
        // answer as one.
        var seen = Set<String>()
        items = draft.items
            .filter { seen.insert($0.candidateID).inserted }
            .prefix(Self.maximumItems)
            .map(Item.init(candidate:))
        self.mealType = mealType
        self.source = source
        transcript = draft.transcript
        contextNote = draft.contextNote
        nutritionLabel = source.channel.isPhoto ? draft.nutritionLabel : nil
    }

    var offersNutritionLabel: Bool { nutritionLabel != nil }

    /// The item the server suggests for the label, shown as a hint only.
    var suggestedLabelItemID: String? {
        nutritionLabel?.appliesToCandidateID
    }

    func usesNutritionLabel(_ id: String) -> Bool {
        labelledItemID == id
    }

    mutating func setUsesNutritionLabel(_ uses: Bool, for id: String) {
        guard offersNutritionLabel, items.contains(where: { $0.id == id }) else { return }
        if uses {
            labelledItemID = id
        } else if labelledItemID == id {
            labelledItemID = nil
        }
    }

    mutating func remove(_ id: String) {
        items.removeAll { $0.id == id }
        if labelledItemID == id { labelledItemID = nil }
    }

    func blocker(language: SupportedAppLanguage) -> Blocker? {
        guard !items.isEmpty else { return .noItems }
        for item in items {
            if item.trimmedName.isEmpty || item.trimmedName.count > Self.maximumNameLength {
                return .invalidName(id: item.id)
            }
            if item.quantity(language: language) == nil {
                return item.hasTypedQuantity
                    ? .invalidQuantity(id: item.id) : .missingQuantity(id: item.id)
            }
            if item.requiresConfirmation, !item.isConfirmed {
                return .unconfirmed(id: item.id)
            }
        }
        return nil
    }

    func request(language: SupportedAppLanguage) -> MealProposalRequest? {
        guard blocker(language: language) == nil else { return nil }
        var requestItems: [MealProposalItemRequest] = []
        for item in items {
            guard let quantity = item.quantity(language: language) else { return nil }
            requestItems.append(MealProposalItemRequest(
                foodName: item.trimmedName,
                quantityG: quantity,
                userKcal: nil,
                quantityBasis: item.basis,
                candidateID: Self.isCandidateID(item.id) ? item.id : nil,
                usesNutritionLabel: labelledItemID == item.id
            ))
        }
        return MealProposalRequest(
            mealType: mealType,
            items: requestItems,
            consumedAt: nil,
            source: source
        )
    }

    /// The shape the BFF accepts for `candidate_id`.
    static func isCandidateID(_ value: String) -> Bool {
        value.wholeMatch(of: /c[0-9]{1,2}-[0-9a-f]{8}/) != nil
    }
}
