import NaturalLanguage
import SwiftUI

/// Read-only component. Callers own trusted transport/session fencing;
/// an HTTP success or this presentation never acknowledges an outbox command.
struct ConversationFeedbackPresentationView: View {
    let feedback: ConversationFeedbackPresentationSnapshot.Bound
    var compact = false
    var showsPhotoQuestion = true
    @Environment(\.locale) private var locale
    @State private var detailsExpanded = false

    private var english: Bool {
        BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates
    }

    var body: some View {
        Group {
            if compact {
                compactContent
            } else {
                expandedContent
            }
        }
        .font(BodyFlowTypography.body)
        .foregroundStyle(BodyFlowColor.primaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversation.feedback.presentation")
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(verbatim: "Flow AI")
                .font(BodyFlowTypography.cardTitle)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: historicalTitle)
                .font(BodyFlowTypography.body)
                .accessibilityIdentifier("conversation.feedback.historical")
            switch feedback.presentation.content {
            case let .sections(_, sections), let .v3Sections(_, sections), let .placeholder(sections):
                ForEach(sections, id: \.key) { section in
                    Text(verbatim: FoodDisplayLocalization.message(section.text,
                        english: BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates))
                        .accessibilityIdentifier("conversation.feedback.section.\(section.key.rawValue)")
                }
            case let .legacy(body):
                RegistrationFeedbackView(feedback: .v1(body))
            }
        }
    }

    private var compactContent: some View {
        let preview = FlowFeedbackPreview(feedback.presentation, english: english)
        return VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Label {
                Text(verbatim: preview.title)
            } icon: {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(BodyFlowColor.accent)
            }
            .font(BodyFlowTypography.headline)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("conversation.feedback.compact-title")

            if let summary = preview.summary {
                Text(verbatim: summary)
                    .font(BodyFlowTypography.caption)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .accessibilityIdentifier("conversation.feedback.compact-summary")
            }
            if let day = preview.day {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text(english ? "Day at registration" : "Dia no momento do registro")
                        .fontWeight(.semibold)
                    Text(verbatim: day)
                }
                .font(BodyFlowTypography.caption)
                .accessibilityIdentifier("conversation.feedback.compact-day")
            }
            if let block = preview.block {
                Text(verbatim: block)
                    .font(BodyFlowTypography.caption)
                    .accessibilityIdentifier("conversation.feedback.compact-block")
            }
            if let comment = preview.education {
                Text(verbatim: comment)
                    .accessibilityIdentifier("conversation.feedback.compact-education")
            }
            if showsPhotoQuestion, let pending = preview.pending {
                Text(verbatim: pending)
                    .foregroundStyle(BodyFlowColor.warning)
                    .accessibilityIdentifier("conversation.feedback.photo-question")
            }
            if !preview.details.isEmpty || preview.legacy != nil {
                DisclosureGroup(
                    english ? "View details" : "Ver detalhes", isExpanded: $detailsExpanded
                ) {
                    if detailsExpanded {
                        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                            if let legacy = preview.legacy {
                                RegistrationFeedbackView(feedback: .v1(legacy))
                            }
                            ForEach(preview.details.indices, id: \.self) { index in
                                Text(verbatim: preview.details[index])
                            }
                        }
                        .padding(.top, BodyFlowSpacing.xs)
                    }
                }
                .tint(BodyFlowColor.accent)
                .accessibilityIdentifier("conversation.feedback.details")
            }
        }
    }

    private var historicalTitle: String {
        let date = feedback.presentation.original.localDate
        return BodyFlowPresentationLanguage.resolve(locale) == .englishUnitedStates
            ? "Historical registration (\(date))" : "Registro histórico (\(date))"
    }
}

/// Short chat copy from the same bound facts as the expanded receipt. Formatting
/// changes here never generate nutrition or supplement the server's policy.
struct FlowFeedbackPreview {
    let title: String
    let summary: String?
    let day: String?
    let block: String?
    let education: String?
    let pending: String?
    let details: [String]
    let legacy: RegistrationFeedbackV1Snapshot?

    init(_ feedback: ConversationFeedbackPresentationSnapshot, english: Bool) {
        typealias Section = ConversationFeedbackPresentationSnapshot.Section
        let sections: [Section]
        var detailLines: [String] = []
        var showsFoodItems = false
        var workoutTitle: String?
        let format = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(0...1))
            .locale(Locale(identifier: english ? "en_US" : "pt_BR"))
        func mealSummary(_ kcal: Double, _ protein: Double) -> String {
            "\(english ? "Approx." : "Aprox.") \(kcal.formatted(format)) kcal · \(protein.formatted(format)) g \(english ? "of protein" : "de proteína")"
        }
        func mealComposition(_ carbs: Double, _ fat: Double) -> String {
            "Total · \(carbs.formatted(format)) g \(english ? "carbs" : "de carboidratos") · \(fat.formatted(format)) g \(english ? "fat" : "de gorduras")"
        }
        if case let .legacy(body) = feedback.content { legacy = body } else { legacy = nil }
        switch feedback.content {
        case let .v3Sections(recorded, savedSections):
            sections = savedSections
            switch recorded {
            case .meal(let meal):
                showsFoodItems = true
                summary = mealSummary(meal.totals.kcal, meal.totals.proteinG)
                detailLines.append(mealComposition(meal.totals.carbsG, meal.totals.fatG))
            case .workout(let workout):
                workoutTitle = english ? "Activity registered" : "Atividade registrada"
                let name = FoodDisplayLocalization.name(workout.workoutType, english: english)
                summary = [
                    name,
                    workout.durationMin.map { "\($0.formatted(format)) min" },
                    workout.estimatedKcal.map { "\(english ? "Approx." : "Aprox.") \($0.formatted(format)) kcal" },
                ].compactMap { $0 }.joined(separator: " · ")
                if let intensity = workout.intensity {
                    detailLines.append(
                        (english ? "Intensity: " : "Intensidade: ")
                            + FoodDisplayLocalization.name(intensity, english: english))
                }
            }
        case let .sections(meal, savedSections):
            showsFoodItems = true
            sections = savedSections
            summary = mealSummary(meal.totals.kcal, meal.totals.proteinG)
            detailLines.append(mealComposition(meal.totals.carbsG, meal.totals.fatG))
        case let .placeholder(savedSections):
            sections = savedSections
            summary = nil
        case .legacy:
            sections = []
            summary = nil
        }
        func text(_ key: Section.Key) -> String? {
            sections.first { $0.key == key }?.text
        }
        func localized(_ line: String) -> String {
            FoodDisplayLocalization.message(line, english: english)
        }
        title = workoutTitle ?? text(.saved) ?? (english ? "Meal recorded" : "Refeição registrada")
        let policy = feedback.currentPolicy
        let dayLines = text(.day)?.components(separatedBy: "\n").compactMap { line -> String? in
            let visible: Bool
            if ["Consumido:", "Consumed:"].contains(where: { line.hasPrefix($0) }) {
                visible = !policy.hide.calories
            } else if ["Proteína:", "Protein:"].contains(where: { line.hasPrefix($0) }) {
                visible = !policy.hide.protein
            } else {
                visible = !policy.hide.budget && !policy.hide.balance
                    && ["Restam para comida:", "Remaining for food:", "Excedente alimentar:", "Food excess:"]
                        .contains(where: { line.hasPrefix($0) })
            }
            guard visible else { return nil }
            return localized(line.replacingOccurrences(of: ". Meta indisponível.", with: "")
                .replacingOccurrences(of: ". Target unavailable.", with: ""))
        } ?? []
        day = dayLines.isEmpty ? nil : dayLines.joined(separator: "\n")
        let blockLines = text(.block)?.components(separatedBy: "\n") ?? []
        if !policy.hide.block && !policy.hide.objective && !policy.pauseWeightLossGuidance,
            let active = blockLines.first(where: {
                $0.hasPrefix("Bloco 7.700:") || $0.hasPrefix("Block 7,700:")
            }) {
            block = localized(active)
            detailLines += blockLines.filter {
                $0.hasPrefix("Saldo total já consolidado:") || $0.hasPrefix("Total already consolidated:")
            }.map(localized)
        } else {
            block = nil
        }
        // Only the server's available educational section has this heading.
        // An unavailable section contains generic fallback copy, not guidance.
        let educationPrefixes = [
            "Educational comment at the time of registration:\n",
            "Comentário educativo no momento do registro:\n",
        ]
        if let comment = text(.education),
            let heading = educationPrefixes.first(where: { comment.hasPrefix($0) }) {
            let content = localized(String(comment.dropFirst(heading.count)))
            let sentences = NLTokenizer(unit: .sentence)
            sentences.string = content
            let parts = sentences.tokens(for: content.startIndex..<content.endIndex)
            let brief = parts.prefix(2).map { String(content[$0]) }.joined(separator: " ")
            education = brief.isEmpty ? nil : brief
            let continuation = parts.dropFirst(2).map { String(content[$0]) }.joined(separator: " ")
            if !continuation.isEmpty { detailLines.append(continuation) }
        } else {
            education = nil
        }
        if showsFoodItems, let items = text(.items) { detailLines.insert(localized(items), at: 0) }
        details = detailLines

        let marker = english ? "To review separately: " : "Ficou para revisar: "
        let nextStep = english ? ". If confirmed, " : ". Se confirmar, "
        if let line = text(.summary)?.components(separatedBy: "\n").first(where: { $0.hasPrefix(marker) }),
            let separator = line.range(of: nextStep) {
            let names = line[line.index(line.startIndex, offsetBy: marker.count)..<separator.lowerBound]
            let multiple = names.contains(",") || names.count > 50
            pending = multiple
                ? (english ? "What else did you eat and how much?" : "O que mais você comeu e em que quantidade?")
                : (english ? "Was that \(names)? How much did you eat?" : "Era \(names)? Quanto você comeu?")
        } else {
            pending = nil
        }
    }
}

struct FlowChatBubble<Content: View>: View {
    var outgoing = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .font(BodyFlowTypography.body)
            .padding(BodyFlowSpacing.sm)
            .background(
                outgoing ? BodyFlowColor.accent.opacity(0.13) : BodyFlowColor.surface,
                in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: .infinity, alignment: outgoing ? .trailing : .leading)
    }
}
