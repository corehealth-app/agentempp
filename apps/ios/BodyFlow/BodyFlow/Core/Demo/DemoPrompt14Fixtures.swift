#if DEBUG
import Foundation

enum DemoPrompt14Fixtures {
    static let fixedNow = Date(timeIntervalSince1970: 1_784_589_300)
    static let opaqueCursor = "opaque 🧭 / + = ? keep-byte-for-byte"

    static let firstSummary = PublishedContentSummary(
        publicationID: "10000000-0000-4000-8000-000000000001",
        slug: "nutricao-sintetica-prompt14",
        locale: .ptBR,
        title: "Nutrição Sintética Prompt 14",
        excerpt: "Amostra sintética e neutra para validar a leitura de conteúdo no aplicativo.",
        category: .nutrition,
        tags: ["sintetico", "nutricao"],
        readingTimeMinutes: 4,
        publishAt: timestamp(1_784_502_900),
        featuredToday: true,
        version: 4,
        saved: true,
        completed: true,
        cover: cover("50000000-0000-4000-8000-000000000001")
    )

    static let secondSummary = PublishedContentSummary(
        publicationID: "10000000-0000-4000-8000-000000000002",
        slug: "planejamento-sintetico-refeicoes",
        locale: .ptBR,
        title: "Planejamento Sintético de Refeições",
        excerpt: "Conteúdo fictício para exercitar uma segunda publicação de nutrição sem dados reais.",
        category: .nutrition,
        tags: ["sintetico", "planejamento"],
        readingTimeMinutes: 6,
        publishAt: timestamp(1_784_416_500),
        featuredToday: false,
        version: 2,
        saved: false,
        completed: false,
        cover: cover("50000000-0000-4000-8000-000000000002")
    )

    static let thirdSummary = PublishedContentSummary(
        publicationID: "10000000-0000-4000-8000-000000000003",
        slug: "sono-sintetico-consistente",
        locale: .ptBR,
        title: "Sono Sintético Consistente",
        excerpt: "Leitura demonstrativa sobre uma rotina de sono inteiramente fictícia e controlada.",
        category: .sleep,
        tags: ["sintetico", "sono"],
        readingTimeMinutes: 5,
        publishAt: timestamp(1_784_330_100),
        featuredToday: true,
        version: 3,
        saved: true,
        completed: false,
        cover: cover("50000000-0000-4000-8000-000000000003")
    )

    static let fourthSummary = PublishedContentSummary(
        publicationID: "10000000-0000-4000-8000-000000000004",
        slug: "treino-sintetico-seguro",
        locale: .ptBR,
        title: "Treino Sintético Seguro",
        excerpt: "Amostra visual neutra que não representa prescrição, pessoa, serviço ou treino real.",
        category: .training,
        tags: ["sintetico", "treino"],
        readingTimeMinutes: 7,
        publishAt: timestamp(1_784_243_700),
        featuredToday: false,
        version: 8,
        saved: false,
        completed: false,
        cover: cover("50000000-0000-4000-8000-000000000004")
    )

    static let fifthSummary = PublishedContentSummary(
        publicationID: "10000000-0000-4000-8000-000000000005",
        slug: "habito-sintetico-pequeno",
        locale: .ptBR,
        title: "Hábito Sintético Pequeno",
        excerpt: "Publicação inventada para conferir ordem recomendada já fornecida pelo servidor fictício.",
        category: .habitFormation,
        tags: ["sintetico", "habito"],
        readingTimeMinutes: 3,
        publishAt: timestamp(1_784_157_300),
        featuredToday: true,
        version: 1,
        saved: false,
        completed: false,
        cover: cover("50000000-0000-4000-8000-000000000005")
    )

    static let sixthSummary = PublishedContentSummary(
        publicationID: "10000000-0000-4000-8000-000000000006",
        slug: "hidratacao-sintetica-neutra",
        locale: .ptBR,
        title: "Hidratação Sintética Neutra",
        excerpt: "Linha editorial artificial para validar capa nula e paginação opaca sem inferências locais.",
        category: .hydration,
        tags: ["sintetico", "hidratacao"],
        readingTimeMinutes: 2,
        publishAt: timestamp(1_784_070_900),
        featuredToday: false,
        version: 6,
        saved: false,
        completed: false,
        cover: nil
    )

    static let todayFeed = PublishedContentFeedResponse(
        data: PublishedContentFeed(
            items: [firstSummary, thirdSummary, fifthSummary],
            nextCursor: nil
        ),
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "90000000-0000-4000-8000-000000000001"
        )
    )

    static let libraryFeed = PublishedContentFeedResponse(
        data: PublishedContentFeed(
            items: [firstSummary, secondSummary, thirdSummary, fourthSummary],
            nextCursor: opaqueCursor
        ),
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "90000000-0000-4000-8000-000000000002"
        )
    )

    static let libraryNextFeed = PublishedContentFeedResponse(
        data: PublishedContentFeed(
            items: [fifthSummary, sixthSummary],
            nextCursor: nil
        ),
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "90000000-0000-4000-8000-000000000003"
        )
    )

    static let savedFeed = PublishedContentFeedResponse(
        data: PublishedContentFeed(
            items: [firstSummary, thirdSummary],
            nextCursor: nil
        ),
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "90000000-0000-4000-8000-000000000004"
        )
    )

    static let nutritionFeed = PublishedContentFeedResponse(
        data: PublishedContentFeed(
            items: [firstSummary, secondSummary],
            nextCursor: nil
        ),
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "90000000-0000-4000-8000-000000000005"
        )
    )

    static let sleepFeed = PublishedContentFeedResponse(
        data: PublishedContentFeed(items: [thirdSummary], nextCursor: nil),
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "90000000-0000-4000-8000-000000000006"
        )
    )

    static let emptyTodayFeed = PublishedContentFeedResponse(
        data: PublishedContentFeed(items: [], nextCursor: nil),
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "90000000-0000-4000-8000-000000000011"
        )
    )

    static let emptyLibraryFeed = PublishedContentFeedResponse(
        data: PublishedContentFeed(items: [], nextCursor: nil),
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "90000000-0000-4000-8000-000000000012"
        )
    )

    static let emptyLibraryNextFeed = PublishedContentFeedResponse(
        data: PublishedContentFeed(items: [], nextCursor: nil),
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "90000000-0000-4000-8000-000000000013"
        )
    )

    static let emptySavedFeed = PublishedContentFeedResponse(
        data: PublishedContentFeed(items: [], nextCursor: nil),
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "90000000-0000-4000-8000-000000000014"
        )
    )

    static let emptyNutritionFeed = PublishedContentFeedResponse(
        data: PublishedContentFeed(items: [], nextCursor: nil),
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "90000000-0000-4000-8000-000000000015"
        )
    )

    static let emptySleepFeed = PublishedContentFeedResponse(
        data: PublishedContentFeed(items: [], nextCursor: nil),
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "90000000-0000-4000-8000-000000000016"
        )
    )

    static let validDetail = PublishedContentDetail(
        summary: firstSummary,
        bodyMarkdown: """
        ## CONTEÚDO SINTÉTICO PROMPT 14

        Este texto é uma amostra inteiramente sintética, criada apenas para validar a leitura determinística no aplicativo BodyFlow.

        * Nenhuma pessoa real é descrita.
        * Nenhuma recomendação clínica é oferecida.
        * Nenhum dado sai deste cenário local.

        **Resultado esperado:** uma apresentação visivelmente fictícia e segura para testes.
        """ + "\n"
    )

    static let invalidMarkdownDetail = PublishedContentDetail(
        summary: firstSummary,
        bodyMarkdown: """
        # CONTEÚDO SINTÉTICO INVÁLIDO

        Este corpo sintético usa um título de nível um, deliberadamente fora do subconjunto Markdown aceito pelo aplicativo, e nunca pode ser publicado na interface.
        """
    )

    static let validDetailResponse = PublishedContentDetailResponse(
        data: validDetail,
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "91000000-0000-4000-8000-000000000001"
        )
    )

    static let invalidMarkdownDetailResponse = PublishedContentDetailResponse(
        data: invalidMarkdownDetail,
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "91000000-0000-4000-8000-000000000002"
        )
    )

    static let coachMetadata = MobileResponseMetadata(
        apiVersion: "1",
        requestID: "93000000-0000-4000-8000-000000000001"
    )

    static let balancedCoachResponse = coachResponse(
        selected: nil,
        effective: .balanced,
        mascot: .inactive,
        changedAt: 1_784_502_900,
        requestID: "93000000-0000-4000-8000-000000000001"
    )

    static let focusCoachResponse = coachResponse(
        selected: .focus,
        effective: .focus,
        mascot: .reactivating,
        changedAt: 1_784_511_540,
        requestID: "93000000-0000-4000-8000-000000000002"
    )

    static let impulseCoachResponse = coachResponse(
        selected: .impulse,
        effective: .impulse,
        mascot: .active,
        changedAt: 1_784_520_180,
        requestID: "93000000-0000-4000-8000-000000000003"
    )

    static let zenCoachResponse = coachResponse(
        selected: .zen,
        effective: .zen,
        mascot: .evolving,
        changedAt: 1_784_528_820,
        requestID: "93000000-0000-4000-8000-000000000004"
    )

    static let neglectedCoachResponse = coachResponse(
        selected: .focus,
        effective: .focus,
        mascot: .neglected,
        changedAt: 1_784_537_460,
        requestID: "93000000-0000-4000-8000-000000000005"
    )

    static let unknownCoachResponse = coachResponse(
        selected: nil,
        effective: .balanced,
        mascot: .unknown("future-synthetic"),
        changedAt: 1_784_546_100,
        requestID: "93000000-0000-4000-8000-000000000006"
    )

    static let coachResponses = [
        balancedCoachResponse,
        focusCoachResponse,
        impulseCoachResponse,
        zenCoachResponse,
        neglectedCoachResponse,
        unknownCoachResponse,
    ]

    static let completeProgress = ProgressResponse(
        data: ProgressSnapshot(
            xpTotal: 2_450,
            level: 7,
            currentStreak: 12,
            longestStreak: 21,
            blocksCompleted: 2,
            deficitBlock: 735,
            currentWeight: Decimal(string: "78.4"),
            currentBodyFatPercent: Decimal(string: "18.6"),
            badgesEarned: [
                "70000000-0000-4000-8000-000000000001",
                "70000000-0000-4000-8000-000000000002",
            ],
            lastActiveDate: "2026-07-20",
            nextReevaluation: "2026-07-29",
            updatedAt: timestamp(1_784_589_300)
        ),
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "92000000-0000-4000-8000-000000000001"
        )
    )

    static let minimumProgress = ProgressResponse(
        data: ProgressSnapshot(
            xpTotal: 0,
            level: 1,
            currentStreak: 0,
            longestStreak: 0,
            blocksCompleted: 0,
            deficitBlock: 0,
            currentWeight: nil,
            currentBodyFatPercent: nil,
            badgesEarned: [],
            lastActiveDate: nil,
            nextReevaluation: nil,
            updatedAt: timestamp(1_784_589_300)
        ),
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "92000000-0000-4000-8000-000000000002"
        )
    )

    static let emptyProgress = ProgressResponse(
        data: nil,
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "92000000-0000-4000-8000-000000000003"
        )
    )

    static let streakZeroProgress = ProgressResponse(
        data: ProgressSnapshot(
            xpTotal: 980,
            level: 4,
            currentStreak: 0,
            longestStreak: 9,
            blocksCompleted: 1,
            deficitBlock: 210,
            currentWeight: Decimal(string: "81.2"),
            currentBodyFatPercent: nil,
            badgesEarned: ["70000000-0000-4000-8000-000000000001"],
            lastActiveDate: "2026-07-12",
            nextReevaluation: "2026-08-01",
            updatedAt: timestamp(1_784_589_300)
        ),
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "92000000-0000-4000-8000-000000000004"
        )
    )

    static let validFeedResponses = [
        todayFeed,
        libraryFeed,
        libraryNextFeed,
        savedFeed,
        nutritionFeed,
        sleepFeed,
        emptyTodayFeed,
        emptyLibraryFeed,
        emptyLibraryNextFeed,
        emptySavedFeed,
        emptyNutritionFeed,
        emptySleepFeed,
    ]

    static let validDetailResponses = [validDetailResponse]

    static func todayQuery() throws -> ContentFeedQuery {
        try ContentFeedQuery(
            surface: .today,
            category: nil,
            limit: 3,
            cursor: nil
        )
    }

    static func libraryQuery() throws -> ContentFeedQuery {
        try ContentFeedQuery(
            surface: .library,
            category: nil,
            limit: 20,
            cursor: nil
        )
    }

    static func libraryNextQuery() throws -> ContentFeedQuery {
        try ContentFeedQuery(
            surface: .library,
            category: nil,
            limit: 20,
            cursor: opaqueCursor
        )
    }

    static func savedQuery() throws -> ContentFeedQuery {
        try ContentFeedQuery(
            surface: .saved,
            category: nil,
            limit: 20,
            cursor: nil
        )
    }

    static func nutritionQuery() throws -> ContentFeedQuery {
        try ContentFeedQuery(
            surface: .library,
            category: .nutrition,
            limit: 20,
            cursor: nil
        )
    }

    static func sleepQuery() throws -> ContentFeedQuery {
        try ContentFeedQuery(
            surface: .library,
            category: .sleep,
            limit: 20,
            cursor: nil
        )
    }

    static func feed(
        for query: ContentFeedQuery,
        empty: Bool
    ) throws -> PublishedContentFeedResponse {
        switch query {
        case try todayQuery():
            empty ? emptyTodayFeed : todayFeed
        case try libraryQuery():
            empty ? emptyLibraryFeed : libraryFeed
        case try libraryNextQuery():
            empty ? emptyLibraryNextFeed : libraryNextFeed
        case try savedQuery():
            empty ? emptySavedFeed : savedFeed
        case try nutritionQuery():
            empty ? emptyNutritionFeed : nutritionFeed
        case try sleepQuery():
            empty ? emptySleepFeed : sleepFeed
        default:
            throw BodyFlowCapabilityError.invalidInput
        }
    }

    static let neutralPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFElEQVR42mNkYGD4z8DAwMDAxAADAAEGAQF7vZ1OAAAAAElFTkSuQmCC"
    ) ?? Data()

    static let invalidCoverBytes = Data("SYNTHETIC-NOT-AN-IMAGE".utf8)

    private static let coachOptions = [
        CoachPersonaOption(
            code: .focus,
            name: "Foco",
            description: "Orientação sintética, direta e organizada."
        ),
        CoachPersonaOption(
            code: .impulse,
            name: "Impulso",
            description: "Incentivo sintético, energético e breve."
        ),
        CoachPersonaOption(
            code: .zen,
            name: "Zen",
            description: "Acompanhamento sintético, calmo e acolhedor."
        ),
    ]

    private static func coachResponse(
        selected: SelectableCoachPersona?,
        effective: EffectiveCoachPersona,
        mascot: MascotWireState,
        changedAt: TimeInterval,
        requestID: String
    ) -> CoachExperienceResponse {
        CoachExperienceResponse(
            data: CoachExperienceSnapshot(
                selected: selected,
                effective: effective,
                options: coachOptions,
                mascot: MascotSnapshot(
                    state: mascot,
                    changedAt: timestamp(changedAt)
                ),
                contractVersion: CoachExperienceV1PresentationContract.version
            ),
            meta: MobileResponseMetadata(apiVersion: "1", requestID: requestID)
        )
    }

    private static func cover(_ capability: String) -> PublishedContentCover {
        PublishedContentCover(
            url: "/api/mobile/v1/content/covers/\(capability)",
            expiresAt: timestamp(1_816_123_500)
        )
    }

    private static func timestamp(_ seconds: TimeInterval) -> APITimestamp {
        APITimestamp(value: Date(timeIntervalSince1970: seconds))
    }
}
#endif
