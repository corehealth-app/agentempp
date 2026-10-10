import SwiftUI

/// The meal is the one primary action of the Register screen: a brand card
/// with its own action (the full choice of ways) and one real button for
/// each way of telling the app what was eaten — photo, text, audio. Each of
/// the three opens its capture at once.
///
/// The four touch areas tile the card: every point of it answers, and no
/// gesture sits on the background.
@MainActor
struct RegisterMealCard: View {
    /// `nil` opens the full choice; an entry opens that way directly.
    let open: @MainActor (MealCaptureEntry?) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// From the card's edge to a way's touch area in the row: the card's own
    /// padding less the half gap every way already carries.
    private static let rowEdge = BodyFlowSpacing.md - BodyFlowSpacing.xxs

    var body: some View {
        VStack(spacing: 0) {
            titleButton
            if dynamicTypeSize <= .xLarge {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(MealCaptureEntry.allCases, id: \.self) { entry in
                        wayButton(entry, stacked: false)
                    }
                }
                .padding(.horizontal, Self.rowEdge)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                // Larger text: one way per row, icon beside its name.
                ForEach(MealCaptureEntry.allCases, id: \.self) { entry in
                    wayButton(entry, stacked: true)
                }
            }
        }
        .background(
            BodyFlowColor.color(.brandPrimary),
            in: RoundedRectangle(cornerRadius: BodyFlowRadius.card, style: .continuous)
        )
    }

    /// The card's own action: the name of the record and what it takes.
    private var titleButton: some View {
        Button { open(nil) } label: {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                Text(verbatim: copy("registration.kind.meal"))
                    .font(BodyFlowTypography.screenTitle)
                Text(verbatim: copy("registration.root.meal.detail"))
                    .font(BodyFlowTypography.callout)
            }
            .foregroundStyle(BodyFlowColor.color(.onPrimary))
            .fixedSize(horizontal: false, vertical: true)
            .padding([.top, .horizontal], BodyFlowSpacing.md)
            .padding(.bottom, BodyFlowSpacing.xs)
            .frame(maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bodyFlowRowAction)
        .accessibilityLabel(copy("registration.kind.meal"))
        .accessibilityHint(copy("registration.root.meal.detail"))
        .accessibilityIdentifier(RegistrationKind.meal.commandAccessibilityIdentifier)
    }

    /// One way. Its touch area reaches the card's edges and half of each gap
    /// to its neighbours, so the ways and the title tile the card.
    private func wayButton(_ entry: MealCaptureEntry, stacked: Bool) -> some View {
        let isFirst = entry == MealCaptureEntry.allCases.first
        let isLast = entry == MealCaptureEntry.allCases.last
        return Button { open(entry) } label: {
            Group {
                if stacked {
                    wayRow(entry)
                        .padding(.horizontal, BodyFlowSpacing.md)
                } else {
                    wayChip(entry)
                        .padding(.horizontal, BodyFlowSpacing.xxs)
                        .padding(.leading, isFirst ? Self.rowEdge : 0)
                        .padding(.trailing, isLast ? Self.rowEdge : 0)
                }
            }
            .padding(.top, stacked && !isFirst ? BodyFlowSpacing.xxs : BodyFlowSpacing.xs)
            .padding(.bottom, stacked && !isLast ? BodyFlowSpacing.xxs : BodyFlowSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bodyFlowRowAction)
        // In the row the three share the width equally; the first and the
        // last reach over the row's edge padding without changing that share.
        .padding(.leading, !stacked && isFirst ? -Self.rowEdge : 0)
        .padding(.trailing, !stacked && isLast ? -Self.rowEdge : 0)
        .accessibilityLabel(copy(titleKey(for: entry)))
        .accessibilityHint(copy(hintKey(for: entry)))
        .accessibilityIdentifier(entry.commandAccessibilityIdentifier)
    }

    private func wayChip(_ entry: MealCaptureEntry) -> some View {
        VStack(spacing: BodyFlowSpacing.xxs) {
            wayIcon(entry)
            Text(verbatim: copy(titleKey(for: entry)))
                .font(BodyFlowTypography.caption.weight(.semibold))
        }
        .foregroundStyle(BodyFlowColor.color(.brandPrimary))
        .padding(.vertical, BodyFlowSpacing.xs)
        .frame(maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget, maxHeight: .infinity)
        .background(
            BodyFlowColor.color(.surfaceElevated),
            in: RoundedRectangle(cornerRadius: BodyFlowRadius.field, style: .continuous)
        )
    }

    private func wayRow(_ entry: MealCaptureEntry) -> some View {
        HStack(spacing: BodyFlowSpacing.sm) {
            wayIcon(entry)
            Text(verbatim: copy(titleKey(for: entry)))
                .font(BodyFlowTypography.headline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(BodyFlowColor.color(.brandPrimary))
        .padding(.horizontal, BodyFlowSpacing.md)
        .padding(.vertical, BodyFlowSpacing.sm)
        .frame(maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget, alignment: .leading)
        .background(
            BodyFlowColor.color(.surfaceElevated),
            in: RoundedRectangle(cornerRadius: BodyFlowRadius.field, style: .continuous)
        )
    }

    /// The three glyphs differ in height: each sits in the box of the
    /// tallest, so the names line up across the ways at any text size.
    private func wayIcon(_ entry: MealCaptureEntry) -> some View {
        ZStack {
            ForEach(MealCaptureEntry.allCases, id: \.self) { other in
                Image(symbol: symbol(for: other)).hidden()
            }
            Image(symbol: symbol(for: entry))
        }
        .font(BodyFlowTypography.headline)
        .accessibilityHidden(true)
    }

    private func symbol(for entry: MealCaptureEntry) -> BodyFlowSymbol {
        switch entry {
        case .photo: .camera
        case .text: .compose
        case .audio: .microphone
        }
    }

    private func titleKey(for entry: MealCaptureEntry) -> String.LocalizationValue {
        switch entry {
        case .photo: "registration.root.way.photo"
        case .text: "registration.root.way.text"
        case .audio: "registration.root.way.audio"
        }
    }

    private func hintKey(for entry: MealCaptureEntry) -> String.LocalizationValue {
        switch entry {
        case .photo: "registration.root.way.photo.hint"
        case .text: "registration.root.way.text.hint"
        case .audio: "registration.root.way.audio.hint"
        }
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(key, language: BodyFlowPresentationLanguage.resolve(locale))
    }
}
