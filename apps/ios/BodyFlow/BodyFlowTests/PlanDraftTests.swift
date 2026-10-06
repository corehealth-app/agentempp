import Foundation
import Testing

@testable import BodyFlow

// Synthetic QA content; no real data.
private enum DraftFixtures {
    static let draftID = "0d0d0d0d-1111-4222-8333-444455556666"
    static let assetID = "0a0a0a0a-1111-4222-8333-444455556666"
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    static let trainingJSON = """
    {"plan_type":"custom","weekly_schedule":[
      {"day":"Treino A","focus":"Inferiores","duration_min":60,"exercises":[
        {"name":"Agachamento livre","muscle_group":"pernas","sets":4,"reps_range":"8-12",
         "rest_seconds":90,"execution_steps":["descer devagar"],"notes":"carga moderada"},
        {"name":"Leg press","muscle_group":"pernas","sets":3,"reps_range":"10","rest_seconds":null}
      ]},
      {"day":"Treino B","focus":"Superiores","duration_min":50,"exercises":[
        {"name":"Supino","muscle_group":"peito","sets":3,"reps_range":"8-12","rest_seconds":90}
      ]}
    ],"progression_rule":"subir carga a cada 2 semanas"}
    """

    static let nutritionJSON = """
    {"horizon":"daily","daily_meals":[
      {"meal_type":"almoco","time_suggestion":"12h30","items":[
        {"food_name":"Arroz integral","quantity_g":120},
        {"food_name":"Azeite","quantity_g":null,"display_qty":1,"display_unit":"colher de sopa"}
      ]}
    ],"shopping_list":[]}
    """

    static func payload(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    static func snapshot(
        domain: PlanDraftDomain = .training,
        json: String = trainingJSON,
        status: String = "needs_completion",
        version: Int = 1,
        uncertain: [PlanDraftUncertainField] = [
            PlanDraftUncertainField(
                pointer: "/weekly_schedule/0/exercises/1/rest_seconds", reason: "missing"
            ),
        ],
        failureCode: String? = nil
    ) throws -> PlanDraftSnapshot {
        PlanDraftSnapshot(
            id: draftID,
            domain: domain,
            origin: "imported_pdf",
            status: status,
            payloadVersion: version,
            payload: status == "extracting" || status == "failed" ? nil : try payload(json),
            uncertainFields: uncertain,
            unrecognizedSegments: ["Tomar creatina 5 g após o treino."],
            replacesCurrentPlan: true,
            canConfirm: status == "ready_for_review",
            notices: ["not_professionally_reviewed", "medications_not_imported"],
            failureCode: failureCode,
            confirmedPlanID: status == "confirmed" ? "plan-1" : nil,
            alreadyConfirmed: nil
        )
    }
}

@Suite("Plan draft document")
struct PlanDraftDocumentTests {
    private func training() throws -> PlanDraftDocument {
        PlanDraftDocument(
            domain: .training,
            payload: try DraftFixtures.payload(DraftFixtures.trainingJSON)
        )
    }

    @Test("Fields carry the same pointers the server uses for what is uncertain")
    func pointers() throws {
        let document = try training()

        #expect(document.sections.map(\.id) == ["/weekly_schedule/0", "/weekly_schedule/1"])
        #expect(document.sections[0].fields.map(\.pointer) == [
            "/weekly_schedule/0/day",
            "/weekly_schedule/0/focus",
            "/weekly_schedule/0/duration_min",
        ])
        #expect(document.sections[0].rows[1].fields.map(\.pointer) == [
            "/weekly_schedule/0/exercises/1/name",
            "/weekly_schedule/0/exercises/1/muscle_group",
            "/weekly_schedule/0/exercises/1/sets",
            "/weekly_schedule/0/exercises/1/reps_range",
            "/weekly_schedule/0/exercises/1/rest_seconds",
        ])
        #expect(PlanDraftDocument.pointer([.key("a/b~c"), .index(2)]) == "/a~1b~0c/2")
    }

    @Test("An edit changes only its field; what the app does not show travels back untouched")
    func editsOnlyTheField() throws {
        var document = try training()
        let original = document.root
        let rest = document.sections[0].rows[1].fields[4]

        document.set(.number(60), at: rest.path)

        #expect(document.value(at: rest.path) == .number(60))
        let exercise = document.value(at: [
            .key("weekly_schedule"), .index(0), .key("exercises"), .index(0),
        ])
        #expect(exercise == JSONValue.object([
            "name": .string("Agachamento livre"),
            "muscle_group": .string("pernas"),
            "sets": .number(4),
            "reps_range": .string("8-12"),
            "rest_seconds": .number(90),
            "execution_steps": .array([.string("descer devagar")]),
            "notes": .string("carga moderada"),
        ]))
        #expect(document.value(at: [.key("progression_rule")])
            == .string("subir carga a cada 2 semanas"))
        #expect(document.root != original)
    }

    @Test("The app never grows the content: a path that leads nowhere is ignored")
    func ignoresForeignPaths() throws {
        var document = try training()
        let original = document.root

        document.set(.string("x"), at: [.key("weekly_schedule"), .index(9), .key("day")])
        document.set(.string("x"), at: [.key("medications"), .index(0), .key("dose")])
        document.set(.string("x"), at: [])
        document.remove(at: [.key("weekly_schedule"), .index(9)])
        document.remove(at: [.key("weekly_schedule")])

        #expect(document.root == original)
    }

    @Test("Removing an exercise or a day removes exactly that one")
    func removes() throws {
        var document = try training()

        document.remove(at: document.sections[0].rows[0].path)
        #expect(document.sections[0].rows.count == 1)
        #expect(document.text(of: document.sections[0].rows[0].fields[0], language: .portugueseBrazil)
            == "Leg press")

        document.remove(at: document.sections[0].path)
        #expect(document.sections.count == 1)
        #expect(document.text(of: document.sections[0].fields[0], language: .portugueseBrazil)
            == "Treino B")
    }

    @Test("What the patient types is sent as it is, or refused — never adjusted")
    func typedValues() throws {
        let document = try training()
        let day = document.sections[0].fields[0]
        let duration = document.sections[0].fields[2]
        let sets = document.sections[0].rows[0].fields[2]
        let rest = document.sections[0].rows[0].fields[4]
        let language = SupportedAppLanguage.portugueseBrazil
        func value(_ text: String, _ field: PlanDraftDocument.Field) -> JSONValue? {
            PlanDraftDocument.value(for: text, of: field, language: language)
        }

        #expect(value("  Treino C ", day) == .string("Treino C"))
        #expect(value("", day) == .null)
        #expect(value("   ", sets) == .null)
        #expect(value(String(repeating: "a", count: 21), day) == nil)
        #expect(value("60", duration) == .number(60))
        #expect(value("9", duration) == nil)
        #expect(value("181", duration) == nil)
        #expect(value("15", sets) == .number(15))
        #expect(value("16", sets) == nil)
        #expect(value("0", sets) == nil)
        #expect(value("3,5", sets) == nil)
        #expect(value("-3", sets) == nil)
        #expect(value("três", sets) == nil)
        #expect(value("0", rest) == .number(0))
        #expect(value("601", rest) == nil)
    }

    @Test("A meal plan shows food and grams, and the household measure as it came")
    func nutrition() throws {
        let document = PlanDraftDocument(
            domain: .nutrition,
            payload: try DraftFixtures.payload(DraftFixtures.nutritionJSON)
        )
        let language = SupportedAppLanguage.portugueseBrazil

        #expect(document.sections.count == 1)
        #expect(document.sections[0].fields.map(\.key) == ["meal_type", "time_suggestion"])
        let rows = document.sections[0].rows
        #expect(rows.map { $0.fields.map(\.key) } == [
            ["food_name", "quantity_g"], ["food_name", "quantity_g"],
        ])
        #expect(document.text(of: rows[0].fields[1], language: language) == "120")
        #expect(document.text(of: rows[1].fields[1], language: language) == "")
        #expect(rows[0].note == nil)
        #expect(rows[1].note == "1 colher de sopa")

        let quantity = rows[1].fields[1]
        let meal = document.sections[0].fields[0]
        #expect(PlanDraftDocument.value(for: "13,5", of: quantity, language: language)
            == .number(Decimal(string: "13.5")!))
        #expect(PlanDraftDocument.value(for: "0", of: quantity, language: language) == nil)
        #expect(PlanDraftDocument.value(for: "2001", of: quantity, language: language) == nil)
        #expect(PlanDraftDocument.value(for: "jantar", of: meal, language: language)
            == .string("jantar"))
        #expect(PlanDraftDocument.value(for: "brunch", of: meal, language: language) == nil)
    }

    @Test("Everything that will be confirmed is on screen, edited or not")
    func showsEveryValue() throws {
        let language = SupportedAppLanguage.portugueseBrazil
        let nutrition = PlanDraftDocument(
            domain: .nutrition,
            payload: try DraftFixtures.payload("""
            {"mode":"referencia","horizon":"weekly","meta_kcal":1200,"meta_protein_g":140,
             "notes":"beber água","daily_meals":[
              {"meal_type":"almoco","day_of_week":3,"total_kcal":390,"total_protein_g":48,
               "notes":"comer devagar","items":[
                {"food_name":"Arroz","quantity_g":120,"kcal":150,"protein_g":3,"carbs_g":33,"fat_g":0.3}
               ]}],
             "shopping_list":[{"category":"carboidratos","food_name":"Arroz","quantity_g":840}]}
            """)
        )
        #expect(nutrition.planDetails(language: language).map { "\($0.key)=\($0.text)" } == [
            "mode=referencia", "horizon=weekly", "meta_kcal=1200", "meta_protein_g=140",
            "notes=beber água",
        ])
        #expect(nutrition.sections[0].details.map { "\($0.key)=\($0.text)" } == [
            "day_of_week=3", "total_kcal=390", "total_protein_g=48", "notes=comer devagar",
        ])
        #expect(nutrition.sections[0].rows[0].details.map { "\($0.key)=\($0.text)" } == [
            "kcal=150", "protein_g=3", "carbs_g=33", "fat_g=0,3",
        ])
        #expect(nutrition.sections[0].rows[0].title == "Arroz")
        #expect(nutrition.shoppingList(language: language).map(\.text)
            == ["Arroz · 840 g · carboidratos"])

        let training = try training()
        #expect(training.planDetails(language: language).map(\.key)
            == ["plan_type", "progression_rule"])
        #expect(training.sections[0].rows[0].details.map { "\($0.key)=\($0.text)" } == [
            "notes=carga moderada", "execution_steps=descer devagar",
        ])
        #expect(training.shoppingList(language: language).isEmpty)
    }

    @Test("Free text goes below its label; closed values, numbers and the equipment list stay beside it")
    func freeTextIsStackedAndShortValuesAreNot() throws {
        let language = SupportedAppLanguage.portugueseBrazil
        func layouts(_ details: [PlanDraftDocument.Detail]) -> [String] {
            details.map { "\($0.key)=\(PlanDraftCopy.detailLayout($0.key))" }
        }

        let training = PlanDraftDocument(
            domain: .training,
            payload: try DraftFixtures.payload("""
            {"plan_type":"full_body","equipment_summary":"Halteres e banco",
             "progression_rule":"subir carga a cada 2 semanas",
             "notes":"Plano Full Body otimizado para 1x/semana","weekly_schedule":[
              {"day":"Treino A","focus":"Peito","duration_min":45,"exercises":[
               {"name":"Supino","muscle_group":"peito","sets":3,"reps_range":"8-12",
                "rest_seconds":90,"rpe_target":"7-8","notes":"carga moderada",
                "execution_steps":["descer devagar"],
                "common_mistakes":["tirar o quadril do banco"]}
              ]}]}
            """)
        )
        #expect(layouts(training.planDetails(language: language)) == [
            "plan_type=row", "equipment_summary=row", "progression_rule=stacked", "notes=stacked",
        ])
        #expect(layouts(training.sections[0].rows[0].details) == [
            "rpe_target=row", "notes=stacked", "execution_steps=stacked", "common_mistakes=stacked",
        ])

        let nutrition = PlanDraftDocument(
            domain: .nutrition,
            payload: try DraftFixtures.payload("""
            {"mode":"referencia","horizon":"weekly","meta_kcal":1200,"meta_protein_g":140,
             "notes":"beber água","daily_meals":[
              {"meal_type":"almoco","day_of_week":3,"total_kcal":390,"total_protein_g":48,
               "notes":"comer devagar","items":[
                {"food_name":"Arroz","quantity_g":120,"kcal":150,"protein_g":3,"carbs_g":33,"fat_g":0.3}
               ]}]}
            """)
        )
        #expect(layouts(nutrition.planDetails(language: language)) == [
            "mode=row", "horizon=row", "meta_kcal=row", "meta_protein_g=row", "notes=stacked",
        ])
        #expect(layouts(nutrition.sections[0].details) == [
            "day_of_week=row", "total_kcal=row", "total_protein_g=row", "notes=stacked",
        ])
        #expect(layouts(nutrition.sections[0].rows[0].details) == [
            "kcal=row", "protein_g=row", "carbs_g=row", "fat_g=row",
        ])
        #expect(PlanDraftCopy.detailLayout("anything_else") == .row)
    }

    @Test("A value of a shape the screen cannot show blocks the confirmation")
    func unreadableContent() throws {
        let document = PlanDraftDocument(
            domain: .training,
            payload: try DraftFixtures.payload("""
            {"weekly_schedule":[{"day":{"x":1},"focus":"a","duration_min":30,"exercises":[]}]}
            """)
        )
        #expect(document.hasUnreadableContent)
        #expect(try !training().hasUnreadableContent)
    }

    @Test("Content that is not an object is an empty document")
    func emptyDocument() {
        for payload in [nil, JSONValue.null, .array([]), .string("x")] {
            let document = PlanDraftDocument(domain: .training, payload: payload)
            #expect(document.isEmpty)
            #expect(document.root == .object([:]))
        }
    }
}

@Suite("Plan draft review model")
@MainActor
struct PlanDraftReviewModelTests {
    private let language = SupportedAppLanguage.portugueseBrazil

    private func makeModel(
        _ provider: PlanDraftProviderFake,
        changed: @escaping @MainActor () -> Void = {}
    ) -> PlanDraftReviewModel {
        PlanDraftReviewModel(
            draftID: DraftFixtures.draftID,
            provider: provider,
            timeProvider: FixedTimeProvider(value: DraftFixtures.now),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "draft-key"),
            planChanged: changed,
            pollInterval: .milliseconds(1),
            maximumPolls: 5
        )
    }

    private func restField(_ model: PlanDraftReviewModel) throws -> PlanDraftDocument.Field {
        try #require(model.document).sections[0].rows[1].fields[4]
    }

    @Test("An incomplete draft is shown with what is missing and cannot be confirmed")
    func incompleteDraft() async throws {
        let provider = PlanDraftProviderFake(try DraftFixtures.snapshot())
        let model = makeModel(provider)

        await model.load()

        #expect(model.phase == .review)
        #expect(!model.canConfirm)
        #expect(!model.canSave(language: language))
        #expect(model.uncertainty(of: try restField(model)) == "missing")
        #expect(model.snapshot?.mentionsMedications == true)
        await model.confirm()
        #expect(await provider.calls == [.draft])
    }

    @Test("Saving sends the content with the patient's edits and the version read")
    func save() async throws {
        let provider = PlanDraftProviderFake(try DraftFixtures.snapshot())
        let model = makeModel(provider)
        await model.load()
        let rest = try restField(model)
        let sets = try #require(model.document).sections[0].rows[0].fields[2]

        model.setText("60", of: rest, language: language)
        model.setText("", of: sets, language: language)
        #expect(model.hasUnsavedChanges)
        #expect(model.uncertainty(of: rest) == nil)
        #expect(!model.canConfirm)
        await provider.setNext(try DraftFixtures.snapshot(
            status: "needs_completion", version: 2,
            uncertain: [PlanDraftUncertainField(
                pointer: "/weekly_schedule/0/exercises/0/sets", reason: "missing"
            )]
        ))

        await model.save(language: language)

        let edit = try #require(await provider.edits.first)
        #expect(edit.payloadVersion == 1)
        var expected = PlanDraftDocument(
            domain: .training,
            payload: try DraftFixtures.payload(DraftFixtures.trainingJSON)
        )
        expected.set(.number(60), at: rest.path)
        expected.set(.null, at: sets.path)
        #expect(edit.payload == expected.root)
        #expect(!model.hasUnsavedChanges)
        #expect(model.snapshot?.payloadVersion == 2)
        #expect(model.uncertainty(of: sets) == "missing")
    }

    @Test("An invalid value blocks saving and nothing is sent")
    func invalidEdit() async throws {
        let provider = PlanDraftProviderFake(try DraftFixtures.snapshot())
        let model = makeModel(provider)
        await model.load()
        let rest = try restField(model)

        model.setText("9000", of: rest, language: language)

        #expect(model.isInvalid(rest, language: language))
        #expect(model.hasInvalidEdits(language: language))
        #expect(!model.canSave(language: language))
        await model.save(language: language)
        await model.remove(try #require(model.document).sections[0].rows[0].path, language: language)
        #expect(await provider.edits.isEmpty)

        // Typing the server's own value back is not an edit.
        model.setText("", of: rest, language: language)
        #expect(!model.hasUnsavedChanges)
    }

    @Test("Only the complete draft, exactly as shown, is confirmed")
    func confirm() async throws {
        let provider = PlanDraftProviderFake(
            try DraftFixtures.snapshot(status: "ready_for_review", version: 3, uncertain: [])
        )
        var changes = 0
        let model = makeModel(provider) { changes += 1 }
        await model.load()
        #expect(model.canConfirm)

        // Something typed and not saved: the confirmation waits.
        let rest = try restField(model)
        model.setText("45", of: rest, language: language)
        #expect(!model.canConfirm)
        await model.confirm()
        #expect(await provider.confirmations.isEmpty)
        model.setText("", of: rest, language: language)

        await provider.setNext(try DraftFixtures.snapshot(status: "confirmed", version: 3))
        await model.confirm()

        #expect(await provider.confirmations.map(\.payload) == [
            PlanDraftConfirmation(draftID: DraftFixtures.draftID, payloadVersion: 3),
        ])
        #expect(model.phase == .confirmed)
        #expect(changes == 1)
        #expect(!model.canConfirm)
        #expect(!model.canDiscard)
    }

    @Test("Coming back to the screen keeps what the patient typed")
    func reloadKeepsEdits() async throws {
        let provider = PlanDraftProviderFake(try DraftFixtures.snapshot())
        let model = makeModel(provider)
        await model.load()
        let rest = try restField(model)
        model.setText("60", of: rest, language: language)

        // Another tab was visited: the screen disappears and appears again.
        model.invalidate()
        await model.load()

        #expect(await provider.calls == [.draft])
        #expect(model.text(of: rest, language: language) == "60")
        #expect(model.hasUnsavedChanges)
        #expect(!model.canConfirm)
    }

    @Test("A new quantity clears the calories that belonged to the old one")
    func quantityClearsDependents() async throws {
        let json = """
        {"horizon":"daily","daily_meals":[
          {"meal_type":"almoco","total_kcal":390,"total_protein_g":48,"items":[
            {"food_name":"Arroz","quantity_g":100,"kcal":128,"protein_g":2.5,"carbs_g":28,"fat_g":0.2},
            {"food_name":"Frango","quantity_g":150,"kcal":240,"protein_g":45}
          ]}],"shopping_list":[]}
        """
        let provider = PlanDraftProviderFake(try DraftFixtures.snapshot(
            domain: .nutrition, json: json, status: "ready_for_review", uncertain: []
        ))
        let model = makeModel(provider)
        await model.load()
        let quantity = try #require(model.document).sections[0].rows[0].fields[1]

        model.setText("300", of: quantity, language: language)
        await model.save(language: language)

        let sent = PlanDraftDocument(
            domain: .nutrition,
            payload: try #require(await provider.edits.first).payload
        )
        let item: PlanDraftDocument.Path = [.key("daily_meals"), .index(0), .key("items"), .index(0)]
        #expect(sent.value(at: item + [.key("quantity_g")]) == .number(300))
        for key in ["kcal", "protein_g", "carbs_g", "fat_g"] {
            #expect(sent.value(at: item + [.key(key)]) == .null, "\(key)")
        }
        let meal: PlanDraftDocument.Path = [.key("daily_meals"), .index(0)]
        #expect(sent.value(at: meal + [.key("total_kcal")]) == .null)
        #expect(sent.value(at: meal + [.key("total_protein_g")]) == .null)
        // The item nobody touched keeps what it had.
        let other: PlanDraftDocument.Path = [.key("daily_meals"), .index(0), .key("items"), .index(1)]
        #expect(sent.value(at: other + [.key("kcal")]) == .number(240))
    }

    @Test("A draft with nothing to show, or with a value that cannot be shown, is not confirmed")
    func emptyOrUnreadableIsNotConfirmed() async throws {
        for json in [
            #"{"notes":"só observações"}"#,
            #"{"weekly_schedule":[{"day":["x"],"focus":"a","duration_min":30,"exercises":[]}]}"#,
        ] {
            let provider = PlanDraftProviderFake(try DraftFixtures.snapshot(
                json: json, status: "ready_for_review", uncertain: []
            ))
            let model = makeModel(provider)
            await model.load()
            #expect(model.snapshot?.canConfirm == true)
            #expect(!model.canConfirm)
            await model.confirm()
            #expect(await provider.confirmations.isEmpty)
        }
    }

    @Test("An item flagged as medication or supplement keeps its name and says why")
    func itemFlags() async throws {
        let json = """
        {"daily_meals":[{"meal_type":"lanche_tarde","items":[
          {"food_name":"Banana","quantity_g":100},
          {"food_name":"Creatina","quantity_g":5}
        ]}]}
        """
        let provider = PlanDraftProviderFake(try DraftFixtures.snapshot(
            domain: .nutrition, json: json, status: "needs_completion",
            uncertain: [PlanDraftUncertainField(pointer: "/daily_meals/0/items/1", reason: "supplement")]
        ))
        let model = makeModel(provider)
        await model.load()
        let rows = try #require(model.document).sections[0].rows

        #expect(rows[1].title == "Creatina")
        #expect(model.text(of: rows[1].fields[0], language: language) == "Creatina")
        #expect(model.uncertainty(ofRow: rows[1]) == "supplement")
        #expect(model.uncertainty(ofRow: rows[0]) == nil)
        #expect(!model.canConfirm)
        #expect(PlanDraftCopy.uncertaintyKey("outside_domain") == "plan.draft.uncertain.outside-domain")
        #expect(PlanDraftCopy.uncertaintyKey("supplement_imported")
            == "plan.draft.uncertain.supplement-imported")
    }

    @Test("A confirmation that failed is repeated as the same request")
    func confirmRetryKeepsKey() async throws {
        let provider = PlanDraftProviderFake(
            try DraftFixtures.snapshot(status: "ready_for_review", version: 2, uncertain: [])
        )
        let model = makeModel(provider)
        await model.load()

        await provider.failNext(.offline)
        await model.confirm()
        #expect(model.actionFailure == .offline)
        #expect(model.phase == .review)

        await provider.setNext(try DraftFixtures.snapshot(status: "confirmed", version: 2))
        await model.confirm()

        let keys = await provider.confirmations.map(\.key)
        #expect(keys.count == 2)
        #expect(Set(keys).count == 1)
        #expect(model.phase == .confirmed)
    }

    @Test("When the plan changed during the review the draft stays unconfirmed and says why")
    func planChanged() async throws {
        let provider = PlanDraftProviderFake(
            try DraftFixtures.snapshot(status: "ready_for_review", version: 2, uncertain: [])
        )
        var changes = 0
        let model = makeModel(provider) { changes += 1 }
        await model.load()

        for failure in [PlanDraftFailure.planChangedDuringReview, .prescribedPlanProtected] {
            await provider.failNext(failure)
            await model.confirm()
            #expect(model.actionFailure == failure)
            #expect(model.phase == .review)
        }
        #expect(changes == 0)
    }

    @Test("A draft that changed on the server is reloaded before anything else")
    func draftChanged() async throws {
        let provider = PlanDraftProviderFake(try DraftFixtures.snapshot())
        let model = makeModel(provider)
        await model.load()
        model.setText("60", of: try restField(model), language: language)

        await provider.failNext(.draftChanged)
        await provider.setStored(try DraftFixtures.snapshot(status: "needs_completion", version: 7))
        await model.save(language: language)

        #expect(model.actionFailure == .draftChanged)
        #expect(model.snapshot?.payloadVersion == 7)
        #expect(!model.hasUnsavedChanges)
        // What was typed could not be applied, and the screen says so.
        #expect(model.droppedEdits)
    }

    @Test("While the document is read the screen waits, then shows the review")
    func waitsForExtraction() async throws {
        let provider = PlanDraftProviderFake(try DraftFixtures.snapshot(status: "extracting"))
        await provider.setSequence([
            try DraftFixtures.snapshot(status: "extracting"),
            try DraftFixtures.snapshot(status: "extracting"),
            try DraftFixtures.snapshot(status: "needs_completion"),
        ])
        let model = makeModel(provider)

        await model.load()

        #expect(await provider.calls == [.draft, .draft, .draft])
        #expect(model.phase == .review)
    }

    @Test("A reading that failed says why and offers no content")
    func failedReading() async throws {
        let provider = PlanDraftProviderFake(try DraftFixtures.snapshot(
            status: "failed", uncertain: [], failureCode: "document_without_text"
        ))
        let model = makeModel(provider)

        await model.load()

        #expect(model.phase == .closed(.failed, failureCode: "document_without_text"))
        #expect(!model.canConfirm)
        #expect(!model.canDiscard)
        #expect(try #require(model.document).isEmpty)
    }

    @Test("Discarding ends the review")
    func discard() async throws {
        let provider = PlanDraftProviderFake(try DraftFixtures.snapshot())
        let model = makeModel(provider)
        await model.load()

        await provider.setNext(try DraftFixtures.snapshot(status: "discarded"))
        await model.discard()

        #expect(await provider.calls == [.draft, .discard])
        #expect(model.phase == .discarded)
    }

    @Test("Another patient's or a missing draft is a failure with nothing shown")
    func notFound() async throws {
        let provider = PlanDraftProviderFake(try DraftFixtures.snapshot())
        await provider.failNext(.notFound)
        let model = makeModel(provider)

        await model.load()

        #expect(model.phase == .failed(.notFound))
        #expect(model.snapshot == nil)
    }
}

@Suite("Plan import model")
@MainActor
struct PlanImportModelTests {
    private struct Harness {
        let model: PlanImportModel
        let server: PlanImportServerFake
        let staging: MediaStagingStore
        let base: URL

        func stagedPDF(size: Int? = nil) throws -> StagedMedia {
            let bytes = Data("%PDF-1.7 synthetic".utf8)
            let url = try staging.stage(bytes, fileExtension: "pdf")
            return StagedMedia(
                fileURL: url, kind: .planDocument, mimeType: "application/pdf",
                sizeBytes: size ?? bytes.count, duration: nil, channel: .gallery
            )
        }
    }

    private func makeHarness(
        withMedia: Bool = true,
        assetID: String = DraftFixtures.assetID,
        draftID: String = DraftFixtures.draftID
    ) -> Harness {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("plan-import-\(UUID().uuidString)", isDirectory: true)
        let staging = MediaStagingStore(temporaryDirectory: base)
        let server = PlanImportServerFake(assetID: assetID, draftID: draftID)
        let model = PlanImportModel(
            capability: PlanDraftCapability(
                drafts: server,
                media: withMedia ? server : nil,
                uploader: withMedia ? server : nil,
                staging: staging
            ),
            timeProvider: FixedTimeProvider(value: DraftFixtures.now),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "import-key")
        )
        return Harness(model: model, server: server, staging: staging, base: base)
    }

    @Test("The document is sent, confirmed by the server and only then read as a draft")
    func pipeline() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        let staged = try harness.stagedPDF()
        harness.model.domain = .nutrition

        await harness.model.submit(staged)

        #expect(await harness.server.calls == [.create, .upload, .complete, .startImport])
        #expect(await harness.server.imports == [
            PlanImportRequest(mediaAssetID: DraftFixtures.assetID, domain: .nutrition),
        ])
        #expect(await harness.server.created.first?.kind == .planDocument)
        #expect(await harness.server.created.first?.mimeType == "application/pdf")
        #expect(harness.model.phase == .started(draftID: DraftFixtures.draftID))
        #expect(!FileManager.default.fileExists(atPath: staged.fileURL.path))
    }

    @Test("A document outside the limits never leaves the phone")
    func precheck() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        let pdf = try harness.stagedPDF()

        #expect(PlanImportModel.precheck(pdf) == nil)
        #expect(PlanImportModel.precheck(try harness.stagedPDF(size: 20 * 1_024 * 1_024 + 1))
            == .fileTooLarge)
        #expect(PlanImportModel.precheck(try harness.stagedPDF(size: 0)) == .unreadableMedia)
        #expect(PlanImportModel.precheck(StagedMedia(
            fileURL: pdf.fileURL, kind: .mealPhoto, mimeType: "image/jpeg",
            sizeBytes: 10, duration: nil, channel: .gallery
        )) == .invalidInput)
        #expect(PlanImportModel.precheck(StagedMedia(
            fileURL: pdf.fileURL, kind: .planDocument, mimeType: "text/html",
            sizeBytes: 10, duration: nil, channel: .gallery
        )) == .unsupportedFile)
    }

    // Physical staging 2026-10-01: camera JPEG uploaded at 12:50:54 BRT;
    // "Sem conexão" appeared before a draft existed. Retry opened the
    // imported draft using the same asset. OCR content is verified live;
    // this fake isolates upload/import ownership and retry identity.
    @Test("camera plan photo 867902 bytes resumes the exact import after Sem conexão without another upload")
    func physicalPhotoOfflineImportResumesSameAsset() async throws {
        let assetID = "d5aabd2a-8d87-41bf-a2f9-aaee52d21f0b"
        let draftID = "48cd7301-67e9-4955-8f63-f5b1bcae5ec7"
        let harness = makeHarness(assetID: assetID, draftID: draftID)
        defer { try? FileManager.default.removeItem(at: harness.base) }
        let file = try harness.staging.stage(
            Data(repeating: 0, count: 867_902), fileExtension: "jpg"
        )
        let photo = StagedMedia(
            fileURL: file, kind: .planDocument, mimeType: "image/jpeg",
            sizeBytes: 867_902, duration: nil, channel: .camera
        )
        await harness.server.failNextImport(.offline)
        await harness.model.submit(photo)

        #expect(harness.model.phase == .failed(.draft(.offline)))
        #expect(harness.model.canRetry)
        #expect(PlanDraftCopy.string(
            PlanDraftCopy.importFailureKey(.draft(.offline)), language: .portugueseBrazil
        ) == "Sem conexão. Verifique a internet e tente novamente.")
        #expect(await harness.server.calls == [.create, .upload, .complete, .startImport])
        let first = try #require(await harness.server.attemptedImports.first)
        #expect(first.payload == PlanImportRequest(mediaAssetID: assetID, domain: .training))
        #expect(!FileManager.default.fileExists(atPath: file.path))

        await harness.model.retry()

        #expect(await harness.server.calls == [.create, .upload, .complete, .startImport, .startImport])
        #expect(await harness.server.attemptedImports == [first, first])
        #expect(await harness.server.created == [photo.uploadRequest])
        #expect(harness.model.phase == .started(draftID: draftID))
        #expect(!harness.model.canRetry)
    }

    @Test("A failed start resumes without sending the file again")
    func resumes() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        await harness.server.failNextImport(.offline)

        await harness.model.submit(try harness.stagedPDF())
        #expect(harness.model.phase == .failed(.draft(.offline)))
        #expect(harness.model.canRetry)

        await harness.model.retry()

        #expect(await harness.server.calls == [
            .create, .upload, .complete, .startImport, .startImport,
        ])
        #expect(Set(await harness.server.importKeys).count == 1)
        #expect(harness.model.phase == .started(draftID: DraftFixtures.draftID))
    }

    @Test("A refusal that a retry cannot fix offers only a new start")
    func finalRefusal() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        await harness.server.failNextImport(.documentAlreadyRead)

        await harness.model.submit(try harness.stagedPDF())

        #expect(harness.model.phase == .failed(.draft(.documentAlreadyRead)))
        #expect(!harness.model.canRetry)
    }

    @Test("Giving up before the import was asked removes the file and the server's copy")
    func startOver() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        let staged = try harness.stagedPDF()
        await harness.server.failNextUpload()
        await harness.model.submit(staged)
        #expect(harness.model.phase == .failed(.capture(.offline)))

        harness.model.startOver()
        try await harness.server.waitForDelete()

        #expect(harness.model.phase == .idle)
        #expect(await harness.server.calls == [.create, .upload, .delete])
        #expect(!FileManager.default.fileExists(atPath: staged.fileURL.path))
    }

    @Test("Once the import was asked the document is never deleted by the app")
    func keepsImportedDocument() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        // The answer was lost: the draft may exist on the server.
        await harness.server.failNextImport(.offline)
        await harness.model.submit(try harness.stagedPDF())

        harness.model.startOver()
        try await Task.sleep(for: .milliseconds(50))
        #expect(!(await harness.server.calls.contains(.delete)))

        let finished = makeHarness()
        defer { try? FileManager.default.removeItem(at: finished.base) }
        await finished.model.submit(try finished.stagedPDF())
        finished.model.screenClosed()
        try await Task.sleep(for: .milliseconds(50))
        #expect(!(await finished.server.calls.contains(.delete)))
    }

    @Test("Cancelling during the upload deletes only after the upload has stopped")
    func cancelDuringUpload() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.base) }
        let staged = try harness.stagedPDF()
        await harness.server.suspendUploads()

        let task = Task { await harness.model.submit(staged) }
        try await harness.server.waitForUploadStart()
        harness.model.startOver()
        try await Task.sleep(for: .milliseconds(30))
        // The upload is still travelling: nothing was deleted yet.
        #expect(await harness.server.calls == [.create, .upload])

        await harness.server.resumeUploads()
        await task.value
        try await harness.server.waitForDelete()

        #expect(await harness.server.calls == [.create, .upload, .delete])
        #expect(harness.model.phase == .idle)
        #expect(!FileManager.default.fileExists(atPath: staged.fileURL.path))
    }

    @Test("Without storage access nothing is sent and the file is removed")
    func unavailable() async throws {
        let harness = makeHarness(withMedia: false)
        defer { try? FileManager.default.removeItem(at: harness.base) }
        let staged = try harness.stagedPDF()

        #expect(!harness.model.isAvailable)
        await harness.model.submit(staged)

        #expect(harness.model.phase == .failed(.capture(.captureUnavailable)))
        #expect(await harness.server.calls.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: staged.fileURL.path))
    }

    @Test("Only a real PDF is staged as one")
    func stagesOnlyPDF() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("plan-pdf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let stager = MealMediaStager(staging: MediaStagingStore(temporaryDirectory: base))
        let real = base.appendingPathComponent("plano.pdf")
        try Data("%PDF-1.7 synthetic".utf8).write(to: real)
        let disguised = base.appendingPathComponent("pagina.pdf")
        try Data("<html>not a pdf</html>".utf8).write(to: disguised)
        let other = base.appendingPathComponent("plano.docx")
        try Data("%PDF-1.7".utf8).write(to: other)

        let staged = try stager.stagePlanPDF(from: real)
        #expect(staged.kind == .planDocument)
        #expect(staged.mimeType == "application/pdf")
        #expect(staged.uploadRequest.durationMS == nil)
        #expect(throws: MealCaptureFailure.unsupportedFile) {
            try stager.stagePlanPDF(from: disguised)
        }
        #expect(throws: MealCaptureFailure.unsupportedFile) {
            try stager.stagePlanPDF(from: other)
        }
        // Nothing of a refused file stays staged.
        let leftovers = try FileManager.default.contentsOfDirectory(
            at: base.appendingPathComponent("performe-media"), includingPropertiesForKeys: nil
        )
        #expect(leftovers.count == 1)
    }
}

@Suite("Plan draft contracts")
struct PlanDraftContractTests {
    private static let draftJSON = Data("""
    {"data":{"id":"0d0d0d0d-1111-4222-8333-444455556666","domain":"training",
      "origin":"imported_pdf","status":"needs_completion","payload_version":2,
      "failure_code":null,"created_at":"2026-09-28T12:00:00.000Z",
      "updated_at":"2026-09-28T12:00:00.000Z","expires_at":"2026-10-28T12:00:00.000Z",
      "resolved_at":null,"confirmed_plan_id":null,"source_media_asset_id":null,
      "payload":{"weekly_schedule":[{"day":"Treino A","exercises":[]}]},
      "uncertain_fields":[{"pointer":"/weekly_schedule/0/focus","reason":"not_in_document"}],
      "unrecognized_segments":["Losartana 50 mg"],"replaces_current_plan":false,
      "can_confirm":false,"notices":["not_professionally_reviewed","medications_not_imported"],
      "future_field":{"x":1}},
     "meta":{"api_version":"v1","request_id":"req-draft-1"}}
    """.utf8)

    private func attempt<Payload: Hashable & Sendable>(
        _ operation: MutationOperation, _ payload: Payload, key: String
    ) throws -> MutationAttempt<Payload> {
        MutationAttempt(
            operation: operation, key: try IdempotencyKey(validating: key),
            payload: payload, createdAt: DraftFixtures.now
        )
    }

    @Test("Every operation addresses the draft by id with the right method and body")
    func requests() async throws {
        let spy = PlanTransportSpy(responseJSON: Self.draftJSON)
        let repository = MobilePlanDraftRepository(transport: spy)
        let id = DraftFixtures.draftID

        let draft = try await repository.draft(id: id)
        _ = try await repository.update(try attempt(
            .planDraftEdit,
            PlanDraftEdit(draftID: id, payloadVersion: 2, payload: .object(["notes": .null])),
            key: "draft-key-0001"
        ))
        _ = try await repository.confirm(try attempt(
            .planDraftConfirm,
            PlanDraftConfirmation(draftID: id, payloadVersion: 3),
            key: "draft-key-0002"
        ))
        _ = try await repository.discard(try attempt(
            .planDraftDiscard, PlanDraftCommand(draftID: id), key: "draft-key-0003"
        ))

        let requests = await spy.requests
        #expect(requests.map(\.method) == [.get, .patch, .post, .delete])
        #expect(requests.map(\.path) == [
            "/api/mobile/v1/plan-drafts/\(id)",
            "/api/mobile/v1/plan-drafts/\(id)",
            "/api/mobile/v1/plan-drafts/\(id)/confirm",
            "/api/mobile/v1/plan-drafts/\(id)",
        ])
        let patch = try #require(requests[1].body.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        })
        #expect(Set(patch.keys) == ["payload_version", "payload"])
        #expect(patch["payload_version"] as? Int == 2)
        let confirm = try #require(requests[2].body.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        })
        // The confirmation carries the reviewed version and nothing else:
        // never a plan, never a payload.
        #expect(confirm.count == 1)
        #expect(confirm["payload_version"] as? Int == 3)
        #expect(requests[2].idempotency
            == .required(try IdempotencyKey(validating: "draft-key-0002")))
        #expect(requests[3].body == nil)

        #expect(draft.state == .needsCompletion)
        #expect(draft.isImported)
        #expect(draft.mentionsMedications)
        #expect(draft.uncertainFields == [PlanDraftUncertainField(
            pointer: "/weekly_schedule/0/focus", reason: "not_in_document"
        )])
    }

    @Test("An import names the document and the kind of plan")
    func importRequest() async throws {
        let spy = PlanTransportSpy(responseJSON: Data("""
        {"data":{"draft_id":"0d0d0d0d-1111-4222-8333-444455556666","status":"extracting"},
         "meta":{"api_version":"v1","request_id":"req-import-1"}}
        """.utf8))
        let receipt = try await MobilePlanDraftRepository(transport: spy).startImport(
            try attempt(
                .planImport,
                PlanImportRequest(mediaAssetID: DraftFixtures.assetID, domain: .nutrition),
                key: "import-key-0001"
            )
        )

        let request = try #require(await spy.requests.first)
        #expect(request.method == .post)
        #expect(request.path == "/api/mobile/v1/plan-imports")
        let body = try #require(request.body.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: String]
        })
        #expect(body == ["media_asset_id": DraftFixtures.assetID, "domain": "nutrition"])
        #expect(receipt == PlanImportReceipt(draftID: DraftFixtures.draftID, status: "extracting"))
    }

    @Test("An id that is not an identifier never becomes a path")
    func refusesForeignID() async {
        let spy = PlanTransportSpy(responseJSON: Self.draftJSON)
        let repository = MobilePlanDraftRepository(transport: spy)
        await #expect(throws: PlanDraftFailure.invalidInput) {
            try await repository.draft(id: "../plan")
        }
        await #expect(throws: PlanDraftFailure.invalidInput) {
            try await repository.draft(id: "a/confirm")
        }
        #expect(await spy.requests.isEmpty)
    }

    @Test("Server refusals are named for the screen")
    func failureMapping() {
        func failure(_ error: MobileAPITransportError) -> PlanDraftFailure {
            PlanDraftFailure(error)
        }
        #expect(failure(.conflict(code: "draft_changed", requestID: nil)) == .draftChanged)
        #expect(failure(.conflict(code: "plan_changed_during_review", requestID: nil))
            == .planChangedDuringReview)
        #expect(failure(.conflict(code: "prescribed_plan_protected", requestID: nil))
            == .prescribedPlanProtected)
        #expect(failure(.conflict(code: "plan_draft_not_reviewable", requestID: nil))
            == .notReviewable)
        #expect(failure(.conflict(code: "plan_document_already_read", requestID: nil))
            == .documentAlreadyRead)
        #expect(failure(.conflict(code: "plan_document_already_imported", requestID: nil))
            == .documentAlreadyImported)
        #expect(failure(.validation(code: "plan_draft_incomplete", requestID: nil)) == .incomplete)
        #expect(failure(.rateLimited(code: "plan_draft_limit_reached", requestID: nil))
            == .tooManyDrafts)
        #expect(failure(.http(status: 404, code: "plan_draft_not_found", requestID: nil))
            == .notFound)
        #expect(failure(.http(status: 410, code: "plan_draft_expired", requestID: nil)) == .expired)
        #expect(failure(.http(status: 402, code: "subscription_required", requestID: nil))
            == .subscriptionRequired)
        #expect(failure(.network) == .offline)
        #expect(failure(.server(status: 500, code: "x", requestID: nil)) == .unavailable)
    }

    @Test("The Flow reply carries the proposal of its turn, and is a reply without it")
    func flowReply() throws {
        func decode(_ draft: String) throws -> FlowSendResponse {
            try JSONDecoder().decode(FlowSendResponse.self, from: Data("""
            {"conversation_id":"flow","message":{"id":"m1","conversation_id":"flow",
             "role":"assistant","content":"Pronto.","state":"completed","request_id":"r1",
             "created_at":"2026-09-28T12:00:00.000Z"}\(draft)}
            """.utf8))
        }
        #expect(try decode(#","draft":{"id":"d1","domain":"training"}"#).draft
            == FlowTurnDraft(id: "d1", domain: .training))
        #expect(try decode(#","draft":null"#).draft == nil)
        #expect(try decode("").draft == nil)
        let unknown = try decode(#","draft":{"id":"d1","domain":"sleep"}"#)
        #expect(unknown.draft == nil)
        #expect(unknown.message.content == "Pronto.")
    }

    @Test("The plan shows its weekly schedule when the server sends it")
    func weeklySchedule() throws {
        func decode(_ schedule: String) throws -> TrainingPlanSnapshot {
            try JSONDecoder().decode(TrainingPlanSnapshot.self, from: Data("""
            {"id":"p1","plan_type":"split","days_per_week":2,"equipment_summary":null,
             "generated_at":"2026-09-28T12:00:00.000Z","valid_until":null,"version":1,
             "notes":null\(schedule)}
            """.utf8))
        }
        let plan = try decode("""
        ,"weekly_schedule":[{"day":"Treino A","focus":"Inferiores","duration_min":60,
          "exercises":[{"name":"Leg press","sets":3,"reps_range":"10","rest_seconds":null},
                       {"name":"Agachamento","sets":4,"reps_range":"8-12","rest_seconds":90}]},
          {"day":"seg","focus":"full body","duration_min":30,"exercises":[]}]
        """)
        let presentation = PlanPresentation(
            snapshot: PlanSnapshot(training: plan, nutrition: []),
            language: .portugueseBrazil
        )
        #expect(presentation.trainingDays.map(\.title) == [
            "Treino A · Inferiores · 60 min", "seg · full body · 30 min",
        ])
        #expect(presentation.trainingDays[0].exercises.map(\.title) == ["Leg press", "Agachamento"])
        // A value the plan does not carry is not shown, and nothing is computed.
        #expect(presentation.trainingDays[0].exercises.map(\.value) == [
            "3 × 10", "4 × 8-12 · descanso 90 s",
        ])

        #expect(try decode("").weeklySchedule == nil)
        #expect(try decode(#","weekly_schedule":"not a list""#).weeklySchedule == nil)
        #expect(try decode(#","weekly_schedule":[{"day":7,"exercises":"x"}]"#).weeklySchedule
            == [TrainingDaySnapshot(day: nil, focus: nil, durationMin: nil, exercises: [])])
        #expect(PlanPresentation(
            snapshot: PlanSnapshot(training: try decode(""), nutrition: []),
            language: .portugueseBrazil
        ).trainingDays.isEmpty)
    }

    @Test("Plans and drafts accept a larger response than the other requests")
    func responseLimit() {
        #expect(MobileAPITransport.planResponseBodyLimit == 1_048_576)
    }
}

// MARK: - Fakes

private actor PlanDraftProviderFake: PlanDraftProviding {
    enum Call: Equatable, Sendable {
        case list, draft, update, confirm, discard, startImport
    }

    private var stored: PlanDraftSnapshot
    private var next: PlanDraftSnapshot?
    private var sequence: [PlanDraftSnapshot] = []
    private var failure: PlanDraftFailure?

    private(set) var calls: [Call] = []
    private(set) var edits: [PlanDraftEdit] = []
    private(set) var confirmations: [MutationAttempt<PlanDraftConfirmation>] = []

    init(_ stored: PlanDraftSnapshot) {
        self.stored = stored
    }

    func setNext(_ snapshot: PlanDraftSnapshot) { next = snapshot }
    func setStored(_ snapshot: PlanDraftSnapshot) { stored = snapshot }
    func setSequence(_ snapshots: [PlanDraftSnapshot]) { sequence = snapshots }
    func failNext(_ failure: PlanDraftFailure) { self.failure = failure }

    private func answer(_ call: Call) throws -> PlanDraftSnapshot {
        calls.append(call)
        if let failure {
            self.failure = nil
            throw failure
        }
        if call == .draft, !sequence.isEmpty {
            stored = sequence.removeFirst()
            return stored
        }
        if call != .draft, let next {
            stored = next
            self.next = nil
        }
        return stored
    }

    func openDrafts() throws -> [PlanDraftSummary] {
        calls.append(.list)
        return []
    }

    func draft(id: String) throws -> PlanDraftSnapshot { try answer(.draft) }

    func update(_ attempt: MutationAttempt<PlanDraftEdit>) throws -> PlanDraftSnapshot {
        edits.append(attempt.payload)
        return try answer(.update)
    }

    func confirm(
        _ attempt: MutationAttempt<PlanDraftConfirmation>
    ) throws -> PlanDraftSnapshot {
        confirmations.append(attempt)
        return try answer(.confirm)
    }

    func discard(_ attempt: MutationAttempt<PlanDraftCommand>) throws -> PlanDraftSnapshot {
        try answer(.discard)
    }

    func startImport(
        _ attempt: MutationAttempt<PlanImportRequest>
    ) throws -> PlanImportReceipt {
        calls.append(.startImport)
        return PlanImportReceipt(draftID: DraftFixtures.draftID, status: "extracting")
    }
}

private actor PlanImportServerFake: PlanDraftProviding, MealMediaProviding, StorageUploading {
    enum Call: Equatable, Sendable {
        case create, upload, complete, startImport, delete
    }

    private let assetID: String
    private let draftID: String

    init(assetID: String = DraftFixtures.assetID, draftID: String = DraftFixtures.draftID) {
        self.assetID = assetID
        self.draftID = draftID
    }

    private var importFailure: PlanDraftFailure?
    private var uploaded = false
    private var uploadFails = false
    private var uploadsSuspended = false
    private var uploadWaiters: [CheckedContinuation<Void, Never>] = []

    func failNextUpload() { uploadFails = true }
    func suspendUploads() { uploadsSuspended = true }

    func resumeUploads() {
        uploadsSuspended = false
        let waiters = uploadWaiters
        uploadWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitForUploadStart() async throws {
        for _ in 0..<500 where !calls.contains(.upload) {
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    private(set) var calls: [Call] = []
    private(set) var created: [MediaUploadRequest] = []
    private(set) var imports: [PlanImportRequest] = []
    private(set) var importKeys: [String] = []
    private(set) var attemptedImports: [MutationAttempt<PlanImportRequest>] = []

    func failNextImport(_ failure: PlanDraftFailure) { importFailure = failure }

    func waitForDelete() async throws {
        for _ in 0..<500 where !calls.contains(.delete) {
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    private func asset(_ status: String) -> MediaAssetSnapshot {
        MediaAssetSnapshot(
            id: assetID, kind: "plan_document", status: status,
            failureStage: nil, failureCode: nil
        )
    }

    func create(
        _ attempt: MutationAttempt<MediaUploadRequest>
    ) -> MediaCreateSnapshot {
        calls.append(.create)
        created.append(attempt.payload)
        return MediaCreateSnapshot(
            asset: asset(uploaded ? "uploaded" : "pending_upload"),
            upload: uploaded ? nil : MediaUploadTicket(
                signedURL: "https://project.supabase.co/storage/v1/object/upload/sign/b/u/a?token=t",
                method: "PUT",
                headers: ["Content-Type": attempt.payload.mimeType],
                expiresAt: APITimestamp(value: DraftFixtures.now.addingTimeInterval(600))
            ),
            replayed: false
        )
    }

    func upload(_ media: StagedMedia, with ticket: MediaUploadTicket) async throws {
        calls.append(.upload)
        if uploadFails {
            uploadFails = false
            throw MealCaptureFailure.offline
        }
        if uploadsSuspended {
            await withCheckedContinuation { uploadWaiters.append($0) }
        }
        guard FileManager.default.fileExists(atPath: media.fileURL.path) else {
            throw MealCaptureFailure.unreadableMedia
        }
        uploaded = true
    }

    func complete(_ attempt: MutationAttempt<MediaAssetCommand>) -> MediaAssetSnapshot {
        calls.append(.complete)
        return asset("uploaded")
    }

    func requestProcessing(
        _ attempt: MutationAttempt<MediaAssetCommand>
    ) -> MediaAssetSnapshot {
        asset("uploaded")
    }

    func asset(id: String) -> MediaAssetSnapshot { asset("uploaded") }

    func delete(_ attempt: MutationAttempt<MediaAssetCommand>) {
        calls.append(.delete)
    }

    func openDrafts() -> [PlanDraftSummary] { [] }

    func draft(id: String) throws -> PlanDraftSnapshot { throw PlanDraftFailure.notFound }

    func update(_ attempt: MutationAttempt<PlanDraftEdit>) throws -> PlanDraftSnapshot {
        throw PlanDraftFailure.notFound
    }

    func confirm(
        _ attempt: MutationAttempt<PlanDraftConfirmation>
    ) throws -> PlanDraftSnapshot {
        throw PlanDraftFailure.notFound
    }

    func discard(_ attempt: MutationAttempt<PlanDraftCommand>) throws -> PlanDraftSnapshot {
        throw PlanDraftFailure.notFound
    }

    func startImport(
        _ attempt: MutationAttempt<PlanImportRequest>
    ) throws -> PlanImportReceipt {
        calls.append(.startImport)
        imports.append(attempt.payload)
        importKeys.append(attempt.key.value)
        attemptedImports.append(attempt)
        if let importFailure {
            self.importFailure = nil
            imports.removeLast()
            throw importFailure
        }
        return PlanImportReceipt(draftID: draftID, status: "extracting")
    }
}

private actor PlanTransportSpy: MobileAPIEnvelopeExecuting {
    struct Recorded: Sendable {
        let method: HTTPMethod
        let path: String
        let body: Data?
        let idempotency: MobileAPIIdempotency
    }

    private(set) var requests: [Recorded] = []
    private let responseJSON: Data

    init(responseJSON: Data) {
        self.responseJSON = responseJSON
    }

    func executeEnvelope<Response: Codable & Sendable>(
        _ request: MobileAPIRequest<Response>
    ) async throws -> MobileResponse<Response> {
        requests.append(Recorded(
            method: request.method, path: request.path,
            body: request.body, idempotency: request.idempotency
        ))
        return try JSONDecoder().decode(MobileResponse<Response>.self, from: responseJSON)
    }
}

@Suite("Plan draft words by origin")
struct PlanDraftOriginCopyTests {
    @Test("physical Flow diet review localizes referencia and daily without changing payload")
    func physicalDietMetadataLabels() throws {
        let payload = try JSONDecoder().decode(JSONValue.self, from: Data(
            #"{"mode":"referencia","horizon":"daily","meta_kcal":3361,"meta_protein_g":186.1}"#.utf8
        ))
        let document = PlanDraftDocument(domain: .nutrition, payload: payload)
        let raw = document.planDetails(language: .portugueseBrazil)
        #expect(raw.map(\.text) == ["referencia", "daily", "3361", "186,1"])
        #expect(PlanDraftCopy.detailValue(key: "mode", text: "referencia", language: .portugueseBrazil) == "Referência")
        #expect(PlanDraftCopy.detailValue(key: "horizon", text: "daily", language: .portugueseBrazil) == "Diário")
        #expect(PlanDraftCopy.detailValue(key: "mode", text: "referencia", language: .englishUnitedStates) == "Reference")
        #expect(PlanDraftCopy.detailValue(key: "horizon", text: "daily", language: .englishUnitedStates) == "Daily")
        #expect(document.root == payload)
    }

    @Test("neighboring closed diet enums localize while unknown and unrelated values stay literal")
    func dietMetadataNeighbors() {
        #expect(PlanDraftCopy.detailValue(key: "mode", text: "rigida", language: .portugueseBrazil) == "Rígida")
        #expect(PlanDraftCopy.detailValue(key: "mode", text: "rigida", language: .englishUnitedStates) == "Strict")
        #expect(PlanDraftCopy.detailValue(key: "horizon", text: "weekly", language: .portugueseBrazil) == "Semanal")
        #expect(PlanDraftCopy.detailValue(key: "horizon", text: "weekly", language: .englishUnitedStates) == "Weekly")
        #expect(PlanDraftCopy.detailValue(key: "horizon", text: "monthly", language: .portugueseBrazil) == "monthly")
        #expect(PlanDraftCopy.detailValue(key: "mode", text: "custom", language: .portugueseBrazil) == "custom")
        #expect(PlanDraftCopy.detailValue(key: "notes", text: "daily", language: .portugueseBrazil) == "daily")
        #expect(PlanDraftCopy.detailValue(key: "plan_type", text: "full_body", language: .portugueseBrazil) == "Corpo inteiro")
    }

    private func text(_ key: String.LocalizationValue, _ language: SupportedAppLanguage) -> String {
        PlanDraftCopy.string(key, language: language)
    }

    @Test("What Flow created is a suggestion; an imported document is never called one")
    func suggestionOnlyForFlow() {
        #expect(text(PlanDraftCopy.navigationTitleKey(imported: false), .portugueseBrazil) == "Revisar sugestão")
        #expect(text(PlanDraftCopy.navigationTitleKey(imported: true), .portugueseBrazil) == "Revisar plano importado")
        #expect(text(PlanDraftCopy.navigationTitleKey(imported: nil), .portugueseBrazil) == "Revisar rascunho")
        #expect(text(PlanDraftCopy.discardKey(imported: false), .portugueseBrazil) == "Descartar sugestão")
        #expect(text(PlanDraftCopy.discardTitleKey(imported: true), .englishUnitedStates) == "Discard this imported plan?")
        #expect(text(PlanDraftCopy.discardedTitleKey(imported: false), .englishUnitedStates) == "Suggestion discarded")
        for language in SupportedAppLanguage.allCases {
            for key in [
                PlanDraftCopy.navigationTitleKey(imported: true),
                PlanDraftCopy.discardKey(imported: true),
                PlanDraftCopy.discardTitleKey(imported: true),
                PlanDraftCopy.discardedTitleKey(imported: true),
            ] {
                let value = text(key, language).lowercased()
                #expect(!value.contains("sugest") && !value.contains("suggest") && !value.contains("propost") && !value.contains("proposal"))
            }
        }
    }
}
