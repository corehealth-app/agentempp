import SwiftUI

private struct PerformeBrandNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var performeBrandNamespace: Namespace.ID? {
        get { self[PerformeBrandNamespaceKey.self] }
        set { self[PerformeBrandNamespaceKey.self] = newValue }
    }
}

private struct PerformeBrandContinuity: ViewModifier {
    @Environment(\.performeBrandNamespace) private var namespace
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    let source: Bool
    let enabled: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if enabled, !reduceMotion, let namespace {
            content.matchedGeometryEffect(id: "signal-spark-launch", in: namespace, isSource: source)
        } else {
            content
        }
    }
}

extension View {
    func performeBrandContinuity(source: Bool, enabled: Bool = true) -> some View {
        modifier(PerformeBrandContinuity(source: source, enabled: enabled))
    }
}
