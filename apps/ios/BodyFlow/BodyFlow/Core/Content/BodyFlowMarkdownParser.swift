import Foundation
import Markdown

struct BodyFlowMarkdownParser: BodyFlowMarkdownParsing {
    func parse(_ source: String) throws -> BodyFlowMarkdownDocument {
        let normalizedSource = MarkdownSourceNormalizer.normalize(source)
        guard (100...50_000).contains(normalizedSource.utf16.count) else {
            throw BodyFlowCapabilityError.unsupportedMarkdown
        }

        let document = Markdown.Document(
            parsing: normalizedSource,
            options: [.disableSmartOpts]
        )
        guard DocumentSourceCoverageGuard(normalizedSource: normalizedSource).validate(document) else {
            throw BodyFlowCapabilityError.unsupportedMarkdown
        }

        var converter = BodyFlowMarkdownConverter(normalizedSource: normalizedSource)
        let converted = try converter.convert(markup: document).get()
        guard case let .document(bodyFlowDocument) = converted else {
            throw BodyFlowCapabilityError.unsupportedMarkdown
        }
        return bodyFlowDocument
    }
}

enum BodyFlowMarkdownNodeClassification: Sendable {
    case knownUnsupported
    case unknown
}

enum BodyFlowMarkdownConvertedNode: Equatable, Sendable {
    case document(BodyFlowMarkdownDocument)
    case block(BodyFlowMarkdownBlock)
    case inline(BodyFlowMarkdownInline)
    case listItem([BodyFlowMarkdownBlock])
}

struct BodyFlowMarkdownConverter: MarkupVisitor {
    typealias Result = Swift.Result<BodyFlowMarkdownConvertedNode, BodyFlowCapabilityError>

    private let normalizedSource: String
    private var containerDepth = 0
    private static let maximumContainerDepth = 8

    init(normalizedSource: String) {
        self.normalizedSource = normalizedSource
    }

    mutating func convert(markup: Markup) -> Result {
        visit(markup)
    }

    mutating func convert(classification: BodyFlowMarkdownNodeClassification) -> Result {
        unsupported(classification)
    }

    mutating func defaultVisit(_ markup: Markup) -> Result {
        unsupported(.knownUnsupported)
    }

    mutating func visitDocument(_ document: Document) -> Result {
        var blocks: [BodyFlowMarkdownBlock] = []
        for child in document.children {
            switch visit(child) {
            case let .success(.block(block)):
                blocks.append(block)
            case let .failure(error):
                return .failure(error)
            default:
                return unsupported(.knownUnsupported)
            }
        }
        return .success(.document(BodyFlowMarkdownDocument(blocks: blocks)))
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> Result {
        convertInlineChildren(of: paragraph).map {
            .block(.paragraph(children: $0))
        }
    }

    mutating func visitHeading(_ heading: Heading) -> Result {
        guard heading.level == 2 || heading.level == 3 else {
            return unsupported(.knownUnsupported)
        }
        return convertInlineChildren(of: heading).map {
            .block(.heading(level: heading.level, children: $0))
        }
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> Result {
        guard enterContainer() else { return unsupported(.knownUnsupported) }
        defer { leaveContainer() }
        return convertBlockChildren(of: blockQuote).map {
            .block(.blockQuote(blocks: $0))
        }
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> Result {
        guard enterContainer() else { return unsupported(.knownUnsupported) }
        defer { leaveContainer() }
        return convertListItems(of: unorderedList).map {
            .block(.unorderedList(items: $0))
        }
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> Result {
        guard orderedList.startIndex == 1 else {
            return unsupported(.knownUnsupported)
        }
        guard enterContainer() else { return unsupported(.knownUnsupported) }
        defer { leaveContainer() }
        return convertListItems(of: orderedList).map {
            .block(.orderedList(items: $0))
        }
    }

    mutating func visitListItem(_ listItem: ListItem) -> Result {
        guard listItem.checkbox == nil else {
            return unsupported(.knownUnsupported)
        }
        return convertBlockChildren(of: listItem).map { .listItem($0) }
    }

    mutating func visitText(_ text: Text) -> Result {
        .success(.inline(.text(text.string)))
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> Result {
        .success(.inline(.text("\n")))
    }

    mutating func visitStrong(_ strong: Strong) -> Result {
        guard enterContainer() else { return unsupported(.knownUnsupported) }
        defer { leaveContainer() }
        return convertInlineChildren(of: strong).map {
            .inline(.strong(children: $0))
        }
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> Result {
        guard enterContainer() else { return unsupported(.knownUnsupported) }
        defer { leaveContainer() }
        return convertInlineChildren(of: emphasis).map {
            .inline(.emphasis(children: $0))
        }
    }

    mutating func visitLink(_ link: Link) -> Result {
        guard link.title == nil,
              let destination = link.destination,
              isApprovedHTTPSDestination(destination),
              InlineLinkSourceGuard(normalizedSource: normalizedSource).validate(
                link,
                destination: destination
              ) else {
            return unsupported(.knownUnsupported)
        }

        guard enterContainer() else { return unsupported(.knownUnsupported) }
        defer { leaveContainer() }
        return convertInlineChildren(of: link).map {
            .inline(.link(destination: destination, children: $0))
        }
    }

    private mutating func convertBlockChildren(
        of markup: Markup
    ) -> Swift.Result<[BodyFlowMarkdownBlock], BodyFlowCapabilityError> {
        var blocks: [BodyFlowMarkdownBlock] = []
        for child in markup.children {
            switch visit(child) {
            case let .success(.block(block)):
                blocks.append(block)
            case let .failure(error):
                return .failure(error)
            default:
                return .failure(.unsupportedMarkdown)
            }
        }
        return .success(blocks)
    }

    private mutating func convertInlineChildren(
        of markup: Markup
    ) -> Swift.Result<[BodyFlowMarkdownInline], BodyFlowCapabilityError> {
        var inlines: [BodyFlowMarkdownInline] = []
        for child in markup.children {
            switch visit(child) {
            case let .success(.inline(inline)):
                appendCoalescingText(inline, to: &inlines)
            case let .failure(error):
                return .failure(error)
            default:
                return .failure(.unsupportedMarkdown)
            }
        }
        return .success(inlines)
    }

    private mutating func convertListItems(
        of markup: Markup
    ) -> Swift.Result<[[BodyFlowMarkdownBlock]], BodyFlowCapabilityError> {
        var items: [[BodyFlowMarkdownBlock]] = []
        for child in markup.children {
            switch visit(child) {
            case let .success(.listItem(blocks)):
                items.append(blocks)
            case let .failure(error):
                return .failure(error)
            default:
                return .failure(.unsupportedMarkdown)
            }
        }
        return .success(items)
    }

    private mutating func enterContainer() -> Bool {
        guard containerDepth < Self.maximumContainerDepth else {
            return false
        }
        containerDepth += 1
        return true
    }

    private mutating func leaveContainer() {
        containerDepth -= 1
    }

    private func appendCoalescingText(
        _ inline: BodyFlowMarkdownInline,
        to inlines: inout [BodyFlowMarkdownInline]
    ) {
        guard case let .text(newText) = inline,
              case let .text(previousText)? = inlines.last else {
            inlines.append(inline)
            return
        }
        inlines[inlines.count - 1] = .text(previousText + newText)
    }

    private func isApprovedHTTPSDestination(_ destination: String) -> Bool {
        guard !destination.unicodeScalars.contains(where: { $0.properties.isWhitespace }),
              !destination.contains("\\"),
              let components = URLComponents(string: destination),
              components.scheme == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil else {
            return false
        }
        return true
    }

    private mutating func unsupported(
        _ classification: BodyFlowMarkdownNodeClassification
    ) -> Result {
        switch classification {
        case .knownUnsupported, .unknown:
            return .failure(.unsupportedMarkdown)
        }
    }
}
