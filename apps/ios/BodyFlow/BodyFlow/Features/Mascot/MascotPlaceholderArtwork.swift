#if DEBUG
import Foundation
import SwiftUI

struct MascotPlaceholderArtwork: View {
    let descriptor: MascotArtworkPresentationDescriptor
    let usesRepeatingMotion: Bool

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1 / 30,
                paused: !usesRepeatingMotion
            )
        ) { context in
            let phase = usesRepeatingMotion
                ? sin(context.date.timeIntervalSinceReferenceDate * 2) * 5
                : 0

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(BodyFlowColor.surface)

                accentOrbit
                    .offset(y: phase)

                abstractBody
                    .offset(y: phase * 0.45)
            }
            .padding(personalityPadding)
        }
        .accessibilityHidden(true)
    }

    private var abstractBody: some View {
        ZStack {
            bodyShape

            HStack(spacing: eyeSpacing) {
                Circle()
                    .fill(BodyFlowColor.primaryText)
                    .frame(width: 8, height: 8)
                Circle()
                    .fill(BodyFlowColor.primaryText)
                    .frame(width: 8, height: 8)
            }
            .offset(y: -10)

            Capsule()
                .fill(BodyFlowColor.background)
                .frame(width: 28, height: 7)
                .offset(y: 18)

            stateMark
                .offset(x: stateMarkOffset, y: stateMarkOffset)
        }
        .rotationEffect(rotation)
    }

    @ViewBuilder
    private var bodyShape: some View {
        switch descriptor.geometry {
        case .stable:
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(BodyFlowColor.accent)
                .frame(width: bodyWidth, height: bodyHeight)
        case .energetic:
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(BodyFlowColor.accent)
                .frame(width: bodyWidth, height: bodyHeight)
        case .calm, .neutral:
            Circle()
                .fill(BodyFlowColor.accent)
                .frame(width: bodyWidth, height: bodyHeight)
        }
    }

    private var accentOrbit: some View {
        Circle()
            .stroke(accentColor, lineWidth: orbitLineWidth)
            .frame(width: orbitSize, height: orbitSize)
            .rotationEffect(rotation)
            .overlay(alignment: orbitAlignment) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 18, height: 18)
            }
    }

    private var stateMark: some View {
        Group {
            switch descriptor.semanticState {
            case .active:
                Circle().fill(BodyFlowColor.achievement)
            case .reactivating:
                Capsule().fill(BodyFlowColor.warning)
            case .inactive, .neglected, .unsupported:
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(BodyFlowColor.secondaryText)
            }
        }
        .frame(width: 18, height: 18)
    }

    private var accentColor: Color {
        switch descriptor.tone {
        case .bright: BodyFlowColor.warning
        case .restrained: BodyFlowColor.accent
        case .soft: BodyFlowColor.achievement
        case .neutral: BodyFlowColor.secondaryText
        }
    }

    private var bodyWidth: CGFloat {
        switch descriptor.geometry {
        case .stable: 104
        case .energetic: 116
        case .calm: 100
        case .neutral: 96
        }
    }

    private var bodyHeight: CGFloat {
        switch descriptor.geometry {
        case .stable: 106
        case .energetic: 96
        case .calm: 100
        case .neutral: 96
        }
    }

    private var personalityPadding: CGFloat {
        switch descriptor.geometry {
        case .stable: BodyFlowSpacing.md
        case .energetic: BodyFlowSpacing.sm
        case .calm: BodyFlowSpacing.lg
        case .neutral: BodyFlowSpacing.md
        }
    }

    private var eyeSpacing: CGFloat {
        descriptor.geometry == .energetic
            ? BodyFlowSpacing.md
            : BodyFlowSpacing.sm
    }

    private var rotation: Angle {
        descriptor.geometry == .energetic ? .degrees(-8) : .zero
    }

    private var orbitSize: CGFloat {
        descriptor.geometry == .calm ? 136 : 148
    }

    private var orbitLineWidth: CGFloat {
        descriptor.tone == .bright ? 6 : 3
    }

    private var orbitAlignment: Alignment {
        switch descriptor.geometry {
        case .stable: .topTrailing
        case .energetic: .bottomTrailing
        case .calm: .topLeading
        case .neutral: .bottomLeading
        }
    }

    private var stateMarkOffset: CGFloat {
        descriptor.geometry == .calm ? 32 : 38
    }
}
#endif
