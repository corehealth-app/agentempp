import Foundation
import Testing

@testable import BodyFlow

@Suite("History Contract")
struct HistoryContractTests {
    @Test("history keeps meal log rows separate and ordered")
    func rowsStaySeparate() throws {
        let response = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()

        #expect(response.data.meals.count == 2)
        #expect(response.data.meals.map(\.id) == [
            "fixture-meal-row-1",
            "fixture-meal-row-2",
        ])
        #expect(response.data.meals.map(\.foodName) == [
            "Arroz integral",
            "Feijao carioca",
        ])
        #expect(response.data.meals.map(\.mealType) == ["almoco", "almoco"])
        #expect(response.data.meals[0].consumedAt == response.data.meals[1].consumedAt)
    }

    @Test("history preserves nullable raw row values")
    func preservesNullableRawRows() throws {
        let response = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()
        let firstMeal = response.data.meals[0]
        let secondMeal = response.data.meals[1]
        let workout = response.data.workouts[0]

        #expect(firstMeal.quantityG == Decimal(string: "125.50"))
        #expect(firstMeal.kcal == Decimal(string: "407.25"))
        #expect(firstMeal.proteinG == Decimal(string: "31.25"))
        #expect(secondMeal.quantityG == nil)
        #expect(secondMeal.kcal == nil)
        #expect(secondMeal.proteinG == nil)
        #expect(secondMeal.carbsG == nil)
        #expect(secondMeal.fatG == nil)
        #expect(workout.workoutType == nil)
        #expect(workout.durationMin == nil)
        #expect(workout.estimatedKcal == nil)
        #expect(workout.intensity == nil)
    }

    @Test("history keeps meal and workout arrays independent")
    func keepsArraysIndependent() throws {
        let mealsOnly = try BodyFlowTestFixtures.decodeHistoryMealsOnly()
        let workoutsOnly = try BodyFlowTestFixtures.decodeHistoryWorkoutsOnly()
        let empty = try BodyFlowTestFixtures.decodeEmptyHistory()

        #expect(mealsOnly.data.meals.map(\.id) == [
            "fixture-meal-row-1",
            "fixture-meal-row-2",
        ])
        #expect(mealsOnly.data.workouts.isEmpty)
        #expect(workoutsOnly.data.meals.isEmpty)
        #expect(workoutsOnly.data.workouts.map(\.id) == ["fixture-workout-row-1"])
        #expect(empty.data.meals.isEmpty)
        #expect(empty.data.workouts.isEmpty)
    }

    @Test("history pagination metadata remains transparent")
    func preservesPaginationMetadata() throws {
        let response = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()

        #expect(response.data.pagination.limit == 2)
        #expect(
            response.data.pagination.before
                == timestamp("2026-07-28T00:00:00Z")
        )
        #expect(labels(of: response.data.pagination) == ["before", "limit"])
    }

    @Test("history exposes only the bounded first page query")
    func exposesFirstPageQuery() {
        let query = HistoryQuery.firstPage

        #expect(query.before == nil)
        #expect(query.limit == 30)
        #expect(labels(of: query) == ["before", "limit"])
        assertQueryContract(query)
    }

    @Test("history production surface keeps query construction private and bounded")
    func keepsQueryConstructionPrivateAndBounded() throws {
        let modelsSource = try historySource(named: "HistoryModels.swift")
        let providerSource = try historySource(named: "HistoryProviding.swift")
        let violations = try historySurfaceViolations(
            modelsSource: modelsSource,
            providerSource: providerSource
        )

        #expect(violations.isEmpty)
    }

    @Test("history analyzer finds the query across alternate whitespace")
    func analyzerFindsQueryAcrossAlternateWhitespace() throws {
        let source = """
            struct
                HistoryQuery
                : Equatable {
                let before: String?
                let limit: Int

                private init(before: String?, limit: Int) {
                    self.before = before
                    self.limit = limit
                }

                static let firstPage = HistoryQuery(before: nil, limit: 30)
            }
            """

        let body = try #require(typeBody(named: "HistoryQuery", in: source))

        #expect(body.contains("static let firstPage"))
    }

    @Test("history analyzer allows transparent cursor metadata")
    func analyzerAllowsTransparentCursorMetadata() throws {
        let sources = syntheticHistorySources()

        #expect(
            try historySurfaceViolations(
                modelsSource: sources.models,
                providerSource: sources.provider
            ).isEmpty
        )
    }

    @Test("history analyzer rejects alternate query construction")
    func analyzerRejectsAlternateQueryConstruction() throws {
        let sources = syntheticHistorySources()
        let alternateConstructions = [
            """
                public init(limit: Int) {
                    self.init(before: nil, limit: limit)
                }
            """,
            """
                internal init(limit: Int) {
                    self.init(before: nil, limit: limit)
                }
            """,
            """
                static func makePage() -> HistoryQuery {
                    .firstPage
                }
            """,
        ]

        for alternateConstruction in alternateConstructions {
            let models = sources.models.replacingOccurrences(
                of: "static let firstPage",
                with: alternateConstruction + "\nstatic let firstPage"
            )

            #expect(
                try !historySurfaceViolations(
                    modelsSource: models,
                    providerSource: sources.provider
                ).isEmpty
            )
        }
    }

    @Test("history analyzer rejects interpretive pagination and detail APIs")
    func analyzerRejectsInterpretiveAPIs() throws {
        let sources = syntheticHistorySources()
        let forbiddenSurfaces = [
            ("let nextBefore: String?", ""),
            ("let next_page: String?", ""),
            ("func loadMore() {}", ""),
            ("", "func detail() async throws {}"),
            ("", "protocol HistoryDetailProviding {}"),
            (#"let detailPath = "/history/detail""#, ""),
            ("struct HistoryDetailAPIRequest {}", ""),
        ]

        for (modelsAddition, providerAddition) in forbiddenSurfaces {
            #expect(
                try !historySurfaceViolations(
                    modelsSource: sources.models + "\n" + modelsAddition,
                    providerSource: sources.provider + "\n" + providerAddition
                ).isEmpty
            )
        }
    }

    @Test("history surface contains only raw meals workouts and pagination")
    func exposesOnlyMainHistoryFields() throws {
        let response = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()
        let meal = response.data.meals[0]
        let encodedMeal = try JSONEncoder().encode(meal)
        let mealObject = try #require(
            JSONSerialization.jsonObject(with: encodedMeal) as? [String: Any]
        )

        #expect(labels(of: response.data) == ["meals", "pagination", "workouts"])
        #expect(
            labels(of: meal) == [
                "carbsG",
                "consumedAt",
                "fatG",
                "foodName",
                "id",
                "kcal",
                "mealType",
                "proteinG",
                "quantityG",
            ]
        )
        #expect(
            Set(mealObject.keys) == [
                "carbs_g",
                "consumed_at",
                "fat_g",
                "food_name",
                "id",
                "kcal",
                "meal_type",
                "protein_g",
                "quantity_g",
            ]
        )
        assertResponseContract(response)
    }

    @Test("history provider performs one first page read")
    func providerPerformsSingleRead() async throws {
        let expected = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()
        let spy = HistoryProviderSpy(response: expected)
        let provider: any HistoryProviding = spy

        #expect(try await provider.history(.firstPage) == expected)
        #expect(await spy.recordedQueries() == [.firstPage])
    }

    private func timestamp(_ value: String) -> APITimestamp {
        try! JSONDecoder().decode(APITimestamp.self, from: Data("\"\(value)\"".utf8))
    }

    private func labels(of value: Any) -> Set<String> {
        Set(Mirror(reflecting: value).children.compactMap(\.label))
    }

    private func historySource(named fileName: String) throws -> String {
        let sourceFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "BodyFlow/Core/History")
            .appending(path: fileName)

        return try String(contentsOf: sourceFile, encoding: .utf8)
    }

    private func syntheticHistorySources() -> (models: String, provider: String) {
        let models = """
            struct
                HistoryQuery
                : Equatable {
                let before: String?
                let limit: Int

                private
                init(before: String?, limit: Int) {
                    self.before = before
                    self.limit = limit
                }

                static let firstPage = HistoryQuery(
                    before: nil,
                    limit: 30
                )
            }

            struct HistoryPaginationMetadata {
                let cursor: String?
            }
            """
        let provider = """
            protocol HistoryProviding {
                func
                history(_ query: HistoryQuery) async throws -> String
            }
            """

        return (models, provider)
    }

    private func historySurfaceViolations(
        modelsSource: String,
        providerSource: String
    ) throws -> [String] {
        guard let queryBody = typeBody(named: "HistoryQuery", in: modelsSource) else {
            return ["HistoryQuery declaration is missing"]
        }

        var violations: [String] = []

        func requireCount(
            _ expectedCount: Int,
            pattern: String,
            in source: String,
            violation: String
        ) throws {
            if try matchCount(pattern, in: source) != expectedCount {
                violations.append(violation)
            }
        }

        try requireCount(
            1,
            pattern: #"\binit\s*\("#,
            in: queryBody,
            violation: "HistoryQuery must have one initializer"
        )
        try requireCount(
            1,
            pattern: #"\bprivate\s+init\s*\("#,
            in: queryBody,
            violation: "HistoryQuery initializer must be private"
        )
        try requireCount(
            1,
            pattern: #"\bstatic\s+(?:let|var)\s+firstPage\b"#,
            in: queryBody,
            violation: "HistoryQuery must expose firstPage once"
        )
        try requireCount(
            0,
            pattern: #"\bstatic\s+(?:let|var)\s+(?!firstPage\b)"#,
            in: queryBody,
            violation: "HistoryQuery must not expose another stored factory"
        )
        try requireCount(
            0,
            pattern: #"\bstatic\s+func\b"#,
            in: queryBody,
            violation: "HistoryQuery must not expose a method factory"
        )
        try requireCount(
            0,
            pattern: #"\bfunc\s+"#,
            in: queryBody,
            violation: "HistoryQuery must not expose methods"
        )
        try requireCount(
            1,
            pattern: #"\bfunc\s+history\s*\("#,
            in: providerSource,
            violation: "HistoryProviding must expose history once"
        )
        try requireCount(
            1,
            pattern: #"\bfunc\s+"#,
            in: providerSource,
            violation: "HistoryProviding must expose only history"
        )

        let productionSurface = modelsSource + "\n" + providerSource
        try requireCount(
            1,
            pattern: #"\bHistoryQuery\s*\(\s*before\s*:"#,
            in: productionSurface,
            violation: "HistoryQuery must be constructed only by firstPage"
        )

        let forbiddenPatterns = [
            (
                #"\bextension\s+HistoryQuery\b"#,
                "HistoryQuery extensions may expose alternate construction"
            ),
            (
                #"(?s)\bfunc\s+\w+\s*\([^{}]*\)\s*(?:(?:async|throws|rethrows)\s+)*->\s*HistoryQuery\b"#,
                "Functions must not act as alternate HistoryQuery factories"
            ),
            (
                #"(?i)\b(?:next_?before|next_?page|load_?more)\b"#,
                "Interpretive pagination APIs are forbidden"
            ),
            (
                #"(?i)\bfunc\s+\w*detail\w*\s*\("#,
                "History detail methods are forbidden"
            ),
            (
                #"(?i)\b(?:protocol|struct|class|actor|enum)\s+\w*detail\w*(?:providing|provider)\b"#,
                "History detail providers are forbidden"
            ),
            (
                #"(?i)\"[^\"\n]*/history[^\"\n]*/detail[^\"\n]*\""#,
                "History detail paths are forbidden"
            ),
            (
                #"(?i)\b(?:\w*detail\w*APIRequest|APIRequest\w*detail\w*)\b"#,
                "History detail API requests are forbidden"
            ),
        ]

        for (pattern, violation) in forbiddenPatterns {
            if try matchCount(pattern, in: productionSurface) != 0 {
                violations.append(violation)
            }
        }

        return violations
    }

    private func typeBody(named typeName: String, in source: String) -> String? {
        let escapedTypeName = NSRegularExpression.escapedPattern(for: typeName)
        let pattern = #"\bstruct\s+"# + escapedTypeName + #"\b"#
        guard
            let expression = try? NSRegularExpression(pattern: pattern),
            let declaration = expression.firstMatch(
                in: source,
                range: NSRange(source.startIndex..<source.endIndex, in: source)
            ),
            let declarationRange = Range(declaration.range, in: source),
            let openingBrace = source[declarationRange.upperBound...].firstIndex(of: "{")
        else {
            return nil
        }

        var depth = 0
        var index = openingBrace

        while index < source.endIndex {
            switch source[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    let bodyStart = source.index(after: openingBrace)
                    return String(source[bodyStart..<index])
                }
            default:
                break
            }
            index = source.index(after: index)
        }

        return nil
    }

    private func matchCount(_ pattern: String, in source: String) throws -> Int {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.numberOfMatches(in: source, range: range)
    }

    private func assertResponseContract<T: Codable & Equatable & Sendable>(_: T) {}

    private func assertQueryContract<T: Equatable & Sendable>(_: T) {}
}

private actor HistoryProviderSpy: HistoryProviding {
    private let response: HistoryResponse
    private var queries: [HistoryQuery] = []

    init(response: HistoryResponse) {
        self.response = response
    }

    func history(_ query: HistoryQuery) async throws -> HistoryResponse {
        queries.append(query)
        return response
    }

    func recordedQueries() -> [HistoryQuery] {
        queries
    }
}
