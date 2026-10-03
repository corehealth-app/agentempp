import SwiftUI

/// Card → detail "zoom" navigation (iOS 18): the tapped card grows into its
/// destination instead of the destination sliding in from the side. The
/// shell owns one namespace per tab stack and publishes it here; a card
/// marks itself as the source for its route, and the shell's destination
/// zooms from whichever source carries the same route. A route without a
/// source keeps the standard push. Reduce Motion keeps the system's own
/// reduced transition.
private struct BodyFlowZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var bodyFlowZoomNamespace: Namespace.ID? {
        get { self[BodyFlowZoomNamespaceKey.self] }
        set { self[BodyFlowZoomNamespaceKey.self] = newValue }
    }
}

private struct BodyFlowZoomSourceModifier: ViewModifier {
    @Environment(\.bodyFlowZoomNamespace) private var namespace
    let route: AppRoute

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: route, in: namespace)
        } else {
            content
        }
    }
}

extension View {
    /// Marks this card as the visual origin of `route`'s destination.
    func bodyFlowZoomSource(_ route: AppRoute) -> some View {
        modifier(BodyFlowZoomSourceModifier(route: route))
    }
}
