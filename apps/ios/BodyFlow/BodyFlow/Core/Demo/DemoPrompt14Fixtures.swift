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

    static let incompleteSummary = PublishedContentSummary(
        publicationID: "10000000-0000-4000-8000-000000000007",
        slug: "conteudo-sintetico-incompleto",
        locale: .ptBR,
        title: "Conteúdo Sintético Incompleto",
        excerpt: "Publicação fictícia e autorizada para validar conclusão explícita sem derivação local.",
        category: .usingBodyFlow,
        tags: ["sintetico", "incompleto"],
        readingTimeMinutes: 3,
        publishAt: timestamp(1_783_984_500),
        featuredToday: false,
        version: 5,
        saved: false,
        completed: false,
        cover: cover("50000000-0000-4000-8000-000000000007")
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

    static let incompleteLibraryFeed = PublishedContentFeedResponse(
        data: PublishedContentFeed(
            items: [
                firstSummary,
                secondSummary,
                thirdSummary,
                fourthSummary,
                incompleteSummary,
            ],
            nextCursor: opaqueCursor
        ),
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "90000000-0000-4000-8000-000000000017"
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

    static let incompleteDetail = PublishedContentDetail(
        summary: incompleteSummary,
        bodyMarkdown: """
        ## CONTEÚDO SINTÉTICO INCOMPLETO

        Esta publicação local começa explicitamente incompleta para validar uma ação real de conclusão no fluxo determinístico.

        * O identificador e a versão permanecem imutáveis.
        * Salvar e concluir usam o ledger real da sessão.
        * Nenhum progresso é derivado no dispositivo.
        """ + "\n"
    )

    static let externalLinkDetail = PublishedContentDetail(
        summary: firstSummary,
        bodyMarkdown: """
        ## CONTEÚDO SINTÉTICO COM REFERÊNCIA

        Este corpo continua sendo uma publicação canônica e inclui somente um destino externo explícito para validar apresentação segura.

        [Referência externa](\("https" + "://example.invalid/prompt14/reference"))

        O destino pertence ao artigo e não concede origem confiável para capas ou qualquer transporte paralelo.
        """ + "\n"
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

    static let incompleteDetailResponse = PublishedContentDetailResponse(
        data: incompleteDetail,
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "91000000-0000-4000-8000-000000000003"
        )
    )

    static let externalLinkDetailResponse = PublishedContentDetailResponse(
        data: externalLinkDetail,
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "91000000-0000-4000-8000-000000000004"
        )
    )

    static let expiredCoverDetailResponse = coverDetailResponse(
        summary: replacingCover(
            in: firstSummary,
            with: PublishedContentCover(
                url: "/api/mobile/v1/content/covers/50000000-0000-4000-8000-000000000008",
                expiresAt: APITimestamp(value: fixedNow)
            )
        ),
        requestID: "91000000-0000-4000-8000-000000000005"
    )

    static let oversizedCoverDetailResponse = coverDetailResponse(
        summary: replacingCover(
            in: firstSummary,
            with: cover("50000000-0000-4000-8000-000000000009")
        ),
        requestID: "91000000-0000-4000-8000-000000000006"
    )

    static let mimeMismatchCoverDetailResponse = coverDetailResponse(
        summary: replacingCover(
            in: firstSummary,
            with: cover("50000000-0000-4000-8000-000000000010")
        ),
        requestID: "91000000-0000-4000-8000-000000000007"
    )

    static let abusiveDimensionsCoverDetailResponse = coverDetailResponse(
        summary: replacingCover(
            in: firstSummary,
            with: cover("50000000-0000-4000-8000-000000000011")
        ),
        requestID: "91000000-0000-4000-8000-000000000008"
    )

    static let externalCoverDetailResponse = coverDetailResponse(
        summary: replacingCover(
            in: firstSummary,
            with: PublishedContentCover(
                url: "https" + "://external.invalid/prompt14/private-cover",
                expiresAt: timestamp(1_816_123_500)
            )
        ),
        requestID: "91000000-0000-4000-8000-000000000009"
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

    static let focusActiveCoachResponse = coachResponse(
        selected: .focus,
        effective: .focus,
        mascot: .active,
        changedAt: 1_784_554_740,
        requestID: "93000000-0000-4000-8000-000000000007"
    )

    static let zenNeglectedCoachResponse = coachResponse(
        selected: .zen,
        effective: .zen,
        mascot: .neglected,
        changedAt: 1_784_563_380,
        requestID: "93000000-0000-4000-8000-000000000008"
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

    static let duplicateBadgeCompleteProgress = ProgressResponse(
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
                "70000000-0000-4000-8000-000000000001",
            ],
            lastActiveDate: "2026-07-20",
            nextReevaluation: "2026-07-29",
            updatedAt: timestamp(1_784_589_300)
        ),
        meta: MobileResponseMetadata(
            apiVersion: "1",
            requestID: "92000000-0000-4000-8000-000000000005"
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
        incompleteLibraryFeed,
    ]

    static let validDetailResponses = [
        validDetailResponse,
        incompleteDetailResponse,
        externalLinkDetailResponse,
        expiredCoverDetailResponse,
        oversizedCoverDetailResponse,
        mimeMismatchCoverDetailResponse,
        abusiveDimensionsCoverDetailResponse,
        externalCoverDetailResponse,
    ]

    static let contentStateMetadata = MobileResponseMetadata(
        apiVersion: "1",
        requestID: "94000000-0000-4000-8000-000000000001"
    )

    static let authoredSummaries = [
        firstSummary,
        secondSummary,
        thirdSummary,
        fourthSummary,
        fifthSummary,
        sixthSummary,
    ]

    static func summary(publicationID: String) -> PublishedContentSummary? {
        authoredSummaries.first { $0.publicationID == publicationID }
    }

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

    static func savedSleepQuery() throws -> ContentFeedQuery {
        try ContentFeedQuery(
            surface: .saved,
            category: .sleep,
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
        case try savedSleepQuery():
            empty ? emptySleepFeed : sleepFeed
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

    static let abusiveDimensionPNG = pngHeader(width: 16_385, height: 1)

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

    private static func coverDetailResponse(
        summary: PublishedContentSummary,
        requestID: String
    ) -> PublishedContentDetailResponse {
        PublishedContentDetailResponse(
            data: PublishedContentDetail(
                summary: summary,
                bodyMarkdown: validDetail.bodyMarkdown
            ),
            meta: MobileResponseMetadata(apiVersion: "1", requestID: requestID)
        )
    }

    private static func replacingCover(
        in summary: PublishedContentSummary,
        with cover: PublishedContentCover
    ) -> PublishedContentSummary {
        PublishedContentSummary(
            publicationID: summary.publicationID,
            slug: summary.slug,
            locale: summary.locale,
            title: summary.title,
            excerpt: summary.excerpt,
            category: summary.category,
            tags: summary.tags,
            readingTimeMinutes: summary.readingTimeMinutes,
            publishAt: summary.publishAt,
            featuredToday: summary.featuredToday,
            version: summary.version,
            saved: summary.saved,
            completed: summary.completed,
            cover: cover
        )
    }

    private static func pngHeader(width: UInt32, height: UInt32) -> Data {
        var body = Data([137, 80, 78, 71, 13, 10, 26, 10])
        var header = Data()
        header.append(contentsOf: bigEndianBytes(width))
        header.append(contentsOf: bigEndianBytes(height))
        header.append(contentsOf: [8, 2, 0, 0, 0])
        body.append(pngChunk(named: "IHDR", payload: header))
        body.append(pngChunk(named: "IEND", payload: Data()))
        return body
    }

    private static func pngChunk(named name: String, payload: Data) -> Data {
        var chunk = Data(bigEndianBytes(UInt32(payload.count)))
        let type = Data(name.utf8)
        chunk.append(type)
        chunk.append(payload)
        chunk.append(contentsOf: bigEndianBytes(crc32(type + payload)))
        return chunk
    }

    private static func bigEndianBytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value),
        ]
    }

    private static func crc32(_ bytes: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = crc & 1 == 0
                    ? crc >> 1
                    : (crc >> 1) ^ 0xEDB8_8320
            }
        }
        return crc ^ UInt32.max
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

actor DemoPrompt14MutationGate {
    private struct StartWaiter {
        let minimumCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var startedCount = 0
    private var nextCompletionID: UInt64 = 0
    private var completions: [
        UInt64: CheckedContinuation<Void, any Error>
    ] = [:]
    private var nextStartWaiterID: UInt64 = 0
    private var startWaiters: [UInt64: StartWaiter] = [:]

    func wait() async throws {
        nextCompletionID &+= 1
        let completionID = nextCompletionID
        startedCount += 1
        resumeSatisfiedStartWaiters()

        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    completions[completionID] = continuation
                }
            }
        }, onCancel: {
            Task {
                await self.cancel(completionID: completionID)
            }
        })
    }

    func waitUntilStarted(count: Int = 1) async {
        precondition(count > 0)
        guard startedCount < count else { return }
        nextStartWaiterID &+= 1
        let startWaiterID = nextStartWaiterID
        await withCheckedContinuation { continuation in
            startWaiters[startWaiterID] = StartWaiter(
                minimumCount: count,
                continuation: continuation
            )
        }
    }

    func finish() {
        let continuations = Array(completions.values)
        completions.removeAll(keepingCapacity: false)
        for continuation in continuations {
            continuation.resume()
        }
        resumeAllStartWaiters()
    }

    func cancelAll() {
        let continuations = Array(completions.values)
        completions.removeAll(keepingCapacity: false)
        for continuation in continuations {
            continuation.resume(throwing: CancellationError())
        }
        resumeAllStartWaiters()
    }

    private func cancel(completionID: UInt64) {
        completions.removeValue(forKey: completionID)?
            .resume(throwing: CancellationError())
    }

    private func resumeSatisfiedStartWaiters() {
        let waiterIDs = startWaiters.compactMap { waiterID, waiter in
            startedCount >= waiter.minimumCount ? waiterID : nil
        }
        for waiterID in waiterIDs {
            startWaiters.removeValue(forKey: waiterID)?.continuation.resume()
        }
    }

    private func resumeAllStartWaiters() {
        let continuations = startWaiters.values.map(\.continuation)
        startWaiters.removeAll(keepingCapacity: false)
        for continuation in continuations {
            continuation.resume()
        }
    }
}
#endif
