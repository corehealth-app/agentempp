import CoreGraphics

/// The dock can scroll when its natural content exceeds the protected viewport.
enum FlowComposerViewportPolicy {
    static func height(natural: CGFloat?, viewport: CGFloat, clearance: CGFloat) -> CGFloat {
        guard viewport.isFinite, clearance.isFinite, viewport > 0, clearance >= 0 else { return 0 }
        let available = max(0, viewport - clearance)
        // Reserve a bounded viewport on the first pass, before content is measured.
        guard let natural else { return available }
        guard natural.isFinite, natural > 0 else { return 0 }
        return min(natural, available)
    }
}
