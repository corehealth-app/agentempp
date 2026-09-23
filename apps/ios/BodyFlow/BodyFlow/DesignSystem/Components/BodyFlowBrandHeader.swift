import SwiftUI

/// The brand band above the tab roots and the persona sheet: one shared
/// wordmark row on the primary background with a bottom rule. The shell uses
/// the compact, leading variant; sheets keep the standard centred wordmark.
struct BodyFlowBrandHeader: View {
    private let presentation: BodyFlowBrandIdentityView.Presentation
    private let alignment: Alignment
    private let horizontalPadding: CGFloat

    init(
        presentation: BodyFlowBrandIdentityView.Presentation = .standard,
        alignment: Alignment = .center,
        horizontalPadding: CGFloat = BodyFlowSpacing.lg
    ) {
        self.presentation = presentation
        self.alignment = alignment
        self.horizontalPadding = horizontalPadding
    }

    var body: some View {
        BodyFlowBrandIdentityView(presentation: presentation)
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, BodyFlowSpacing.xs)
            .background(BodyFlowColor.color(.backgroundPrimary))
            .overlay(alignment: .bottom) {
                Divider()
            }
    }
}
