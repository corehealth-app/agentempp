import Foundation
import Testing
@testable import BodyFlow

struct MarkdownBackendCompatibilityTests {
    // Mutation caught: accepting explicit null accepted-only fields lets a rejected wire record bypass the same field-presence contract enforced by the backend decoder.
    @Test
    func rejectsNullAcceptedOnlyFieldsOnRejectedFixtures() {
        let fixture = """
        [{
          "name": "synthetic-null-accepted-fields",
          "source": "Synthetic rejected fixture.",
          "accepted": false,
          "native_expectation": "reject_source",
          "normalized": null,
          "document": null
        }]
        """

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([Prompt14MarkdownCorpus.Fixture].self, from: Data(fixture.utf8))
        }
    }

    @Test
    func matchesTheBackendCompatibilityCorpus() throws {
        let fixtures = try Prompt14MarkdownCorpus.load()
        var parsedFixtureNames: [String] = []

        try Self.evaluate(fixtures) { fixture, input in
            parsedFixtureNames.append(fixture.name)
            return try BodyFlowMarkdownParser().parse(input)
        }

        #expect(parsedFixtureNames.count == 47)
        #expect(Set(parsedFixtureNames).count == 47)
        #expect(parsedFixtureNames.allSatisfy { name in
            !Prompt14MarkdownCorpus.backendCanonicalizationOnlyNames.contains(name)
        })
    }

    private static func evaluate(
        _ fixtures: [Prompt14MarkdownCorpus.Fixture],
        parse: (Prompt14MarkdownCorpus.Fixture, String) throws -> BodyFlowMarkdownDocument
    ) throws {
        for fixture in fixtures {
            switch fixture.nativeExpectation {
            case .parseNormalized:
                let normalized = try #require(fixture.normalized)
                let expectedDocument = try #require(fixture.document)
                #expect(try parse(fixture, normalized) == expectedDocument)
            case .rejectSource:
                #expect(throws: BodyFlowCapabilityError.unsupportedMarkdown) {
                    try parse(fixture, fixture.source)
                }
            case .backendCanonicalizationOnly:
                break
            }
        }
    }
}

private enum Prompt14MarkdownCorpus {
    static let backendCanonicalizationOnlyNames: Set<String> = [
        "normalized-body-under-100-characters",
        "normalized-body-over-50000-characters",
        "normalized-crlf-over-50000-utf16-units",
    ]

    static func load(filePath: String = #filePath) throws -> [Fixture] {
        let sourceFile = URL(fileURLWithPath: filePath)
        let corpusFile = sourceFile
            .deletingLastPathComponent()
            .appending(path: "Fixtures", directoryHint: .isDirectory)
            .appending(path: "Prompt14MarkdownCompatibility.json")
        let data = try Data(contentsOf: corpusFile)
        let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
        try validate(fixtures)
        return fixtures
    }

    struct Fixture: Decodable {
        enum NativeExpectation: String, Decodable {
            case parseNormalized = "parse_normalized"
            case rejectSource = "reject_source"
            case backendCanonicalizationOnly = "backend_canonicalization_only"
        }

        let name: String
        let source: String
        let accepted: Bool
        let nativeExpectation: NativeExpectation
        let normalized: String?
        private let documentPayload: PortableDocument?

        var document: BodyFlowMarkdownDocument? {
            documentPayload.map { BodyFlowMarkdownDocument(blocks: $0.blocks.map(\.bodyFlowBlock)) }
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case name
            case source
            case accepted
            case nativeExpectation = "native_expectation"
            case normalized
            case document
            case blocks
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let rawContainer = try decoder.container(keyedBy: AnyCodingKey.self)
            let allowedKeys = Set(CodingKeys.allCases.map(\.rawValue))
            guard rawContainer.allKeys.allSatisfy({ allowedKeys.contains($0.stringValue) }) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Fixture contains an unsupported field.")
                )
            }
            name = try container.decode(String.self, forKey: .name)
            source = try container.decode(String.self, forKey: .source)
            accepted = try container.decode(Bool.self, forKey: .accepted)
            nativeExpectation = try container.decode(NativeExpectation.self, forKey: .nativeExpectation)
            normalized = try container.decodeIfPresent(String.self, forKey: .normalized)
            documentPayload = try container.decodeIfPresent(PortableDocument.self, forKey: .document)

            if container.contains(.blocks) {
                throw DecodingError.dataCorruptedError(
                    forKey: .blocks,
                    in: container,
                    debugDescription: "Portable documents must use { blocks: [...] }, not top-level blocks."
                )
            }
            if accepted {
                guard nativeExpectation == .parseNormalized, normalized != nil, documentPayload != nil else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .nativeExpectation,
                        in: container,
                        debugDescription: "Accepted fixtures require parse_normalized, normalized, and document."
                    )
                }
            } else {
                guard nativeExpectation != .parseNormalized,
                      normalized == nil,
                      documentPayload == nil,
                      !container.contains(.normalized),
                      !container.contains(.document)
                else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .nativeExpectation,
                        in: container,
                        debugDescription: "Rejected fixtures must not provide accepted-only fields."
                    )
                }
            }
        }

        private struct PortableDocument: Decodable {
            let blocks: [PortableBlock]

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: AnyCodingKey.self)
                guard Set(container.allKeys.map(\.stringValue)) == Set(["blocks"]),
                      let blocksKey = AnyCodingKey(stringValue: "blocks")
                else {
                    throw DecodingError.dataCorrupted(
                        .init(
                            codingPath: decoder.codingPath,
                            debugDescription: "Portable documents must use exactly { blocks: [...] }."
                        )
                    )
                }
                blocks = try container.decode([PortableBlock].self, forKey: blocksKey)
            }
        }
    }

    static func validate(_ fixtures: [Fixture]) throws {
        guard fixtures.count == 50 else {
            throw CorpusError.invalid("Expected 50 fixtures, received \(fixtures.count).")
        }
        guard Set(fixtures.map(\.name)).count == fixtures.count else {
            throw CorpusError.invalid("Fixture names must be unique.")
        }
        let counts = fixtures.reduce(into: [Fixture.NativeExpectation: Int]()) { counts, fixture in
            counts[fixture.nativeExpectation, default: 0] += 1
        }
        guard counts[.parseNormalized] == 11,
              counts[.rejectSource] == 36,
              counts[.backendCanonicalizationOnly] == 3
        else {
            throw CorpusError.invalid("Expected native expectation distribution 11/36/3.")
        }
        for fixture in fixtures {
            let isCanonicalizationOnly = fixture.nativeExpectation == .backendCanonicalizationOnly
            guard isCanonicalizationOnly == backendCanonicalizationOnlyNames.contains(fixture.name) else {
                throw CorpusError.invalid("Unexpected canonicalization-only fixture: \(fixture.name).")
            }
        }
    }

    enum CorpusError: Error {
        case invalid(String)
    }

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }

    struct PortableBlock: Decodable {
        let type: String
        let level: Int?
        let ordered: Bool?
        let children: [PortableNode]?
        let items: [[PortableBlock]]?

        var bodyFlowBlock: BodyFlowMarkdownBlock {
            switch type {
            case "paragraph":
                .paragraph(children: (children ?? []).map(\.bodyFlowInline))
            case "heading":
                .heading(level: level ?? 0, children: (children ?? []).map(\.bodyFlowInline))
            case "blockquote":
                .blockQuote(blocks: (children ?? []).map(\.bodyFlowBlock))
            case "list" where ordered == true:
                .orderedList(items: (items ?? []).map { $0.map(\.bodyFlowBlock) })
            case "list":
                .unorderedList(items: (items ?? []).map { $0.map(\.bodyFlowBlock) })
            default:
                preconditionFailure("Unsupported portable block: \(type)")
            }
        }
    }

    struct PortableNode: Decodable {
        let type: String
        let value: String?
        let url: String?
        let level: Int?
        let ordered: Bool?
        let children: [PortableNode]?
        let items: [[PortableBlock]]?

        var bodyFlowInline: BodyFlowMarkdownInline {
            switch type {
            case "text":
                .text(value ?? "")
            case "strong":
                .strong(children: (children ?? []).map(\.bodyFlowInline))
            case "emphasis":
                .emphasis(children: (children ?? []).map(\.bodyFlowInline))
            case "link":
                .link(destination: url ?? "", children: (children ?? []).map(\.bodyFlowInline))
            default:
                preconditionFailure("Unsupported portable inline: \(type)")
            }
        }

        var bodyFlowBlock: BodyFlowMarkdownBlock {
            switch type {
            case "paragraph":
                .paragraph(children: (children ?? []).map(\.bodyFlowInline))
            case "heading":
                .heading(level: level ?? 0, children: (children ?? []).map(\.bodyFlowInline))
            case "blockquote":
                .blockQuote(blocks: (children ?? []).map(\.bodyFlowBlock))
            case "list" where ordered == true:
                .orderedList(items: (items ?? []).map { $0.map(\.bodyFlowBlock) })
            case "list":
                .unorderedList(items: (items ?? []).map { $0.map(\.bodyFlowBlock) })
            default:
                preconditionFailure("Unsupported portable block: \(type)")
            }
        }
    }
}
