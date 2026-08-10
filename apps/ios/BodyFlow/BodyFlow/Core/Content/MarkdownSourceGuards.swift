import Foundation
import Markdown

enum MarkdownSourceNormalizer {
    static func normalize(_ source: String) -> String {
        var normalized = ""
        normalized.reserveCapacity(source.utf8.count)

        let scalars = source.unicodeScalars
        var index = scalars.startIndex
        while index < scalars.endIndex {
            if scalars[index] == "\r" {
                let next = scalars.index(after: index)
                if next < scalars.endIndex, scalars[next] == "\n" {
                    index = scalars.index(after: next)
                } else {
                    index = next
                }
                normalized.unicodeScalars.append("\n")
            } else {
                normalized.unicodeScalars.append(scalars[index])
                index = scalars.index(after: index)
            }
        }

        return normalized
    }
}

struct MarkdownSourceMap {
    let source: String
    let bytes: [UInt8]
    private let lineStarts: [Int]

    init(_ source: String) {
        self.source = source
        bytes = Array(source.utf8)

        var starts = [0]
        for (offset, byte) in bytes.enumerated() where byte == 0x0A {
            starts.append(offset + 1)
        }
        lineStarts = starts
    }

    func byteRange(for markup: Markup) -> Range<Int>? {
        guard let range = markup.range,
              let lower = byteOffset(for: range.lowerBound),
              let upper = byteOffset(for: range.upperBound),
              lower <= upper else {
            return nil
        }
        return lower..<upper
    }

    func substring(for markup: Markup) -> String? {
        guard let range = byteRange(for: markup),
              let lower = String.Index(utf8Offset: range.lowerBound, in: source),
              let upper = String.Index(utf8Offset: range.upperBound, in: source) else {
            return nil
        }
        return String(source[lower..<upper])
    }

    private func byteOffset(for location: SourceLocation) -> Int? {
        guard location.line > 0,
              location.line <= lineStarts.count,
              location.column > 0 else {
            return nil
        }
        let offset = lineStarts[location.line - 1] + location.column - 1
        return offset <= bytes.count ? offset : nil
    }
}

struct InlineLinkSourceGuard {
    private let sourceMap: MarkdownSourceMap

    init(normalizedSource: String) {
        sourceMap = MarkdownSourceMap(normalizedSource)
    }

    func validate(_ link: Link, destination: String) -> Bool {
        guard let source = sourceMap.substring(for: link) else { return false }
        let scalars = Array(source.unicodeScalars)
        guard scalars.count >= 3 else { return false }

        if scalars.first == "<" {
            return scalars.last == ">"
                && String(String.UnicodeScalarView(scalars.dropFirst().dropLast())) == destination
        }

        guard scalars.first == "[" else { return false }
        var labelDepth = 1
        var cursor = 1
        while cursor < scalars.count, labelDepth > 0 {
            switch scalars[cursor] {
            case "[": labelDepth += 1
            case "]": labelDepth -= 1
            case "\\": return false
            default: break
            }
            cursor += 1
        }

        guard labelDepth == 0,
              cursor < scalars.count,
              scalars[cursor] == "(" else {
            return false
        }
        cursor += 1

        let destinationStart: Int
        let destinationEnd: Int
        if cursor < scalars.count, scalars[cursor] == "<" {
            cursor += 1
            destinationStart = cursor
            while cursor < scalars.count, scalars[cursor] != ">" {
                guard !isWhitespace(scalars[cursor]), scalars[cursor] != "\\" else { return false }
                cursor += 1
            }
            guard cursor < scalars.count, scalars[cursor] == ">" else { return false }
            destinationEnd = cursor
            cursor += 1
            guard cursor < scalars.count, scalars[cursor] == ")", cursor == scalars.count - 1 else {
                return false
            }
        } else {
            destinationStart = cursor
            var nestedParentheses = 0
            while cursor < scalars.count {
                let scalar = scalars[cursor]
                if isWhitespace(scalar) || scalar == "\\" || scalar == "<" || scalar == ">" {
                    return false
                }
                if scalar == "(" {
                    nestedParentheses += 1
                } else if scalar == ")" {
                    if nestedParentheses == 0 { break }
                    nestedParentheses -= 1
                }
                cursor += 1
            }
            guard nestedParentheses == 0, cursor == scalars.count - 1, scalars[cursor] == ")" else {
                return false
            }
            destinationEnd = cursor
        }

        return destinationStart < destinationEnd
            && String(String.UnicodeScalarView(scalars[destinationStart..<destinationEnd])) == destination
    }

    private func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace
    }
}

struct DocumentSourceCoverageGuard {
    private let sourceMap: MarkdownSourceMap

    init(normalizedSource: String) {
        sourceMap = MarkdownSourceMap(normalizedSource)
    }

    func validate(_ document: Document) -> Bool {
        guard validateCoverage(
            within: 0..<sourceMap.bytes.count,
            children: Array(document.children),
            allowedGap: isWhitespace
        ) else {
            return false
        }
        return document.children.allSatisfy(validateRecursively)
    }

    private func validateRecursively(_ markup: Markup) -> Bool {
        if let text = markup as? Text {
            return validateText(text)
        }
        if markup is SoftBreak {
            // swift-markdown 0.8.0 omits SoftBreak ranges. Its parent coverage
            // check owns the exact normalized LF between ranged siblings.
            return true
        }
        if let heading = markup as? Heading {
            guard validateHeading(heading) else { return false }
            return validateChildren(of: heading, allowedGap: headingGap)
        }
        if markup is Paragraph {
            return validateChildren(of: markup, allowedGap: isWhitespace)
        }
        if markup is Strong {
            guard let source = sourceMap.substring(for: markup),
                  (source.hasPrefix("**") && source.hasSuffix("**")
                    || source.hasPrefix("__") && source.hasSuffix("__")) else {
                return false
            }
            return validateChildren(of: markup, allowedGap: emphasisGap)
        }
        if markup is Emphasis {
            guard let source = sourceMap.substring(for: markup),
                  source.count >= 2,
                  (source.hasPrefix("*") && source.hasSuffix("*")
                    || source.hasPrefix("_") && source.hasSuffix("_")),
                  !source.hasPrefix("**"),
                  !source.hasPrefix("__") else {
                return false
            }
            return validateChildren(of: markup, allowedGap: emphasisGap)
        }
        if markup is Link {
            return markup.children.allSatisfy(validateRecursively)
        }
        if markup is BlockQuote {
            return validateChildren(of: markup, allowedGap: quoteGap)
        }
        if markup is OrderedList || markup is UnorderedList || markup is ListItem {
            return validateChildren(of: markup, allowedGap: listGap)
        }

        // Unsupported nodes are rejected by the converter's single default route.
        return true
    }

    private func validateChildren(
        of markup: Markup,
        allowedGap: (UInt8) -> Bool
    ) -> Bool {
        guard let range = sourceMap.byteRange(for: markup),
              validateCoverage(
                within: range,
                children: Array(markup.children),
                allowedGap: allowedGap
              ) else {
            return false
        }
        return markup.children.allSatisfy(validateRecursively)
    }

    private func validateCoverage(
        within parentRange: Range<Int>,
        children: [Markup],
        allowedGap: (UInt8) -> Bool
    ) -> Bool {
        var cursor = parentRange.lowerBound
        for (index, child) in children.enumerated() {
            if let childRange = sourceMap.byteRange(for: child) {
                guard parentRange.lowerBound <= childRange.lowerBound,
                      childRange.upperBound <= parentRange.upperBound,
                      cursor <= childRange.lowerBound,
                      sourceMap.bytes[cursor..<childRange.lowerBound].allSatisfy(allowedGap) else {
                    return false
                }
                cursor = childRange.upperBound
                continue
            }

            guard child is SoftBreak,
                  index > children.startIndex,
                  index + 1 < children.endIndex,
                  let previousRange = sourceMap.byteRange(for: children[index - 1]),
                  let nextRange = sourceMap.byteRange(for: children[index + 1]),
                  previousRange.upperBound == cursor,
                  parentRange.lowerBound <= nextRange.lowerBound,
                  nextRange.upperBound <= parentRange.upperBound,
                  cursor <= nextRange.lowerBound else {
                return false
            }

            let softBreakGap = sourceMap.bytes[cursor..<nextRange.lowerBound]
            guard softBreakGap.count == 1, softBreakGap.first == 0x0A else {
                return false
            }
            cursor = nextRange.lowerBound
        }
        return sourceMap.bytes[cursor..<parentRange.upperBound].allSatisfy(allowedGap)
    }

    private func validateHeading(_ heading: Heading) -> Bool {
        guard let source = sourceMap.substring(for: heading) else { return false }
        switch heading.level {
        case 2: return source.hasPrefix("## ") && !source.hasPrefix("### ")
        case 3: return source.hasPrefix("### ") && !source.hasPrefix("#### ")
        default: return true
        }
    }

    private func validateText(_ text: Text) -> Bool {
        guard let source = sourceMap.substring(for: text) else {
            return false
        }

        let sourceScalars = source.unicodeScalars
        let textScalars = text.string.unicodeScalars
        var sourceIndex = sourceScalars.startIndex
        var textIndex = textScalars.startIndex

        while sourceIndex < sourceScalars.endIndex {
            guard textIndex < textScalars.endIndex else { return false }

            let sourceScalar = sourceScalars[sourceIndex]
            if sourceScalar == "\\" {
                let nextSourceIndex = sourceScalars.index(after: sourceIndex)
                if nextSourceIndex < sourceScalars.endIndex,
                   isCommonMarkEscapable(sourceScalars[nextSourceIndex]) {
                    guard textScalars[textIndex] == sourceScalars[nextSourceIndex] else {
                        return false
                    }
                    sourceIndex = sourceScalars.index(after: nextSourceIndex)
                    textIndex = textScalars.index(after: textIndex)
                    continue
                }
            } else if sourceScalar == "*" {
                let nextSourceIndex = sourceScalars.index(after: sourceIndex)
                guard nextSourceIndex == sourceScalars.endIndex
                    || sourceScalars[nextSourceIndex] != "*" else {
                    return false
                }
            }

            guard textScalars[textIndex] == sourceScalar else { return false }
            sourceIndex = sourceScalars.index(after: sourceIndex)
            textIndex = textScalars.index(after: textIndex)
        }

        return textIndex == textScalars.endIndex
    }

    private func isCommonMarkEscapable(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x21...0x2F, 0x3A...0x40, 0x5B...0x60, 0x7B...0x7E:
            true
        default:
            false
        }
    }

    private func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A
    }

    private func headingGap(_ byte: UInt8) -> Bool {
        isWhitespace(byte) || byte == 0x23
    }

    private func emphasisGap(_ byte: UInt8) -> Bool {
        byte == 0x2A || byte == 0x5F
    }

    private func quoteGap(_ byte: UInt8) -> Bool {
        isWhitespace(byte) || byte == 0x3E
    }

    private func listGap(_ byte: UInt8) -> Bool {
        isWhitespace(byte)
            || (0x30...0x39).contains(byte)
            || byte == 0x2E
            || byte == 0x29
            || byte == 0x2D
            || byte == 0x2B
            || byte == 0x2A
    }
}

private extension String.Index {
    init?(utf8Offset: Int, in string: String) {
        guard utf8Offset >= 0,
              let utf8Index = string.utf8.index(
                string.utf8.startIndex,
                offsetBy: utf8Offset,
                limitedBy: string.utf8.endIndex
              ) else {
            return nil
        }
        self = utf8Index
    }
}
