import SwiftUI

/// Approved Signal Spark, shared by navigation and the visible registration.
/// A ready proposal is active; only the coordinator's confirmed receipt is success.
struct PerformeBrandAction: View {
    let state: PerformeBrandState
    let label: String
    var status: String? = nil
    var selected = false
    var showsLabel = true
    var isNavigationAction = false
    var navigationIdentifier: String? = nil
    var connectsLaunch = false
    var action: (@MainActor () -> Void)? = nil
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let action, isNavigationAction {
                PerformeNavigationAction(
                    title: label,
                    largeContentImage: UIImage(named: PerformeAIBrandAsset.symbolNegative.resourceName)?.withRenderingMode(.alwaysTemplate),
                    isSelected: selected,
                    identifier: navigationIdentifier,
                    status: status,
                    action: action
                ) {
                    content.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
            } else if let action {
                Button(action: action) {
                    content
                        .dynamicTypeSize(...(isNavigationAction ? DynamicTypeSize.xxxLarge : .accessibility5))
                }
                    .buttonStyle(PerformeBrandPressStyle())
                    .accessibilityShowsLargeContentViewer {
                        Label(label, image: PerformeAIBrandAsset.symbolLight.resourceName)
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel(label)
                    .accessibilityValue(status ?? "")
                    .accessibilityAddTraits(selected ? .isSelected : [])
            } else {
                content
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(status ?? label)
            }
        }
    }

    private var content: some View {
        VStack(spacing: BodyFlowSpacing.xxs) {
            ZStack(alignment: .bottomTrailing) {
                Image(decorative: PerformeAIBrandAsset.symbolNegative.resourceName)
                    .resizable().renderingMode(.original).scaledToFit()
                    .frame(width: 28, height: 28)
                    .performeBrandContinuity(source: false, enabled: connectsLaunch)
                    .frame(width: 44, height: 44)
                    .background(BodyFlowColor.color(.heroBackground), in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        if selected || state == .active {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(BodyFlowColor.color(.brandPrimary), lineWidth: 2)

                        }
                    }
                if state == .processing {
                    BodyFlowDelayedProgress()
                        .foregroundStyle(BodyFlowColor.color(.brandPrimary))
                        .background(BodyFlowColor.color(.surfaceElevated), in: Circle())
                        .offset(x: 6, y: 2)
                        .accessibilityHidden(true)
                } else if let symbol = statusSymbol {
                    Image(systemName: symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BodyFlowColor.color(state == .error ? .feedbackDestructive : .feedbackPositive))
                        .padding(3)
                        .background(BodyFlowColor.color(.surfaceElevated), in: Circle())
                        .offset(x: 6, y: 2)
                        .accessibilityHidden(true)
                }
            }
            if showsLabel { caption }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .scaleEffect(state == .press && !reduceMotion ? BodyFlowMotion.pressedScale : 1)
        .animation(BodyFlowMotion.animation(.content, reduceMotion: reduceMotion), value: state)
    }

    private var caption: some View {
        Text(label)
            .font(.caption2.weight(selected ? .semibold : .regular))
            .multilineTextAlignment(.center)
            .lineLimit(isNavigationAction ? 1 : nil)
            .minimumScaleFactor(isNavigationAction ? 0.8 : 1)
            .fixedSize(horizontal: false, vertical: !isNavigationAction)
            .foregroundStyle(BodyFlowColor.color(selected ? .brandPrimary : .textSecondary))
    }

    private var statusSymbol: String? {
        switch state {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.circle.fill"
        case .idle, .press, .active, .processing: nil
        }
    }
}

private struct PerformeBrandPressStyle: ButtonStyle {
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? BodyFlowMotion.pressedScale : 1)
            .opacity(configuration.isPressed ? BodyFlowOpacity.pressed : 1)
            .animation(BodyFlowMotion.animation(.press, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
