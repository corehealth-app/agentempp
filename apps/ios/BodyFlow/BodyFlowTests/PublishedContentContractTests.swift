import Foundation
import Testing

@testable import BodyFlow

@Suite("Published Content Contracts")
struct PublishedContentContractTests {
    @Test("feed decodes every summary field, nullable cover, and opaque cursor")
    func decodesFeedContract() throws {
        let response = try JSONDecoder().decode(
            PublishedContentFeedResponse.self,
            from: Prompt14ContractJSON.feed
        )

        #expect(response.meta.apiVersion == "v1")
        #expect(response.meta.requestID == "mobile-content-feed-0001")
        #expect(response.data.nextCursor == Prompt14ContractJSON.opaqueCursor)
        #expect(response.data.items.count == 2)

        let item = try #require(response.data.items.first)
        #expect(item.id == Prompt14ContractJSON.publicationID)
        #expect(item.publicationID == Prompt14ContractJSON.publicationID)
        #expect(item.slug == "rotina-de-sono")
        #expect(item.locale == .ptBR)
        #expect(item.title == "Rotina de sono")
        #expect(item.excerpt == "Um exemplo sintético de resumo educativo para o aplicativo.")
        #expect(item.category == .sleep)
        #expect(item.tags == ["sono", "rotina"])
        #expect(item.readingTimeMinutes == 3)
        #expect(item.publishAt.value == Prompt14ContractJSON.publishDate)
        #expect(item.featuredToday == false)
        #expect(item.version == 4)
        #expect(item.saved == true)
        #expect(item.completed == false)
        #expect(item.cover?.url == "/api/mobile/v1/content/covers/opaque-capability_01")
        #expect(item.cover?.expiresAt.value == Prompt14ContractJSON.coverExpiryDate)
        #expect(response.data.items[1].cover == nil)
        try PublishedContentContractValidator.validate(response.data)

        let encoded = try JSONEncoder().encode(response)
        let roundTrip = try JSONDecoder().decode(PublishedContentFeedResponse.self, from: encoded)
        #expect(roundTrip.data.nextCursor == Prompt14ContractJSON.opaqueCursor)
        #expect(try encodedKeys(item) == Prompt14ContractJSON.summaryKeys)
    }

    @Test("all eleven categories decode with their exact wire values")
    func decodesAllCategories() throws {
        let categories = try JSONDecoder().decode(
            [ContentCategory].self,
            from: Prompt14ContractJSON.categories
        )

        #expect(categories == [
            .weightLoss,
            .hypertrophy,
            .nutrition,
            .training,
            .neuroscience,
            .habitFormation,
            .cardiovascularHealth,
            .hydration,
            .supplementation,
            .sleep,
            .usingBodyFlow,
        ])
        #expect(ContentCategory.allCases.map(\.rawValue) == [
            "weight_loss",
            "hypertrophy",
            "nutrition",
            "training",
            "neuroscience",
            "habit_formation",
            "cardiovascular_health",
            "hydration",
            "supplementation",
            "sleep",
            "using_bodyflow",
        ])
    }

    @Test("all three surfaces preserve exact query identity")
    func preservesAllSurfaces() throws {
        let surfaces = try JSONDecoder().decode(
            [ContentSurface].self,
            from: Prompt14ContractJSON.surfaces
        )
        #expect(surfaces == [.today, .library, .saved])

        for surface in surfaces {
            let query = try ContentFeedQuery(
                surface: surface,
                category: nil,
                limit: 20,
                cursor: nil
            )
            #expect(query.surface == surface)
            #expect(query.category == nil)
            #expect(query.limit == 20)
            #expect(query.cursor == nil)
        }
    }

    @Test("detail is flat on the wire and adds only body_markdown")
    func decodesFlatDetail() throws {
        let response = try JSONDecoder().decode(
            PublishedContentDetailResponse.self,
            from: Prompt14ContractJSON.detail
        )
        #expect(response.data.summary.publicationID == Prompt14ContractJSON.publicationID)
        #expect(response.data.summary.version == 4)
        #expect(response.data.summary.cover == nil)
        #expect(response.data.bodyMarkdown.hasPrefix("## Exemplo"))
        try PublishedContentContractValidator.validate(response.data)

        #expect(try encodedKeys(response.data) == Prompt14ContractJSON.detailKeys)
    }

    @Test("read bodies expose every event and origin without route identity")
    func encodesReadBodyContract() throws {
        let events = try JSONDecoder().decode(
            [ContentReadEvent].self,
            from: Prompt14ContractJSON.readEvents
        )
        let origins = try JSONDecoder().decode(
            [ContentOrigin].self,
            from: Prompt14ContractJSON.origins
        )

        #expect(events == [.impression, .opened, .completed])
        #expect(origins == [.today, .library, .push])

        for event in events {
            for origin in origins {
                let command = ContentReadCommand(
                    publicationID: Prompt14ContractJSON.publicationID,
                    body: ContentReadBody(event: event, origin: origin, version: 4)
                )
                #expect(try encodedKeys(command.body) == ["event", "origin", "version"])
            }
        }
    }

    @Test("route identity is absent from strict mutation bodies")
    func encodesStrictBodies() throws {
        let read = ContentReadCommand(
            publicationID: Prompt14ContractJSON.publicationID,
            body: ContentReadBody(event: .opened, origin: .library, version: 4)
        )
        let save = ContentSaveCommand(
            publicationID: Prompt14ContractJSON.publicationID,
            body: ContentSaveBody(saved: true, version: 4)
        )
        #expect(try encodedKeys(read.body) == ["event", "origin", "version"])
        #expect(try encodedKeys(save.body) == ["saved", "version"])
    }

    @Test("state response decodes every consolidated field")
    func decodesConsolidatedState() throws {
        let response = try JSONDecoder().decode(
            PublishedContentStateResponse.self,
            from: Prompt14ContractJSON.state
        )

        #expect(response.data.publicationID == Prompt14ContractJSON.publicationID)
        #expect(response.data.version == 4)
        #expect(response.data.saved == true)
        #expect(response.data.completed == false)
        #expect(response.data.changed == true)
        #expect(response.data.replayed == false)
        #expect(try encodedKeys(response.data) == [
            "changed",
            "completed",
            "publication_id",
            "replayed",
            "saved",
            "version",
        ])
    }

    @Test("query accepts exact limit and cursor boundaries without repairing cursor")
    func acceptsQueryBoundaries() throws {
        let exactCursor = "  opaque/+== cursor_🙂  "
        let minimum = try ContentFeedQuery(
            surface: .library,
            category: .sleep,
            limit: 1,
            cursor: "x"
        )
        let maximum = try ContentFeedQuery(
            surface: .saved,
            category: nil,
            limit: 50,
            cursor: String(repeating: "a", count: 512)
        )
        let opaque = try ContentFeedQuery(
            surface: .today,
            category: .nutrition,
            limit: 3,
            cursor: exactCursor
        )

        #expect(minimum.limit == 1)
        #expect(minimum.cursor == "x")
        #expect(maximum.limit == 50)
        #expect(maximum.cursor?.utf16.count == 512)
        #expect(opaque.cursor == exactCursor)
    }

    @Test("query rejects limits outside one through fifty")
    func rejectsInvalidQueryLimits() {
        for limit in [0, 51] {
            #expect(throws: BodyFlowCapabilityError.invalidContentContract) {
                try ContentFeedQuery(
                    surface: .library,
                    category: nil,
                    limit: limit,
                    cursor: nil
                )
            }
        }
    }

    @Test("query rejects empty and 513 UTF-16-unit cursors")
    func rejectsInvalidCursorBounds() {
        for cursor in ["", String(repeating: "a", count: 513)] {
            #expect(throws: BodyFlowCapabilityError.invalidContentCursor) {
                try ContentFeedQuery(
                    surface: .library,
                    category: nil,
                    limit: 20,
                    cursor: cursor
                )
            }
        }
    }

    @Test("cursor bounds match JavaScript UTF-16 length for surrogate pairs")
    func cursorUsesUTF16Bounds() throws {
        let accepted = String(repeating: "a", count: 510) + "🙂"
        let rejected = String(repeating: "a", count: 511) + "🙂"
        #expect(accepted.count == 511)
        #expect(accepted.utf16.count == 512)
        #expect(rejected.count == 512)
        #expect(rejected.utf16.count == 513)

        let query = try ContentFeedQuery(
            surface: .library,
            category: nil,
            limit: 20,
            cursor: accepted
        )
        #expect(query.cursor == accepted)
        #expect(throws: BodyFlowCapabilityError.invalidContentCursor) {
            try ContentFeedQuery(
                surface: .library,
                category: nil,
                limit: 20,
                cursor: rejected
            )
        }
    }

    @Test("validator rejects malformed publication UUID and slug")
    func rejectsMalformedIdentity() {
        for publicationID in ["not-a-uuid", "00000000000040008000000000000101"] {
            #expect(throws: BodyFlowCapabilityError.invalidContentContract) {
                try PublishedContentContractValidator.validate(
                    summary(publicationID: publicationID)
                )
            }
        }

        for slug in ["ab", "Bad-slug", "bad--slug", "bad_slug", String(repeating: "a", count: 121)] {
            #expect(throws: BodyFlowCapabilityError.invalidContentContract) {
                try PublishedContentContractValidator.validate(summary(slug: slug))
            }
        }
    }

    @Test("unsupported locale is rejected while decoding the literal summary")
    func rejectsMalformedLocale() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                PublishedContentSummary.self,
                from: Prompt14ContractJSON.invalidLocaleSummary
            )
        }
    }

    @Test("validator rejects malformed title and excerpt bounds")
    func rejectsMalformedTextBounds() {
        for title in ["aa", String(repeating: "a", count: 121)] {
            #expect(throws: BodyFlowCapabilityError.invalidContentContract) {
                try PublishedContentContractValidator.validate(summary(title: title))
            }
        }
        for excerpt in [String(repeating: "a", count: 19), String(repeating: "a", count: 281)] {
            #expect(throws: BodyFlowCapabilityError.invalidContentContract) {
                try PublishedContentContractValidator.validate(summary(excerpt: excerpt))
            }
        }
    }

    @Test("title and excerpt bounds use UTF-16 units for surrogate pairs")
    func summaryTextUsesUTF16Bounds() throws {
        let minimumTitle = String(repeating: "🙂", count: 2)
        let maximumTitle = String(repeating: "🙂", count: 60)
        let invalidTitle = maximumTitle + "🙂"
        let minimumExcerpt = String(repeating: "🙂", count: 10)
        let maximumExcerpt = String(repeating: "🙂", count: 140)
        let invalidExcerpt = maximumExcerpt + "🙂"

        #expect(minimumTitle.count == 2)
        #expect(minimumTitle.utf16.count == 4)
        #expect(maximumTitle.utf16.count == 120)
        #expect(invalidTitle.count == 61)
        #expect(invalidTitle.utf16.count == 122)
        #expect(minimumExcerpt.count == 10)
        #expect(minimumExcerpt.utf16.count == 20)
        #expect(maximumExcerpt.utf16.count == 280)
        #expect(invalidExcerpt.count == 141)
        #expect(invalidExcerpt.utf16.count == 282)

        try PublishedContentContractValidator.validate(summary(title: minimumTitle))
        try PublishedContentContractValidator.validate(summary(title: maximumTitle))
        try PublishedContentContractValidator.validate(summary(excerpt: minimumExcerpt))
        try PublishedContentContractValidator.validate(summary(excerpt: maximumExcerpt))
        #expect(throws: BodyFlowCapabilityError.invalidContentContract) {
            try PublishedContentContractValidator.validate(summary(title: invalidTitle))
        }
        #expect(throws: BodyFlowCapabilityError.invalidContentContract) {
            try PublishedContentContractValidator.validate(summary(excerpt: invalidExcerpt))
        }
    }

    @Test("validator rejects duplicate, malformed, oversized, and excessive tags")
    func rejectsMalformedTags() {
        let invalidTags = [
            ["sono", "sono"],
            ["Sono"],
            ["bad--tag"],
            ["bad_tag"],
            [String(repeating: "a", count: 41)],
            Array(repeating: "tag", count: 21),
        ]

        for tags in invalidTags {
            #expect(throws: BodyFlowCapabilityError.invalidContentContract) {
                try PublishedContentContractValidator.validate(summary(tags: tags))
            }
        }
    }

    @Test("validator enforces reading-time and version integer bounds")
    func rejectsInvalidIntegerBounds() throws {
        for readingTime in [0, 501] {
            #expect(throws: BodyFlowCapabilityError.invalidContentContract) {
                try PublishedContentContractValidator.validate(
                    summary(readingTimeMinutes: readingTime)
                )
            }
        }
        for version in [0, 2_147_483_648] {
            #expect(throws: BodyFlowCapabilityError.invalidContentContract) {
                try PublishedContentContractValidator.validate(summary(version: version))
            }
        }

        try PublishedContentContractValidator.validate(summary(readingTimeMinutes: 1, version: 1))
        try PublishedContentContractValidator.validate(
            summary(readingTimeMinutes: 500, version: 2_147_483_647)
        )
    }

    @Test("body bounds match JavaScript UTF-16 length for surrogate pairs")
    func bodyUsesUTF16Bounds() throws {
        let minimum = String(repeating: "🙂", count: 50)
        let maximum = String(repeating: "🙂", count: 25_000)
        let rejected = maximum + "🙂"
        #expect(minimum.count == 50)
        #expect(minimum.utf16.count == 100)
        #expect(maximum.count == 25_000)
        #expect(maximum.utf16.count == 50_000)
        #expect(rejected.count == 25_001)
        #expect(rejected.utf16.count == 50_002)

        try PublishedContentContractValidator.validate(
            PublishedContentDetail(summary: summary(), bodyMarkdown: minimum)
        )
        try PublishedContentContractValidator.validate(
            PublishedContentDetail(summary: summary(), bodyMarkdown: maximum)
        )
        #expect(throws: BodyFlowCapabilityError.invalidContentContract) {
            try PublishedContentContractValidator.validate(
                PublishedContentDetail(summary: summary(), bodyMarkdown: rejected)
            )
        }
    }
}

private func summary(
    publicationID: String = Prompt14ContractJSON.publicationID,
    slug: String = "rotina-de-sono",
    title: String = "Rotina de sono",
    excerpt: String = "Um exemplo sintético de resumo educativo para o aplicativo.",
    tags: [String] = ["sono", "rotina"],
    readingTimeMinutes: Int = 3,
    version: Int = 4
) -> PublishedContentSummary {
    PublishedContentSummary(
        publicationID: publicationID,
        slug: slug,
        locale: .ptBR,
        title: title,
        excerpt: excerpt,
        category: .sleep,
        tags: tags,
        readingTimeMinutes: readingTimeMinutes,
        publishAt: APITimestamp(value: Prompt14ContractJSON.publishDate),
        featuredToday: false,
        version: version,
        saved: true,
        completed: false,
        cover: nil
    )
}

private func encodedKeys<Value: Encodable>(_ value: Value) throws -> Set<String> {
    let data = try JSONEncoder().encode(value)
    guard let object = try JSONSerialization.jsonObject(with: data)
        as? [String: Any] else {
        return []
    }
    return Set(object.keys)
}

private enum Prompt14ContractJSON {
    static let publicationID = "00000000-0000-4000-8000-000000000101"
    static let opaqueCursor = "opaque/+==:keep.exact_🙂"
    static let publishDate = Date(timeIntervalSince1970: 1_774_353_600)
    static let coverExpiryDate = Date(timeIntervalSince1970: 1_774_353_900)
    static let summaryKeys: Set<String> = [
        "category",
        "completed",
        "cover",
        "excerpt",
        "featured_today",
        "locale",
        "publication_id",
        "publish_at",
        "reading_time_minutes",
        "saved",
        "slug",
        "tags",
        "title",
        "version",
    ]
    static let detailKeys = summaryKeys.union(["body_markdown"])

    static let categories = Data(
        #"["weight_loss","hypertrophy","nutrition","training","neuroscience","habit_formation","cardiovascular_health","hydration","supplementation","sleep","using_bodyflow"]"#.utf8
    )

    static let surfaces = Data(#"["today","library","saved"]"#.utf8)
    static let readEvents = Data(#"["impression","opened","completed"]"#.utf8)
    static let origins = Data(#"["today","library","push"]"#.utf8)

    static let feed = Data(
        #"""
        {
          "data": {
            "items": [
              {
                "publication_id": "00000000-0000-4000-8000-000000000101",
                "slug": "rotina-de-sono",
                "locale": "pt-BR",
                "title": "Rotina de sono",
                "excerpt": "Um exemplo sintético de resumo educativo para o aplicativo.",
                "category": "sleep",
                "tags": ["sono", "rotina"],
                "reading_time_minutes": 3,
                "publish_at": "2026-03-24T12:00:00Z",
                "featured_today": false,
                "version": 4,
                "saved": true,
                "completed": false,
                "cover": {
                  "url": "/api/mobile/v1/content/covers/opaque-capability_01",
                  "expires_at": "2026-03-24T12:05:00Z"
                }
              },
              {
                "publication_id": "00000000-0000-4000-8000-000000000102",
                "slug": "hidratacao-consistente",
                "locale": "en-US",
                "title": "Consistent hydration",
                "excerpt": "A synthetic educational summary long enough for the mobile contract.",
                "category": "hydration",
                "tags": [],
                "reading_time_minutes": 1,
                "publish_at": "2026-03-24T11:00:00Z",
                "featured_today": true,
                "version": 1,
                "saved": false,
                "completed": true,
                "cover": null
              }
            ],
            "next_cursor": "opaque/+==:keep.exact_🙂"
          },
          "meta": {
            "api_version": "v1",
            "request_id": "mobile-content-feed-0001"
          }
        }
        """#.utf8
    )

    static let detail = Data(
        #"""
        {
          "data": {
            "publication_id": "00000000-0000-4000-8000-000000000101",
            "slug": "rotina-de-sono",
            "locale": "pt-BR",
            "title": "Rotina de sono",
            "excerpt": "Um exemplo sintético de resumo educativo para o aplicativo.",
            "category": "sleep",
            "tags": ["sono", "rotina"],
            "reading_time_minutes": 3,
            "publish_at": "2026-03-24T12:00:00Z",
            "featured_today": false,
            "version": 4,
            "saved": true,
            "completed": false,
            "cover": null,
            "body_markdown": "## Exemplo\n\nEste conteúdo sintético existe apenas para documentar o formato do contrato móvel, sem representar orientação real ou dado de paciente."
          },
          "meta": {
            "api_version": "v1",
            "request_id": "mobile-content-detail-0001"
          }
        }
        """#.utf8
    )

    static let state = Data(
        #"""
        {
          "data": {
            "publication_id": "00000000-0000-4000-8000-000000000101",
            "version": 4,
            "saved": true,
            "completed": false,
            "changed": true,
            "replayed": false
          },
          "meta": {
            "api_version": "v1",
            "request_id": "mobile-content-state-0001"
          }
        }
        """#.utf8
    )

    static let invalidLocaleSummary = Data(
        #"""
        {
          "publication_id": "00000000-0000-4000-8000-000000000101",
          "slug": "rotina-de-sono",
          "locale": "pt_BR",
          "title": "Rotina de sono",
          "excerpt": "Um exemplo sintético de resumo educativo para o aplicativo.",
          "category": "sleep",
          "tags": ["sono", "rotina"],
          "reading_time_minutes": 3,
          "publish_at": "2026-03-24T12:00:00Z",
          "featured_today": false,
          "version": 4,
          "saved": true,
          "completed": false,
          "cover": null
        }
        """#.utf8
    )
}
