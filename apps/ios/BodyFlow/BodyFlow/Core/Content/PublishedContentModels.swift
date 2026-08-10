typealias PublishedContentFeedResponse = MobileResponse<PublishedContentFeed>
typealias PublishedContentDetailResponse = MobileResponse<PublishedContentDetail>
typealias PublishedContentStateResponse = MobileResponse<PublishedContentState>

enum ContentSurface: String, Codable, Hashable, Sendable {
    case today
    case library
    case saved
}

enum ContentLocale: String, Codable, Hashable, Sendable {
    case ptBR = "pt-BR"
    case enUS = "en-US"
}

enum ContentCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case weightLoss = "weight_loss"
    case hypertrophy
    case nutrition
    case training
    case neuroscience
    case habitFormation = "habit_formation"
    case cardiovascularHealth = "cardiovascular_health"
    case hydration
    case supplementation
    case sleep
    case usingBodyFlow = "using_bodyflow"
}

struct ContentFeedQuery: Equatable, Hashable, Sendable {
    let surface: ContentSurface
    let category: ContentCategory?
    let limit: Int
    let cursor: String?

    init(
        surface: ContentSurface,
        category: ContentCategory?,
        limit: Int,
        cursor: String?
    ) throws {
        guard (1...50).contains(limit) else {
            throw BodyFlowCapabilityError.invalidContentContract
        }
        if let cursor,
           !(1...512).contains(cursor.utf16.count) {
            throw BodyFlowCapabilityError.invalidContentCursor
        }

        self.surface = surface
        self.category = category
        self.limit = limit
        self.cursor = cursor
    }
}

struct PublishedContentSummary: Codable, Equatable, Sendable, Identifiable {
    let publicationID: String
    let slug: String
    let locale: ContentLocale
    let title: String
    let excerpt: String
    let category: ContentCategory
    let tags: [String]
    let readingTimeMinutes: Int
    let publishAt: APITimestamp
    let featuredToday: Bool
    let version: Int
    let saved: Bool
    let completed: Bool
    let cover: PublishedContentCover?

    var id: String { publicationID }

    private enum CodingKeys: String, CodingKey {
        case publicationID = "publication_id"
        case slug
        case locale
        case title
        case excerpt
        case category
        case tags
        case readingTimeMinutes = "reading_time_minutes"
        case publishAt = "publish_at"
        case featuredToday = "featured_today"
        case version
        case saved
        case completed
        case cover
    }
}

struct PublishedContentCover: Codable, Equatable, Sendable {
    let url: String
    let expiresAt: APITimestamp

    private enum CodingKeys: String, CodingKey {
        case url
        case expiresAt = "expires_at"
    }
}

struct PublishedContentFeed: Codable, Equatable, Sendable {
    let items: [PublishedContentSummary]
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

struct PublishedContentDetail: Codable, Equatable, Sendable {
    let summary: PublishedContentSummary
    let bodyMarkdown: String

    init(summary: PublishedContentSummary, bodyMarkdown: String) {
        self.summary = summary
        self.bodyMarkdown = bodyMarkdown
    }

    init(from decoder: any Decoder) throws {
        summary = try PublishedContentSummary(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bodyMarkdown = try container.decode(String.self, forKey: .bodyMarkdown)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(summary.publicationID, forKey: .publicationID)
        try container.encode(summary.slug, forKey: .slug)
        try container.encode(summary.locale, forKey: .locale)
        try container.encode(summary.title, forKey: .title)
        try container.encode(summary.excerpt, forKey: .excerpt)
        try container.encode(summary.category, forKey: .category)
        try container.encode(summary.tags, forKey: .tags)
        try container.encode(
            summary.readingTimeMinutes,
            forKey: .readingTimeMinutes
        )
        try container.encode(summary.publishAt, forKey: .publishAt)
        try container.encode(summary.featuredToday, forKey: .featuredToday)
        try container.encode(summary.version, forKey: .version)
        try container.encode(summary.saved, forKey: .saved)
        try container.encode(summary.completed, forKey: .completed)
        try container.encode(summary.cover, forKey: .cover)
        try container.encode(bodyMarkdown, forKey: .bodyMarkdown)
    }

    private enum CodingKeys: String, CodingKey {
        case publicationID = "publication_id"
        case slug
        case locale
        case title
        case excerpt
        case category
        case tags
        case readingTimeMinutes = "reading_time_minutes"
        case publishAt = "publish_at"
        case featuredToday = "featured_today"
        case version
        case saved
        case completed
        case cover
        case bodyMarkdown = "body_markdown"
    }
}

enum ContentReadEvent: String, Codable, Hashable, Sendable {
    case impression
    case opened
    case completed
}

enum ContentOrigin: String, Codable, Hashable, Sendable {
    case today
    case library
    case push
}

struct ContentReadBody: Codable, Equatable, Hashable, Sendable {
    let event: ContentReadEvent
    let origin: ContentOrigin
    let version: Int
}

struct ContentReadCommand: Equatable, Hashable, Sendable {
    let publicationID: String
    let body: ContentReadBody
}

struct ContentSaveBody: Codable, Equatable, Hashable, Sendable {
    let saved: Bool
    let version: Int
}

struct ContentSaveCommand: Equatable, Hashable, Sendable {
    let publicationID: String
    let body: ContentSaveBody
}

struct PublishedContentState: Codable, Equatable, Sendable {
    let publicationID: String
    let version: Int
    let saved: Bool
    let completed: Bool
    let changed: Bool
    let replayed: Bool

    private enum CodingKeys: String, CodingKey {
        case publicationID = "publication_id"
        case version
        case saved
        case completed
        case changed
        case replayed
    }
}
