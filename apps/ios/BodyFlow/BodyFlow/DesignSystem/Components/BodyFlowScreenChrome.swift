import SwiftUI

/// Native inline bar for pushed and root screens: the title lives in the
/// bar, never as a large-title band above the content, and the bar keeps its
/// native background so live theme changes stay native.
struct BodyFlowScreenChrome: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    func bodyFlowScreenChrome(title: String) -> some View {
        modifier(BodyFlowScreenChrome(title: title))
    }
}
