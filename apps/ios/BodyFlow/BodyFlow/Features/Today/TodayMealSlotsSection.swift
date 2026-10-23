import SwiftUI

/// The day by meal: each expected meal is a slot. A slot with records shows
/// them (every record keeps its own row and identifier); an open slot offers
/// the registration; a skipped one says so. Slots come from the server's own
/// `meal_gaps` and from the records themselves — nothing is inferred here.
struct TodayMealSlotsDescriptor: Equatable, Sendable {
    struct Slot: Equatable, Sendable, Identifiable {
        enum State: Equatable, Sendable { case registered, open, skipped }
        let type: String
        let state: State
        let meals: [TodayMealDescriptor]
        var id: String { type }

        /// Sum of the records' own kcal; nil when no record carries one.
        var totalKcal: Decimal? {
            let values = meals.compactMap(\.kcal)
            return values.isEmpty ? nil : values.reduce(0, +)
        }
    }

    nonisolated static let order = ["cafe", "almoco", "lanche", "jantar", "ceia", "outro"]

    let slots: [Slot]

    var registeredCount: Int { slots.filter { $0.state == .registered }.count }

    init(meals: [TodayMealDescriptor], expected: [String], skipped: [String]) {
        let grouped = Dictionary(grouping: meals) { $0.mealType ?? "outro" }
        var types: [String] = []
        for type in expected + skipped + meals.map({ $0.mealType ?? "outro" }) where !types.contains(type) {
            types.append(type)
        }
        types.sort { left, right in
            let l = Self.order.firstIndex(of: left) ?? Self.order.count
            let r = Self.order.firstIndex(of: right) ?? Self.order.count
            return l == r ? left < right : l < r
        }
        slots = types.map { type in
            if let records = grouped[type], !records.isEmpty {
                return Slot(type: type, state: .registered, meals: records)
            }
            return Slot(type: type, state: skipped.contains(type) ? .skipped : .open, meals: [])
        }
    }
}

@MainActor
struct TodayMealSlotsSection: View {
    let descriptor: TodayMealSlotsDescriptor
    /// Opens the meal registration; nil where no registration exists
    /// (previews, unavailable capability) and the open slot is then inert.
    var register: ((MealType) -> Void)?
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            BodyFlowSectionHeader(copy("today.meals.title"), symbol: .meals) {
                if !descriptor.slots.isEmpty {
                    Text(verbatim: String(
                        format: copy("today.meals.count"),
                        descriptor.registeredCount, descriptor.slots.count
                    ))
                    .font(BodyFlowTypography.caption)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                }
            }
            // One VoiceOver stop: "Refeições, 2 de 3", still a heading.
            .accessibilityElement(children: .combine)

            if descriptor.slots.isEmpty {
                Text(copy("today.records.meals.empty"))
                    .font(BodyFlowTypography.body)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            } else {
                ForEach(descriptor.slots) { slot in
                    switch slot.state {
                    case .registered: registered(slot)
                    case .open: open(slot)
                    case .skipped: skipped(slot)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.meals")
    }

    private func registered(_ slot: TodayMealSlotsDescriptor.Slot) -> some View {
        BodyFlowCard(surface: .elevated, padding: BodyFlowSpacing.sm) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                HStack(alignment: .center, spacing: BodyFlowSpacing.sm) {
                    slotGlyph(symbol: .confirm, filled: false)
                    Text(verbatim: title(slot.type))
                        .font(BodyFlowTypography.headline)
                        .foregroundStyle(BodyFlowColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: BodyFlowSpacing.sm)
                    if let total = slot.totalKcal {
                        BodyFlowFigure.text(
                            TodayValueFormatter.mealKcal(total, language: language),
                            value: BodyFlowTypography.headline.monospacedDigit(),
                            unit: BodyFlowTypography.caption,
                            unitColor: BodyFlowColor.secondaryText
                        )
                        .foregroundStyle(BodyFlowColor.primaryText)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("today.meal-slot.\(slot.type)")

                ForEach(slot.meals) { meal in
                    Divider()
                    mealRow(meal)
                }
            }
        }
    }

    /// One record: its name and energy on a line, its provenance below.
    private func mealRow(_ meal: TodayMealDescriptor) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: BodyFlowSpacing.sm) {
                    mealName(meal).fixedSize()
                    Spacer(minLength: BodyFlowSpacing.sm)
                    mealKcal(meal).fixedSize()
                }
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                    mealName(meal).fixedSize(horizontal: false, vertical: true)
                    mealKcal(meal)
                }
            }
            let quantity = MealQuantityValue(grams: meal.quantityG, metadata: meal.quantityDisplay, name: meal.foodName)
            if quantity.usesReference, let label = quantity.label(language: language) {
                Text(label)
                    .font(BodyFlowTypography.caption)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            }
            BodyFlowStatusLine(meal.provenance, kind: .info, font: BodyFlowTypography.caption)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.meal.\(meal.id)")
    }

    private func mealName(_ meal: TodayMealDescriptor) -> some View {
        Text(meal.foodName)
            .font(BodyFlowTypography.callout)
            .foregroundStyle(BodyFlowColor.primaryText)
    }

    private func mealKcal(_ meal: TodayMealDescriptor) -> some View {
        Text(TodayValueFormatter.mealKcal(meal.kcal, language: language))
            .font(BodyFlowTypography.callout.monospacedDigit())
            .foregroundStyle(BodyFlowColor.secondaryText)
    }

    private func open(_ slot: TodayMealSlotsDescriptor.Slot) -> some View {
        Button {
            register?(MealType(rawValue: slot.type) ?? .other)
        } label: {
            HStack(alignment: .center, spacing: BodyFlowSpacing.sm) {
                slotGlyph(symbol: .add, filled: true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: title(slot.type))
                        .font(BodyFlowTypography.headline)
                        .foregroundStyle(BodyFlowColor.primaryText)
                    Text(verbatim: copy("today.meals.open"))
                        .font(BodyFlowTypography.caption)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: BodyFlowSpacing.sm)
                Text(verbatim: copy("today.meals.register"))
                    .font(BodyFlowTypography.callout.weight(.semibold))
                    .foregroundStyle(BodyFlowColor.color(.brandPrimary))
            }
            .padding(BodyFlowSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget, alignment: .leading)
            .overlay {
                RoundedRectangle(cornerRadius: BodyFlowRadius.card, style: .continuous)
                    .strokeBorder(
                        BodyFlowColor.color(.controlBoundary),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.bodyFlowRowAction)
        .disabled(register == nil)
        .accessibilityIdentifier("today.meal-slot.\(slot.type).register")
    }

    private func skipped(_ slot: TodayMealSlotsDescriptor.Slot) -> some View {
        HStack(alignment: .center, spacing: BodyFlowSpacing.sm) {
            slotGlyph(symbol: .skipped, filled: false)
            Text(verbatim: title(slot.type))
                .font(BodyFlowTypography.headline)
                .foregroundStyle(BodyFlowColor.primaryText)
            Spacer(minLength: BodyFlowSpacing.sm)
            Text(verbatim: copy("today.meals.skipped"))
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)
        }
        .padding(BodyFlowSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.meal-slot.\(slot.type)")
    }

    private func slotGlyph(symbol: BodyFlowSymbol, filled: Bool) -> some View {
        Image(symbol: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(BodyFlowColor.color(filled ? .onPrimary : .brandPrimary))
            .frame(width: 28, height: 28)
            .background(
                BodyFlowColor.color(.brandPrimary).opacity(filled ? 1 : BodyFlowOpacity.glyphWash),
                in: Circle()
            )
            .accessibilityHidden(true)
    }

    private func title(_ type: String) -> String {
        RegistrationCopy.mealTypeTitle(code: type, language: language)
    }

    private var language: SupportedAppLanguage { BodyFlowPresentationLanguage.resolve(locale) }

    private func copy(_ key: String.LocalizationValue) -> String {
        TodayCopy.string(key, language: language)
    }
}
