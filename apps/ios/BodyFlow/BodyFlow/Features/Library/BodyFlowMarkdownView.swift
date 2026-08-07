import Foundation
import SwiftUI

enum BodyFlowMarkdownLinkPolicy {
    static let accessibilityAnnouncement = "Link externo"

    static func validatedHTTPSURL(_ destination: String) -> URL? {
        guard !destination.unicodeScalars.contains(where: {
            $0.properties.isWhitespace
        }),
        !destination.contains("\\"),
        let components = URLComponents(string: destination),
        components.scheme == "https",
        let host = components.host,
        !host.isEmpty,
        components.user == nil,
        components.password == nil,
        let url = components.url,
        url.absoluteURL == url else {
            return nil
        }
        return url
    }
}

enum BodyFlowMarkdownOpenURLPresentation: Equatable, Sendable {
    case systemAction(URL)
    case discarded

    @MainActor
    var openURLActionResult: OpenURLAction.Result {
        switch self {
        case let .systemAction(url):
            return .systemAction(url)
        case .discarded:
            return .discarded
        }
    }
}

struct BodyFlowMarkdownOpenURLHandler: Sendable {
    func callAsFunction(
        _ requestedURL: URL
    ) -> BodyFlowMarkdownOpenURLPresentation {
        guard let approvedURL = BodyFlowMarkdownLinkPolicy.validatedHTTPSURL(
            requestedURL.absoluteString
        ) else {
            return .discarded
        }
        return .systemAction(approvedURL)
    }

    @MainActor
    var openURLAction: OpenURLAction {
        OpenURLAction { requestedURL in
            self(requestedURL).openURLActionResult
        }
    }
}

enum BodyFlowMarkdownAccessibilitySemanticRole: Equatable, Sendable {
    case list
    case listItem
}

struct BodyFlowMarkdownListAccessibilityItem: Equatable, Identifiable, Sendable {
    let position: Int
    let count: Int
    let blocks: [BodyFlowMarkdownBlock]
    let semanticRole: BodyFlowMarkdownAccessibilitySemanticRole

    var id: Int { position }
}

struct BodyFlowMarkdownListAccessibilityPresentation: Equatable, Sendable {
    let items: [BodyFlowMarkdownListAccessibilityItem]
    let ordered: Bool
    let semanticRole: BodyFlowMarkdownAccessibilitySemanticRole

    var itemCount: Int { items.count }
}

enum BodyFlowMarkdownListAccessibilityPolicy {
    static func presentation(
        items: [[BodyFlowMarkdownBlock]],
        ordered: Bool
    ) -> BodyFlowMarkdownListAccessibilityPresentation {
        let count = items.count
        return BodyFlowMarkdownListAccessibilityPresentation(
            items: items.enumerated().map { index, blocks in
                BodyFlowMarkdownListAccessibilityItem(
                    position: index + 1,
                    count: count,
                    blocks: blocks,
                    semanticRole: .listItem
                )
            },
            ordered: ordered,
            semanticRole: .list
        )
    }
}

@MainActor
struct BodyFlowMarkdownView: View {
    let document: BodyFlowMarkdownDocument

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            ForEach(Array(document.blocks.enumerated()), id: \.offset) {
                _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func blockView(_ block: BodyFlowMarkdownBlock) -> AnyView {
        switch block {
        case let .paragraph(children):
            AnyView(
                MarkdownInlineText(children: children)
                    .font(BodyFlowTypography.body)
                    .foregroundStyle(BodyFlowColor.primaryText)
            )
        case let .heading(level, children):
            AnyView(
                MarkdownInlineText(children: children)
                    .font(level == 2
                        ? BodyFlowTypography.title
                        : BodyFlowTypography.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .accessibilityAddTraits(.isHeader)
            )
        case let .blockQuote(blocks):
            AnyView(
                HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(BodyFlowColor.accent)
                        .frame(width: 4)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) {
                            _, nestedBlock in
                            blockView(nestedBlock)
                        }
                    }
                }
            )
        case let .unorderedList(items):
            AnyView(listView(items: items, ordered: false))
        case let .orderedList(items):
            AnyView(listView(items: items, ordered: true))
        }
    }

    private func listView(
        items: [[BodyFlowMarkdownBlock]],
        ordered: Bool
    ) -> some View {
        let accessibility =
            BodyFlowMarkdownListAccessibilityPolicy.presentation(
                items: items,
                ordered: ordered
            )

        return VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, blocks in
                HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .font(BodyFlowTypography.body)
                        .foregroundStyle(BodyFlowColor.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) {
                            _, block in
                            blockView(block)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(
                    ordered ? "Item \(index + 1)" : "Item da lista"
                )
            }
        }
        .accessibilityRepresentation {
            List(accessibility.items) { item in
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    ForEach(
                        Array(item.blocks.enumerated()),
                        id: \.offset
                    ) { _, block in
                        blockView(block)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityValue(
                    "Item \(item.position) de \(item.count)"
                )
            }
            .accessibilityLabel(ordered ? "Lista ordenada" : "Lista")
        }
    }
}

@MainActor
private struct MarkdownInlineText: View {
    @Environment(\.openURL) private var openURL

    let children: [BodyFlowMarkdownInline]

    @ViewBuilder
    var body: some View {
        let presentation = BodyFlowMarkdownInlinePresentation.make(children)
        let openURLHandler = BodyFlowMarkdownOpenURLHandler()

        if let link = BodyFlowMarkdownStandaloneLink.make(children) {
            Text(presentation.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(link.label), "
                        + BodyFlowMarkdownLinkPolicy
                            .accessibilityAnnouncement
                )
                .accessibilityIdentifier(link.label)
                .accessibilityAddTraits(.isLink)
                .accessibilityAction {
                    openValidated(link.destination)
                }
                .environment(\.openURL, openURLHandler.openURLAction)
        } else {
            Text(presentation.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHint(presentation.accessibilityHint)
                .environment(\.openURL, openURLHandler.openURLAction)
        }
    }

    private func openValidated(_ destination: URL) {
        guard let approvedURL =
                BodyFlowMarkdownLinkPolicy.validatedHTTPSURL(
                    destination.absoluteString
                ) else {
            return
        }
        openURL(approvedURL)
    }
}

private struct BodyFlowMarkdownStandaloneLink: Equatable, Sendable {
    let label: String
    let destination: URL

    static func make(
        _ inlines: [BodyFlowMarkdownInline]
    ) -> Self? {
        guard inlines.count == 1,
              case let .link(destination, children) = inlines[0],
              let url = BodyFlowMarkdownLinkPolicy.validatedHTTPSURL(
                  destination
              ) else {
            return nil
        }

        let label = plainText(children)
        guard !label.isEmpty else { return nil }
        return Self(label: label, destination: url)
    }

    private static func plainText(
        _ inlines: [BodyFlowMarkdownInline]
    ) -> String {
        inlines.map(plainText).joined()
    }

    private static func plainText(
        _ inline: BodyFlowMarkdownInline
    ) -> String {
        switch inline {
        case let .text(value):
            value
        case let .strong(children),
             let .emphasis(children),
             let .link(_, children):
            plainText(children)
        }
    }
}

struct BodyFlowMarkdownInlinePresentation: Equatable, Sendable {
    private struct Fragment {
        var text = AttributedString()
        var hasExternalLink = false
    }

    let text: AttributedString
    let accessibilityHint: String

    static func make(
        _ inlines: [BodyFlowMarkdownInline]
    ) -> Self {
        let fragment = makeFragment(inlines)
        return Self(
            text: fragment.text,
            accessibilityHint: fragment.hasExternalLink
                ? BodyFlowMarkdownLinkPolicy.accessibilityAnnouncement
                : ""
        )
    }

    private static func makeFragment(
        _ inlines: [BodyFlowMarkdownInline],
        intent: InlinePresentationIntent = []
    ) -> Fragment {
        var result = Fragment()
        for inline in inlines {
            let fragment = makeFragment(inline, intent: intent)
            result.text += fragment.text
            result.hasExternalLink = result.hasExternalLink
                || fragment.hasExternalLink
        }
        return result
    }

    private static func makeFragment(
        _ inline: BodyFlowMarkdownInline,
        intent: InlinePresentationIntent
    ) -> Fragment {
        switch inline {
        case let .text(value):
            var attributed = AttributedString(value)
            if !intent.isEmpty {
                attributed.inlinePresentationIntent = intent
            }
            return Fragment(text: attributed, hasExternalLink: false)
        case let .strong(children):
            return makeFragment(
                children,
                intent: intent.union(.stronglyEmphasized)
            )
        case let .emphasis(children):
            return makeFragment(
                children,
                intent: intent.union(.emphasized)
            )
        case let .link(destination, children):
            guard let url = BodyFlowMarkdownLinkPolicy.validatedHTTPSURL(
                destination
            ) else {
                return Fragment()
            }
            var result = makeFragment(children, intent: intent)
            result.text.link = url
            result.hasExternalLink = true
            return result
        }
    }
}
