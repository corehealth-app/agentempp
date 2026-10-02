import SwiftUI

/// One visual policy for the existing component library. Reading surfaces
/// remain opaque; only floating navigation can use the system glass/material.
struct BodyFlowVisualPolicy: Equatable, Sendable {
    var reduceMotion = false
    var reduceTransparency = false
    var increasedContrast = false
    var differentiateWithoutColor = false
    var lowPower = false
    var thermalLimited = false

    enum Treatment: Equatable { case opaque, material, liquidGlass }

    var allowsMotion: Bool { !reduceMotion && !lowPower && !thermalLimited }
    var requiresOpaqueSurfaces: Bool {
        reduceTransparency || increasedContrast || lowPower || thermalLimited
    }

    func treatment(for role: BodyFlowSurfaceRole, supportsLiquidGlass: Bool) -> Treatment {
        guard role == .floating, !requiresOpaqueSurfaces else { return .opaque }
        return supportsLiquidGlass ? .liquidGlass : .material
    }
}

private struct BodyFlowVisualPolicyKey: EnvironmentKey {
    static let defaultValue = BodyFlowVisualPolicy()
}

extension EnvironmentValues {
    var bodyFlowVisualPolicy: BodyFlowVisualPolicy {
        get { self[BodyFlowVisualPolicyKey.self] }
        set { self[BodyFlowVisualPolicyKey.self] = newValue }
    }
}

private struct BodyFlowVisualEnvironment: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var thermalState = ProcessInfo.processInfo.thermalState
    let reduceMotion: Bool
    let differentiateWithoutColor: Bool

    private var policy: BodyFlowVisualPolicy {
        BodyFlowVisualPolicy(
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            increasedContrast: contrast == .increased,
            differentiateWithoutColor: differentiateWithoutColor,
            lowPower: lowPower,
            thermalLimited: thermalState == .serious || thermalState == .critical
        )
    }

    func body(content: Content) -> some View {
        content
            .transaction { transaction in
                if !policy.allowsMotion {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .environment(\.bodyFlowVisualPolicy, policy)
            .environment(\.bodyFlowReduceMotion, !policy.allowsMotion)
            .environment(\.bodyFlowDifferentiateWithoutColor, differentiateWithoutColor)
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
                thermalState = ProcessInfo.processInfo.thermalState
            }
    }
}

struct BodyFlowSurface: ViewModifier {
    @Environment(\.bodyFlowVisualPolicy) private var policy
    let role: BodyFlowSurfaceRole
    var cornerRadius: CGFloat = BodyFlowRadius.card

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder func body(content: Content) -> some View {
        switch policy.treatment(for: role, supportsLiquidGlass: supportsLiquidGlass) {
        case .liquidGlass:
            if #available(iOS 26, *) {
                content.glassEffect(.regular, in: shape)
            } else {
                content.background(.regularMaterial, in: shape)
            }
        case .material:
            content.background(.regularMaterial, in: shape)
        case .opaque:
            content
                .background(BodyFlowColor.color(role.colorRole), in: shape)
                .overlay {
                    if policy.increasedContrast || role == .floating {
                        shape.strokeBorder(BodyFlowColor.color(.controlBoundary), lineWidth: 1)
                    }
                }
        }
    }

    private var supportsLiquidGlass: Bool {
        if #available(iOS 26, *) { true } else { false }
    }
}

extension View {
    func bodyFlowVisualEnvironment(reduceMotion: Bool, differentiateWithoutColor: Bool) -> some View {
        modifier(BodyFlowVisualEnvironment(
            reduceMotion: reduceMotion,
            differentiateWithoutColor: differentiateWithoutColor
        ))
    }

    func bodyFlowSurface(_ role: BodyFlowSurfaceRole, cornerRadius: CGFloat = BodyFlowRadius.card) -> some View {
        modifier(BodyFlowSurface(role: role, cornerRadius: cornerRadius))
    }
}
