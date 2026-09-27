import SwiftUI

struct MealProposalEditorSeed {
    let mealType: MealType
    /// Every item of the pending proposal, in the server's order.
    let items: [MealProposalItemSnapshot]
    let consumedAt: Date

    init(registration: RegistrationSnapshot, initialConsumedAt: Date) {
        let proposal: MealProposalSnapshot
        switch registration.proposal {
        case let .meal(value): proposal = value
        case .workout, .unknown:
            proposal = MealProposalSnapshot(
                mealType: "outro",
                items: [],
                totals: nil,
                warnings: []
            )
        }
        mealType = MealType(rawValue: proposal.mealType) ?? .other
        items = proposal.items
        consumedAt = initialConsumedAt
    }

    var foodName: String { items.first?.name ?? "" }
    var quantityG: Decimal? { items.first?.quantityG }
    /// The server's current value for the first item, shown read-only.
    var officialKcal: Decimal? { items.first?.kcal }
    var firstItemKcalOrigin: MealItemKcalOrigin { items.first?.kcalOrigin ?? .official }
    /// True when any item came without its calorie provenance.
    var hasUnknownKcalOrigin: Bool { items.contains { $0.kcalOrigin == .unknown } }
}

enum MealProposalEditorKcalInput: Equatable, Sendable {
    /// Nothing typed: `user_kcal` is omitted and the server calculates.
    case official
    /// A value the patient typed, sent as `user_kcal` (reported by them).
    case manual(Decimal)
    /// Typed but not a readable calorie value; saving is blocked.
    case invalid
    /// A value the patient had reported was erased without choosing the
    /// server calculation; saving is blocked.
    case clearedReportedValue
}

enum MealProposalEditorBlocker: Equatable, Sendable {
    case unknownKcalOrigin
    case noItems
    case invalidQuantity
    case invalidKcal
    case clearedReportedKcal
}

/// Reads a number typed in the editor by the app language, with no partial
/// reads: `Decimal(string:)` turns "140,5" into 140 and blank text into 0.
/// Digits with at most one separator; "," and "." are both accepted as the
/// decimal mark (the keyboard's may differ from the app language), except the
/// language's grouping mark followed by exactly three digits ("1.234" in
/// pt-BR, "1,234" in en), which is refused as ambiguous rather than guessed.
enum MealProposalNumberParser {
    static func parse(_ text: String, language: SupportedAppLanguage) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.allSatisfy({ ($0.isASCII && $0.isNumber) || $0 == "," || $0 == "." })
        else {
            return nil
        }
        let separators = trimmed.filter { $0 == "," || $0 == "." }
        guard separators.count <= 1 else { return nil }
        let parts = trimmed.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "," || $0 == "." }
        )
        guard let whole = parts.first, !whole.isEmpty else { return nil }
        var canonical = String(whole)
        if parts.count == 2 {
            let fraction = parts[1]
            guard !fraction.isEmpty else { return nil }
            if separators.first == groupingSeparator(language), fraction.count == 3 {
                return nil
            }
            canonical += ".\(fraction)"
        }
        return Decimal(string: canonical, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// The language's own decimal mark and no grouping, so a shown value
    /// always reads back as itself.
    static func format(_ value: Decimal, language: SupportedAppLanguage) -> String {
        let formatter = NumberFormatter()
        formatter.locale = language.formattingLocale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }

    private static func groupingSeparator(_ language: SupportedAppLanguage) -> Character {
        language.formattingLocale.groupingSeparator?.first ?? ","
    }
}

/// The editor's working copy and the only place its edit request is built.
/// Only the first item is editable; every other item is sent back as it came,
/// with a patient-reported calorie kept and a calculated one left to the server.
struct MealProposalEditorDraft: Equatable, Sendable {
    let items: [MealProposalItemSnapshot]
    let hasUnknownKcalOrigin: Bool
    var mealType: MealType
    var foodName: String
    var consumedAt: Date
    /// nil until the patient edits the field: the server's quantity is sent
    /// exactly, never re-read from formatted text.
    var quantityText: String?
    /// nil until the patient edits the field.
    var manualKcalText: String?
    private(set) var usesServerCalculation = false

    /// The BFF accepts `user_kcal` in 0…20 000 and `quantity_g` in (0, 9 999].
    static let maximumManualKcal = Decimal(20_000)
    static let maximumQuantityG = Decimal(9_999)

    init(seed: MealProposalEditorSeed) {
        items = seed.items
        hasUnknownKcalOrigin = seed.hasUnknownKcalOrigin
        mealType = seed.mealType
        foodName = seed.foodName
        consumedAt = seed.consumedAt
    }

    private var firstItemOrigin: MealItemKcalOrigin {
        items.first?.kcalOrigin ?? .official
    }

    private var keptReportedKcal: Decimal? {
        guard !usesServerCalculation,
              case let .patientReported(value) = firstItemOrigin
        else {
            return nil
        }
        return value
    }

    /// The only way back to the server calculation for a reported value.
    mutating func useServerCalculation() {
        usesServerCalculation = true
        manualKcalText = ""
    }

    var offersServerCalculation: Bool {
        keptReportedKcal != nil
    }

    func quantityDisplay(language: SupportedAppLanguage) -> String {
        if let quantityText { return quantityText }
        return items.first.map {
            MealProposalNumberParser.format($0.quantityG, language: language)
        } ?? ""
    }

    func manualKcalDisplay(language: SupportedAppLanguage) -> String {
        if let manualKcalText { return manualKcalText }
        return keptReportedKcal.map {
            MealProposalNumberParser.format($0, language: language)
        } ?? ""
    }

    func quantityValue(language: SupportedAppLanguage) -> Decimal? {
        guard let quantityText else { return items.first?.quantityG }
        guard let value = MealProposalNumberParser.parse(quantityText, language: language),
              value > 0, value <= Self.maximumQuantityG
        else {
            return nil
        }
        return value
    }

    func kcalInput(language: SupportedAppLanguage) -> MealProposalEditorKcalInput {
        guard let manualKcalText else {
            return keptReportedKcal.map { .manual($0) } ?? .official
        }
        if manualKcalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return keptReportedKcal == nil ? .official : .clearedReportedValue
        }
        guard let value = MealProposalNumberParser.parse(manualKcalText, language: language),
              value >= 0, value <= Self.maximumManualKcal
        else {
            return .invalid
        }
        return .manual(value)
    }

    /// A reported value kept while the quantity changed deserves a second look.
    func asksToReviewReportedKcal(language: SupportedAppLanguage) -> Bool {
        guard manualKcalText == nil, keptReportedKcal != nil,
              let quantity = quantityValue(language: language)
        else {
            return false
        }
        return quantity != items.first?.quantityG
    }

    func blocker(language: SupportedAppLanguage) -> MealProposalEditorBlocker? {
        if hasUnknownKcalOrigin { return .unknownKcalOrigin }
        if items.isEmpty { return .noItems }
        if quantityValue(language: language) == nil { return .invalidQuantity }
        switch kcalInput(language: language) {
        case .invalid: return .invalidKcal
        case .clearedReportedValue: return .clearedReportedKcal
        case .official, .manual: return nil
        }
    }

    func request(language: SupportedAppLanguage) -> MealProposalRequest? {
        guard blocker(language: language) == nil,
              let quantity = quantityValue(language: language)
        else {
            return nil
        }
        let firstItemKcal: Decimal? = if case let .manual(value) = kcalInput(language: language) {
            value
        } else {
            nil
        }
        let untouchedItems = items.dropFirst().map { item in
            MealProposalItemRequest(
                foodName: item.name,
                quantityG: item.quantityG,
                userKcal: Self.keptKcal(of: item)
            )
        }
        return MealProposalRequest(
            mealType: mealType,
            items: [MealProposalItemRequest(
                foodName: foodName,
                quantityG: quantity,
                userKcal: firstItemKcal
            )] + untouchedItems,
            consumedAt: APITimestamp(value: consumedAt)
        )
    }

    /// A calorie the server applied from the patient is re-sent; a calculated
    /// one never is.
    private static func keptKcal(of item: MealProposalItemSnapshot) -> Decimal? {
        if case let .patientReported(value) = item.kcalOrigin { value } else { nil }
    }
}

enum MealProposalEditorPresentation {
    /// The server's value as it came, formatted for the language; never a
    /// zero standing in for a missing value.
    static func officialKcalText(
        _ value: Decimal?,
        language: SupportedAppLanguage
    ) -> String {
        guard let value else {
            return RegistrationCopy.string(
                "registration.editor.official-kcal.unavailable",
                language: language
            )
        }
        return RegistrationMetricPresentation.text(
            label: "",
            value: value,
            unit: .kilocalories,
            language: language
        )
    }
}

struct MealProposalEditorView: View {
    private let save: @MainActor (MealProposalRequest) -> Void
    private let officialKcal: Decimal?
    private let kcalOrigin: MealItemKcalOrigin

    @State private var draft: MealProposalEditorDraft
    @Environment(\.locale) private var locale

    init(
        registration: RegistrationSnapshot,
        initialConsumedAt: Date,
        isSubmitting: Bool,
        save: @escaping @MainActor (MealProposalRequest) -> Void
    ) {
        let seed = MealProposalEditorSeed(
            registration: registration,
            initialConsumedAt: initialConsumedAt
        )
        _draft = State(initialValue: MealProposalEditorDraft(seed: seed))
        officialKcal = seed.officialKcal
        kcalOrigin = seed.firstItemKcalOrigin
        self.save = save
        _ = isSubmitting
    }

    var body: some View {
        Form {
            Section {
                if draft.blocker(language: language) == .unknownKcalOrigin {
                    BodyFlowStatusLine(copy("registration.editor.origin-unknown"), kind: .warning)
                        .accessibilityIdentifier("registration.proposal.edit.origin-unknown")
                }
                Text(copy("registration.proposal.first-item-notice"))
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                TextField(copy("registration.editor.food"), text: $draft.foodName)
                    .accessibilityIdentifier("registration.proposal.edit.food-name")
                TextField(copy("registration.editor.quantity"), text: quantityBinding)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("registration.proposal.edit.quantity")
                if draft.blocker(language: language) == .invalidQuantity {
                    BodyFlowStatusLine(copy("registration.editor.quantity.invalid"), kind: .error)
                        .accessibilityIdentifier("registration.proposal.edit.quantity.invalid")
                }
                TextField(copy("registration.editor.user-kcal"), text: manualKcalBinding)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("registration.proposal.edit.user-kcal")
                switch draft.kcalInput(language: language) {
                case .invalid:
                    BodyFlowStatusLine(copy("registration.editor.user-kcal.invalid"), kind: .error)
                        .accessibilityIdentifier("registration.proposal.edit.user-kcal.invalid")
                case .clearedReportedValue:
                    BodyFlowStatusLine(copy("registration.editor.user-kcal.cleared"), kind: .warning)
                        .accessibilityIdentifier("registration.proposal.edit.user-kcal.cleared")
                case .official, .manual:
                    EmptyView()
                }
                if draft.asksToReviewReportedKcal(language: language) {
                    BodyFlowStatusLine(copy("registration.editor.user-kcal.check-quantity"), kind: .info)
                        .accessibilityIdentifier("registration.proposal.edit.user-kcal.check-quantity")
                }
                if draft.offersServerCalculation {
                    Button(copy("registration.editor.use-server-calculation")) {
                        draft.useServerCalculation()
                    }
                    .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                    .accessibilityIdentifier("registration.proposal.edit.use-server-calculation")
                }
            } header: {
                Text(copy("registration.editor.first-item"))
            }
            .bodyFlowListRow()
            Section(copy("registration.editor.meal")) {
                Menu {
                    ForEach(MealType.allCases, id: \.self) { type in
                        Button(mealTypeTitle(type)) { draft.mealType = type }
                    }
                } label: {
                    Text(mealTypeTitle(draft.mealType))
                }
                .accessibilityIdentifier("registration.proposal.edit.meal-type")

                DatePicker(copy("registration.editor.time"), selection: $draft.consumedAt)
                    .accessibilityIdentifier("registration.proposal.edit.consumed-at")
            }
            .bodyFlowListRow()
            // The server's value stays read-only and apart from the optional
            // override; it sits after the meal section so the first two
            // sections keep the positions the editor already had.
            Section {
                LabeledContent(serverValueTitle) {
                    Text(MealProposalEditorPresentation.officialKcalText(
                        officialKcal,
                        language: language
                    ))
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("registration.proposal.edit.official-kcal")
            } footer: {
                Text(copy("registration.editor.user-kcal.footer"))
            }
            .bodyFlowListRow()
        }
        .bodyFlowList()
        .accessibilityIdentifier("registration.proposal.editor")
        .navigationTitle(copy("registration.editor.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(copy("registration.editor.save"), action: saveProposal)
                    .disabled(draft.request(language: language) == nil)
                    .accessibilityIdentifier("registration.proposal.edit.save")
            }
        }
    }

    private func saveProposal() {
        guard let request = draft.request(language: language) else { return }
        save(request)
    }

    /// Truthful by origin: the value in the proposal is either the server's
    /// calculation or the patient's reported value; unknown says neither.
    private var serverValueTitle: String {
        switch kcalOrigin {
        case .official: copy("registration.editor.kcal.calculated")
        case .patientReported: copy("registration.editor.kcal.reported")
        case .unknown: copy("registration.editor.official-kcal")
        }
    }

    private var quantityBinding: Binding<String> {
        Binding(
            get: { draft.quantityDisplay(language: language) },
            set: { draft.quantityText = $0 }
        )
    }

    private var manualKcalBinding: Binding<String> {
        Binding(
            get: { draft.manualKcalDisplay(language: language) },
            set: { draft.manualKcalText = $0 }
        )
    }

    static func decimalText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(
            key,
            language: language
        )
    }

    private func mealTypeTitle(_ mealType: MealType) -> String {
        RegistrationCopy.mealTypeTitle(mealType, language: language)
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }
}
