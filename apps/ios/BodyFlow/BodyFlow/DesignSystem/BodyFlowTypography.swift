import SwiftUI

enum BodyFlowTypography {
    static let largeTitle: Font = .largeTitle.bold()
    static let screenTitle: Font = .title2.weight(.semibold)
    static let sectionTitle: Font = .headline.weight(.semibold)
    static let cardTitle: Font = .headline.weight(.semibold)
    static let supporting: Font = .callout
    static let metricLarge: Font = .largeTitle.weight(.semibold).monospacedDigit()
    static let metricSmall: Font = .title2.weight(.semibold).monospacedDigit()
    static let button: Font = .headline.weight(.semibold)
    static let title: Font = .title2
    static let headline: Font = .headline
    static let body: Font = .body
    static let callout: Font = .callout
    static let caption: Font = .caption
}
