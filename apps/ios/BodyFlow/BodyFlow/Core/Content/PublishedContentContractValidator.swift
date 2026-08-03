enum PublishedContentContractValidator {
    static func validate(_ feed: PublishedContentFeed) throws {
        for item in feed.items {
            try validate(item)
        }
    }

    static func validate(_ detail: PublishedContentDetail) throws {
        try validate(detail.summary)
        let normalizedBodyLength = MarkdownSourceNormalizer.normalize(detail.bodyMarkdown).utf16.count
        guard (100...50_000).contains(normalizedBodyLength) else {
            throw BodyFlowCapabilityError.invalidContentContract
        }
    }

    static func validate(_ summary: PublishedContentSummary) throws {
        guard isUUID(summary.publicationID),
              isSlug(summary.slug, length: 3...120),
              (3...120).contains(summary.title.utf16.count),
              (20...280).contains(summary.excerpt.utf16.count),
              summary.tags.count <= 20,
              Set(summary.tags).count == summary.tags.count,
              summary.tags.allSatisfy({ isSlug($0, length: 1...40) }),
              (1...500).contains(summary.readingTimeMinutes),
              (1...2_147_483_647).contains(summary.version)
        else {
            throw BodyFlowCapabilityError.invalidContentContract
        }
    }

    private static func isUUID(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 36 else { return false }

        for (index, byte) in bytes.enumerated() {
            if index == 8 || index == 13 || index == 18 || index == 23 {
                guard byte == 45 else { return false }
            } else {
                guard isASCIIHexDigit(byte) else { return false }
            }
        }
        return true
    }

    private static func isSlug(
        _ value: String,
        length: ClosedRange<Int>
    ) -> Bool {
        let bytes = Array(value.utf8)
        guard length.contains(bytes.count),
              bytes.first != 45,
              bytes.last != 45
        else {
            return false
        }

        var previousWasHyphen = false
        for byte in bytes {
            if byte == 45 {
                guard !previousWasHyphen else { return false }
                previousWasHyphen = true
            } else {
                guard isASCIILowercaseLetterOrDigit(byte) else { return false }
                previousWasHyphen = false
            }
        }
        return true
    }

    private static func isASCIIHexDigit(_ byte: UInt8) -> Bool {
        switch byte {
        case 48...57, 65...70, 97...102:
            true
        default:
            false
        }
    }

    private static func isASCIILowercaseLetterOrDigit(_ byte: UInt8) -> Bool {
        switch byte {
        case 48...57, 97...122:
            true
        default:
            false
        }
    }
}
