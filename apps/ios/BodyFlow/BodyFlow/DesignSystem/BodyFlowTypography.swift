import SwiftUI

/// Direction v2 (2026-10-03): titles and figures use the system's rounded
/// design (the face of Apple Fitness's numbers) so the display voice is the
/// app's own without bundling a typeface; body text stays the default
/// design. Every role is a scalable text style.
enum BodyFlowTypography {
    static let largeTitle: Font = .system(.largeTitle, design: .rounded).bold()
    static let screenTitle: Font = .system(.title2, design: .rounded).weight(.bold)
    static let sectionTitle: Font = .system(.headline, design: .rounded).weight(.bold)
    static let cardTitle: Font = .system(.headline, design: .rounded).weight(.bold)
    static let supporting: Font = .callout
    static let metricLarge: Font = .system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit()
    static let metricSmall: Font = .system(.title2, design: .rounded).weight(.bold).monospacedDigit()
    static let button: Font = .headline.weight(.semibold)
    static let title: Font = .title2
    static let headline: Font = .headline
    static let body: Font = .body
    static let callout: Font = .callout
    static let caption: Font = .caption
    /// Compact shell wordmark: one scalable role used at every Dynamic Type
    /// size (never switching roles per category, which reads as unsupported
    /// Dynamic Type to the accessibility audit).
    static let brandCompact: Font = .subheadline.weight(.bold)
}
