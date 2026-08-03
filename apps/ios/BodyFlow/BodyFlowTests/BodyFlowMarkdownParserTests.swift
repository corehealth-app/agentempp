import Markdown
import Testing

@testable import BodyFlow

@Suite("Fail-closed BodyFlow Markdown parser")
struct BodyFlowMarkdownParserTests {
    // Mutation caught: removing an approved block/inline conversion, smart-options disabling, CRLF normalization, soft-break preservation, text coalescing, or HTTPS-link conversion changes the exact BodyFlow AST.
    @Test("approved nodes become an exact BodyFlow-owned AST")
    func parsesApprovedSubset() throws {
        let source = padded(
            "## Título\r\n\r\nLinha um\r\nlinha dois com **força**, *ênfase* e [fonte](https://bodyflow.app/path?q=1#parte). Aspas \"retas\" --.\r\n\r\n### Fim"
        )

        let document = try BodyFlowMarkdownParser().parse(source)

        #expect(document == BodyFlowMarkdownDocument(blocks: [
            .heading(level: 2, children: [.text("Título")]),
            .paragraph(children: [
                .text("Linha um\nlinha dois com "),
                .strong(children: [.text("força")]),
                .text(", "),
                .emphasis(children: [.text("ênfase")]),
                .text(" e "),
                .link(
                    destination: "https://bodyflow.app/path?q=1#parte",
                    children: [.text("fonte")]
                ),
                .text(". Aspas \"retas\" --."),
            ]),
            .heading(level: 3, children: [.text("Fim")]),
        ]))
    }

    // Mutation caught: dropping block quotes, unordered lists, ordered lists that start at one, or their item block structure changes the exact BodyFlow AST.
    @Test("quotes and both approved list kinds preserve block structure")
    func parsesQuotesAndLists() throws {
        let source = padded(
            "> Citação\n\n- Primeiro\n- Segundo\n\n1. Um\n2. Dois"
        )

        let document = try BodyFlowMarkdownParser().parse(source)

        #expect(document == BodyFlowMarkdownDocument(blocks: [
            .blockQuote(blocks: [
                .paragraph(children: [.text("Citação")]),
            ]),
            .unorderedList(items: [
                [.paragraph(children: [.text("Primeiro")])],
                [.paragraph(children: [.text("Segundo")])],
            ]),
            .orderedList(items: [
                [.paragraph(children: [.text("Um")])],
                [.paragraph(children: [.text("Dois")])],
            ]),
        ]))
    }

    // Mutation caught: rejecting the published maximum nesting depth of eight prevents an otherwise approved document from parsing.
    @Test("depth eight remains inside the published subset")
    func acceptsDepthEight() throws {
        let source = padded(String(repeating: "> ", count: 8) + "Profundo")

        let document = try BodyFlowMarkdownParser().parse(source)

        #expect(document.blocks == [
            .blockQuote(blocks: [
                .blockQuote(blocks: [
                    .blockQuote(blocks: [
                        .blockQuote(blocks: [
                            .blockQuote(blocks: [
                                .blockQuote(blocks: [
                                    .blockQuote(blocks: [
                                        .blockQuote(blocks: [
                                            .paragraph(children: [.text("Profundo")]),
                                        ]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
        ])
    }

    // Mutation caught: counting grapheme clusters or raw CRLF/CR input instead of normalized UTF-16 units rejects valid boundary documents.
    @Test("100 and 50,000 normalized UTF-16 units are accepted with surrogate pairs")
    func acceptsNormalizedUTF16Bounds() throws {
        let minimum = String(repeating: "a", count: 98) + "😀"
        let maximum = String(repeating: "b", count: 49_998) + "😀"
        let normalizedMaximum = String(repeating: "c", count: 49_995) + "\r\nd\r😀"

        #expect(minimum.utf16.count == 100)
        #expect(maximum.utf16.count == 50_000)
        #expect(normalizedMaximum.utf16.count == 50_001)
        #expect(try BodyFlowMarkdownParser().parse(minimum).blocks == [
            .paragraph(children: [.text(minimum)]),
        ])
        #expect(try BodyFlowMarkdownParser().parse(maximum).blocks == [
            .paragraph(children: [.text(maximum)]),
        ])
        #expect(try BodyFlowMarkdownParser().parse(normalizedMaximum).blocks == [
            .paragraph(children: [.text(String(repeating: "c", count: 49_995) + "\nd\n😀")]),
        ])
    }

    // Mutation caught: a global pipe, at-sign, or backslash ban rejects canonical text that swift-markdown represents only as Text.
    @Test("canonical text spellings preserve their exact BodyFlow AST", arguments: CanonicalTextSyntax.allCases)
    func parsesCanonicalTextSpellings(_ syntax: CanonicalTextSyntax) throws {
        let document = try BodyFlowMarkdownParser().parse(padded(syntax.source))

        #expect(document == BodyFlowMarkdownDocument(blocks: [
            .paragraph(children: [.text(syntax.expectedText)]),
        ]))
    }

    // Mutation caught: routing real Directive or Doxygen nodes through text conversion bypasses the converter's single fail-closed default route.
    @Test("actual Directive and Doxygen probe nodes use the default reject route")
    func actualDirectiveAndDoxygenNodesUseDefaultRejectRoute() {
        var directiveConverter = BodyFlowMarkdownConverter(normalizedSource: "directive")
        var doxygenConverter = BodyFlowMarkdownConverter(normalizedSource: "doxygen")

        #expect(throws: BodyFlowCapabilityError.unsupportedMarkdown) {
            try directiveConverter.convert(
                markup: BlockDirective(
                    name: "Callout",
                    children: Paragraph(Text("Conteúdo"))
                )
            ).get()
        }
        #expect(throws: BodyFlowCapabilityError.unsupportedMarkdown) {
            try doxygenConverter.convert(
                markup: DoxygenDiscussion(children: Paragraph(Text("Conteúdo")))
            ).get()
        }
    }

    // Mutation caught: broadening the explicit node, source-form, URL, list-start, or depth allowlist lets a forbidden Markdown construct render.
    @Test("every forbidden syntax fails closed", arguments: RejectedSyntax.allCases)
    func rejectsForbiddenSyntax(_ syntax: RejectedSyntax) {
        #expect(throws: BodyFlowCapabilityError.unsupportedMarkdown) {
            try BodyFlowMarkdownParser().parse(padded(syntax.source))
        }
    }

    // Mutation caught: an off-by-one bound or Character/Unicode-scalar counting admits 99 or 50,001 normalized UTF-16 units, including surrogate-pair cases.
    @Test("out-of-range UTF-16 sizes fail closed", arguments: RejectedBound.allCases)
    func rejectsUTF16Bounds(_ bound: RejectedBound) {
        #expect(bound.source.utf16.count == bound.expectedUTF16Count)
        #expect(throws: BodyFlowCapabilityError.unsupportedMarkdown) {
            try BodyFlowMarkdownParser().parse(bound.source)
        }
    }

    // Mutation caught: rendering or descending through a newly encountered current Markup node bypasses the visitor's default reject route.
    @Test("a current unsupported Markup node uses the default reject route")
    func currentUnsupportedMarkupUsesDefaultRejectRoute() {
        var converter = BodyFlowMarkdownConverter(normalizedSource: "future")

        #expect(throws: BodyFlowCapabilityError.unsupportedMarkdown) {
            try converter.convert(markup: CustomInline("future")).get()
        }
    }

    // Mutation caught: treating a future converter classification as renderable bypasses the same default reject route used by known unsupported nodes.
    @Test("a test-only unknown classification uses the default reject route")
    func unknownClassificationUsesDefaultRejectRoute() {
        var converter = BodyFlowMarkdownConverter(normalizedSource: "future")

        #expect(throws: BodyFlowCapabilityError.unsupportedMarkdown) {
            try converter.convert(classification: .unknown).get()
        }
    }

    // Mutation caught: adding mutable or non-Sendable state to the public AST/parser contract breaks Swift 6 transfer safety.
    @Test("the package-independent parser contract and AST are Sendable")
    func parserContractIsSendable() throws {
        let parser: any BodyFlowMarkdownParsing = BodyFlowMarkdownParser()
        let document = try parser.parse(padded("Texto seguro"))

        requireSendable(BodyFlowMarkdownParser.self)
        requireSendable(BodyFlowMarkdownDocument.self)
        requireSendable(BodyFlowMarkdownBlock.self)
        requireSendable(BodyFlowMarkdownInline.self)
        requireSendableValue(parser)
        requireSendableValue(document)
    }
}

enum RejectedSyntax: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case blockHTML
    case inlineHTML
    case headingOne
    case headingFour
    case headingFive
    case headingSix
    case fencedCode
    case indentedCode
    case inlineCode
    case image
    case hardBreak
    case thematicBreak
    case table
    case strikethrough
    case taskListCheckbox
    case titledLink
    case referenceLink
    case collapsedReferenceLink
    case shortcutReferenceLink
    case nestedRemovedReferenceDefinitions
    case httpURL
    case dataURL
    case javascriptURL
    case protocolRelativeURL
    case relativeURL
    case httpsWithoutHost
    case orderedStartOtherThanOne
    case depthNine
    case symbolLink
    case malformedSource

    var testDescription: String { rawValue }

    var source: String {
        switch self {
        case .blockHTML:
            "<section>não renderizar</section>"
        case .inlineHTML:
            "Texto <em>não renderizar</em>."
        case .headingOne:
            "# Um"
        case .headingFour:
            "#### Quatro"
        case .headingFive:
            "##### Cinco"
        case .headingSix:
            "###### Seis"
        case .fencedCode:
            "```swift\nlet forbidden = true\n```"
        case .indentedCode:
            "    código indentado"
        case .inlineCode:
            "Use `código` aqui."
        case .image:
            "![texto](https://bodyflow.app/image.png)"
        case .hardBreak:
            "Linha um  \nlinha dois"
        case .thematicBreak:
            "---"
        case .table:
            "| A | B |\n| - | - |\n| 1 | 2 |"
        case .strikethrough:
            "Texto ~~removido~~."
        case .taskListCheckbox:
            "- [x] Concluído"
        case .titledLink:
            "[fonte](https://bodyflow.app \"Título\")"
        case .referenceLink:
            "[fonte][bodyflow]\n\n[bodyflow]: https://bodyflow.app"
        case .collapsedReferenceLink:
            "[fonte][]\n\n[fonte]: https://bodyflow.app"
        case .shortcutReferenceLink:
            "[fonte]\n\n[fonte]: https://bodyflow.app"
        case .nestedRemovedReferenceDefinitions:
            "> [fonte][bodyflow]\n>\n> [bodyflow]: https://bodyflow.app"
        case .httpURL:
            "[fonte](http://bodyflow.app)"
        case .dataURL:
            "[fonte](data:text/plain,BodyFlow)"
        case .javascriptURL:
            "[fonte](javascript:alert(1))"
        case .protocolRelativeURL:
            "[fonte](//bodyflow.app/path)"
        case .relativeURL:
            "[fonte](/conteudo/local)"
        case .httpsWithoutHost:
            "[fonte](https:///conteudo/local)"
        case .orderedStartOtherThanOne:
            "2. Dois\n3. Três"
        case .depthNine:
            String(repeating: "> ", count: 9) + "Profundo demais"
        case .symbolLink:
            "``BodyFlow.symbol``"
        case .malformedSource:
            "Texto com **ênfase sem fechamento"
        }
    }
}

enum CanonicalTextSyntax: CaseIterable, Sendable, CustomTestStringConvertible {
    case ordinaryPipe
    case escapedPipe
    case blockDirectiveSpelling
    case inlineDirectiveSpelling
    case doxygenCommandSpelling
    case doxygenSourceSpelling
    case backendEscapes

    var testDescription: String {
        switch self {
        case .ordinaryPipe: "ordinary pipe"
        case .escapedPipe: "escaped pipe"
        case .blockDirectiveSpelling: "block directive spelling"
        case .inlineDirectiveSpelling: "inline directive spelling"
        case .doxygenCommandSpelling: "Doxygen command spelling"
        case .doxygenSourceSpelling: "Doxygen source spelling"
        case .backendEscapes: "safe backend backslash escapes"
        }
    }

    var source: String {
        switch self {
        case .ordinaryPipe:
            "Conteúdo | seguro"
        case .escapedPipe:
            "Conteúdo \\| seguro"
        case .blockDirectiveSpelling:
            "@Callout { Conteúdo }"
        case .inlineDirectiveSpelling:
            "Texto @Image(source: \"cover.png\")"
        case .doxygenCommandSpelling:
            "@discussion Conteúdo Doxygen"
        case .doxygenSourceSpelling:
            #"\discussion Conteúdo Doxygen"#
        case .backendEscapes:
            "Escapes: \\! \\@ \\[ \\] \\_ \\* \\~ \\^ \\| \\\\ e \\q"
        }
    }

    var expectedText: String {
        switch self {
        case .ordinaryPipe:
            "Conteúdo | seguro"
        case .escapedPipe:
            "Conteúdo | seguro"
        case .blockDirectiveSpelling:
            "@Callout { Conteúdo }"
        case .inlineDirectiveSpelling:
            "Texto @Image(source: \"cover.png\")"
        case .doxygenCommandSpelling:
            "@discussion Conteúdo Doxygen"
        case .doxygenSourceSpelling:
            #"\discussion Conteúdo Doxygen"#
        case .backendEscapes:
            "Escapes: ! @ [ ] _ * ~ ^ | \\ e \\q"
        }
    }
}

enum RejectedBound: CaseIterable, Sendable, CustomTestStringConvertible {
    case minimumWithSurrogatePair
    case maximumWithSurrogatePair

    var testDescription: String {
        switch self {
        case .minimumWithSurrogatePair: "99 UTF-16 units"
        case .maximumWithSurrogatePair: "50,001 UTF-16 units"
        }
    }

    var expectedUTF16Count: Int {
        switch self {
        case .minimumWithSurrogatePair: 99
        case .maximumWithSurrogatePair: 50_001
        }
    }

    var source: String {
        switch self {
        case .minimumWithSurrogatePair:
            String(repeating: "a", count: 97) + "😀"
        case .maximumWithSurrogatePair:
            String(repeating: "b", count: 49_999) + "😀"
        }
    }
}

private func padded(_ source: String) -> String {
    let missingUnits = max(0, 100 - source.utf16.count)
    return source + String(repeating: " ", count: missingUnits)
}

private func requireSendable<T: Sendable>(_: T.Type) {}

private func requireSendableValue<T: Sendable>(_: T) {}
