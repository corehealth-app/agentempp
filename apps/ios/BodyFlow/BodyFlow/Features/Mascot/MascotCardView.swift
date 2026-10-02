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
        temporaryArtworkAvailable: Bool = Self.defaultArtworkAvailability,
        language: SupportedAppLanguage = .portugueseBrazil
    ) {
        let personaName = Self.personaName(
            from: presentation,
            language: language
        )
        self.surface = surface
        title = MascotCopy.string("mascot.title", language: language)
        self.personaName = personaName
        personaText = String(
            format: MascotCopy.string("mascot.personality-format", language: language),
            locale: language.formattingLocale,
            personaName
        )
        stateText = Self.stateText(
            presentation.mascotState.semanticState,
            language: language
        )
        changedAtText = presentation.changedAtText
        accessibilityAnnouncement = String(
            format: MascotCopy.string("mascot.accessibility-format", language: language),
            locale: language.formattingLocale,
            personaName,
            stateText
        )
        artworkAccessibilityHidden = true
        showsTemporaryArtwork = temporaryArtworkAvailable
        usesRepeatingMotion = temporaryArtworkAvailable && !reduceMotion
        primaryActionTitle = MascotCopy.string(
            surface == .card ? "mascot.action.view" : "mascot.action.refresh",
            language: language
        )
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
        from presentation: MascotExperiencePresentation,
        language: SupportedAppLanguage
    ) -> String {
        let unavailable = MascotCopy.string(
            "common.not-available",
            language: language
        )
        return switch presentation.effective {
        case .focus:
            presentation.optionsByCode[.focus]?.name
                ?? unavailable
        case .impulse:
            presentation.optionsByCode[.impulse]?.name
                ?? unavailable
        case .zen:
            presentation.optionsByCode[.zen]?.name
                ?? unavailable
        case .balanced:
            MascotCopy.string("mascot.persona.balanced", language: language)
        }
    }

    private static func stateText(
        _ state: MascotSemanticState,
        language: SupportedAppLanguage
    ) -> String {
        let key: String.LocalizationValue = switch state {
        case .inactive: "mascot.state.inactive"
        case .reactivating: "mascot.state.reactivating"
        case .active: "mascot.state.active"
        case .neglected: "mascot.state.neglected"
        case .unsupported: "mascot.state.updating"
        }
        return MascotCopy.string(key, language: language)
    }
}

@MainActor
struct MascotCardView: View {
    let model: MascotExperienceViewModel
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

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
            reduceMotion: reduceMotion,
            language: language
        )

        return NavigationLink(value: AppRoute.mascot(.detail)) {
            BodyFlowCard {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                    if showsStaleBanner {
                        BodyFlowStatusLine(copy("mascot.stale"), kind: .warning)
                    }

                    MascotSemanticContent(descriptor: descriptor)

                    HStack(spacing: BodyFlowSpacing.xs) {
                        Text(descriptor.primaryActionTitle)
                            .font(BodyFlowTypography.headline)
                            .foregroundStyle(BodyFlowColor.accent)
                        Spacer(minLength: 0)
                        Image(symbol: .chevron)
                            .font(BodyFlowTypography.caption)
                            .foregroundStyle(BodyFlowColor.accent)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                }
            }
        }
        .buttonStyle(.bodyFlowRow)
        .accessibilityIdentifier("today.mascot")
    }

    private func compactState(_ state: ScreenState) -> some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                Text(copy("mascot.title"))
                    .font(BodyFlowTypography.headline)
                    .foregroundStyle(BodyFlowColor.primaryText)

                if state == .loading {
                    BodyFlowDelayedProgress(label: copy("mascot.loading"))
                        .tint(BodyFlowColor.accent)
                } else {
                    Text(state.descriptor.title)
                        .font(BodyFlowTypography.body)
                        .foregroundStyle(BodyFlowColor.secondaryText)

                    if state.descriptor.showsRetry {
                        Button(copy("state.retry")) {
                            Task { await model.retry() }
                        }
                        .buttonStyle(BodyFlowButtonStyle(role: .secondary, isCompact: true))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("today.mascot.state")
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        MascotCopy.string(key, language: language)
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
                    .font(BodyFlowTypography.cardTitle)
                    .foregroundStyle(BodyFlowColor.primaryText)
                Text(descriptor.personaText)
                    .font(BodyFlowTypography.body)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .accessibilityLabel(descriptor.personaText)
                Text(descriptor.stateText)
                    .font(BodyFlowTypography.headline)
                    .foregroundStyle(BodyFlowColor.primaryText)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(descriptor.accessibilityAnnouncement)
        }
    }
}
