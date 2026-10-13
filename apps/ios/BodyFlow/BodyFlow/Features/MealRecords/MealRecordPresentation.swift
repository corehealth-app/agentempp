import Foundation

/// What the confirmed-record screen shows, decided outside the view body so a
/// unit test can pin it. Saved values always come from the current official
/// read; the only thing read from the form is what the person typed.
struct MealRecordDetailPresentation: Equatable {
    struct Row: Equatable, Identifiable {
        /// The row as the current official read has it.
        let official: MealRecordItemSnapshot
        /// Where the typed fields of the record being corrected live in the
        /// form; nil for every row that is only shown.
        let draftIndex: Int?
        var id: String { official.id }
    }

    enum Content: Equatable {
        /// No official read and no local row to show.
        case nothing
        /// The row History already holds, read-only: while the official read
        /// loads and when it fails.
        case localRow(HistoryMealLogRow)
        /// Official values only: the record cannot be changed, or a change
        /// was just saved.
        case readOnly([MealRecordItemSnapshot])
        /// Official rows; the record being corrected adds its fields.
        case form([Row])
    }

    let content: Content

    @MainActor
    static func make(model: MealRecordModel, localRow: HistoryMealLogRow?) -> MealRecordDetailPresentation {
        if isRecordUnavailable(model: model) {
            if let detail = model.detail?.data {
                return MealRecordDetailPresentation(content: .readOnly(detail.items))
            }
            if let localRow, localRow.id == model.recordID {
                return MealRecordDetailPresentation(content: .localRow(localRow))
            }
            return MealRecordDetailPresentation(content: .nothing)
        }
        guard let detail = model.detail?.data else {
            // After a saved change the row History held describes the past.
            if model.confirmedReceipt == nil, let localRow, localRow.id == model.recordID {
                return MealRecordDetailPresentation(content: .localRow(localRow))
            }
            return MealRecordDetailPresentation(content: .nothing)
        }
        guard !model.hasCompletedCurrentPresentation, detail.editable, !detail.dayClosed,
              let draft = model.draft else {
            return MealRecordDetailPresentation(content: .readOnly(detail.items))
        }
        let anchor = draft.items.firstIndex { $0.id == model.recordID }
        return MealRecordDetailPresentation(content: .form(detail.items.map { item in
            Row(official: item, draftIndex: item.id == model.recordID ? anchor : nil)
        }))
    }

    /// A typed official GET says this original record no longer exists. A
    /// command with an unknown outcome still owns its key and retry path;
    /// neither a failed read nor this presentation resolves that command.
    @MainActor
    static func isRecordUnavailable(model: MealRecordModel) -> Bool {
        model.readFailure == .notFound && model.confirmedReceipt == nil
            && (model.retainedAttempt == nil || model.failure?.mayRetrySameAttempt == false)
    }

    /// Whether the screen offers Save: the model accepts the form and sending
    /// it would change the record. An untouched form is valid for the model,
    /// yet sending it would only give the record another id.
    @MainActor
    static func offersSave(model: MealRecordModel, language: SupportedAppLanguage) -> Bool {
        model.canSave(language: language) && model.draft?.changesRecord(language: language) == true
    }
}

extension MealRecordEditDraft {
    /// True when sending the form would change the record being corrected:
    /// another name, another quantity or a new calorie total. Typing the
    /// saved value again, or blank space around the same name, is no change.
    func changesRecord(language: SupportedAppLanguage) -> Bool {
        guard let item = items.first(where: { $0.id == recordID }),
              let request = item.request(language: language) else { return false }
        return Self.normalizedQuantityIdentity(request.foodName)
                != Self.normalizedQuantityIdentity(item.original.foodName)
            || request.quantityG != item.original.quantityG
            || request.userKcal != nil
    }

    /// Match the server's quantity-only identity without rewriting typed fields.
    private static func normalizedQuantityIdentity(_ name: String) -> String {
        name.lowercased().decomposedStringWithCanonicalMapping
            .replacingOccurrences(of: #"\p{Diacritic}"#, with: "", options: .regularExpression)
            // ECMAScript whitespace: ICU's \s also includes characters the server keeps.
            .replacingOccurrences(
                of: #"[ \t-\r\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+"#,
                with: " ", options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: " "))
    }
}

/// Catalog access for the confirmed-record screen. Every sentence lives in
/// `Localizable.xcstrings` under `confirmed-meal.*`, in pt-BR and en.
enum MealRecordCopy {
    static func string(_ key: String, language: SupportedAppLanguage) -> String {
        let value = String.LocalizationValue(key)
        return (try? AppLocalization.string(value, for: language)) ?? String(localized: value)
    }

    static func failureKey(_ failure: MealRecordFailure) -> String {
        switch failure {
        case .versionChanged: "confirmed-meal.failure.changed"
        case .notEditable: "confirmed-meal.failure.not-editable"
        case .notFound: "confirmed-meal.failure.not-found"
        case .commandConflict: "confirmed-meal.failure.send-conflict"
        case .requestInProgress: "confirmed-meal.failure.in-progress"
        case .interruptedUnknown: "confirmed-meal.failure.unconfirmed"
        case .invalidInput: "confirmed-meal.failure.invalid"
        case .countryRequired: "confirmed-meal.failure.country-required"
        case .quantityNotRepresentable: "confirmed-meal.failure.quantity"
        case .nutritionUnresolved: "confirmed-meal.failure.nutrition"
        case .groupLimitExceeded: "confirmed-meal.failure.group-limit"
        case .groupLimitChanged: "confirmed-meal.failure.group-changed"
        case .capability: "confirmed-meal.failure.generic"
        }
    }

    /// The failure in the person's words. The sentence about typed fields is
    /// added only when there are typed fields to speak of.
    static func failureMessage(_ failure: MealRecordFailure, hasTypedFields: Bool,
                               language: SupportedAppLanguage) -> String {
        let message = string(failureKey(failure), language: language)
        guard hasTypedFields else { return message }
        return message + " " + string("confirmed-meal.fields-kept", language: language)
    }

    static func readFailureMessage(hasReceipt: Bool, hasOfficialRead: Bool, hasTypedFields: Bool,
                                   showsLocalRow: Bool, language: SupportedAppLanguage) -> String {
        if hasReceipt { return string("confirmed-meal.read-failed.after-save", language: language) }
        if showsLocalRow { return string("confirmed-meal.read-failed.local", language: language) }
        guard hasOfficialRead || hasTypedFields else {
            return string("confirmed-meal.read-failed", language: language)
        }
        let message = string("confirmed-meal.read-failed.refresh", language: language)
        guard hasTypedFields else { return message }
        return message + " " + string("confirmed-meal.fields-kept", language: language)
    }

    static func deleteConfirmationTitle(count: Int, language: SupportedAppLanguage) -> String {
        string(count == 1 ? "confirmed-meal.delete.title.one" : "confirmed-meal.delete.title.other",
               language: language)
    }

    static func deleteConfirmationMessage(count: Int, language: SupportedAppLanguage) -> String {
        String(format: string(count == 1 ? "confirmed-meal.delete.message.one"
                                         : "confirmed-meal.delete.message.other", language: language),
               locale: language.formattingLocale, count)
    }
}
