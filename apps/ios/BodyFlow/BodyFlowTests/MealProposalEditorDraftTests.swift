import Foundation
import Testing

@testable import BodyFlow

/// The editor never turns the server's calories into a patient override, keeps
/// an override the server applied, keeps every item it does not edit, and reads
/// numbers by the app language without truncating them. `user_kcal` leaves the
/// device only for a value the patient reported, and is omitted (never `null`,
/// which the BFF rejects) otherwise.
@Suite("Meal proposal editor draft")
struct MealProposalEditorDraftTests {
    private static let consumedAt = Date(timeIntervalSince1970: 1_784_589_300)
    private static let pt = SupportedAppLanguage.portugueseBrazil
    private static let en = SupportedAppLanguage.englishUnitedStates

    private static func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private static func item(
        _ name: String,
        quantity: String,
        kcal: String?,
        userKcal: String? = nil,
        source: String? = "canonical_exact"
    ) -> MealProposalItemSnapshot {
        MealProposalItemSnapshot(
            name: name,
            quantityG: decimal(quantity),
            kcal: kcal.map(decimal),
            proteinG: 3,
            carbsG: 30,
            fatG: 1,
            userKcal: userKcal.map(decimal),
            nutritionSource: source
        )
    }

    private static func registration(_ items: [MealProposalItemSnapshot]) -> RegistrationSnapshot {
        RegistrationSnapshot(
            id: "7c9c0c5e-1f6a-4a1a-9c0b-0f1d2e3a4b5c",
            status: "pending",
            createdAt: APITimestamp(value: Date(timeIntervalSince1970: 1_784_589_000)),
            expiresAt: APITimestamp(value: Date(timeIntervalSince1970: 1_784_675_400)),
            resolvedAt: nil,
            proposal: .meal(MealProposalSnapshot(
                mealType: "almoco",
                items: items,
                totals: nil,
                warnings: []
            ))
        )
    }

    private static func draft(_ items: [MealProposalItemSnapshot]) -> MealProposalEditorDraft {
        MealProposalEditorDraft(seed: MealProposalEditorSeed(
            registration: registration(items),
            initialConsumedAt: consumedAt
        ))
    }

    private static let calculated = item("Arroz integral", quantity: "133.5", kcal: "155.4")
    private static let reported = item(
        "Wrap", quantity: "43", kcal: "200", userKcal: "200", source: "user_kcal"
    )

    private static func itemsJSON(_ request: MealProposalRequest) throws -> [[String: Any]] {
        let data = try JSONEncoder().encode(request)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(object["items"] as? [[String: Any]])
    }

    // 1. Official calculation, open and save without editing.
    @Test("a calculated item saved untouched stays calculated")
    func calculatedItemStaysCalculated() throws {
        let draft = Self.draft([Self.calculated])

        #expect(draft.kcalInput(language: Self.pt) == .official)
        let request = try #require(draft.request(language: Self.pt))
        #expect(request.items.map(\.userKcal) == [nil])
        #expect(request.items.map(\.quantityG) == [Self.decimal("133.5")])
        #expect(Set(try Self.itemsJSON(request)[0].keys) == ["food_name", "quantity_g"])
    }

    // 2. Earlier override, open and save without editing.
    @Test("a value the patient reported and the server applied is kept when saved untouched")
    func reportedValueIsKept() throws {
        let draft = Self.draft([Self.reported])

        #expect(draft.manualKcalDisplay(language: Self.pt) == "200")
        #expect(draft.kcalInput(language: Self.pt) == .manual(200))
        let request = try #require(draft.request(language: Self.pt))
        #expect(request.items.map(\.userKcal) == [200])
    }

    @Test("a patient value the server refused is not re-sent as an override")
    func refusedPatientValueIsNotResent() throws {
        let refused = Self.item("Queijo", quantity: "30", kcal: "96", userKcal: "900", source: "canonical_fuzzy")
        let request = try #require(Self.draft([refused]).request(language: Self.pt))

        #expect(request.items.map(\.userKcal) == [nil])
    }

    // 3. Changing another field keeps each item's origin.
    @Test("changing another field keeps the calorie origin of the edited item")
    func otherFieldChangesKeepOrigin() throws {
        for (source, expected) in [(Self.calculated, nil), (Self.reported, Decimal(200))] as [(MealProposalItemSnapshot, Decimal?)] {
            var draft = Self.draft([source])
            draft.mealType = .dinner
            draft.foodName = "Outro nome"
            draft.quantityText = "140,5"
            draft.consumedAt = Self.consumedAt.addingTimeInterval(-3_600)

            let request = try #require(draft.request(language: Self.pt))
            #expect(request.mealType == .dinner)
            #expect(request.items.map(\.foodName) == ["Outro nome"])
            #expect(request.items.map(\.quantityG) == [Self.decimal("140.5")])
            #expect(request.items.map(\.userKcal) == [expected])
        }
    }

    // 4. Explicit manual change.
    @Test(
        "a value the patient types is sent as their reported value, fractions included",
        arguments: [
            (SupportedAppLanguage.portugueseBrazil, "180,5", "180.5"),
            (SupportedAppLanguage.portugueseBrazil, "12,25", "12.25"),
            (SupportedAppLanguage.portugueseBrazil, "1,234", "1.234"),
            (SupportedAppLanguage.portugueseBrazil, "12.25", "12.25"),
            (SupportedAppLanguage.portugueseBrazil, " 95 ", "95"),
            (SupportedAppLanguage.portugueseBrazil, "0", "0"),
            (SupportedAppLanguage.portugueseBrazil, "20000", "20000"),
            (SupportedAppLanguage.englishUnitedStates, "12.25", "12.25"),
            (SupportedAppLanguage.englishUnitedStates, "1.234", "1.234"),
            (SupportedAppLanguage.englishUnitedStates, "180,5", "180.5"),
        ]
    )
    func typedValueIsReported(language: SupportedAppLanguage, typed: String, expected: String) throws {
        var draft = Self.draft([Self.calculated])
        draft.manualKcalText = typed

        #expect(draft.kcalInput(language: language) == .manual(Self.decimal(expected)))
        let request = try #require(draft.request(language: language))
        #expect(request.items.map(\.userKcal) == [Self.decimal(expected)])
    }

    @Test(
        "an unreadable, ambiguous or out-of-range calorie entry blocks saving with an explicit error",
        arguments: [
            (SupportedAppLanguage.portugueseBrazil, "1.234"),
            (SupportedAppLanguage.englishUnitedStates, "1,234"),
            (SupportedAppLanguage.portugueseBrazil, "1.234,5"),
            (SupportedAppLanguage.englishUnitedStates, "1,234.5"),
            (SupportedAppLanguage.portugueseBrazil, "12,3,4"),
            (SupportedAppLanguage.portugueseBrazil, "abc"),
            (SupportedAppLanguage.portugueseBrazil, "-5"),
            (SupportedAppLanguage.portugueseBrazil, "1e3"),
            (SupportedAppLanguage.portugueseBrazil, ",5"),
            (SupportedAppLanguage.portugueseBrazil, "12,"),
            (SupportedAppLanguage.portugueseBrazil, "20001"),
            (SupportedAppLanguage.portugueseBrazil, "20000,5"),
        ]
    )
    func invalidKcalBlocksSaving(language: SupportedAppLanguage, typed: String) {
        var draft = Self.draft([Self.calculated])
        draft.manualKcalText = typed

        #expect(draft.kcalInput(language: language) == .invalid)
        #expect(draft.blocker(language: language) == .invalidKcal)
        #expect(draft.request(language: language) == nil)
    }

    // 5. Back to the official calculation only by the explicit action.
    @Test("erasing a reported value does not silently return to the calculation")
    func erasingReportedValueIsBlocked() {
        var draft = Self.draft([Self.reported])
        draft.manualKcalText = ""

        #expect(draft.kcalInput(language: Self.pt) == .clearedReportedValue)
        #expect(draft.blocker(language: Self.pt) == .clearedReportedKcal)
        #expect(draft.request(language: Self.pt) == nil)
    }

    @Test("the explicit server-calculation action omits user_kcal, and a new typed value still counts")
    func explicitServerCalculation() throws {
        var draft = Self.draft([Self.reported])
        draft.useServerCalculation()

        #expect(draft.manualKcalDisplay(language: Self.pt).isEmpty)
        #expect(draft.kcalInput(language: Self.pt) == .official)
        let request = try #require(draft.request(language: Self.pt))
        #expect(request.items.map(\.userKcal) == [nil])
        #expect(Set(try Self.itemsJSON(request)[0].keys) == ["food_name", "quantity_g"])

        draft.manualKcalText = "150"
        #expect(try #require(draft.request(language: Self.pt)).items.map(\.userKcal) == [150])
    }

    @Test("keeping a reported value while changing the quantity asks the patient to check it")
    func reportedValueWithNewQuantityIsFlagged() {
        var draft = Self.draft([Self.reported])
        #expect(!draft.asksToReviewReportedKcal(language: Self.pt))

        draft.quantityText = "86"
        #expect(draft.asksToReviewReportedKcal(language: Self.pt))

        draft.manualKcalText = "400"
        #expect(!draft.asksToReviewReportedKcal(language: Self.pt))
        #expect(!Self.draft([Self.calculated]).offersServerCalculation)
        #expect(Self.draft([Self.reported]).offersServerCalculation)
    }

    // Items 2…N.
    @Test("editing the first item keeps every other item, in order, with its quantity and origin")
    func otherItemsArePreserved() throws {
        let second = Self.item("Feijão", quantity: "86.5", kcal: "66")
        let third = Self.item("Suco", quantity: "250", kcal: "55", userKcal: "55", source: "user_kcal")
        var draft = Self.draft([Self.calculated, second, third])
        draft.quantityText = "150"

        let request = try #require(draft.request(language: Self.pt))
        #expect(request.items.map(\.foodName) == ["Arroz integral", "Feijão", "Suco"])
        #expect(request.items.map(\.quantityG) == [150, Self.decimal("86.5"), 250])
        #expect(request.items.map(\.userKcal) == [nil, nil, 55])
        let json = try Self.itemsJSON(request)
        #expect(Set(json[1].keys) == ["food_name", "quantity_g"])
        #expect((json[2]["user_kcal"] as? NSNumber)?.decimalValue == 55)
    }

    // Version mismatch: a response without provenance.
    @Test("a response without calorie provenance blocks editing instead of guessing")
    func unknownOriginBlocksEditing() throws {
        let legacy = Data("""
        {"id":"7c9c0c5e-1f6a-4a1a-9c0b-0f1d2e3a4b5c","status":"pending",
         "created_at":"2026-07-20T12:00:00Z","expires_at":"2026-07-21T12:00:00Z","resolved_at":null,
         "proposal":{"kind":"meal","meal_type":"almoco",
           "items":[{"name":"Wrap","quantity_g":43,"kcal":200,"protein_g":2,"carbs_g":12,"fat_g":1.5},
                    {"name":"Suco","quantity_g":250,"kcal":55,"protein_g":0,"carbs_g":13,"fat_g":0}],
           "totals":null,"warnings":[]}}
        """.utf8)
        let registration = try JSONDecoder().decode(RegistrationSnapshot.self, from: legacy)
        let seed = MealProposalEditorSeed(registration: registration, initialConsumedAt: Self.consumedAt)
        #expect(seed.hasUnknownKcalOrigin)

        var draft = MealProposalEditorDraft(seed: seed)
        #expect(draft.blocker(language: Self.pt) == .unknownKcalOrigin)
        #expect(draft.request(language: Self.pt) == nil)
        draft.manualKcalText = "200"
        #expect(draft.request(language: Self.pt) == nil)
    }

    // Quantities.
    @Test(
        "a quantity is read by the app language and never truncated",
        arguments: [
            (SupportedAppLanguage.portugueseBrazil, "140,5", "140.5"),
            (SupportedAppLanguage.englishUnitedStates, "140.5", "140.5"),
            (SupportedAppLanguage.portugueseBrazil, "140.5", "140.5"),
            (SupportedAppLanguage.englishUnitedStates, "140,5", "140.5"),
            (SupportedAppLanguage.portugueseBrazil, "1,234", "1.234"),
            (SupportedAppLanguage.portugueseBrazil, "9999", "9999"),
        ]
    )
    func quantityIsReadByLanguage(language: SupportedAppLanguage, typed: String, expected: String) throws {
        var draft = Self.draft([Self.calculated])
        draft.quantityText = typed

        let request = try #require(draft.request(language: language))
        #expect(request.items.map(\.quantityG) == [Self.decimal(expected)])
    }

    @Test(
        "an ambiguous, grouped, empty or out-of-range quantity blocks saving",
        arguments: [
            (SupportedAppLanguage.portugueseBrazil, "1.234"),
            (SupportedAppLanguage.englishUnitedStates, "1,234"),
            (SupportedAppLanguage.portugueseBrazil, "1.234,5"),
            (SupportedAppLanguage.portugueseBrazil, "0"),
            (SupportedAppLanguage.portugueseBrazil, "10000"),
            (SupportedAppLanguage.portugueseBrazil, "abc"),
            (SupportedAppLanguage.portugueseBrazil, ""),
        ]
    )
    func invalidQuantityBlocksSaving(language: SupportedAppLanguage, typed: String) {
        var draft = Self.draft([Self.calculated])
        draft.quantityText = typed

        #expect(draft.blocker(language: language) == .invalidQuantity)
        #expect(draft.request(language: language) == nil)
    }

    @Test("an untouched quantity is shown in the app language and sent exactly as the server gave it")
    func untouchedQuantity() throws {
        let draft = Self.draft([Self.calculated])

        #expect(draft.quantityDisplay(language: Self.pt) == "133,5")
        #expect(draft.quantityDisplay(language: Self.en) == "133.5")
        #expect(try #require(draft.request(language: Self.en)).items.map(\.quantityG) == [Self.decimal("133.5")])
    }

    @Test("a reported value is shown in the app language")
    func reportedValueDisplay() {
        let fractional = Self.item("Wrap", quantity: "43", kcal: "12.3", userKcal: "12.25", source: "user_kcal")
        let draft = Self.draft([fractional])

        #expect(draft.manualKcalDisplay(language: Self.pt) == "12,25")
        #expect(draft.manualKcalDisplay(language: Self.en) == "12.25")
        #expect(draft.kcalInput(language: Self.pt) == .manual(Self.decimal("12.25")))
    }

    @Test("the read-only server value follows the language's number format and never shows zero for a missing value")
    func serverValueTextFollowsTheLanguage() throws {
        let value = Self.decimal("155.4")
        #expect(MealProposalEditorPresentation.officialKcalText(value, language: Self.pt) == "155,4 kcal")
        #expect(MealProposalEditorPresentation.officialKcalText(value, language: Self.en) == "155.4 kcal")
        #expect(MealProposalEditorPresentation.officialKcalText(1_250, language: Self.pt) == "1.250 kcal")
        #expect(MealProposalEditorPresentation.officialKcalText(1_250, language: Self.en) == "1,250 kcal")
        #expect(MealProposalEditorPresentation.officialKcalText(nil, language: Self.pt) == "Sem valor do servidor")
        #expect(MealProposalEditorPresentation.officialKcalText(nil, language: Self.en) == "No server value")
    }

    @Test("a proposal without a server value keeps the calculation on the server")
    func missingServerValueStaysOnTheServer() throws {
        let seed = MealProposalEditorSeed(
            registration: Self.registration([Self.item("Arroz", quantity: "120", kcal: nil, source: nil)]),
            initialConsumedAt: Self.consumedAt
        )
        #expect(seed.officialKcal == nil)

        let request = try #require(MealProposalEditorDraft(seed: seed).request(language: Self.pt))
        #expect(request.items.map(\.userKcal) == [nil])
    }

    // MARK: - Items the server has not calculated (device gate 2026-09-27)

    private static let unresolvedBeans = MealProposalItemSnapshot(
        name: "Feijão carioca",
        quantityG: decimal("86.5"),
        kcal: 0,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        userKcal: nil,
        nutritionSource: "no_match",
        resolution: "needs_clarification",
        preparationOptions: ["cru", "cozido"]
    )

    @Test("the pending item decodes its resolution and preparation options; an earlier server has none")
    func decodesResolution() throws {
        let json = """
            {"name":"Feijão carioca","quantity_g":86.5,"kcal":0,"protein_g":0,"carbs_g":0,
             "fat_g":0,"user_kcal":null,"nutrition_source":"no_match",
             "resolution":"needs_clarification","preparation_options":["cru","cozido"]}
            """
        let item = try JSONDecoder().decode(MealProposalItemSnapshot.self, from: Data(json.utf8))
        #expect(item.needsClarification)
        #expect(item.preparationOptions == ["cru", "cozido"])

        let legacy = """
            {"name":"Água","quantity_g":250,"kcal":0,"protein_g":0,"carbs_g":0,"fat_g":0,
             "user_kcal":null,"nutrition_source":"rule_based"}
            """
        let water = try JSONDecoder().decode(MealProposalItemSnapshot.self, from: Data(legacy.utf8))
        #expect(!water.needsClarification)
        #expect(water.preparationOptions == nil)
    }

    @Test("an item without calculation blocks the confirmation; a legitimate zero does not")
    func unresolvedItemBlocksConfirmation() {
        let water = Self.item("Água", quantity: "250", kcal: "0", source: "rule_based")
        let blocked = MealProposalPresentation(
            registration: Self.registration([Self.calculated, Self.unresolvedBeans])
        )
        #expect(blocked.hasUnresolvedItems)
        #expect(!blocked.allowsConfirm)
        #expect(blocked.allowsEdit)
        #expect(blocked.items.map(\.needsClarification) == [false, true])

        let allowed = MealProposalPresentation(
            registration: Self.registration([Self.calculated, water])
        )
        #expect(!allowed.hasUnresolvedItems)
        #expect(allowed.allowsConfirm)
    }

    @Test("fixing the second item sends every item in order and only renames that one")
    func editsAnyItemKeepingTheOthers() throws {
        var draft = MealProposalEditorDraft(seed: MealProposalEditorSeed(
            registration: Self.registration([Self.reported, Self.unresolvedBeans, Self.calculated]),
            initialConsumedAt: Self.consumedAt,
            editedIndex: 1
        ))
        #expect(draft.foodName == "Feijão carioca")
        #expect(draft.preparationOptions == ["cru", "cozido"])

        draft.choosePreparation("cru")
        draft.choosePreparation("cozido")
        #expect(draft.foodName == "Feijão carioca cozido")

        let request = try #require(draft.request(language: Self.pt))
        let items = try Self.itemsJSON(request)
        #expect(items.map { $0["food_name"] as? String } == [
            "Wrap", "Feijão carioca cozido", "Arroz integral",
        ])
        #expect((items[1]["quantity_g"] as? NSNumber)?.decimalValue == Self.decimal("86.5"))
        // The unresolved item never carries a calorie from the device.
        #expect(items[1]["user_kcal"] == nil)
        // The patient's value on another item is kept; a calculated one is not sent.
        #expect((items[0]["user_kcal"] as? NSNumber)?.decimalValue == 200)
        #expect(items[2]["user_kcal"] == nil)
    }

    @Test("an out-of-range index edits the first item; a resolved item offers no preparation")
    func editorIndexIsBounded() {
        let draft = MealProposalEditorDraft(seed: MealProposalEditorSeed(
            registration: Self.registration([Self.calculated, Self.unresolvedBeans]),
            initialConsumedAt: Self.consumedAt,
            editedIndex: 9
        ))
        #expect(draft.editedIndex == 0)
        #expect(draft.foodName == "Arroz integral")
        #expect(draft.preparationOptions.isEmpty)
    }

    @Test("the editor shows no server value for an item that was not calculated")
    func unresolvedItemHasNoServerValue() {
        let seed = MealProposalEditorSeed(
            registration: Self.registration([Self.calculated, Self.unresolvedBeans]),
            initialConsumedAt: Self.consumedAt,
            editedIndex: 1
        )
        #expect(seed.officialKcal == nil)
    }
}
