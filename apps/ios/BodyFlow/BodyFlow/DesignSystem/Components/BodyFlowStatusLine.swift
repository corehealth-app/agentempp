import SwiftUI

/// One-line status message with the vocabulary glyph and role color for its
/// kind (info, success, warning, error, pending, unavailable). Read as a
/// single element; the glyph is decorative and the color is never the only
/// channel because the glyph and the text carry the meaning too.
@MainActor
struct BodyFlowStatusLine: View {
    enum Kind: Sendable {
        case info, success, warning, error, pending, empty, unavailable

        var symbol: BodyFlowSymbol {
            switch self {
            case .info: .info
            case .success: .success
            case .warning: .warning
            case .error: .error
            case .pending: .clock
            case .empty: .empty
            case .unavailable: .unavailable
            }
        }

        var foregroundRole: BodyFlowColor.Role {
            switch self {
            case .info, .pending, .empty, .unavailable: .textSecondary
            case .success: .feedbackPositive
            case .warning: .feedbackWarning
            case .error: .feedbackDestructive
            }
        }
    }

    private let message: String
    private let kind: Kind
    private let font: Font

    init(_ message: String, kind: Kind, font: Font = BodyFlowTypography.supporting) {
        self.message = message
        self.kind = kind
        self.font = font
    }

    var body: some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(symbol: kind.symbol)
                .accessibilityHidden(true)
        }
        .font(font)
        .foregroundStyle(BodyFlowColor.color(kind.foregroundRole))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
