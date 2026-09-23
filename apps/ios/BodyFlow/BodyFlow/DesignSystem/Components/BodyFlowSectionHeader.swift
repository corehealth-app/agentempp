import SwiftUI

/// Section heading for scrolling screens: one scalable label with its domain
/// symbol, exposed as a VoiceOver header, plus an optional trailing accessory
/// (a link or count). The accessory shares the row while both fit and drops
/// below the title otherwise, so nothing truncates at accessibility sizes.
///
/// It takes the `screenTitle` role because `sectionTitle` and `cardTitle`
/// resolve to the same font: a section heading rendered at `sectionTitle`
/// would tie with the card titles underneath it and flatten the page.
@MainActor
struct BodyFlowSectionHeader<Accessory: View>: View {
    private let title: String
    private let symbol: BodyFlowSymbol?
    private let accessory: Accessory
    private let hasAccessory: Bool

    init(
        _ title: String,
        symbol: BodyFlowSymbol? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.symbol = symbol
        self.accessory = accessory()
        hasAccessory = true
    }

    fileprivate init(
        title: String,
        symbol: BodyFlowSymbol?,
        accessory: Accessory,
        hasAccessory: Bool
    ) {
        self.title = title
        self.symbol = symbol
        self.accessory = accessory
        self.hasAccessory = hasAccessory
    }

    var body: some View {
        Group {
            if hasAccessory {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: BodyFlowSpacing.sm) {
                        heading
                        Spacer(minLength: BodyFlowSpacing.sm)
                        accessory
                    }
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                        heading
                        accessory
                    }
                }
            } else {
                heading
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heading: some View {
        Group {
            if let symbol {
                Label(verbatim: title, symbol: symbol)
            } else {
                Text(title)
            }
        }
        .font(BodyFlowTypography.screenTitle)
        .foregroundStyle(BodyFlowColor.color(.textPrimary))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
    }
}

extension BodyFlowSectionHeader where Accessory == EmptyView {
    init(_ title: String, symbol: BodyFlowSymbol? = nil) {
        self.init(
            title: title,
            symbol: symbol,
            accessory: EmptyView(),
            hasAccessory: false
        )
    }
}
