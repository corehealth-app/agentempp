struct BodyFlowMarkdownDocument: Equatable, Sendable {
    let blocks: [BodyFlowMarkdownBlock]
}

indirect enum BodyFlowMarkdownBlock: Equatable, Sendable {
    case paragraph(children: [BodyFlowMarkdownInline])
    case heading(level: Int, children: [BodyFlowMarkdownInline])
    case blockQuote(blocks: [BodyFlowMarkdownBlock])
    case unorderedList(items: [[BodyFlowMarkdownBlock]])
    case orderedList(items: [[BodyFlowMarkdownBlock]])
}

indirect enum BodyFlowMarkdownInline: Equatable, Sendable {
    case text(String)
    case strong(children: [BodyFlowMarkdownInline])
    case emphasis(children: [BodyFlowMarkdownInline])
    case link(destination: String, children: [BodyFlowMarkdownInline])
}

protocol BodyFlowMarkdownParsing: Sendable {
    func parse(_ source: String) throws -> BodyFlowMarkdownDocument
}
