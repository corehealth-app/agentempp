import SwiftUI

enum MascotViewSurface: Equatable, Sendable {
    case card
    case detail
}

struct MascotArtworkPresentationDescriptor: Equatable, Sendable {
    let geometry: MascotPersonalityGeometry
    let tone: MascotPersonalityTone
    let semanticState: MascotSemanticState
}

struct MascotViewCompositionDescriptor: Equatable, Sendable {
    let surface: MascotViewSurface
    let title: String
    let personaName: String
    let personaText: String
    let stateText: String
    let changedAtText: String
    let accessibilityAnnouncement: String
    let artworkAccessibilityHidden: Bool
    let showsTemporaryArtwork: Bool
    let usesRepeatingMotion: Bool
    let primaryActionTitle: String
    let artwork: MascotArtworkPresentationDescriptor

    init(
        presentation: MascotExperiencePresentation,
        surface: MascotViewSurface,
        reduceMotion: Bool,
        temporaryArtworkAvailable: Bool = Self.defaultArtworkAvailability
    ) {
        let personaName = Self.personaName(from: presentation)
        self.surface = surface
        title = "Mascote BodyFlow"
        self.personaName = personaName
        personaText = "Personalidade: \(personaName)"
        stateText = presentation.mascotState.title
        changedAtText = presentation.changedAtText
        accessibilityAnnouncement =
            "Mascote BodyFlow, personalidade \(personaName), estado \(presentation.mascotState.title)"
        artworkAccessibilityHidden = true
        showsTemporaryArtwork = temporaryArtworkAvailable
        usesRepeatingMotion = temporaryArtworkAvailable && !reduceMotion
        primaryActionTitle = surface == .card ? "Ver mascote" : "Atualizar"
        artwork = MascotArtworkPresentationDescriptor(
            geometry: presentation.personality.geometry,
            tone: presentation.personality.tone,
            semanticState: presentation.mascotState.semanticState
        )
    }

    private static var defaultArtworkAvailability: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    private static func personaName(
        from presentation: MascotExperiencePresentation
    ) -> String {
        switch presentation.effective {
        case .focus:
            presentation.optionsByCode[.focus]?.name
                ?? "indisponível"
        case .impulse:
            presentation.optionsByCode[.impulse]?.name
                ?? "indisponível"
        case .zen:
            presentation.optionsByCode[.zen]?.name
                ?? "indisponível"
        case .balanced:
            "Equilibrada"
        }
    }
}

@MainActor
struct MascotCardView: View {
    let model: MascotExperienceViewModel
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion

    var body: some View {
        let presentation = model.state.presentation
        if let value = presentation.value {
            loadedCard(
                value,
                showsStaleBanner: presentation.showsStaleBanner
            )
        } else if let fullScreenState = presentation.fullScreenState {
            compactState(fullScreenState)
        } else {
            compactState(.loading)
        }
    }

    private func loadedCard(
        _ presentation: MascotExperiencePresentation,
        showsStaleBanner: Bool
    ) -> some View {
        let descriptor = MascotViewCompositionDescriptor(
            presentation: presentation,
            surface: .card,
            reduceMotion: reduceMotion
        )

        return NavigationLink(value: AppRoute.mascot(.detail)) {
            BodyFlowCard {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                    if showsStaleBanner {
                        Text("Dados salvos desta sessão")
                            .font(BodyFlowTypography.callout)
                            .foregroundStyle(BodyFlowColor.secondaryText)
                    }

                    MascotSemanticContent(descriptor: descriptor)

                    HStack(spacing: BodyFlowSpacing.xs) {
                        Text(descriptor.primaryActionTitle)
                            .font(BodyFlowTypography.headline)
                            .foregroundStyle(BodyFlowColor.accent)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(BodyFlowColor.accent)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.mascot")
    }

    private func compactState(_ state: ScreenState) -> some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                Text("Mascote BodyFlow")
                    .font(BodyFlowTypography.headline)
                    .foregroundStyle(BodyFlowColor.primaryText)

                if state == .loading {
                    ProgressView("Carregando mascote…")
                        .tint(BodyFlowColor.accent)
                } else {
                    Text(state.descriptor.title)
                        .font(BodyFlowTypography.body)
                        .foregroundStyle(BodyFlowColor.secondaryText)

                    if state.descriptor.showsRetry {
                        Button("Tentar novamente") {
                            Task { await model.retry() }
                        }
                        .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("today.mascot.state")
    }
}

struct MascotSemanticContent: View {
    let descriptor: MascotViewCompositionDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
#if DEBUG
            if descriptor.showsTemporaryArtwork {
                MascotPlaceholderArtwork(
                    descriptor: descriptor.artwork,
                    usesRepeatingMotion: descriptor.usesRepeatingMotion
                )
                .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 180)
                .accessibilityHidden(descriptor.artworkAccessibilityHidden)
            }
#endif

            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text(descriptor.title)
                    .font(BodyFlowTypography.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(BodyFlowColor.primaryText)
                Text(descriptor.personaText)
                    .font(BodyFlowTypography.body)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .accessibilityLabel("personalidade \(descriptor.personaName)")
                Text(descriptor.stateText)
                    .font(BodyFlowTypography.headline)
                    .foregroundStyle(BodyFlowColor.primaryText)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(descriptor.accessibilityAnnouncement)
        }
    }
}
